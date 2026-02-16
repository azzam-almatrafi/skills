# FastAPI Conduit (Medium Clone) — Example Scaffold

A concrete example of a generated FastAPI Modular Monolith for a Conduit application (Medium clone) with Auth, Articles, and Comments modules.

---

## Generated File Tree

```
conduit/
├── app/
│   ├── __init__.py
│   ├── main.py
│   ├── backend_pre_start.py
│   ├── initial_data.py
│   │
│   ├── core/
│   │   ├── __init__.py
│   │   ├── configs/
│   │   │   ├── __init__.py
│   │   │   └── app.py
│   │   ├── db/
│   │   │   ├── __init__.py
│   │   │   ├── session.py
│   │   │   ├── base_model.py
│   │   │   └── base_repository.py
│   │   ├── api/
│   │   │   ├── __init__.py
│   │   │   ├── schemas.py
│   │   │   ├── exceptions.py
│   │   │   ├── rate_limiter.py
│   │   │   └── list_params.py
│   │   ├── services/
│   │   │   ├── __init__.py
│   │   │   ├── cache/
│   │   │   │   ├── __init__.py
│   │   │   │   ├── interface.py
│   │   │   │   └── provider.py
│   │   │   ├── mail/
│   │   │   │   ├── __init__.py
│   │   │   │   ├── interface.py
│   │   │   │   └── provider.py
│   │   │   ├── queue/
│   │   │   │   ├── __init__.py
│   │   │   │   ├── interface.py
│   │   │   │   └── provider.py
│   │   │   ├── log/
│   │   │   │   ├── __init__.py
│   │   │   │   └── provider.py
│   │   │   └── events/
│   │   │       ├── __init__.py
│   │   │       ├── interface.py
│   │   │       └── provider.py
│   │   ├── deps.py
│   │   ├── routers.py
│   │   ├── exception_handlers.py
│   │   ├── middlewares.py
│   │   ├── listeners.py
│   │   ├── tasks.py
│   │   └── models.py
│   │
│   ├── auth/
│   │   ├── __init__.py
│   │   ├── models/
│   │   │   ├── __init__.py
│   │   │   ├── user.py
│   │   │   └── refresh_token.py
│   │   ├── schemas/
│   │   │   ├── __init__.py
│   │   │   ├── requests.py
│   │   │   ├── responses.py
│   │   │   └── dtos.py
│   │   ├── repositories/
│   │   │   ├── __init__.py
│   │   │   ├── user.py
│   │   │   └── refresh_token.py
│   │   ├── services/
│   │   │   ├── __init__.py
│   │   │   ├── auth.py
│   │   │   └── user.py
│   │   ├── routes/
│   │   │   ├── __init__.py
│   │   │   └── v1/
│   │   │       ├── __init__.py
│   │   │       ├── auth.py
│   │   │       ├── users.py
│   │   │       └── profile.py
│   │   ├── dependencies/
│   │   │   ├── __init__.py
│   │   │   ├── repositories.py
│   │   │   └── services.py
│   │   ├── emails/
│   │   │   ├── welcome.html
│   │   │   └── password_reset.html
│   │   ├── gateway.py
│   │   ├── events.py
│   │   ├── exceptions.py
│   │   ├── security.py
│   │   ├── config.py
│   │   └── routers.py
│   │
│   ├── articles/
│   │   ├── __init__.py
│   │   ├── models/
│   │   │   ├── __init__.py
│   │   │   ├── article.py
│   │   │   └── tag.py
│   │   ├── schemas/
│   │   │   ├── __init__.py
│   │   │   ├── requests.py
│   │   │   ├── responses.py
│   │   │   └── dtos.py
│   │   ├── repositories/
│   │   │   ├── __init__.py
│   │   │   ├── article.py
│   │   │   └── tag.py
│   │   ├── services/
│   │   │   ├── __init__.py
│   │   │   └── article.py
│   │   ├── routes/
│   │   │   ├── __init__.py
│   │   │   └── v1/
│   │   │       ├── __init__.py
│   │   │       ├── articles.py
│   │   │       └── tags.py
│   │   ├── dependencies/
│   │   │   ├── __init__.py
│   │   │   ├── repositories.py
│   │   │   └── services.py
│   │   ├── gateway.py
│   │   ├── events.py
│   │   ├── exceptions.py
│   │   └── routers.py
│   │
│   └── comments/
│       ├── __init__.py
│       ├── models/
│       │   ├── __init__.py
│       │   └── comment.py
│       ├── schemas/
│       │   ├── __init__.py
│       │   ├── requests.py
│       │   ├── responses.py
│       │   └── dtos.py
│       ├── repositories/
│       │   ├── __init__.py
│       │   └── comment.py
│       ├── services/
│       │   ├── __init__.py
│       │   └── comment.py
│       ├── routes/
│       │   ├── __init__.py
│       │   └── v1/
│       │       ├── __init__.py
│       │       └── comments.py
│       ├── dependencies/
│       │   ├── __init__.py
│       │   ├── repositories.py
│       │   └── services.py
│       ├── gateway.py
│       ├── events.py
│       ├── exceptions.py
│       └── routers.py
│
├── migrations/
│   ├── versions/
│   │   ├── 001_create_users_and_refresh_tokens.py
│   │   ├── 002_create_articles_and_tags.py
│   │   └── 003_create_comments.py
│   ├── env.py
│   └── script.py.mako
│
├── tests/
│   ├── __init__.py
│   ├── conftest.py
│   ├── factories/
│   │   ├── __init__.py
│   │   ├── user.py
│   │   ├── article.py
│   │   └── comment.py
│   ├── auth/
│   │   ├── unit/
│   │   │   ├── test_auth_service.py
│   │   │   └── test_user_service.py
│   │   └── integration/
│   │       ├── test_auth_routes.py
│   │       ├── test_user_routes.py
│   │       └── test_profile_routes.py
│   ├── articles/
│   │   ├── unit/
│   │   │   └── test_article_service.py
│   │   └── integration/
│   │       ├── test_article_routes.py
│   │       └── test_tag_routes.py
│   ├── comments/
│   │   ├── unit/
│   │   │   └── test_comment_service.py
│   │   └── integration/
│   │       └── test_comment_routes.py
│   ├── contracts/
│   │   ├── test_auth_gateway.py
│   │   └── test_articles_gateway.py
│   └── architecture/
│       └── test_module_boundaries.py
│
├── docker/
│   └── .env.example
├── docker-compose.yaml
├── Dockerfile
├── alembic.ini
├── pyproject.toml
├── prestart.sh
├── start.sh
└── README.md
```

