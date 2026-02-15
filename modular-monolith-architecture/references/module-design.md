# Module Design Patterns Reference

Detailed guidance on designing modules within a Modular Monolith.

---

## Module Internal Architecture

Each module can adopt its own architecture. The choice depends on the module's complexity.

### Option 1: Layered Architecture (Simple Modules)

Best for straightforward CRUD modules with limited business logic.

```
module/
├── domain/       → Entities, value objects, repository interfaces
├── application/  → Use cases, DTOs, validation
├── infrastructure/ → Repository implementations, DB config, external services
└── api/          → Controllers/handlers, request/response models
```

**Dependency rule**: domain ← application ← infrastructure, api → application

### Option 2: Clean Architecture (Complex Modules)

Best for modules with rich business logic and many domain rules.

```
module/
├── domain/       → Entities, aggregates, domain events, domain services
├── application/  → Commands, queries, handlers, ports (interfaces)
├── infrastructure/ → Adapters (DB, external APIs, messaging)
└── presentation/  → Controllers, view models, mappers
```

**Dependency rule**: All layers depend inward toward domain. Domain has zero dependencies.

### Option 3: Vertical Slice (Feature-Rich Modules)

Best for modules with many independent features that rarely overlap.

```
module/
├── features/
│   ├── create-product/
│   │   ├── command.ts
│   │   ├── handler.ts
│   │   ├── validator.ts
│   │   └── controller.ts
│   ├── list-products/
│   │   ├── query.ts
│   │   ├── handler.ts
│   │   └── controller.ts
│   └── update-price/
├── domain/       → Shared entities within the module
└── persistence/  → Shared database access
```

---

## Inter-Module Communication

### Rule: Modules NEVER reference each other's internals

```
❌ WRONG — Direct reference to internal type
import { Product } from '../product/domain/entities/product';

✅ CORRECT — Reference only the public contract
import { IProductModule } from '../product/api/product-module.interface';
import { ProductDto } from '../../shared/contracts/product.dto';
```

### Pattern 1: Synchronous — Module Contracts (Interfaces)

Each module exposes a public interface. Other modules depend on this contract.

```typescript
// product/api/product-module.interface.ts — PUBLIC CONTRACT
export interface IProductModule {
  getProductById(id: string): Promise<ProductDto | null>;
  getProductsByIds(ids: string[]): Promise<ProductDto[]>;
  checkAvailability(productId: string, quantity: number): Promise<boolean>;
}

// product/application/product.service.ts — INTERNAL implementation
export class ProductService implements IProductModule {
  // Implementation details hidden from other modules
}

// order/application/order.service.ts — Consumer
export class OrderService {
  constructor(private readonly productModule: IProductModule) {} // Injected interface
  
  async createOrder(items: OrderItem[]) {
    for (const item of items) {
      const available = await this.productModule.checkAvailability(item.productId, item.quantity);
      if (!available) throw new InsufficientStockError(item.productId);
    }
  }
}
```

### Pattern 2: Asynchronous — Domain Events (In-Process Event Bus)

For operations where the caller doesn't need an immediate response.

```typescript
// shared/events/event-bus.interface.ts
export interface IEventBus {
  publish(event: DomainEvent): Promise<void>;
  subscribe(eventType: string, handler: EventHandler): void;
}

// order/application/order.service.ts — Publisher
async completeOrder(orderId: string) {
  const order = await this.orderRepo.findById(orderId);
  order.markCompleted();
  await this.orderRepo.save(order);
  
  await this.eventBus.publish(new OrderCompletedEvent({
    orderId: order.id,
    items: order.items,
    total: order.total,
  }));
}

// payment/application/event-handlers/on-order-completed.ts — Subscriber
export class OnOrderCompleted {
  async handle(event: OrderCompletedEvent) {
    await this.paymentService.initiatePayment(event.orderId, event.total);
  }
}
```

### Pattern 3: Anti-Corruption Layer (for Legacy Integration)

When a module must interact with a legacy system or third-party API.

```typescript
// shipping/infrastructure/anti-corruption/legacy-shipping-adapter.ts
export class LegacyShippingAdapter implements IShippingProvider {
  async calculateRate(request: ShippingRateRequest): Promise<ShippingRate> {
    // Translate our domain model → legacy API format
    const legacyRequest = this.toLegacyFormat(request);
    const legacyResponse = await this.legacyClient.getRates(legacyRequest);
    // Translate legacy response → our domain model
    return this.fromLegacyFormat(legacyResponse);
  }
}
```

---

## Database Schema Isolation

### Strategy 1: Schema-per-Module (Recommended)

Each module uses a named schema in the same database.

```sql
-- Product module schema
CREATE SCHEMA product;
CREATE TABLE product.products (
    id UUID PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    price DECIMAL(10,2) NOT NULL,
    created_at TIMESTAMP DEFAULT NOW()
);

-- Order module schema
CREATE SCHEMA ordering;
CREATE TABLE ordering.orders (
    id UUID PRIMARY KEY,
    customer_id UUID NOT NULL,
    status VARCHAR(50) NOT NULL,
    total DECIMAL(10,2) NOT NULL,
    created_at TIMESTAMP DEFAULT NOW()
);

-- Order references product by ID only — no foreign key across schemas
CREATE TABLE ordering.order_items (
    id UUID PRIMARY KEY,
    order_id UUID REFERENCES ordering.orders(id),
    product_id UUID NOT NULL,           -- References product, but NO FK constraint
    quantity INT NOT NULL,
    unit_price DECIMAL(10,2) NOT NULL
);
```

