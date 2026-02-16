# {{PROJECT_NAME}}

A modular monolith API built with **FastAPI**, featuring clean module boundaries, async-first design, and production-ready infrastructure.

## Architecture

This project follows the **Modular Monolith** architecture pattern — a single deployable application organized into loosely coupled, highly cohesive modules.

```
app/
├── core/          # Shared kernel — config, database, API utils, services
{{MODULE_TABLE}}
```

### Module Communication Rules
- Modules communicate **only** through gateway contracts and domain events
- No direct imports of another module's models, repositories, or services
- Cross-module references use IDs only — no SQLAlchemy ForeignKey across modules
- Architecture boundary tests enforce these rules in CI

## Tech Stack

| Category | Technology |
|----------|-----------|
| Framework | FastAPI |
| ORM | SQLAlchemy 2.0 (async) |
| Database | PostgreSQL |
| Cache | Redis + aiocache |
| Migrations | Alembic |
| Auth | JWT + Argon2 |
| Events | fastapi-events |
| Task Queue | Taskiq + Redis |
| Testing | pytest + httpx + faker |
| Package Manager | UV |

## Getting Started

### Prerequisites
{{PREREQUISITES}}

### Quick Start with Docker

```bash
# Clone the repository
git clone <repo-url>
cd {{PROJECT_NAME_LOWER}}

# Copy environment file
cp docker/.env.example docker/.env

# Start all services
docker compose up -d

# The API is available at http://localhost:8000
# API docs at http://localhost:8000/docs
```

### Local Development

```bash
# Install dependencies
uv sync

# Set up environment variables
cp docker/.env.example .env

# Start PostgreSQL and Redis (via Docker)
docker compose up db redis -d

# Run migrations
alembic upgrade head

# Seed initial data
python app/initial_data.py

# Start the development server
uvicorn app.main:app --reload
```

## API Documentation

FastAPI generates interactive API documentation automatically:

- **Swagger UI**: http://localhost:8000/docs
- **ReDoc**: http://localhost:8000/redoc

## Project Structure

```
{{PROJECT_STRUCTURE}}
```

## Running Tests

```bash
# Run all tests
uv run pytest

# Run with coverage
uv run pytest --cov=app

# Run specific module tests
uv run pytest tests/auth/
uv run pytest tests/articles/

# Run architecture boundary tests
uv run pytest tests/architecture/

# Run only unit tests
uv run pytest tests/*/unit/

# Run only integration tests
uv run pytest tests/*/integration/
```

## Adding a New Module

1. Create the module directory structure:

```bash
mkdir -p app/new_module/{models,schemas,repositories,services,routes/v1,dependencies}
```

2. Create the required files:
   - `models/` — SQLAlchemy ORM entities
   - `schemas/` — Pydantic request/response/DTO schemas
   - `repositories/` — Data access extending `BaseRepository`
   - `services/` — Business logic
   - `routes/v1/` — Versioned API endpoints
   - `dependencies/` — DI setup
   - `gateway.py` — Public interface for other modules
   - `events.py` — Domain events
   - `exceptions.py` — Custom exceptions
   - `routers.py` — Module router aggregation

3. Register the module:
   - Add model imports to `app/core/models.py`
   - Add router to `app/core/routers.py`
   - Add event listeners to `app/core/listeners.py` (if needed)
   - Update `MODULES` list in `tests/architecture/test_module_boundaries.py`

4. Generate migration:

```bash
alembic revision --autogenerate -m "create_new_module_tables"
alembic upgrade head
```

5. Write tests following the existing pattern in `tests/`.

## Database Migrations

```bash
# Generate a new migration
alembic revision --autogenerate -m "description"

# Apply all pending migrations
alembic upgrade head

# Rollback last migration
alembic downgrade -1

# View current migration
alembic current
```

## Code Quality

```bash
# Lint
uv run ruff check .

# Format
uv run ruff format .

# Type check
uv run mypy app/
```

## Deployment

See the deployment guide for:
- Docker production builds
- CI/CD with GitHub Actions
- AWS / GCP deployment options
- Scaling strategies

## License

MIT
