# FastAPI Event-Driven Patterns

In-process event-driven communication between modules using fastapi-events, with upgrade paths to Kafka/RabbitMQ.

---

## Why Events in a FastAPI Modular Monolith?

Events decouple modules temporally and logically. The publishing module doesn't know (or care) who handles its events. This enables:

- **Adding new behaviors without modifying existing modules** — a new Notification module can subscribe to `ArticlePublished` without the Articles module changing
- **Independent module evolution** — handlers can be added, removed, or rewritten without touching the publisher
- **Natural migration path** — the same event contracts work with in-process dispatch and message brokers

---

## Event Types

### Domain Events (Internal to a Module)

Events that represent something that happened within a single module's domain. Stay inside the module boundary.

```python
# app/articles/events.py (internal to articles module)
from dataclasses import dataclass

@dataclass
class ArticleDraftSaved:
    """Internal event — triggers auto-save behavior within articles module."""
    __event_name__ = "article.draft_saved"
    article_id: int
    version: int
```

### Integration Events (Cross-Module)

Events published to communicate between modules. Travel through the event bus.

```python
# app/articles/events.py (public contract — other modules can import)
from dataclasses import dataclass

@dataclass
class ArticlePublished:
    """Published when an article goes live. Other modules can react."""
    __event_name__ = "article.published"
    article_id: int
    author_id: int
    title: str

@dataclass
class ArticleDeleted:
    __event_name__ = "article.deleted"
    article_id: int
```

**Rule**: Integration events use only primitive types and IDs — never domain entities.

---

## Implementation with fastapi-events

### Event Service Interface

```python
# app/core/services/events/interface.py
from abc import ABC, abstractmethod

class EventService(ABC):
    @abstractmethod
    def dispatch(self, event) -> None:
        """Dispatch a domain event."""
        ...
```

### fastapi-events Provider

```python
# app/core/services/events/provider.py
from fastapi_events.dispatcher import dispatch as fastapi_dispatch
from app.core.services.events.interface import EventService

class FastAPIEventService(EventService):
    def dispatch(self, event) -> None:
        event_name = getattr(event, "__event_name__", event.__class__.__name__)
        fastapi_dispatch(event_name, payload=event)
```

### Registering Listeners

```python
# app/core/listeners.py
from fastapi import FastAPI
from fastapi_events.handlers.local import local_handler
from fastapi_events.middleware import EventHandlerASGIMiddleware

def register_listeners(app: FastAPI) -> None:
    """Register all event listeners across modules."""
    app.add_middleware(EventHandlerASGIMiddleware, handlers=[local_handler])

    # Auth module listeners
    from app.auth.events import UserCreated

    @local_handler.register(event_name="user.created")
    async def handle_user_created(event):
        event_name, payload = event
        # Forward to notification module, analytics, etc.
        pass

    # Articles module listeners
    from app.articles.events import ArticlePublished

    @local_handler.register(event_name="article.published")
    async def handle_article_published(event):
        event_name, payload = event
        # Notify followers, update search index, etc.
        pass
```

### Publishing Events from Services

```python
# app/articles/services/article.py
class ArticleService:
    def __init__(self, article_repo, events: EventService):
        self._repo = article_repo
        self._events = events

    async def publish_article(self, article_id: int, user_id: int):
        article = await self._repo.get(article_id)
        if not article:
            raise ArticleNotFound(article_id)

        article.status = "published"
        await self._repo.commit()

        # Dispatch event — listeners react asynchronously
        self._events.dispatch(ArticlePublished(
            article_id=article.id,
            author_id=user_id,
            title=article.title,
        ))
```

---

## Event Definitions Best Practices

```python
# app/auth/events.py
from dataclasses import dataclass, field
from datetime import datetime
import uuid

@dataclass
class UserCreated:
    __event_name__ = "user.created"
    user_id: int
    email: str
    event_id: str = field(default_factory=lambda: str(uuid.uuid4()))
    occurred_at: datetime = field(default_factory=datetime.utcnow)

@dataclass
class UserDeleted:
    __event_name__ = "user.deleted"
    user_id: int
    event_id: str = field(default_factory=lambda: str(uuid.uuid4()))
    occurred_at: datetime = field(default_factory=datetime.utcnow)
```

