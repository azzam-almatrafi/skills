# Migration to Microservices Guide

Step-by-step guide for extracting a module from a Modular Monolith into an independent microservice.

---

## When to Extract a Module

Extract only when you have measurable evidence — never "just in case."

| Signal | Evidence | Example |
|--------|----------|---------|
| **Scaling divergence** | One module needs 10x+ resources | Image processing module pegs CPU while others idle |
| **Team autonomy** | Team blocked by shared release cycle | Payments team can't deploy without full regression |
| **Tech stack mismatch** | Module needs a different runtime | ML recommendation module needs Python, app is in Java |
| **Regulatory isolation** | Data must be in a separate process | PCI-DSS requires cardholder data in isolated service |
| **Performance bottleneck** | Module degrades the entire app | Search indexing causes latency spikes for all modules |

### Do NOT Extract When:
- You have vague concerns about "future scaling"
- Another team asked for a microservice because it sounds modern
- The module is simply large — refactor it internally first
- You don't have infrastructure to operate services (CI/CD, monitoring, container orchestration)

---

## Pre-Extraction Checklist

Before extracting a module, verify these prerequisites:

```
☐ Module has clean boundaries (architecture tests pass)
☐ Module communicates via contracts/interfaces only
☐ Module has its own database schema (no cross-schema joins)
☐ Module's integration tests pass independently
☐ Event contracts are documented and versioned
☐ Team has CI/CD pipeline for independent deployments
☐ Observability stack is ready (distributed tracing, centralized logging)
☐ Team understands eventual consistency implications
```

---

## Extraction Steps

### Phase 1: Prepare the Module (While Still in the Monolith)

#### 1.1 Audit Dependencies

Map all connections between the target module and the rest of the monolith.

```
Incoming calls (other modules calling Target):
  ├── OrderModule → TargetModule.getProductById()
  ├── ReportModule → TargetModule.getProductsByCategory()
  └── CartModule → TargetModule.checkAvailability()

Outgoing calls (Target calling other modules):
  └── TargetModule → InventoryModule.reserveStock()

Events published:
  ├── ProductCreatedEvent
  └── ProductPriceChangedEvent

Events consumed:
  └── OrderPlacedEvent (to update stock)
```

#### 1.2 Harden the Module Contract

Ensure the module's public API is:
- Complete (every external interaction goes through the contract)
- Stable (no frequent changes to method signatures)
- Documented (what each method does, error conditions, expected payloads)

```typescript
// product/api/product-module.interface.ts
export interface IProductModule {
  // Queries
  getProductById(id: string): Promise<ProductDto | null>;
  getProductsByIds(ids: string[]): Promise<ProductDto[]>;
  getProductsByCategory(category: string, pagination: PaginationDto): Promise<PagedResult<ProductDto>>;

  // Commands
  checkAvailability(productId: string, quantity: number): Promise<boolean>;
  reserveStock(productId: string, quantity: number): Promise<ReservationResult>;
  releaseStock(reservationId: string): Promise<void>;
}
```

#### 1.3 Replace Synchronous Calls with Async Where Possible

Before extraction, identify calls that don't need an immediate response and switch them to events. This reduces the number of synchronous cross-service calls later.

```
Before:
  OrderModule → ProductModule.updateStockAfterOrder()   // Synchronous

After:
  OrderModule → publishes OrderPlacedEvent
  ProductModule → subscribes to OrderPlacedEvent → updates stock
```

---

### Phase 2: Create the Service

#### 2.1 Set Up the New Service Repository

```
product-service/
├── src/
│   ├── domain/          # Copy from monolith module
│   ├── application/     # Copy from monolith module
│   ├── infrastructure/  # Copy, update DB connection
│   ├── api/
│   │   ├── http/        # REST/gRPC controllers
│   │   └── events/      # Message broker consumers
│   └── main.ts          # Standalone entry point
├── database/
│   └── migrations/      # Copy from monolith module's schema
├── test/
├── Dockerfile
├── docker-compose.yml
└── package.json
```

#### 2.2 Expose the Same Contract as HTTP/gRPC

```typescript
// product-service/src/api/http/product.controller.ts
@Controller('/api/products')
export class ProductController {
  constructor(private readonly productService: ProductService) {}

  @Get(':id')
  async getById(@Param('id') id: string): Promise<ProductDto | null> {
    return this.productService.getProductById(id);
  }

  @Post(':id/availability')
  async checkAvailability(
    @Param('id') id: string,
    @Body() body: { quantity: number },
  ): Promise<{ available: boolean }> {
    const available = await this.productService.checkAvailability(id, body.quantity);
    return { available };
  }
}
```

#### 2.3 Migrate the Database Schema

```bash
# 1. Create new database
createdb product_service_db

# 2. Run module migrations against the new database
npm run migrate -- --database=product_service_db

# 3. Copy data from the monolith's product schema
pg_dump monolith_db --schema=product | psql product_service_db
```

---

### Phase 3: Update the Monolith

#### 3.1 Create an HTTP/gRPC Client That Implements the Same Interface

