# FastAPI Database Patterns

SQLAlchemy 2.0 async patterns, Alembic migrations, and the generic repository for FastAPI Modular Monoliths.

---

## Async SQLAlchemy Setup

### Engine & Session Factory

```python
# app/core/db/session.py
from sqlalchemy.ext.asyncio import create_async_engine, async_sessionmaker, AsyncSession
from app.core.configs.app import app_config

engine = create_async_engine(
    app_config.POSTGRES_URL,
    pool_size=5,
    max_overflow=10,
    echo=app_config.SQL_ECHO,
)

async_session = async_sessionmaker(
    bind=engine,
    class_=AsyncSession,
    expire_on_commit=False,
)

async def get_session() -> AsyncSession:
    async with async_session() as session:
        yield session
```

### Configuration

```python
# app/core/configs/app.py
from pydantic_settings import BaseSettings
from pydantic import computed_field

class AppConfig(BaseSettings):
    ENVIRONMENT: str = "local"

    # Database
    POSTGRES_HOST: str = "localhost"
    POSTGRES_PORT: int = 5432
    POSTGRES_USER: str = "postgres"
    POSTGRES_PASSWORD: str = "postgres"
    POSTGRES_DB: str = "my_app"
    SQL_ECHO: bool = False

    # Redis
    REDIS_HOST: str = "localhost"
    REDIS_PORT: int = 6379

    @computed_field
    @property
    def POSTGRES_URL(self) -> str:
        return (
            f"postgresql+asyncpg://{self.POSTGRES_USER}:{self.POSTGRES_PASSWORD}"
            f"@{self.POSTGRES_HOST}:{self.POSTGRES_PORT}/{self.POSTGRES_DB}"
        )

    @computed_field
    @property
    def REDIS_URL(self) -> str:
        return f"redis://{self.REDIS_HOST}:{self.REDIS_PORT}"

    model_config = {"env_file": ".env", "env_file_encoding": "utf-8"}

app_config = AppConfig()
```

---

## Base Model with Timestamps & Soft Deletes

```python
# app/core/db/base_model.py
from datetime import datetime
from sqlalchemy import Column, DateTime, func
from sqlalchemy.orm import DeclarativeBase

class BaseModel(DeclarativeBase):
    """Base model with automatic timestamps."""

    created_at = Column(DateTime, default=func.now(), nullable=False)
    updated_at = Column(DateTime, default=func.now(), onupdate=func.now(), nullable=False)

    def to_dict(self) -> dict:
        return {c.name: getattr(self, c.name) for c in self.__table__.columns}

    def update(self, **kwargs) -> None:
        for key, value in kwargs.items():
            if hasattr(self, key) and value is not None:
                setattr(self, key, value)


class SoftDeleteMixin:
    """Mixin for soft delete support."""

    deleted_at = Column(DateTime, nullable=True, default=None)

    @property
    def is_deleted(self) -> bool:
        return self.deleted_at is not None

    def soft_delete(self) -> None:
        self.deleted_at = datetime.utcnow()
```

---

## Generic Base Repository