### Event Design Rules

| Guideline | Rationale |
|-----------|-----------|
| Use past tense (`UserCreated`, not `CreateUser`) | Events describe what happened |
| Include only IDs and primitive data | Avoids coupling to another module's domain model |
| Include `event_id` and `occurred_at` | Enables deduplication and ordering |
| Make events immutable (`@dataclass(frozen=True)`) | Events are facts |
| Add `__event_name__` attribute | Used by fastapi-events for routing |

---

## Background Task Queue Integration

For events that trigger long-running operations (sending emails, generating reports), use Taskiq:

```python
# app/core/services/queue/provider.py
from taskiq import AsyncBroker
from taskiq_redis import ListQueueBroker

broker = ListQueueBroker(redis_url="redis://localhost:6379")

# app/auth/tasks.py
from app.core.services.queue.provider import broker

@broker.task(task_name="send_welcome_email")
async def send_welcome_email(user_id: int, email: str):
    """Background task triggered by UserCreated event."""
    from app.core.services.mail.provider import mail_service
    await mail_service.send(
        to=email,
        subject="Welcome!",
        template="welcome.html",
        context={"user_id": user_id},
    )

# In the event listener
@local_handler.register(event_name="user.created")
async def handle_user_created(event):
    event_name, payload = event
    await send_welcome_email.kiq(payload.user_id, payload.email)
```

---

## Upgrading to a Message Broker

When extracting a module to a microservice, swap the in-process event dispatch for Kafka or RabbitMQ. Module code doesn't change because it depends on the `EventService` interface.

### Step 1: Create Broker Implementation

```python
# app/core/services/events/kafka_provider.py
from aiokafka import AIOKafkaProducer
import json
from app.core.services.events.interface import EventService

class KafkaEventService(EventService):
    def __init__(self, producer: AIOKafkaProducer):
        self._producer = producer

    async def dispatch(self, event) -> None:
        event_name = getattr(event, "__event_name__", event.__class__.__name__)
        payload = json.dumps(event.__dict__, default=str).encode()
        await self._producer.send(event_name, payload)
```

### Step 2: Swap in Dependency Injection

```python
# Before (in-process)
def get_event_service() -> EventService:
    return FastAPIEventService()

# After (Kafka for extracted module)
def get_event_service() -> EventService:
    return KafkaEventService(kafka_producer)
```

### Step 3: Handle Eventual Consistency

With a message broker, events are no longer instant:
- **Idempotency**: Use `event_id` to deduplicate
- **Ordering**: Design handlers to be order-independent or partition by entity ID
- **Latency**: UI should not assume instant propagation

---

## The Outbox Pattern (Reliable Events)

For critical events that must not be lost:

```python
# Store event in the same transaction as business data
class ArticleService:
    async def publish_article(self, article_id: int):
        article = await self._repo.get(article_id)
        article.status = "published"

        # Save event to outbox table in the same transaction
        outbox_entry = OutboxMessage(
            event_type="article.published",
            payload={"article_id": article.id, "author_id": article.author_id},
        )
        self._session.add(outbox_entry)
        await self._repo.commit()  # Both saved atomically

# Background worker dispatches from outbox
async def dispatch_outbox_events():
    pending = await outbox_repo.get_undispatched(limit=100)
    for entry in pending:
        events.dispatch(deserialize_event(entry))
        entry.dispatched_at = datetime.utcnow()
    await outbox_repo.commit()
```

---

## Common Anti-Patterns

### 1. Event as a Command
**Wrong**: `SendEmailEvent` — this is a command disguised as an event.
**Fix**: Publish `UserCreated`. The Notification module decides to send an email.

### 2. Fat Events
**Wrong**: Including the entire SQLAlchemy model in the event payload.
**Fix**: Include only IDs and the data consumers actually need.

### 3. Sync Event Handling
**Wrong**: Handling events synchronously in the request cycle, blocking the response.
**Fix**: Use `fastapi-events` for fire-and-forget, or Taskiq for heavy processing.

### 4. Missing Idempotency
**Wrong**: Processing every received event without checking for duplicates.
**Fix**: Store processed `event_id`s and skip duplicates.