```typescript
// In the monolith: product/infrastructure/product-http-client.ts
export class ProductHttpClient implements IProductModule {
  constructor(
    private readonly httpClient: HttpService,
    private readonly baseUrl: string,
  ) {}

  async getProductById(id: string): Promise<ProductDto | null> {
    const response = await this.httpClient.get(`${this.baseUrl}/api/products/${id}`);
    if (response.status === 404) return null;
    return response.data;
  }

  async checkAvailability(productId: string, quantity: number): Promise<boolean> {
    const response = await this.httpClient.post(
      `${this.baseUrl}/api/products/${productId}/availability`,
      { quantity },
    );
    return response.data.available;
  }
}
```

#### 3.2 Swap the Implementation in the Composition Root

```typescript
// Before (in-process)
providers: [{ provide: 'IProductModule', useClass: ProductService }]

// After (HTTP client to extracted service)
providers: [{
  provide: 'IProductModule',
  useFactory: (http: HttpService) =>
    new ProductHttpClient(http, process.env.PRODUCT_SERVICE_URL),
  inject: [HttpService],
}]
```

**The rest of the monolith doesn't change at all** — every other module still calls `IProductModule` the same way.

#### 3.3 Swap the Event Bus for That Module

```typescript
// Events published by the extracted Product service now go through RabbitMQ/Kafka
// Events it consumed now come from RabbitMQ/Kafka

// In the monolith's composition root:
providers: [{
  provide: 'IEventBus',
  useFactory: () => new HybridEventBus({
    inProcess: new InMemoryEventBus(),       // For modules still in the monolith
    broker: new RabbitMQEventBus(amqpUrl),   // For the extracted service
    routingTable: {
      'product.*': 'broker',   // Product events go through broker
      '*': 'inProcess',        // Everything else stays in-process
    },
  }),
}]
```

---

### Phase 4: Add Resilience

#### 4.1 Circuit Breaker

Network calls can fail. Wrap the HTTP client with a circuit breaker.

```typescript
import CircuitBreaker from 'opossum';

export class ResilientProductClient implements IProductModule {
  private breaker: CircuitBreaker;

  constructor(private readonly client: ProductHttpClient) {
    this.breaker = new CircuitBreaker(
      (fn: () => Promise<any>) => fn(),
      {
        timeout: 3000,        // 3s timeout
        errorThresholdPercentage: 50,
        resetTimeout: 10000,  // Try again after 10s
      },
    );
  }

  async getProductById(id: string): Promise<ProductDto | null> {
    return this.breaker.fire(() => this.client.getProductById(id));
  }
}
```

#### 4.2 Fallback Strategies

| Strategy | When to Use |
|----------|------------|
| **Cache fallback** | Return cached data when the service is down (for queries) |
| **Graceful degradation** | Show "price unavailable" instead of error |
| **Queue and retry** | For commands — save to local outbox, retry when service recovers |
| **Default values** | Return sensible defaults for non-critical data |

#### 4.3 Distributed Tracing

```typescript
// Propagate trace context across service boundaries
const response = await this.httpClient.get(`${this.baseUrl}/api/products/${id}`, {
  headers: {
    'traceparent': context.active().traceParent,  // OpenTelemetry W3C format
  },
});
```

---

### Phase 5: Validate and Stabilize

#### 5.1 Run Contract Tests Against the New Service

The same contract tests that verified the in-process module should now pass against the HTTP service.

```typescript
describe('Product Module Contract (Remote)', () => {
  let productModule: IProductModule;

  beforeAll(() => {
    // Point at the real service
    productModule = new ProductHttpClient(httpService, 'http://localhost:3001');
  });

  it('getProductById should return ProductDto with required fields', async () => {
    const product = await productModule.getProductById('prod-1');
    expect(product).toEqual(expect.objectContaining({
      id: expect.any(String),
      name: expect.any(String),
      price: expect.any(Number),
    }));
  });
});
```

#### 5.2 Monitor the Boundary

Track these metrics after extraction:

| Metric | Target | Action if Exceeded |
|--------|--------|-------------------|
| Latency (p99) | < 100ms | Check network, optimize queries |
| Error rate | < 0.1% | Check circuit breaker, service health |
| Availability | > 99.9% | Add replicas, improve fallbacks |
| Event delivery lag | < 1s | Tune broker consumers, scale workers |

#### 5.3 Rollback Plan

If extraction causes problems:
1. Swap `ProductHttpClient` back to `ProductService` in composition root
2. Point the database connection back to the monolith's schema
3. Revert event bus routing to in-process

Because the interface never changed, rollback is a configuration change — not a code change.

---

## Incremental Extraction Timeline

```
Week 1-2: Audit and harden module boundaries
Week 3:   Set up new service repo, CI/CD pipeline
Week 4:   Copy module code, expose HTTP/gRPC API
Week 5:   Migrate database, sync data
Week 6:   Switch monolith to HTTP client (behind feature flag)
Week 7:   Canary rollout (10% traffic → 50% → 100%)
Week 8:   Remove old module code from monolith, stabilize
```

---

## Common Pitfalls

| Pitfall | Consequence | Prevention |
|---------|-------------|-----------|
| Extracting without clean boundaries | Massive refactoring during extraction | Run architecture tests in CI before attempting |
| Skipping the HTTP client interface swap | Module consumers need rewrites | Always implement the same `IModule` interface |
| Ignoring eventual consistency | Business logic assumes instant data | Audit all call sites for consistency requirements |
| No circuit breaker | One failing service cascades | Add resilience from day one |
| Extracting multiple modules at once | Too many moving parts | Extract one at a time, stabilize, then proceed |
