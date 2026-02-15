# Observability for Modular Monoliths

Logging, tracing, metrics, and health checks across module boundaries — while the app is still a single process.

---

## Why Observability Matters in a Modular Monolith

Even though everything runs in one process, a modular monolith has internal boundaries. Without observability:
- You can't tell which **module** caused a latency spike
- You can't trace a request **across module boundaries**
- You can't detect **boundary violations** happening at runtime
- You can't make data-driven decisions about **which module to extract**

---

## Structured Logging

### Module-Scoped Logging

Every log line should include the module name. This lets you filter logs per module — essential for debugging.

#### TypeScript / NestJS

```typescript
// shared/logging/module-logger.ts
export class ModuleLogger {
  constructor(
    private readonly logger: Logger,
    private readonly moduleName: string,
  ) {}

  log(message: string, context?: Record<string, unknown>) {
    this.logger.log({ message, module: this.moduleName, ...context });
  }

  error(message: string, error: Error, context?: Record<string, unknown>) {
    this.logger.error({
      message,
      module: this.moduleName,
      error: error.message,
      stack: error.stack,
      ...context,
    });
  }

  warn(message: string, context?: Record<string, unknown>) {
    this.logger.warn({ message, module: this.moduleName, ...context });
  }
}

// In each module
@Module({
  providers: [
    { provide: ModuleLogger, useFactory: (logger: Logger) =>
        new ModuleLogger(logger, 'product'), inject: [Logger] },
  ],
})
export class ProductModule {}
```

#### C# / .NET (Serilog)

```csharp
// Each module's service gets a scoped logger
public class ProductService
{
    private readonly ILogger<ProductService> _logger;

    public async Task<ProductDto?> GetProductById(string id)
    {
        using (_logger.BeginScope(new Dictionary<string, object>
        {
            ["Module"] = "Product",
            ["Operation"] = "GetProductById",
        }))
        {
            _logger.LogInformation("Fetching product {ProductId}", id);
            // ...
        }
    }
}

// Serilog configuration — enrich all logs with module context
Log.Logger = new LoggerConfiguration()
    .Enrich.WithProperty("Application", "MyApp")
    .WriteTo.Console(new JsonFormatter())
    .CreateLogger();
```

#### Java / Spring Boot

```java
// Use MDC (Mapped Diagnostic Context) for module tagging
@Service
public class ProductService {
    private static final Logger log = LoggerFactory.getLogger(ProductService.class);

    public ProductDto getProductById(String id) {
        MDC.put("module", "product");
        MDC.put("operation", "getProductById");
        try {
            log.info("Fetching product {}", id);
            // ...
        } finally {
            MDC.remove("module");
            MDC.remove("operation");
        }
    }
}
```

### Log Format Standard

Use structured JSON logs with these fields:

```json
{
  "timestamp": "2025-01-15T10:30:00.000Z",
  "level": "info",
  "module": "order",
  "operation": "placeOrder",
  "traceId": "abc123def456",
  "spanId": "span789",
  "message": "Order placed successfully",
  "orderId": "ord-001",
  "customerId": "cust-042",
  "durationMs": 45
}
```

---

## Distributed Tracing (In-Process)

Even within a single process, tracing inter-module calls reveals bottlenecks and dependency chains. Use OpenTelemetry — it works both in-process and across services (when you extract later).

### OpenTelemetry Setup

#### TypeScript

```typescript
// shared/tracing/setup.ts
import { NodeSDK } from '@opentelemetry/sdk-node';
import { OTLPTraceExporter } from '@opentelemetry/exporter-trace-otlp-http';

const sdk = new NodeSDK({
  serviceName: 'my-modular-app',
  traceExporter: new OTLPTraceExporter({
    url: process.env.OTEL_EXPORTER_OTLP_ENDPOINT || 'http://localhost:4318/v1/traces',
  }),
});

sdk.start();
```

### Tracing Module Calls

Wrap inter-module calls in spans to see the call chain.

