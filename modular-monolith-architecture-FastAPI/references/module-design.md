# FastAPI Module Design Patterns

Detailed guidance on designing modules within a FastAPI Modular Monolith.

---

## Module Internal Architecture

Each module follows a consistent layered structure tailored to FastAPI:

```
module_name/
├── __init__.py
├── models/                 # SQLAlchemy ORM entities
│   ├── __init__.py
│   └── entity_name.py
├── schemas/                # Pydantic v2 schemas
│   ├── __init__.py
│   ├── requests.py         # Input validation schemas
│   ├── responses.py        # Output serialization schemas
│   └── dtos.py             # Internal data transfer objects
├── repositories/           # Data access layer
│   ├── __init__.py
│   └── entity_repo.py      # Extends BaseRepository
├── services/               # Business logic layer
│   ├── __init__.py
│   └── entity_service.py   # Orchestrates repos + events + external calls
├── routes/                 # API endpoints
│   ├── __init__.py
│   └── v1/                 # Versioned endpoints
│       ├── __init__.py
│       └── resource.py     # FastAPI router endpoints
├── dependencies/           # Dependency injection setup
│   ├── __init__.py
│   ├── repositories.py     # get_entity_repo()
│   └── services.py         # get_entity_service(), auth guards
├── gateway.py              # PUBLIC interface for other modules
├── events.py               # Domain event definitions
├── exceptions.py           # Module-specific exceptions
├── config.py               # Module-specific configuration
└── routers.py              # Module router aggregation
```

**Dependency rule**: routes → services → repositories → models. Gateway → services.

---

## Layer Details

### Models Layer (SQLAlchemy ORM)

```python
# app/articles/models/article.py
from sqlalchemy import Column, Integer, String, Text, ForeignKey, DateTime
from sqlalchemy.orm import relationship
from app.core.db.base_model import BaseModel, SoftDeleteMixin

class Article(BaseModel, SoftDeleteMixin):
    __tablename__ = "articles"

    id = Column(Integer, primary_key=True, autoincrement=True)
    title = Column(String(255), nullable=False)
    slug = Column(String(255), unique=True, nullable=False, index=True)
    body = Column(Text, nullable=False)
    description = Column(String(500))
    author_id = Column(Integer, nullable=False)  # Reference by ID, no FK to auth schema

    # Relations within the same module only
    tags = relationship("ArticleTag", back_populates="article", lazy="selectin")

    def is_author(self, user_id: int) -> bool:
        return self.author_id == user_id
```

**Rules**:
- Models inherit from `BaseModel` (provides `created_at`, `updated_at`)
- Use `SoftDeleteMixin` for entities that should not be hard-deleted
- Reference other modules by ID only — no SQLAlchemy ForeignKey across modules
- Keep domain logic in models where appropriate (e.g., `is_author()`)

### Schemas Layer (Pydantic v2)

```python
# app/articles/schemas/requests.py
from pydantic import BaseModel, Field

class ArticleCreateRequest(BaseModel):
    title: str = Field(..., min_length=1, max_length=255)
    body: str = Field(..., min_length=1)
    description: str | None = Field(None, max_length=500)
    tags: list[str] = Field(default_factory=list)

class ArticleUpdateRequest(BaseModel):
    title: str | None = Field(None, min_length=1, max_length=255)
    body: str | None = None
    description: str | None = Field(None, max_length=500)

# app/articles/schemas/responses.py
from pydantic import BaseModel
from datetime import datetime

class ArticleResponse(BaseModel):
    id: int
    title: str
    slug: str
    body: str
    description: str | None
    author_id: int
    created_at: datetime
    updated_at: datetime

    model_config = {"from_attributes": True}

# app/articles/schemas/dtos.py
from pydantic import BaseModel

class ArticleCreate(BaseModel):
    """Internal DTO — used between service and repository."""
    title: str
    slug: str
    body: str
    description: str | None
    author_id: int

class ArticleDTO(BaseModel):
    """DTO for cross-module communication via gateway."""
    id: int
    title: str
    slug: str
    author_id: int

    model_config = {"from_attributes": True}
```

**Rules**:
- **Requests**: Validate user input (min/max length, required fields)
- **Responses**: Serialize output (use `model_config = {"from_attributes": True}` for ORM)
- **DTOs**: Internal data transfer between layers and cross-module via gateways
- Never expose SQLAlchemy models directly in API responses

### Repository Layer (Data Access)

