# Event-Driven Patterns for Modular Monoliths

Patterns for in-process event-driven communication between modules, with a clear upgrade path to message brokers.

---

## Why Events in a Modular Monolith?

Events decouple modules temporally and logically. The publishing module doesn't know (or care) who handles its events. This enables:

- **Adding new behaviors without modifying existing modules** — a new Notification module can subscribe to `OrderPlacedEvent` without the Order module changing
- **Independent module evolution** — handlers can be added, removed, or rewritten without touching the publisher
- **Natural migration path** — the same event contracts work with in-process buses and message brokers

---

## Event Types

### Domain Events (Internal to a Module)

Events that represent something that happened within a single module's domain. These stay inside the module boundary.

```typescript
// order/domain/events/order-status-changed.event.ts
export class OrderStatusChangedEvent {
  constructor(
    public readonly orderId: string,
    public readonly previousStatus: OrderStatus,
    public readonly newStatus: OrderStatus,
    public readonly changedAt: Date,
  ) {}
}
```

**Usage**: Trigger side effects within the same module (e.g., update a read model, log an audit trail).

### Integration Events (Cross-Module)

Events published to communicate between modules. These are the events that travel through the event bus.

```typescript
// shared/contracts/events/order-placed.event.ts
export class OrderPlacedEvent {
  public readonly type = 'order.placed';
  constructor(
    public readonly orderId: string,
    public readonly customerId: string,
    public readonly items: Array<{ productId: string; quantity: number }>,
    public readonly total: number,
    public readonly occurredAt: Date,
  ) {}
}
```

**Rule**: Integration events live in the shared contracts directory. They contain only primitive types and IDs — never domain entities.

---

## In-Process Event Bus Implementations

### TypeScript / NestJS

```typescript
// shared/events/event-bus.interface.ts
export interface DomainEvent {
  readonly type: string;
  readonly occurredAt: Date;
}

export interface EventHandler<T extends DomainEvent = DomainEvent> {
  handle(event: T): Promise<void>;
}

export interface IEventBus {
  publish(event: DomainEvent): Promise<void>;
  publishAll(events: DomainEvent[]): Promise<void>;
  subscribe<T extends DomainEvent>(eventType: string, handler: EventHandler<T>): void;
}

// shared/events/in-memory-event-bus.ts
export class InMemoryEventBus implements IEventBus {
  private handlers = new Map<string, EventHandler[]>();

  subscribe<T extends DomainEvent>(eventType: string, handler: EventHandler<T>): void {
    const existing = this.handlers.get(eventType) || [];
    this.handlers.set(eventType, [...existing, handler]);
  }

  async publish(event: DomainEvent): Promise<void> {
    const handlers = this.handlers.get(event.type) || [];
    for (const handler of handlers) {
      await handler.handle(event);
    }
  }

  async publishAll(events: DomainEvent[]): Promise<void> {
    for (const event of events) {
      await this.publish(event);
    }
  }
}
```

### C# / .NET (MediatR)

```csharp
// Shared/Events/IDomainEvent.cs
public interface IDomainEvent : INotification
{
    Guid EventId { get; }
    DateTime OccurredAt { get; }
    string EventType { get; }
}

// Shared/Events/DomainEventBase.cs
public abstract record DomainEventBase : IDomainEvent
{
    public Guid EventId { get; } = Guid.NewGuid();
    public DateTime OccurredAt { get; } = DateTime.UtcNow;
    public abstract string EventType { get; }
}

// Order module publishes
await _mediator.Publish(new OrderPlacedEvent(order.Id, order.Total));

// Payment module handles
public class OrderPlacedHandler : INotificationHandler<OrderPlacedEvent>
{
    public async Task Handle(OrderPlacedEvent notification, CancellationToken ct)
    {
        await _paymentService.InitiatePayment(notification.OrderId, notification.Total);
    }
}
```

### Java / Spring Boot