```typescript
// shared/tracing/traced-module.ts
import { trace, SpanKind } from '@opentelemetry/api';

const tracer = trace.getTracer('modular-monolith');

export function traceModuleCall<T>(
  sourceModule: string,
  targetModule: string,
  operation: string,
  fn: () => Promise<T>,
): Promise<T> {
  return tracer.startActiveSpan(
    `${sourceModule} → ${targetModule}.${operation}`,
    { kind: SpanKind.INTERNAL,
      attributes: {
        'module.source': sourceModule,
        'module.target': targetModule,
        'module.operation': operation,
      },
    },
    async (span) => {
      try {
        const result = await fn();
        span.setStatus({ code: 0 }); // OK
        return result;
      } catch (error) {
        span.setStatus({ code: 2, message: error.message }); // ERROR
        span.recordException(error);
        throw error;
      } finally {
        span.end();
      }
    },
  );
}

// Usage in OrderModule
async placeOrder(cmd: PlaceOrderCommand) {
  const available = await traceModuleCall(
    'order', 'product', 'checkAvailability',
    () => this.productModule.checkAvailability(cmd.productId, cmd.quantity),
  );
  // ...
}
```

### Trace Visualization

With Jaeger or Zipkin, a traced request looks like:

```
[HTTP] POST /api/orders                          120ms
  └─ [order] placeOrder                          115ms
       ├─ [order → product] checkAvailability     12ms
       ├─ [order → product] getProductById         8ms
       ├─ [order] saveOrder (DB)                  35ms
       ├─ [eventbus] publish OrderPlacedEvent       2ms
       │    ├─ [payment] onOrderPlaced             25ms
       │    │    └─ [payment] savePayment (DB)     18ms
       │    └─ [notification] onOrderPlaced        15ms
       │         └─ [notification] queueEmail       5ms
       └─ [order] returnResponse                    1ms
```

---

## Metrics

### Per-Module Metrics

Track key indicators per module to understand where time and resources are spent.

```typescript
// shared/metrics/module-metrics.ts
import { Counter, Histogram } from 'prom-client';

export class ModuleMetrics {
  private readonly requestDuration: Histogram;
  private readonly requestCount: Counter;
  private readonly errorCount: Counter;

  constructor(moduleName: string) {
    this.requestDuration = new Histogram({
      name: 'module_request_duration_seconds',
      help: 'Duration of module operations',
      labelNames: ['module', 'operation'],
    });

    this.requestCount = new Counter({
      name: 'module_request_total',
      help: 'Total module operations',
      labelNames: ['module', 'operation'],
    });

    this.errorCount = new Counter({
      name: 'module_error_total',
      help: 'Total module errors',
      labelNames: ['module', 'operation', 'error_type'],
    });
  }

  trackOperation(operation: string) {
    const timer = this.requestDuration.startTimer({ module: this.moduleName, operation });
    this.requestCount.inc({ module: this.moduleName, operation });
    return {
      success: () => timer(),
      error: (errorType: string) => {
        timer();
        this.errorCount.inc({ module: this.moduleName, operation, error_type: errorType });
      },
    };
  }
}
```

### Key Metrics to Track

| Metric | Type | Labels | Purpose |
|--------|------|--------|---------|
| `module_request_duration_seconds` | Histogram | module, operation | Find slow modules/operations |
| `module_request_total` | Counter | module, operation | Traffic distribution across modules |
| `module_error_total` | Counter | module, operation, error_type | Error hotspots |
| `module_event_published_total` | Counter | module, event_type | Event traffic |
| `module_event_processing_duration_seconds` | Histogram | module, event_type | Slow event handlers |
| `module_db_query_duration_seconds` | Histogram | module, query_type | DB bottlenecks per module |

### Extraction Decision Metrics

These metrics directly inform the decision to extract a module:

| Metric | Extraction Signal |
|--------|------------------|
| Module accounts for >60% of total CPU/memory | Scaling divergence |
| Module latency p99 is 10x higher than others | Performance bottleneck |
| Module error rate is significantly higher | Fault isolation needed |
| Module deploys trigger full regression testing | Team autonomy demand |

---

## Health Checks

### Per-Module Health Checks

Each module registers its own health check. The aggregate health endpoint calls all of them.

#### TypeScript

