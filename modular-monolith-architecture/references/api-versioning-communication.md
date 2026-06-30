# API Versioning & Module Communication Patterns

Patterns for inter-module communication and strategies for evolving module contracts without breaking consumers.

---

## Communication Patterns

### Synchronous Communication (In-Process Calls)

Modules call each other through injected interfaces. The call is in-process (nanosecond latency, shared transaction context).

```
OrderModule ──calls──▶ IProductModule.checkAvailability()
                              │
                     (resolved at startup via DI)
                              │
                     ProductService (implementation)
```

#### When to Use Synchronous
- The caller **needs an immediate response** to continue its operation
- The operation is part of a **single transaction** (e.g., check stock before placing order)
- The data is **read-only** from the target module's perspective

#### When to Avoid Synchronous
- The operation is a **side effect** (sending email, updating analytics)
- The operation can be **deferred** without affecting the user experience
- The operation involves a **long-running process** (report generation)

### Asynchronous Communication (Events)

Modules publish events. Other modules subscribe to them. The publisher doesn't know or care who listens.

```
OrderModule ──publishes──▶ OrderPlacedEvent ──▶ EventBus
                                                  │
                               ┌──────────────────┼──────────────────┐
                               ▼                  ▼                  ▼
                        PaymentModule      InventoryModule     NotificationModule
                     (initiate payment)   (reserve stock)     (send confirmation)
```

#### When to Use Asynchronous
- The operation is a **side effect** of the main action
- Multiple modules need to **react** to the same event
- The operation can tolerate **eventual consistency**
- You want to **decouple** modules from knowing about each other

### Choosing Between Sync and Async

| Scenario | Pattern | Reason |
|----------|---------|--------|
| Check product availability before placing order | Sync | Need the answer now to validate |
| Notify payment module after order placed | Async | Side effect, doesn't block order creation |
| Get user profile for display | Sync | Need data to render the response |
| Update search index after product change | Async | Can tolerate brief staleness |
| Reserve inventory during checkout | Sync | Must be atomic with the order |
| Send welcome email after registration | Async | Non-critical, can retry independently |

---

## Module Contract Design

### Contract Structure

Every module exposes a public contract — an interface that defines what operations other modules can use.

```typescript
// product/api/product-module.interface.ts

/** Public API for the Product module. Other modules depend ONLY on this interface. */
export interface IProductModule {
  // ── Queries ──────────────────────────────────────────────
  getProductById(id: string): Promise<ProductDto | null>;
  getProductsByIds(ids: string[]): Promise<ProductDto[]>;
  searchProducts(query: SearchQuery): Promise<PagedResult<ProductSummaryDto>>;

  // ── Commands ─────────────────────────────────────────────
  checkAvailability(productId: string, quantity: number): Promise<boolean>;
  reserveStock(productId: string, quantity: number): Promise<ReservationDto>;
  releaseReservation(reservationId: string): Promise<void>;
}
```

### DTO Design Rules

| Rule | Rationale |
|------|-----------|
| Use primitives and simple objects only | Avoids coupling to domain entities |
| Include only what consumers need | Don't expose internal fields (e.g., `internalSku`, `costPrice`) |
| Use `readonly` properties | DTOs are data snapshots, not mutable objects |
| Define DTOs in the shared contracts or the module's `api/` directory | Consumers import from the public surface |

```typescript
// shared/contracts/product.dto.ts
export interface ProductDto {
  readonly id: string;
  readonly name: string;
  readonly price: number;
  readonly currency: string;
  readonly available: boolean;
}

// NOT this — exposes domain internals
export interface ProductDto {
  readonly id: string;
  readonly name: string;
  readonly price: number;
  readonly costPrice: number;       // ❌ Internal business data
  readonly internalSku: string;     // ❌ Internal identifier
  readonly dbCreatedAt: Date;       // ❌ Infrastructure detail
}
```

---

## Contract Versioning

When a module's contract needs to change, version it to avoid breaking consumers.

### Strategy 1: Additive Changes (Preferred)

Add new fields or methods without removing existing ones. This is backward-compatible.

```typescript
// v1 — original
export interface ProductDto {
  readonly id: string;
  readonly name: string;
  readonly price: number;
}

// v1.1 — additive (backward-compatible)
export interface ProductDto {
  readonly id: string;
  readonly name: string;
  readonly price: number;
  readonly category?: string;          // New optional field
  readonly discountPercentage?: number; // New optional field
}
```

**Rule**: New fields must be optional (`?`). Consumers that don't know about them continue working.

### Strategy 2: Interface Versioning (Breaking Changes)

When you must remove or rename fields, create a new version of the interface.

```typescript
// product/api/product-module.interface.ts
export interface IProductModule {
  // Keep the old method
  getProductById(id: string): Promise<ProductDto | null>;

  // Add the new version alongside
  getProductByIdV2(id: string): Promise<ProductDetailDto | null>;
}

// Deprecation timeline:
// 1. Add V2 method, mark V1 as deprecated
// 2. Migrate all consumers to V2
// 3. Remove V1 in a later release
```