```python
# app/core/db/base_repository.py
from typing import Generic, TypeVar, Type, Sequence
from sqlalchemy import select, func, asc, desc
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import joinedload, selectinload
from pydantic import BaseModel as PydanticModel
from app.core.db.base_model import BaseModel, SoftDeleteMixin

ModelType = TypeVar("ModelType", bound=BaseModel)
CreateSchemaType = TypeVar("CreateSchemaType", bound=PydanticModel)
UpdateSchemaType = TypeVar("UpdateSchemaType", bound=PydanticModel)


class BaseRepository(Generic[ModelType, CreateSchemaType, UpdateSchemaType]):
    """Generic async repository with CRUD, pagination, filtering, sorting, soft deletes."""

    def __init__(self, model: Type[ModelType], session: AsyncSession):
        self.model = model
        self.session = session

    def _select_not_deleted(self):
        """Base query excluding soft-deleted records."""
        query = select(self.model)
        if issubclass(self.model, SoftDeleteMixin):
            query = query.where(self.model.deleted_at.is_(None))
        return query

    async def get(
        self,
        model_id: int,
        with_deleted: bool = False,
        relations: list[str] | None = None,
    ) -> ModelType | None:
        query = select(self.model) if with_deleted else self._select_not_deleted()
        query = query.where(self.model.id == model_id)
        if relations:
            query = self._load_relations(query, relations)
        result = await self.session.execute(query)
        return result.scalar_one_or_none()

    async def get_list(
        self,
        params: dict | None = None,
        filters: dict | None = None,
        with_deleted: bool = False,
        relations: list[str] | None = None,
    ) -> tuple[Sequence[ModelType], int]:
        query = select(self.model) if with_deleted else self._select_not_deleted()

        if filters:
            query = self._apply_filters(query, filters)
        if relations:
            query = self._load_relations(query, relations)
        if params:
            query = self._apply_sort(query, params)

        total = await self._count(query)

        if params:
            query = self._apply_pagination(query, params)

        result = await self.session.execute(query)
        return result.scalars().all(), total

    async def create(self, data: CreateSchemaType) -> ModelType:
        instance = self.model(**data.model_dump())
        self.session.add(instance)
        await self.session.flush()
        await self.session.refresh(instance)
        return instance

    async def update(self, model: ModelType, data: UpdateSchemaType) -> ModelType:
        update_data = data.model_dump(exclude_unset=True)
        model.update(**update_data)
        await self.session.flush()
        await self.session.refresh(model)
        return model

    async def delete(
        self,
        model_id: int | None = None,
        model: ModelType | None = None,
        is_soft: bool = True,
    ) -> None:
        if model is None:
            model = await self.get(model_id)
        if model is None:
            return

        if is_soft and isinstance(model, SoftDeleteMixin):
            model.soft_delete()
        else:
            await self.session.delete(model)
        await self.session.flush()

    async def commit(self) -> None:
        await self.session.commit()

    async def flush(self) -> None:
        await self.session.flush()

    async def refresh(self, model: ModelType) -> None:
        await self.session.refresh(model)

    # --- Private helpers ---

    def _apply_filters(self, query, filters: dict):
        for field, value in filters.items():
            if hasattr(self.model, field):
                query = query.where(getattr(self.model, field) == value)
        return query

    def _apply_sort(self, query, params: dict):
        sort_field = params.get("sort_by", "id")
        sort_order = params.get("sort_order", "asc")
        if hasattr(self.model, sort_field):
            column = getattr(self.model, sort_field)
            query = query.order_by(desc(column) if sort_order == "desc" else asc(column))
        return query

    def _apply_pagination(self, query, params: dict):
        page = params.get("page", 1)
        per_page = params.get("per_page", 20)
        offset = (page - 1) * per_page
        return query.offset(offset).limit(per_page)

    async def _count(self, query) -> int:
        count_query = select(func.count()).select_from(query.subquery())
        result = await self.session.execute(count_query)
        return result.scalar_one()

    def _load_relations(self, query, relations: list[str]):
        for relation in relations:
            if hasattr(self.model, relation):
                query = query.options(selectinload(getattr(self.model, relation)))
        return query
```

---

## Alembic Migration Setup

### alembic.ini

```ini
[alembic]
script_location = migrations
sqlalchemy.url = postgresql+asyncpg://postgres:postgres@localhost:5432/my_app

[loggers]
keys = root,sqlalchemy,alembic

[handlers]
keys = console

[formatters]
keys = generic

[logger_root]
level = WARN
handlers = console

[logger_sqlalchemy]
level = WARN
handlers =
qualname = sqlalchemy.engine

[logger_alembic]
level = INFO
handlers =
qualname = alembic

[handler_console]
class = StreamHandler
args = (sys.stderr,)
level = NOTSET
formatter = generic

[formatter_generic]
format = %(levelname)-5.5s [%(name)s] %(message)s
datefmt = %H:%M:%S
```

