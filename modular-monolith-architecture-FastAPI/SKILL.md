---
name: modular-monolith-architecture-FastAPI
description: Scaffold and create a Modular Monolith Architecture project using Python/FastAPI. Use when the user wants to create a new FastAPI modular monolith, restructure a FastAPI monolith into modules, design module boundaries, or set up a FastAPI project following modular monolith best practices with async support, SQLAlchemy, and production-ready patterns.
argument-hint: "[project-name] [modules...]"
---

# FastAPI Modular Monolith Architecture — Project Scaffolder

Generate production-ready Modular Monolith projects with FastAPI, featuring proper module boundaries, async-first design, dependency injection, shared kernel, and infrastructure following industry best practices.

## Overview

A Modular Monolith is a single deployable application organized into loosely coupled, highly cohesive modules — each representing a bounded context. FastAPI's speed, async capabilities, dependency injection system, and automatic API documentation make it an ideal framework for this architecture.

This skill scaffolds complete FastAPI projects with:
- **Module isolation**: Each module owns its models, repositories, services, routes, schemas, and dependencies
- **Async-first design**: All I/O operations use async/await (SQLAlchemy async, aiosmtplib, aiocache)
- **FastAPI dependency injection**: Loose coupling via `Depends()` and `Annotated` types
- **Generic repository pattern**: Base CRUD with pagination, filtering, sorting, and soft deletes
- **Inter-module communication**: Via gateway contracts and domain events (fastapi-events)
- **Shared kernel (core)**: Cross-cutting concerns — base models, config, services, exception handling
- **Database-per-module schema**: Logical isolation within a single PostgreSQL database via Alembic
- **Production-ready**: Docker, Redis caching, task queues (Taskiq), structured logging, rate limiting
- **Migration-ready boundaries**: Modules can be extracted to microservices later

## Workflow

### Step 1: Gather Requirements

If the user hasn't specified, ask for:
1. **Project name** (e.g., `conduit`, `saas-platform`, `ecommerce-api`)
2. **Business modules** (e.g., Auth, Articles, Comments, Payments, Notifications)
3. **Database** preference (PostgreSQL recommended, MySQL supported)
4. **Additional features**: Event bus, caching (Redis), task queue, email, Docker, CI/CD
5. **Authentication method**: JWT (default), OAuth2, API keys

If the user provides `$ARGUMENTS`, parse them: `$ARGUMENTS[0]` = project name, remaining = module names.

### Step 2: Generate Project Structure

Read the architecture references for FastAPI:
- For detailed project structure, see [references/project-structure.md](references/project-structure.md)
- For module design patterns, see [references/module-design.md](references/module-design.md)
- For architecture decisions and comparisons, see [references/architecture-guide.md](references/architecture-guide.md)
- For event-driven patterns, see [references/event-driven-patterns.md](references/event-driven-patterns.md)
- For database patterns (SQLAlchemy async, Alembic), see [references/database-patterns.md](references/database-patterns.md)
- For testing strategies (pytest, TestClient), see [references/testing-strategies.md](references/testing-strategies.md)
- For authentication and security patterns, see [references/authentication-security.md](references/authentication-security.md)
- For deployment and scaling, see [references/deployment-scaling.md](references/deployment-scaling.md)
- For a concrete Conduit (Medium clone) scaffold, see [examples/conduit-scaffold.md](examples/conduit-scaffold.md)
- For the generated README template, see [examples/README-template.md](examples/README-template.md)

Generate the project following these **critical rules**:

#### Module Rules
1. Each module gets its own directory with internal layers: `models/`, `schemas/`, `repositories/`, `services/`, `routes/`, `dependencies/`
2. Modules communicate ONLY through gateway contracts — never import another module's internal types
3. Each module has its own Alembic migration files
4. Each module registers its own dependencies via `Depends()` functions
5. No circular dependencies between modules
6. Each module has its own `routers.py` that aggregates its versioned route files

#### Shared Kernel (Core) Rules
1. Contains ONLY cross-cutting concerns: base models, configuration, database session, generic repository, API response schemas, service interfaces (cache, mail, queue, log, events), exception handlers, middlewares
2. Must be thin — if it grows large, something belongs in a module
3. Never contains business logic specific to any module

#### Infrastructure Rules
1. Single entry point: `app/main.py` (FastAPI app initialization)
2. Composition root: `app/core/routers.py` wires all module routers together
3. Database session is shared but models/schemas are isolated per module
4. Domain events via `fastapi-events` for async inter-module communication (upgradeable to Kafka/RabbitMQ)
5. Background tasks via Taskiq with Redis backend

### Step 3: Generate Code

For each module, generate:
- **Models layer** (`models/`): SQLAlchemy ORM models with soft delete support
- **Schemas layer** (`schemas/`): Pydantic v2 request/response/DTO schemas
- **Repository layer** (`repositories/`): Data access extending `BaseRepository` with custom queries
- **Service layer** (`services/`): Business logic with event dispatch and cross-cutting service calls
- **Routes layer** (`routes/v1/`): Versioned API endpoints with FastAPI routers
- **Dependencies layer** (`dependencies/`): DI setup for repositories, services, and auth guards
- **Gateway** (`gateway.py`): Public interface exposing module functionality to other modules
- **Events** (`events.py`): Domain event definitions
- **Exceptions** (`exceptions.py`): Module-specific custom exceptions
- **Config** (`config.py`): Module-specific configuration