### Strategy 3: Event Versioning

For integration events, version the event type.

```typescript
// v1 — original
export class OrderPlacedEvent {
  public readonly type = 'order.placed.v1';
  constructor(
    public readonly orderId: string,
    public readonly total: number,
  ) {}
}

// v2 — breaking change (total split into subtotal + tax)
export class OrderPlacedEventV2 {
  public readonly type = 'order.placed.v2';
  constructor(
    public readonly orderId: string,
    public readonly subtotal: number,
    public readonly tax: number,
    public readonly total: number,  // Keep for backward compat
  ) {}
}
```

**Migration approach**:
1. Publish both v1 and v2 simultaneously during the transition
2. Migrate consumers from v1 to v2
3. Stop publishing v1 once all consumers have migrated

---

## Cross-Module Query Patterns

### Pattern 1: Direct Contract Call (Simple)

For simple lookups, call the module contract directly.

```typescript
// In OrderModule
async getOrderWithProducts(orderId: string): Promise<OrderWithProductsDto> {
  const order = await this.orderRepo.findById(orderId);
  const products = await this.productModule.getProductsByIds(
    order.items.map(i => i.productId)
  );
  return this.mapToDto(order, products);
}
```

### Pattern 2: Local Cache / Read Model (Performance)

When a module frequently queries another module's data, maintain a local read model updated via events.

```typescript
// In OrderModule — local product cache updated by events
@EventHandler('product.price.changed')
async onProductPriceChanged(event: ProductPriceChangedEvent) {
  await this.productCache.update(event.productId, { price: event.newPrice });
}

// Queries use the local cache instead of calling ProductModule
async getOrderTotal(orderId: string): Promise<number> {
  const order = await this.orderRepo.findById(orderId);
  let total = 0;
  for (const item of order.items) {
    const product = await this.productCache.get(item.productId); // Local lookup
    total += product.price * item.quantity;
  }
  return total;
}
```

**Trade-off**: Eventual consistency — the local cache may be briefly stale.

### Pattern 3: Dedicated Reporting Module (Complex Queries)

For queries that span many modules (dashboards, reports, analytics), create a dedicated Reporting module.

```
OrderModule ──event──▶ ┌─────────────────────┐
ProductModule ──event──▶│  Reporting Module    │──▶ Dashboard API
PaymentModule ──event──▶│  (denormalized read  │
ShippingModule ──event──▶│   model / views)     │
                        └─────────────────────┘
```

The Reporting module:
- Subscribes to events from all modules
- Maintains denormalized read models optimized for queries
- Has read-only access — never modifies business data
- Can use cross-module JOINs in its own schema (because it owns the denormalized data)

---

## Error Handling Across Module Boundaries

### Synchronous Errors

Define explicit error types in the module contract.

**Go:** put package-level sentinel errors (`var ErrNotFound = errors.New(...)`) in the module's `api/` package so callers can `errors.Is` them, not in `internal/domain` (which other modules cannot import).

```typescript
// product/api/errors.ts — part of the public contract
export class ProductNotFoundError extends Error {
  constructor(public readonly productId: string) {
    super(`Product ${productId} not found`);
  }
}

export class InsufficientStockError extends Error {
  constructor(
    public readonly productId: string,
    public readonly requested: number,
    public readonly available: number,
  ) {
    super(`Insufficient stock for ${productId}: requested ${requested}, available ${available}`);
  }
}
```

### Asynchronous Errors

Event handlers must handle their own errors. Failed handlers should not affect the publisher or other subscribers.

```typescript
// In the event bus implementation
async publish(event: DomainEvent): Promise<void> {
  const handlers = this.handlers.get(event.type) || [];
  const results = await Promise.allSettled(
    handlers.map(h => h.handle(event))
  );

  for (const result of results) {
    if (result.status === 'rejected') {
      this.logger.error(`Event handler failed for ${event.type}`, result.reason);
      await this.deadLetterQueue.enqueue(event, result.reason);
    }
  }
}
```

---

## Communication Anti-Patterns

### 1. Chain of Synchronous Calls
**Wrong**: Module A → Module B → Module C → Module D (all synchronous, all blocking).
**Fix**: Use events for non-critical steps. Only synchronous calls for data you need immediately.

### 2. Bidirectional Dependencies
**Wrong**: Module A calls Module B, and Module B calls Module A.
**Fix**: Extract the shared concern into a new module, or convert one direction to events.

### 3. Passing Domain Entities Across Boundaries
**Wrong**: `IProductModule.getProduct()` returns a `Product` entity with methods and internal state.
**Fix**: Return a `ProductDto` — a flat data structure with no behavior.

### 4. Leaking Transaction Context
**Wrong**: Module A starts a transaction, calls Module B, expects both to rollback together.
**Fix**: Each module manages its own transactions. Use sagas or compensating actions for cross-module consistency.

### 5. Event Sourcing Without Need
**Wrong**: Using event sourcing for all modules because "we use events."
**Fix**: Events for communication (integration events) and event sourcing (domain pattern) are different things. Use event sourcing only when you need full audit history or temporal queries.