---

## Key Generated Files

### app/main.py (Entry Point)

```python
from contextlib import asynccontextmanager
from fastapi import FastAPI
from app.core.routers import router_v1
from app.core.exception_handlers import register_exception_handlers
from app.core.middlewares import register_middlewares
from app.core.listeners import register_listeners


@asynccontextmanager
async def lifespan(app: FastAPI):
    # Startup
    yield
    # Shutdown


def create_app() -> FastAPI:
    app = FastAPI(
        title="Conduit API",
        description="A Medium clone API built with FastAPI Modular Monolith architecture",
        version="1.0.0",
        lifespan=lifespan,
    )

    register_exception_handlers(app)
    register_middlewares(app)
    register_listeners(app)
    app.include_router(router_v1)

    return app


app = create_app()
```

### app/core/routers.py (Composition Root)

```python
from fastapi import APIRouter
from app.auth.routers import auth_router_v1
from app.articles.routers import articles_router_v1
from app.comments.routers import comments_router_v1

router_v1 = APIRouter(prefix="/api/v1")

router_v1.include_router(auth_router_v1)
router_v1.include_router(articles_router_v1)
router_v1.include_router(comments_router_v1)
```

### app/core/deps.py (Shared Dependencies)

```python
from typing import Annotated
from fastapi import Depends
from sqlalchemy.ext.asyncio import AsyncSession
from app.core.db.session import get_session
from app.core.services.events.provider import FastAPIEventService
from app.core.services.events.interface import EventService

DBSessionDep = Annotated[AsyncSession, Depends(get_session)]


def get_event_service() -> EventService:
    return FastAPIEventService()

EventServiceDep = Annotated[EventService, Depends(get_event_service)]
```