```java
// Spring's ApplicationEventPublisher — built in, no extra libraries needed

// Shared event contract
public record OrderPlacedEvent(
    String orderId,
    String customerId,
    BigDecimal total,
    Instant occurredAt
) {}

// Order module publishes
@Service
public class OrderService {
    private final ApplicationEventPublisher eventPublisher;

    public void placeOrder(PlaceOrderCommand cmd) {
        Order order = orderRepository.save(Order.create(cmd));
        eventPublisher.publishEvent(new OrderPlacedEvent(
            order.getId(), order.getCustomerId(), order.getTotal(), Instant.now()
        ));
    }
}

// Payment module subscribes
@Component
public class PaymentEventHandler {
    @EventListener
    public void onOrderPlaced(OrderPlacedEvent event) {
        paymentService.initiatePayment(event.orderId(), event.total());
    }

    @TransactionalEventListener(phase = TransactionPhase.AFTER_COMMIT)
    public void onOrderPlacedAfterCommit(OrderPlacedEvent event) {
        // Runs only after the publishing transaction commits
        notificationService.notifyPaymentTeam(event.orderId());
    }
}
```

### Go

```go
// shared/events/bus.go
type Event interface {
    EventType() string
    OccurredAt() time.Time
}

type Handler func(ctx context.Context, event Event) error

type EventBus interface {
    Publish(ctx context.Context, event Event) error
    Subscribe(eventType string, handler Handler)
}

// shared/events/inmemory.go
type inMemoryBus struct {
    mu       sync.RWMutex
    handlers map[string][]Handler
}

func NewInMemoryBus() EventBus {
    return &inMemoryBus{handlers: make(map[string][]Handler)}
}

func (b *inMemoryBus) Subscribe(eventType string, handler Handler) {
    b.mu.Lock()
    defer b.mu.Unlock()
    b.handlers[eventType] = append(b.handlers[eventType], handler)
}

func (b *inMemoryBus) Publish(ctx context.Context, event Event) error {
    b.mu.RLock()
    handlers := b.handlers[event.EventType()]
    b.mu.RUnlock()
    for _, h := range handlers {
        if err := h(ctx, event); err != nil {
            return err
        }
    }
    return nil
}
```

### Python / Django

```python
# shared/events/bus.py
from abc import ABC, abstractmethod
from dataclasses import dataclass, field
from datetime import datetime
from typing import Callable, Dict, List
import uuid

@dataclass
class DomainEvent:
    event_id: str = field(default_factory=lambda: str(uuid.uuid4()))
    occurred_at: datetime = field(default_factory=datetime.utcnow)

    @property
    def event_type(self) -> str:
        return self.__class__.__name__

class EventBus(ABC):
    @abstractmethod
    def publish(self, event: DomainEvent) -> None: ...

    @abstractmethod
    def subscribe(self, event_type: str, handler: Callable) -> None: ...

# shared/events/in_memory.py
class InMemoryEventBus(EventBus):
    def __init__(self):
        self._handlers: Dict[str, List[Callable]] = {}

    def subscribe(self, event_type: str, handler: Callable) -> None:
        self._handlers.setdefault(event_type, []).append(handler)

    def publish(self, event: DomainEvent) -> None:
        for handler in self._handlers.get(event.event_type, []):
            handler(event)
```

---

## The Outbox Pattern

When events must be reliably delivered (no lost events, even if the app crashes), use the Outbox Pattern.

### Problem

Publishing an event after committing a transaction has a gap: the app can crash between commit and publish, losing the event.

### Solution

Store events in a database outbox table within the same transaction, then dispatch them asynchronously.

```
1. BEGIN TRANSACTION
2. Save business data (e.g., INSERT order)
3. Save event to outbox table (INSERT into outbox)
4. COMMIT TRANSACTION
5. Background worker reads outbox and publishes events
6. Worker marks events as dispatched
```

### Outbox Table Schema