```typescript
// shared/health/health.interface.ts
export interface ModuleHealthCheck {
  moduleName: string;
  check(): Promise<HealthResult>;
}

export interface HealthResult {
  status: 'healthy' | 'degraded' | 'unhealthy';
  details?: Record<string, unknown>;
}

// product/infrastructure/product-health.ts
export class ProductHealthCheck implements ModuleHealthCheck {
  moduleName = 'product';

  constructor(private readonly db: ProductDbContext) {}

  async check(): Promise<HealthResult> {
    try {
      await this.db.query('SELECT 1');
      return { status: 'healthy' };
    } catch (error) {
      return { status: 'unhealthy', details: { error: error.message } };
    }
  }
}

// Host health endpoint — aggregates all modules
@Get('/health')
async healthCheck(@Inject('MODULE_HEALTH_CHECKS') checks: ModuleHealthCheck[]) {
  const results = await Promise.all(
    checks.map(async (check) => ({
      module: check.moduleName,
      ...await check.check(),
    }))
  );

  const overallStatus = results.every(r => r.status === 'healthy')
    ? 'healthy'
    : results.some(r => r.status === 'unhealthy')
      ? 'unhealthy'
      : 'degraded';

  return { status: overallStatus, modules: results };
}
```

#### Health Check Response

```json
{
  "status": "healthy",
  "modules": [
    { "module": "product", "status": "healthy" },
    { "module": "order", "status": "healthy" },
    { "module": "payment", "status": "healthy" },
    { "module": "notification", "status": "degraded", "details": { "emailQueue": "backlogged" } }
  ]
}
```

#### C# / .NET

```csharp
// Each module registers its health check
public static IServiceCollection AddProductModule(this IServiceCollection services, IConfiguration config)
{
    // ... other registrations
    services.AddHealthChecks()
        .AddDbContextCheck<ProductDbContext>("product-db")
        .AddCheck<ProductCacheHealthCheck>("product-cache");
    return services;
}

// Host/Program.cs
app.MapHealthChecks("/health", new HealthCheckOptions
{
    ResponseWriter = async (context, report) =>
    {
        var result = new
        {
            status = report.Status.ToString(),
            modules = report.Entries.Select(e => new
            {
                module = e.Key,
                status = e.Value.Status.ToString(),
                details = e.Value.Description,
            }),
        };
        await context.Response.WriteAsJsonAsync(result);
    },
});
```

---

## Event Bus Observability

Track events flowing through the system to debug async issues.

```typescript
// shared/events/observable-event-bus.ts
export class ObservableEventBus implements IEventBus {
  constructor(
    private readonly inner: IEventBus,
    private readonly logger: ModuleLogger,
    private readonly metrics: ModuleMetrics,
  ) {}

  async publish(event: DomainEvent): Promise<void> {
    this.logger.log('Event published', {
      eventType: event.type,
      eventId: event.eventId,
    });
    this.metrics.eventPublished(event.type);
    const start = Date.now();

    await this.inner.publish(event);

    this.logger.log('Event handled', {
      eventType: event.type,
      eventId: event.eventId,
      durationMs: Date.now() - start,
    });
  }
}
```

---

## Docker Compose with Observability Stack

```yaml
# docker-compose.observability.yml
services:
  app:
    build: .
    environment:
      - OTEL_EXPORTER_OTLP_ENDPOINT=http://jaeger:4318
      - METRICS_ENDPOINT=http://prometheus:9090
    ports:
      - "3000:3000"

  jaeger:
    image: jaegertracing/all-in-one:latest
    ports:
      - "16686:16686"  # UI
      - "4318:4318"    # OTLP HTTP

  prometheus:
    image: prom/prometheus:latest
    volumes:
      - ./prometheus.yml:/etc/prometheus/prometheus.yml
    ports:
      - "9090:9090"

  grafana:
    image: grafana/grafana:latest
    ports:
      - "3001:3000"
    environment:
      - GF_SECURITY_ADMIN_PASSWORD=admin
```

---

## Observability Checklist for New Modules

When generating a new module, include:

```
☐ Module-scoped logger with structured JSON output
☐ ModuleMetrics instance tracking request duration, count, errors
☐ Health check registered in the host's aggregate health endpoint
☐ OpenTelemetry spans on inter-module calls
☐ Event bus logging for published and consumed events
```