Also generate:
- **Shared kernel** (`app/core/`): Base classes, database setup, generic repository, API schemas, service interfaces, exception handlers, middlewares, dependency injection
- **Entry point** (`app/main.py`): FastAPI app with lifespan, middleware registration, exception handlers
- **Tests**: Unit tests, integration tests, factories, and architecture boundary tests — see [references/testing-strategies.md](references/testing-strategies.md)
- **Docker** (if requested): Dockerfile + docker-compose with PostgreSQL, Redis, Taskiq worker, and Mailhog — see [references/deployment-scaling.md](references/deployment-scaling.md)
- **Alembic**: Migration configuration with `alembic.ini` and `migrations/env.py`
- **pyproject.toml**: Dependencies managed with UV or pip
- **README.md**: Architecture overview, how to run, how to add modules (use [examples/README-template.md](examples/README-template.md))

### Step 4: Validate

After generation:
1. Verify no module directly imports another module's internal types (only gateways)
2. Confirm each module has its own models and migration support
3. Check that the shared kernel (`app/core/`) contains no business logic
4. Ensure the project runs successfully with `uvicorn app.main:app --reload`
5. Run any generated tests with `pytest`

Validation scripts are available in [scripts/](scripts/) for CI integration:
- `scripts/validate-boundaries.sh <app-dir>` — detects cross-module boundary violations in Python imports
- `scripts/validate-shared-kernel.sh <core-dir> <modules-dir>` — ensures core doesn't reference modules
- `scripts/check-circular-deps.sh <app-dir>` — detects circular dependencies between modules

### Step 5: Migration Guidance

If the user asks about extracting modules to microservices:
- Replace gateway contracts (in-process function calls) with HTTP/gRPC clients
- Swap `fastapi-events` for Kafka/RabbitMQ for that module's events
- Migrate module's database tables to a separate database
- Deploy the extracted module as a standalone FastAPI service
- Keep remaining modules as a monolith (no need to extract everything)

## Key Principles to Enforce

| Principle | What It Means | How to Enforce in FastAPI |
|-----------|---------------|--------------------------|
| High Cohesion | Module contains everything for its domain | models + schemas + repos + services + routes per module |
| Low Coupling | Modules don't depend on each other's internals | Communication only via gateway contracts |
| Dependency Injection | All dependencies are explicit and injectable | FastAPI `Depends()` with `Annotated` types |
| Async-First | All I/O operations are non-blocking | `async def` for routes, services, repositories |
| Repository Pattern | Data access is abstracted behind interfaces | `BaseRepository[Model, Create, Update]` generic class |
| Schema Separation | Request/response/DTO schemas are distinct | Pydantic v2 models in `schemas/` per module |
| Event-Driven Communication | Async inter-module messaging | `fastapi-events` with domain event dispatch |
| Encapsulated Data | Module owns its data | Per-module SQLAlchemy models, no cross-module FKs |

## Example Invocations

```
/modular-monolith-architecture-FastAPI conduit Auth Articles Comments
/modular-monolith-architecture-FastAPI ecommerce-api Auth Products Orders Payments
/modular-monolith-architecture-FastAPI saas-platform Auth Tenants Billing Notifications
/modular-monolith-architecture-FastAPI social-api Auth Users Posts Messages
```

## When NOT to Use This

Suggest microservices instead if the user describes:
- Teams needing completely independent deployment cadences
- Requirements for polyglot tech stacks (Python ML + Go APIs + Java enterprise)
- Extreme per-service scaling requirements
- Already having Kubernetes infrastructure and DevOps maturity

Suggest a simple FastAPI monolith if:
- Solo developer or very small team (1-3 devs)
- Prototype/MVP with unclear domain boundaries
- Application with fewer than 3 distinct business domains
- Simple CRUD API without complex business logic

## Technology Stack

| Category | Technology | Purpose |
|----------|-----------|---------|
| Framework | FastAPI | Web framework with async support |
| ORM | SQLAlchemy 2.0 (async) | Database ORM with async session |
| Validation | Pydantic v2 | Request/response validation and serialization |
| Database | PostgreSQL | Primary relational database |
| Cache | Redis + aiocache | Caching with async Redis backend |
| Migrations | Alembic | Database schema migrations |
| Auth | PyJWT + Passlib (Argon2) | JWT tokens + password hashing |
| Events | fastapi-events | In-process domain event dispatcher |
| Task Queue | Taskiq + Redis | Async background job processing |
| Email | aiosmtplib + Jinja2 | Async email with templates |
| Logging | structlog | Structured async logging |
| Testing | pytest + httpx + faker + factory-boy | Comprehensive test suite |
| Package Manager | UV | Fast Python dependency management |
| Linting | Ruff | Code linter and formatter |
| Type Checking | MyPy | Static type analysis |
| Containerization | Docker + docker-compose | Development and deployment |