### app/core/exception_handlers.py

```python
from fastapi import FastAPI, Request, status
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from app.core.api.exceptions import GeneralException
from app.core.api.schemas import ResponseStatus
import structlog

logger = structlog.get_logger()


def register_exception_handlers(app: FastAPI) -> None:

    @app.exception_handler(RequestValidationError)
    async def validation_exception_handler(request: Request, exc: RequestValidationError):
        return JSONResponse(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            content={
                "code": ResponseStatus.INVALID_INPUT,
                "message": "Validation error",
                "data": exc.errors(),
            },
        )

    @app.exception_handler(GeneralException)
    async def general_exception_handler(request: Request, exc: GeneralException):
        return JSONResponse(
            status_code=exc.status_code,
            content={
                "code": exc.code,
                "message": exc.message,
                "data": None,
            },
        )

    @app.exception_handler(Exception)
    async def unhandled_exception_handler(request: Request, exc: Exception):
        await logger.a_exception("unhandled_error", error=str(exc))
        return JSONResponse(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            content={
                "code": ResponseStatus.ERROR,
                "message": "Internal server error",
                "data": None,
            },
        )
```

### app/auth/routers.py (Module Router)

```python
from fastapi import APIRouter
from app.auth.routes.v1 import auth, users, profile

auth_router_v1 = APIRouter()

auth_router_v1.include_router(auth.router, prefix="/auth", tags=["Auth"])
auth_router_v1.include_router(users.router, prefix="/users", tags=["Users"])
auth_router_v1.include_router(profile.router, prefix="/profile", tags=["Profile"])
```

### app/auth/gateway.py (Public Interface)

```python
from app.auth.schemas.dtos import UserDTO


class AuthGateway:
    """Public interface to the Auth module.

    Other modules MUST import only from this gateway to
    interact with auth functionality.
    """

    def __init__(self, user_service):
        self._user_service = user_service

    async def get_user_by_id(self, user_id: int) -> UserDTO | None:
        user = await self._user_service.get_by_id(user_id)
        return UserDTO.model_validate(user) if user else None

    async def get_users_by_ids(self, user_ids: list[int]) -> list[UserDTO]:
        users = await self._user_service.get_by_ids(user_ids)
        return [UserDTO.model_validate(u) for u in users]

    async def is_user_active(self, user_id: int) -> bool:
        user = await self._user_service.get_by_id(user_id)
        return user is not None and user.is_active
```

### app/auth/events.py (Domain Events)

```python
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

### app/articles/gateway.py (Articles Public Interface)

```python
from app.articles.schemas.dtos import ArticleDTO


class ArticlesGateway:
    """Public interface to the Articles module."""

    def __init__(self, article_service):
        self._article_service = article_service

    async def get_article_by_id(self, article_id: int) -> ArticleDTO | None:
        article = await self._article_service.get_by_id(article_id)
        return ArticleDTO.model_validate(article) if article else None

    async def get_articles_by_author(self, author_id: int) -> list[ArticleDTO]:
        articles = await self._article_service.get_by_author(author_id)
        return [ArticleDTO.model_validate(a) for a in articles]

    async def article_exists(self, article_id: int) -> bool:
        article = await self._article_service.get_by_id(article_id)
        return article is not None
```

### app/articles/models/article.py

```python
from sqlalchemy import Column, Integer, String, Text
from app.core.db.base_model import BaseModel, SoftDeleteMixin