### migrations/env.py

```python
import asyncio
from logging.config import fileConfig
from sqlalchemy import pool
from sqlalchemy.ext.asyncio import create_async_engine
from alembic import context

# Import all models so Alembic can discover them
from app.core.db.base_model import BaseModel
import app.core.models  # noqa: F401 — triggers model imports

config = context.config
if config.config_file_name is not None:
    fileConfig(config.config_file_name)

target_metadata = BaseModel.metadata


def run_migrations_offline() -> None:
    url = config.get_main_option("sqlalchemy.url")
    context.configure(url=url, target_metadata=target_metadata, literal_binds=True)
    with context.begin_transaction():
        context.run_migrations()


def do_run_migrations(connection):
    context.configure(connection=connection, target_metadata=target_metadata)
    with context.begin_transaction():
        context.run_migrations()


async def run_migrations_online() -> None:
    connectable = create_async_engine(
        config.get_main_option("sqlalchemy.url"),
        poolclass=pool.NullPool,
    )
    async with connectable.connect() as connection:
        await connection.run_sync(do_run_migrations)
    await connectable.dispose()


if context.is_offline_mode():
    run_migrations_offline()
else:
    asyncio.run(run_migrations_online())
```

### Model Discovery

```python
# app/core/models.py — Import all models for Alembic autodiscovery
# Add imports here as new modules are created

from app.auth.models.user import User  # noqa: F401
from app.auth.models.refresh_token import RefreshToken  # noqa: F401
from app.articles.models.article import Article  # noqa: F401
from app.comments.models.comment import Comment  # noqa: F401
```

### Migration Commands

```bash
# Generate a new migration
alembic revision --autogenerate -m "create_articles_table"

# Run migrations
alembic upgrade head

# Rollback last migration
alembic downgrade -1

# Show current migration state
alembic current
```

---

## API Response Schemas

```python
# app/core/api/schemas.py
from typing import Generic, TypeVar
from pydantic import BaseModel
from enum import IntEnum

T = TypeVar("T")

class ResponseStatus(IntEnum):
    SUCCESS = 0
    ERROR = 1
    INVALID_INPUT = 2
    NOT_FOUND = 3
    UNAUTHORIZED = 4
    FORBIDDEN = 5

class Response(BaseModel, Generic[T]):
    code: int = ResponseStatus.SUCCESS
    message: str = "Success"
    data: T | None = None

class PaginationMeta(BaseModel):
    page: int
    per_page: int
    total: int
    total_pages: int

class PaginatedResponse(BaseModel, Generic[T]):
    code: int = ResponseStatus.SUCCESS
    message: str = "Success"
    data: list[T] = []
    meta: PaginationMeta | None = None
```

---

## Dependency Injection for Database Session

```python
# app/core/deps.py
from typing import Annotated
from fastapi import Depends
from sqlalchemy.ext.asyncio import AsyncSession
from app.core.db.session import get_session

DBSessionDep = Annotated[AsyncSession, Depends(get_session)]
```

---

## Best Practices

1. **Always use async**: `create_async_engine`, `async_sessionmaker`, `AsyncSession`
2. **Expire on commit = False**: Set `expire_on_commit=False` in session factory to avoid lazy load issues
3. **Flush before commit**: Use `flush()` to get auto-generated IDs, then `commit()` at the end of the operation
4. **Soft deletes by default**: Use `SoftDeleteMixin` for user-facing entities
5. **No cross-module ForeignKeys**: Reference other modules by raw ID columns only
6. **Relationship loading**: Use `selectinload` for collections, `joinedload` for single relations
7. **Per-request sessions**: Each request gets its own session via `Depends(get_session)`