**Critical rule**: No foreign keys between schemas. Use product_id as a reference, not a FK constraint.

### Strategy 2: Table Prefix (Simpler Alternative)

For databases that don't support schemas (e.g., MySQL without multi-schema).

```sql
CREATE TABLE product_products (...);
CREATE TABLE product_categories (...);
CREATE TABLE order_orders (...);
CREATE TABLE order_order_items (...);
```

### Strategy 3: Separate Database Contexts (ORM Level)

Enforce isolation at the ORM level even with a single database.

```csharp
// C# / Entity Framework Core
public class ProductDbContext : DbContext
{
    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        modelBuilder.HasDefaultSchema("product");
        modelBuilder.ApplyConfigurationsFromAssembly(typeof(ProductDbContext).Assembly);
    }
}

public class OrderDbContext : DbContext
{
    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        modelBuilder.HasDefaultSchema("ordering");
        modelBuilder.ApplyConfigurationsFromAssembly(typeof(OrderDbContext).Assembly);
    }
}
```

---

## Module Registration Pattern

Each module provides a registration method that the host calls during startup.

### .NET Example

```csharp
// Product module installer
public static class ProductModuleInstaller
{
    public static IServiceCollection AddProductModule(this IServiceCollection services, IConfiguration config)
    {
        // Register domain services
        services.AddScoped<IProductRepository, PostgresProductRepository>();
        services.AddScoped<IProductModule, ProductService>();
        
        // Register DB context
        services.AddDbContext<ProductDbContext>(options =>
            options.UseNpgsql(config.GetConnectionString("Default")));
        
        // Register event handlers
        services.AddScoped<IEventHandler<OrderCompletedEvent>, OnOrderCompletedHandler>();
        
        return services;
    }
}

// Host/Program.cs — Composition Root
var builder = WebApplication.CreateBuilder(args);
builder.Services.AddProductModule(builder.Configuration);
builder.Services.AddOrderModule(builder.Configuration);
builder.Services.AddPaymentModule(builder.Configuration);
builder.Services.AddSharedInfrastructure(builder.Configuration);
```

### NestJS Example

```typescript
// product.module.ts
@Module({
  imports: [TypeOrmModule.forFeature([ProductEntity]), SharedModule],
  controllers: [ProductController],
  providers: [ProductService, ProductRepository],
  exports: [ProductService],  // Only export the public contract
})
export class ProductModule {}

// app.module.ts — Composition Root
@Module({
  imports: [
    SharedModule,
    ProductModule,
    OrderModule,
    PaymentModule,
  ],
})
export class AppModule {}
```

---

## Architecture Boundary Tests

Enforce module isolation at build/test time. These are critical for preventing boundary erosion over time.

### .NET with NetArchTest

```csharp
[Fact]
public void ProductModule_ShouldNotDependOn_OrderModule()
{
    var result = Types.InAssembly(typeof(ProductService).Assembly)
        .ShouldNot()
        .HaveDependencyOn("MyApp.Modules.Order")
        .GetResult();
    
    Assert.True(result.IsSuccessful);
}

[Fact]
public void DomainLayer_ShouldNotDependOn_Infrastructure()
{
    var result = Types.InNamespace("MyApp.Modules.Product.Domain")
        .ShouldNot()
        .HaveDependencyOn("MyApp.Modules.Product.Infrastructure")
        .GetResult();
    
    Assert.True(result.IsSuccessful);
}
```

### Java with ArchUnit

```java
@ArchTest
static final ArchRule productModuleShouldNotAccessOrderInternals =
    noClasses()
        .that().resideInAPackage("..modules.product..")
        .should().accessClassesThat()
        .resideInAPackage("..modules.order.domain..")
        .orShould().accessClassesThat()
        .resideInAPackage("..modules.order.infrastructure..");

@ArchTest
static final ArchRule modulesShouldOnlyCommunicateThroughApi =
    noClasses()
        .that().resideInAPackage("..modules.*.domain..")
        .should().accessClassesThat()
        .resideInAPackage("..modules.*.domain..")
        .andShould().notBe(inSameModule());
```

### TypeScript/Python with Import Analysis

```typescript
// test/architecture/module-boundaries.spec.ts
import * as fs from 'fs';
import * as path from 'path';

describe('Module Boundaries', () => {
  it('product module should not import from order internals', () => {
    const productFiles = getAllTsFiles('src/modules/product');
    for (const file of productFiles) {
      const content = fs.readFileSync(file, 'utf-8');
      expect(content).not.toMatch(/from ['"].*modules\/order\/(?!api)/);
    }
  });
});
```

---

## Event Bus Implementation (In-Process, Upgradeable)

Start with an in-process event bus. When you need to extract a module to a microservice, swap the implementation to RabbitMQ/Kafka without changing module code.

```typescript
// shared/events/in-memory-event-bus.ts
export class InMemoryEventBus implements IEventBus {
  private handlers = new Map<string, EventHandler[]>();
  
  subscribe(eventType: string, handler: EventHandler): void {
    const existing = this.handlers.get(eventType) || [];
    this.handlers.set(eventType, [...existing, handler]);
  }
  
  async publish(event: DomainEvent): Promise<void> {
    const handlers = this.handlers.get(event.type) || [];
    await Promise.all(handlers.map(h => h.handle(event)));
  }
}

// Later, swap to:
// shared/events/rabbitmq-event-bus.ts  (same IEventBus interface)
```