class Article(BaseModel, SoftDeleteMixin):
    __tablename__ = "articles"

    id = Column(Integer, primary_key=True, autoincrement=True)
    title = Column(String(255), nullable=False)
    slug = Column(String(255), unique=True, nullable=False, index=True)
    body = Column(Text, nullable=False)
    description = Column(String(500))
    author_id = Column(Integer, nullable=False)  # Ref to auth module by ID only

    def is_author(self, user_id: int) -> bool:
        return self.author_id == user_id
```

### app/comments/models/comment.py

```python
from sqlalchemy import Column, Integer, Text
from app.core.db.base_model import BaseModel, SoftDeleteMixin


class Comment(BaseModel, SoftDeleteMixin):
    __tablename__ = "comments"

    id = Column(Integer, primary_key=True, autoincrement=True)
    body = Column(Text, nullable=False)
    article_id = Column(Integer, nullable=False)  # Ref to articles module by ID only
    author_id = Column(Integer, nullable=False)    # Ref to auth module by ID only

    def is_author(self, user_id: int) -> bool:
        return self.author_id == user_id
```

### app/comments/services/comment.py

```python
from app.comments.repositories.comment import CommentRepository
from app.comments.schemas.requests import CommentCreateRequest
from app.comments.schemas.dtos import CommentCreate
from app.comments.exceptions import CommentNotFound
from app.articles.gateway import ArticlesGateway  # Import from gateway ONLY
from app.articles.exceptions import ArticleNotFound


class CommentService:
    def __init__(
        self,
        comment_repo: CommentRepository,
        articles_gateway: ArticlesGateway,
    ):
        self._repo = comment_repo
        self._articles = articles_gateway

    async def create_comment(
        self, request: CommentCreateRequest, article_id: int, author_id: int,
    ):
        # Use gateway to check article exists — never access articles internals
        if not await self._articles.article_exists(article_id):
            raise ArticleNotFound(article_id)

        dto = CommentCreate(
            body=request.body,
            article_id=article_id,
            author_id=author_id,
        )
        comment = await self._repo.create(dto)
        await self._repo.commit()
        return comment

    async def get_comments_for_article(self, article_id: int):
        return await self._repo.get_by_article(article_id)

    async def delete_comment(self, comment_id: int, user_id: int):
        comment = await self._repo.get(comment_id)
        if not comment:
            raise CommentNotFound(comment_id)
        if not comment.is_author(user_id):
            raise PermissionError("Not the comment author")
        await self._repo.delete(model=comment, is_soft=True)
        await self._repo.commit()
```

### pyproject.toml

```toml
[project]
name = "conduit"
version = "1.0.0"
description = "Conduit API — Medium clone built with FastAPI Modular Monolith"
requires-python = ">=3.12"
dependencies = [
    # Web framework
    "fastapi>=0.115.0",
    "uvicorn[standard]>=0.30.0",

    # Database
    "sqlalchemy[asyncio]>=2.0.0",
    "asyncpg>=0.30.0",
    "alembic>=1.14.0",

    # Validation
    "pydantic>=2.0.0",
    "pydantic-settings>=2.0.0",

    # Authentication
    "pyjwt>=2.9.0",
    "passlib[argon2]>=1.7.0",

    # Cache & Queue
    "aiocache[redis]>=0.12.0",
    "redis>=5.0.0",
    "taskiq[redis]>=0.11.0",
    "taskiq-redis>=1.0.0",

    # Email
    "aiosmtplib>=3.0.0",
    "jinja2>=3.1.0",

    # Events
    "fastapi-events>=0.11.0",

    # Logging
    "structlog>=24.0.0",

    # Utilities
    "python-slugify>=8.0.0",
    "python-multipart>=0.0.9",
]

[project.optional-dependencies]
dev = [
    # Testing
    "pytest>=8.0.0",
    "pytest-asyncio>=0.24.0",
    "httpx>=0.27.0",
    "faker>=30.0.0",
    "factory-boy>=3.3.0",
    "freezegun>=1.3.0",
    "pytest-cov>=5.0.0",

    # Code quality
    "ruff>=0.7.0",
    "mypy>=1.11.0",
]

