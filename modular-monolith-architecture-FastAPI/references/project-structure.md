# FastAPI Modular Monolith — Project Structure Reference

Detailed directory structure for FastAPI Modular Monolith projects.

---

## Complete Project Structure

```
my_app/
├── app/
│   ├── main.py                              # FastAPI app initialization & lifespan
│   ├── backend_pre_start.py                 # Database readiness check
│   ├── initial_data.py                      # Seed data script
│   │
│   ├── core/                                # Shared kernel — cross-cutting concerns
│   │   ├── __init__.py
│   │   ├── configs/                         # Configuration management
│   │   │   ├── __init__.py
│   │   │   └── app.py                       # Pydantic BaseSettings with env vars
│   │   ├── db/                              # Database setup
│   │   │   ├── __init__.py
│   │   │   ├── session.py                   # Async engine & session factory
│   │   │   ├── base_model.py                # BaseModel with timestamps, SoftDeleteMixin
│   │   │   └── base_repository.py           # Generic BaseRepository[M, C, U]
│   │   ├── api/                             # API utilities
│   │   │   ├── __init__.py
│   │   │   ├── schemas.py                   # Response[T], PaginatedResponse, ResponseStatus
│   │   │   ├── exceptions.py                # GeneralException base class
│   │   │   ├── rate_limiter.py              # ConfigurableRateLimiter
│   │   │   └── list_params.py               # ListParamsBuilder for pagination/sort/filter
│   │   ├── services/                        # Cross-cutting service interfaces & providers
│   │   │   ├── __init__.py
│   │   │   ├── cache/                       # Cache service (aiocache + Redis)
│   │   │   │   ├── __init__.py
│   │   │   │   ├── interface.py             # Abstract cache interface
│   │   │   │   └── provider.py              # aiocache Redis implementation
│   │   │   ├── mail/                        # Email service (aiosmtplib + Jinja2)
│   │   │   │   ├── __init__.py
│   │   │   │   ├── interface.py
│   │   │   │   └── provider.py
│   │   │   ├── queue/                       # Task queue (Taskiq + Redis)
│   │   │   │   ├── __init__.py
│   │   │   │   ├── interface.py
│   │   │   │   └── provider.py
│   │   │   ├── log/                         # Structured logging (structlog)
│   │   │   │   ├── __init__.py
│   │   │   │   └── provider.py
│   │   │   └── events/                      # Domain events (fastapi-events)
│   │   │       ├── __init__.py
│   │   │       ├── interface.py
│   │   │       └── provider.py
│   │   ├── deps.py                          # Shared dependencies (DBSessionDep, etc.)
│   │   ├── routers.py                       # Router aggregation — composition root
│   │   ├── exception_handlers.py            # Global exception handlers
│   │   ├── middlewares.py                    # Logging, CORS, timing middlewares
│   │   ├── listeners.py                     # Event listener registration
│   │   ├── tasks.py                         # Task imports for Taskiq
│   │   └── models.py                        # Model imports for Alembic autodiscovery
│   │
│   ├── auth/                                # Auth module (example business module)
│   │   ├── __init__.py
│   │   ├── models/                          # SQLAlchemy ORM models
│   │   │   ├── __init__.py
│   │   │   ├── user.py                      # User entity
│   │   │   └── refresh_token.py             # RefreshToken entity
│   │   ├── schemas/                         # Pydantic v2 schemas
│   │   │   ├── __init__.py
│   │   │   ├── requests.py                  # UserCreateRequest, LoginRequest
│   │   │   ├── responses.py                 # UserResponse, TokenGroupResponse
│   │   │   └── dtos.py                      # UserCreate, UserUpdate DTOs
│   │   ├── repositories/                    # Data access layer
│   │   │   ├── __init__.py
│   │   │   ├── user.py                      # UserRepository extends BaseRepository
│   │   │   └── refresh_token.py             # RefreshTokenRepository
│   │   ├── services/                        # Business logic
│   │   │   ├── __init__.py
│   │   │   ├── auth.py                      # AuthService (login, register, refresh)
│   │   │   └── user.py                      # UserService (CRUD, delete with events)
│   │   ├── routes/                          # API endpoints
│   │   │   ├── __init__.py
│   │   │   └── v1/                          # Versioned routes
│   │   │       ├── __init__.py
│   │   │       ├── auth.py                  # Login, register, refresh, password reset
│   │   │       ├── users.py                 # User listing with pagination
│   │   │       └── profile.py               # Get/update/delete current user
│   │   ├── dependencies/                    # DI configuration
│   │   │   ├── __init__.py
│   │   │   ├── repositories.py              # get_user_repo, get_refresh_token_repo
│   │   │   └── services.py                  # get_auth_service, get_user_service, CurrentUser
│   │   ├── emails/                          # Email templates (Jinja2)
│   │   │   ├── welcome.html
│   │   │   └── password_reset.html
│   │   ├── gateway.py                       # Public interface for other modules
│   │   ├── events.py                        # UserCreated, UserDeleted events
│   │   ├── exceptions.py                    # InvalidCredentials, UserNotFound, etc.
│   │   ├── security.py                      # JWT + Argon2 password hashing utilities
│   │   ├── config.py                        # Auth-specific settings
│   │   └── routers.py                       # Auth module router aggregation
│   │
│   ├── articles/                            # Articles module (same pattern)
│   │   ├── __init__.py
│   │   ├── models/
│   │   ├── schemas/
│   │   ├── repositories/
│   │   ├── services/
│   │   ├── routes/v1/
│   │   ├── dependencies/
│   │   ├── gateway.py
│   │   ├── events.py
│   │   ├── exceptions.py
│   │   └── routers.py
│   │
│   └── comments/                            # Comments module (same pattern)
│       ├── __init__.py
│       ├── models/
│       ├── schemas/
│       ├── repositories/
│       ├── services/
│       ├── routes/v1/
│       ├── dependencies/
│       ├── gateway.py
│       ├── events.py
│       ├── exceptions.py
│       └── routers.py
│
├── migrations/                              # Alembic migrations
│   ├── versions/                            # Migration files (auto-generated)
│   │   └── 001_create_users_table.py
│   ├── env.py                               # Alembic environment config
│   └── script.py.mako                       # Migration template
│
├── tests/                                   # Test suite
│   ├── __init__.py
│   ├── conftest.py                          # Shared fixtures (db, client, faker)
│   ├── factories/                           # Test data factories (factory-boy)
│   │   ├── __init__.py
│   │   └── user.py                          # UserFactory
│   ├── core/                                # Core/shared kernel tests
│   │   └── unit/
│   │       └── test_base_repository.py
│   ├── auth/                                # Auth module tests
│   │   ├── unit/
│   │   │   ├── test_auth_service.py
│   │   │   └── test_user_service.py
│   │   └── integration/
│   │       ├── test_auth_routes.py
│   │       ├── test_user_routes.py
│   │       └── test_profile_routes.py
│   ├── articles/                            # Articles module tests
│   │   ├── unit/
│   │   └── integration/
│   └── architecture/                        # Boundary enforcement tests
│       └── test_module_boundaries.py
│
├── docker/                                  # Docker configuration
│   └── .env.example                         # Environment variable template
├── docker-compose.yaml                      # Multi-container setup
├── Dockerfile                               # Production image
├── alembic.ini                              # Alembic configuration
├── pyproject.toml                           # Dependencies & project config
├── prestart.sh                              # Pre-start script (migrations, seed data)
├── start.sh                                 # Application startup script
├── uv.lock                                  # UV lockfile
└── README.md
```