```sql
CREATE TABLE shared.outbox (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    event_type VARCHAR(255) NOT NULL,
    payload JSONB NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    dispatched_at TIMESTAMP NULL,
    retry_count INT NOT NULL DEFAULT 0
);

CREATE INDEX idx_outbox_undispatched ON shared.outbox (created_at)
    WHERE dispatched_at IS NULL;
```

### Outbox Worker (TypeScript Example)

```typescript
export class OutboxDispatcher {
  constructor(
    private readonly db: DatabaseConnection,
    private readonly eventBus: IEventBus,
  ) {}

  async dispatchPending(): Promise<void> {
    const events = await this.db.query(
      `SELECT * FROM shared.outbox
       WHERE dispatched_at IS NULL
       ORDER BY created_at ASC
       LIMIT 100
       FOR UPDATE SKIP LOCKED`
    );

    for (const row of events) {
      const event = this.deserialize(row.event_type, row.payload);
      await this.eventBus.publish(event);
      await this.db.query(
        `UPDATE shared.outbox SET dispatched_at = NOW() WHERE id = $1`,
        [row.id]
      );
    }
  }
}
```

---

## Upgrading to a Message Broker

When extracting a module to a microservice, swap the in-process event bus for RabbitMQ, Kafka, or similar. The module code doesn't change because it depends on the `IEventBus` interface.

### Step 1: Create Broker Implementation

```typescript
// shared/events/rabbitmq-event-bus.ts
export class RabbitMQEventBus implements IEventBus {
  constructor(private readonly channel: Channel) {}

  async publish(event: DomainEvent): Promise<void> {
    this.channel.publish(
      'domain-events',
      event.type,
      Buffer.from(JSON.stringify(event)),
      { persistent: true }
    );
  }

  subscribe<T extends DomainEvent>(eventType: string, handler: EventHandler<T>): void {
    this.channel.consume(eventType, async (msg) => {
      const event = JSON.parse(msg.content.toString()) as T;
      await handler.handle(event);
      this.channel.ack(msg);
    });
  }
}
```

### Step 2: Swap in Composition Root

```typescript
// Before (in-process)
providers: [{ provide: 'IEventBus', useClass: InMemoryEventBus }]

// After (RabbitMQ for extracted module)
providers: [{ provide: 'IEventBus', useClass: RabbitMQEventBus }]
```

### Step 3: Handle Eventual Consistency

With a message broker, events are no longer instant. Consumers must handle:
- **Idempotency**: The same event may arrive more than once — use the `eventId` to deduplicate
- **Ordering**: Events may arrive out of order — design handlers to be order-independent, or partition by aggregate ID
- **Latency**: There's a delay between publish and consume — UI should not assume instant propagation

---

## Event Design Best Practices

| Guideline | Rationale |
|-----------|-----------|
| Use past tense for event names (`OrderPlaced`, not `PlaceOrder`) | Events describe what happened, not what should happen |
| Include only IDs and primitive data | Avoids coupling to another module's domain model |
| Include a unique `eventId` and `occurredAt` timestamp | Enables deduplication and ordering |
| Make events immutable | Events are facts — they cannot be changed after the fact |
| Version events when their schema changes | `OrderPlacedV2` or `order.placed.v2` prevents breaking existing consumers |
| Keep events small and focused | One event per state change; don't bundle unrelated changes |

---

## Common Anti-Patterns

### 1. Event as a Command
**Wrong**: Publishing `SendEmailEvent` — this is a command disguised as an event.
**Fix**: Publish `OrderPlacedEvent`. The Notification module decides to send an email.

### 2. Chatty Events
**Wrong**: Publishing an event for every field change (`PriceChangedEvent`, `NameChangedEvent`, `DescriptionChangedEvent`).
**Fix**: Publish one `ProductUpdatedEvent` with what changed.

### 3. Fat Events
**Wrong**: Including the entire aggregate in the event payload.
**Fix**: Include only the IDs and the data the consumers actually need. Consumers can query for more via the module contract.

### 4. Missing Idempotency
**Wrong**: Processing every received event without checking for duplicates.
**Fix**: Store processed `eventId`s and skip duplicates.