```python
# app/articles/repositories/article.py
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from app.core.db.base_repository import BaseRepository
from app.articles.models.article import Article
from app.articles.schemas.dtos import ArticleCreate, ArticleUpdate

class ArticleRepository(BaseRepository[Article, ArticleCreate, ArticleUpdate]):
    def __init__(self, session: AsyncSession):
        super().__init__(Article, session)

    async def get_by_slug(self, slug: str) -> Article | None:
        query = self._select_not_deleted().where(Article.slug == slug)
        result = await self.session.execute(query)
        return result.scalar_one_or_none()

    async def get_by_author(self, author_id: int, params) -> tuple[list[Article], int]:
        filters = {"author_id": author_id}
        return await self.get_list(params, filters=filters)

    async def slug_exists(self, slug: str) -> bool:
        query = select(Article.id).where(Article.slug == slug)
        result = await self.session.execute(query)
        return result.scalar_one_or_none() is not None
```

**Rules**:
- Extend `BaseRepository[ModelType, CreateSchemaType, UpdateSchemaType]`
- Base provides: `get()`, `get_list()`, `create()`, `update()`, `delete()`
- Add custom query methods specific to the domain
- Always use `self._select_not_deleted()` for soft-delete aware queries

### Service Layer (Business Logic)

```python
# app/articles/services/article.py
from slugify import slugify
from app.articles.repositories.article import ArticleRepository
from app.articles.schemas.dtos import ArticleCreate
from app.articles.schemas.requests import ArticleCreateRequest
from app.articles.events import ArticlePublished
from app.articles.exceptions import ArticleNotFound, SlugAlreadyExists
from app.core.services.events.interface import EventService

class ArticleService:
    def __init__(
        self,
        article_repo: ArticleRepository,
        events: EventService,
    ):
        self._repo = article_repo
        self._events = events

    async def create_article(
        self, request: ArticleCreateRequest, author_id: int
    ) -> Article:
        slug = slugify(request.title)
        if await self._repo.slug_exists(slug):
            raise SlugAlreadyExists(slug)

        dto = ArticleCreate(
            title=request.title,
            slug=slug,
            body=request.body,
            description=request.description,
            author_id=author_id,
        )
        article = await self._repo.create(dto)
        await self._repo.commit()

        self._events.dispatch(ArticlePublished(article_id=article.id, author_id=author_id))
        return article

    async def get_by_slug(self, slug: str) -> Article:
        article = await self._repo.get_by_slug(slug)
        if not article:
            raise ArticleNotFound(slug)
        return article

    async def delete_article(self, article_id: int, user_id: int) -> None:
        article = await self._repo.get(article_id)
        if not article:
            raise ArticleNotFound(article_id)
        if not article.is_author(user_id):
            raise PermissionError("Not the article author")
        await self._repo.delete(model=article, is_soft=True)
        await self._repo.commit()
```

**Rules**:
- Service orchestrates repositories, events, and cross-cutting services
- Never call another module's repository directly — use the gateway
- Dispatch domain events for cross-module side effects
- Handle authorization checks in the service layer

### Routes Layer (API Endpoints)

```python
# app/articles/routes/v1/articles.py
from fastapi import APIRouter, status
from app.articles.dependencies.services import ArticleServiceDep
from app.auth.dependencies.services import ActiveUser
from app.articles.schemas.requests import ArticleCreateRequest
from app.articles.schemas.responses import ArticleResponse
from app.core.api.schemas import Response

router = APIRouter()

@router.post("/", status_code=status.HTTP_201_CREATED)
async def create_article(
    request: ArticleCreateRequest,
    service: ArticleServiceDep,
    current_user: ActiveUser,
) -> Response[ArticleResponse]:
    article = await service.create_article(request, current_user.id)
    return Response(data=ArticleResponse.model_validate(article))

@router.get("/{slug}")
async def get_article(
    slug: str,
    service: ArticleServiceDep,
) -> Response[ArticleResponse]:
    article = await service.get_by_slug(slug)
    return Response(data=ArticleResponse.model_validate(article))

@router.delete("/{article_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_article(
    article_id: int,
    service: ArticleServiceDep,
    current_user: ActiveUser,
) -> None:
    await service.delete_article(article_id, current_user.id)
```

**Rules**:
- Routes are thin — delegate all logic to services
- Use `Annotated` dependency types for clean signatures
- Return standardized `Response[T]` wrapper
- Version routes via directory structure (`routes/v1/`, `routes/v2/`)

### Dependencies Layer (Dependency Injection)