---

## Key Implementation Notes

### Module Registration Pattern

Each module provides a router that the composition root includes:

```python
# app/core/routers.py — Composition Root
from fastapi import APIRouter
from app.auth.routers import auth_router_v1
from app.articles.routers import articles_router_v1
from app.comments.routers import comments_router_v1

router_v1 = APIRouter(prefix="/api/v1")
router_v1.include_router(auth_router_v1)
router_v1.include_router(articles_router_v1)
router_v1.include_router(comments_router_v1)
```

### Module Router Aggregation

Each module aggregates its own versioned routes:

```python
# app/auth/routers.py
from fastapi import APIRouter
from app.auth.routes.v1 import auth, users, profile

auth_router_v1 = APIRouter()
auth_router_v1.include_router(auth.router, prefix="/auth", tags=["Auth"])
auth_router_v1.include_router(users.router, prefix="/users", tags=["Users"])
auth_router_v1.include_router(profile.router, prefix="/profile", tags=["Profile"])
```

### FastAPI App Initialization

```python
# app/main.py
from contextlib import asynccontextmanager
from fastapi import FastAPI
from app.core.routers import router_v1
from app.core.exception_handlers import register_exception_handlers
from app.core.middlewares import register_middlewares
from app.core.listeners import register_listeners

@asynccontextmanager
async def lifespan(app: FastAPI):
    # Startup: initialize services, run migrations
    yield
    # Shutdown: close connections, cleanup

def create_app() -> FastAPI:
    app = FastAPI(
        title="My App",
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

### Dependency Injection Pattern

```python
# Annotated types for clean dependency injection
from typing import Annotated
from fastapi import Depends
from sqlalchemy.ext.asyncio import AsyncSession

DBSessionDep = Annotated[AsyncSession, Depends(get_session)]

# Module-level dependencies
def get_user_repo(db: DBSessionDep) -> UserRepository:
    return UserRepository(db)

UserRepoDep = Annotated[UserRepository, Depends(get_user_repo)]

def get_user_service(
    user_repo: UserRepoDep,
    events: EventServiceDep,
) -> UserService:
    return UserService(user_repo, events)

UserServiceDep = Annotated[UserService, Depends(get_user_service)]
```

### Gateway Pattern (Public Module Interface)

```python
# app/auth/gateway.py — Public interface for other modules
from app.auth.dependencies.services import get_user_service

class AuthGateway:
    """Public interface to the Auth module.
    Other modules import ONLY from this gateway."""

    def __init__(self, user_service: UserServiceDep):
        self._user_service = user_service

    async def get_user_by_id(self, user_id: int) -> UserDTO | None:
        return await self._user_service.get_by_id(user_id)

    async def is_user_active(self, user_id: int) -> bool:
        user = await self._user_service.get_by_id(user_id)
        return user is not None and user.is_active
```

### Naming Conventions

| Item | Convention | Example |
|------|-----------|---------|
| Module directories | `snake_case` | `app/auth/`, `app/articles/` |
| Model files | `snake_case` singular | `models/user.py`, `models/article.py` |
| Schema files | Grouped by purpose | `schemas/requests.py`, `schemas/responses.py` |
| Route files | `snake_case` resource | `routes/v1/auth.py`, `routes/v1/users.py` |
| Repository classes | `PascalCase` + Repository | `UserRepository`, `ArticleRepository` |
| Service classes | `PascalCase` + Service | `AuthService`, `ArticleService` |
| Dependency functions | `get_` prefix | `get_user_repo()`, `get_auth_service()` |
| Annotated types | `PascalCase` + Dep | `DBSessionDep`, `UserServiceDep` |
| Gateway classes | `PascalCase` + Gateway | `AuthGateway`, `ArticlesGateway` |
| Events | Past tense | `UserCreated`, `ArticlePublished` |