[tool.ruff]
target-version = "py312"
line-length = 100

[tool.ruff.lint]
select = ["E", "F", "I", "N", "W"]

[tool.pytest.ini_options]
asyncio_mode = "auto"
testpaths = ["tests"]

[tool.mypy]
python_version = "3.12"
plugins = ["pydantic.mypy"]
ignore_missing_imports = true
```

### docker-compose.yaml

```yaml
services:
  web:
    build: .
    ports:
      - "8000:8000"
    volumes:
      - .:/app
    env_file:
      - docker/.env
    depends_on:
      db:
        condition: service_healthy
      redis:
        condition: service_healthy
    networks:
      - conduit-network

  db:
    image: postgres:17-alpine
    environment:
      POSTGRES_DB: conduit
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: postgres
    ports:
      - "5432:5432"
    volumes:
      - postgres_data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U postgres"]
      interval: 5s
      timeout: 5s
      retries: 5
    networks:
      - conduit-network

  redis:
    image: redis:8.0-alpine
    ports:
      - "6379:6379"
    volumes:
      - redis_data:/data
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 5s
      timeout: 5s
      retries: 5
    networks:
      - conduit-network

  queue_worker:
    build: .
    command: uv run taskiq worker app.core.tasks:broker
    volumes:
      - .:/app
    env_file:
      - docker/.env
    depends_on:
      - redis
      - db
    networks:
      - conduit-network

  mailhog:
    image: mailhog/mailhog
    ports:
      - "1025:1025"
      - "8025:8025"
    networks:
      - conduit-network

networks:
  conduit-network:
    driver: bridge

volumes:
  postgres_data:
  redis_data:
```

### tests/architecture/test_module_boundaries.py

```python
import ast
import os
import pytest

APP_DIR = os.path.join(os.path.dirname(__file__), "../../app")
MODULES = ["auth", "articles", "comments"]
CORE_DIR = "core"


def get_python_files(directory: str) -> list[str]:
    files = []
    for root, _, filenames in os.walk(directory):
        for f in filenames:
            if f.endswith(".py"):
                files.append(os.path.join(root, f))
    return files


def get_imports(filepath: str) -> list[str]:
    with open(filepath) as f:
        try:
            tree = ast.parse(f.read())
        except SyntaxError:
            return []
    imports = []
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            for alias in node.names:
                imports.append(alias.name)
        elif isinstance(node, ast.ImportFrom) and node.module:
            imports.append(node.module)
    return imports


class TestModuleBoundaries:
    @pytest.mark.parametrize("source,target", [
        (s, t) for s in MODULES for t in MODULES if s != t
    ])
    def test_module_does_not_import_other_module_internals(self, source, target):
        source_dir = os.path.join(APP_DIR, source)
        if not os.path.isdir(source_dir):
            pytest.skip(f"Module {source} not found")

        for filepath in get_python_files(source_dir):
            for imp in get_imports(filepath):
                if f"app.{target}" in imp:
                    allowed = (
                        f"app.{target}.gateway" in imp
                        or f"app.{target}.events" in imp
                        or f"app.{target}.schemas.dtos" in imp
                        or f"app.{target}.exceptions" in imp
                    )
                    assert allowed, (
                        f"{filepath} imports '{imp}' — only gateway, events, "
                        f"DTOs, and exceptions are allowed"
                    )

    def test_core_does_not_import_from_modules(self):
        core_dir = os.path.join(APP_DIR, CORE_DIR)
        exempt = {"models.py", "routers.py", "listeners.py", "tasks.py"}

        for filepath in get_python_files(core_dir):
            if os.path.basename(filepath) in exempt:
                continue
            for imp in get_imports(filepath):
                for module in MODULES:
                    assert f"app.{module}" not in imp, (
                        f"{filepath} imports '{imp}' — core must not depend on modules"
                    )
```