```python
# app/articles/dependencies/repositories.py
from typing import Annotated
from fastapi import Depends
from app.core.deps import DBSessionDep
from app.articles.repositories.article import ArticleRepository

def get_article_repo(db: DBSessionDep) -> ArticleRepository:
    return ArticleRepository(db)

ArticleRepoDep = Annotated[ArticleRepository, Depends(get_article_repo)]

# app/articles/dependencies/services.py
from typing import Annotated
from fastapi import Depends
from app.articles.services.article import ArticleService
from app.articles.dependencies.repositories import ArticleRepoDep
from app.core.deps import EventServiceDep

def get_article_service(
    article_repo: ArticleRepoDep,
    events: EventServiceDep,
) -> ArticleService:
    return ArticleService(article_repo, events)

ArticleServiceDep = Annotated[ArticleService, Depends(get_article_service)]
```

---

## Inter-Module Communication

### Rule: Modules NEVER import each other's internals

```python
# ❌ WRONG — Direct import of internal type
from app.auth.models.user import User
from app.auth.repositories.user import UserRepository

# ✅ CORRECT — Import only from gateway
from app.auth.gateway import AuthGateway
from app.auth.schemas.dtos import UserDTO
```

### Gateway Pattern (Synchronous In-Process)

Each module exposes a gateway for other modules to use:

```python
# app/auth/gateway.py
from app.auth.schemas.dtos import UserDTO

class AuthGateway:
    """Public contract for the Auth module."""

    def __init__(self, user_service):
        self._user_service = user_service

    async def get_user_by_id(self, user_id: int) -> UserDTO | None:
        user = await self._user_service.get_by_id(user_id)
        return UserDTO.model_validate(user) if user else None

    async def is_user_active(self, user_id: int) -> bool:
        user = await self._user_service.get_by_id(user_id)
        return user is not None and user.is_active
```

Consumer usage:

```python
# app/articles/services/article.py
class ArticleService:
    def __init__(self, article_repo, auth_gateway: AuthGateway):
        self._repo = article_repo
        self._auth = auth_gateway

    async def create_article(self, request, author_id: int):
        # Use gateway — never access auth internals directly
        if not await self._auth.is_user_active(author_id):
            raise InactiveUserError()
        ...
```

### Domain Events (Asynchronous)

For operations where the caller doesn't need an immediate response:

```python
# app/articles/events.py
from dataclasses import dataclass

@dataclass
class ArticlePublished:
    __event_name__ = "article.published"
    article_id: int
    author_id: int

@dataclass
class ArticleDeleted:
    __event_name__ = "article.deleted"
    article_id: int

# In the service — publish event
self._events.dispatch(ArticlePublished(article_id=article.id, author_id=author_id))

# In another module — handle event
# app/notifications/listeners.py
from app.articles.events import ArticlePublished  # Events are part of the public contract

async def on_article_published(event: ArticlePublished):
    await notification_service.notify_followers(event.author_id, event.article_id)
```

---

## Database Schema Isolation

### Strategy: Per-Module Table Prefix or Schema

```python
# Each module owns its tables — no cross-module foreign keys
# app/articles/models/article.py
class Article(BaseModel):
    __tablename__ = "articles"  # Owned by articles module

# app/comments/models/comment.py
class Comment(BaseModel):
    __tablename__ = "comments"  # Owned by comments module
    article_id = Column(Integer, nullable=False)  # Reference by ID only, no FK
```

**Critical rule**: No SQLAlchemy `ForeignKey` constraints between modules. Use raw IDs.

### Migration Isolation

Each module's models are auto-discovered via `app/core/models.py`:

```python
# app/core/models.py — Import all models for Alembic to discover
from app.auth.models.user import User
from app.auth.models.refresh_token import RefreshToken
from app.articles.models.article import Article
from app.comments.models.comment import Comment
```

---

## Module Configuration

Each module can have its own settings:

```python
# app/auth/config.py
from pydantic_settings import BaseSettings

class AuthConfig(BaseSettings):
    JWT_SECRET_KEY: str = "change-me"
    JWT_ALGORITHM: str = "HS256"
    ACCESS_TOKEN_EXPIRE_MINUTES: int = 30
    REFRESH_TOKEN_EXPIRE_DAYS: int = 7
    PASSWORD_RESET_TOKEN_EXPIRE_HOURS: int = 1

    model_config = {"env_prefix": "AUTH_"}

auth_config = AuthConfig()
```

---

## Module Exceptions

```python
# app/articles/exceptions.py
from app.core.api.exceptions import GeneralException
from fastapi import status

class ArticleNotFound(GeneralException):
    def __init__(self, identifier):
        super().__init__(
            status_code=status.HTTP_404_NOT_FOUND,
            message=f"Article '{identifier}' not found",
        )

class SlugAlreadyExists(GeneralException):
    def __init__(self, slug: str):
        super().__init__(
            status_code=status.HTTP_409_CONFLICT,
            message=f"Article with slug '{slug}' already exists",
        )
```
