# FastAPI Deployment & Scaling

Docker containerization, cloud deployment, and scaling strategies for FastAPI Modular Monoliths.

---

## Docker Setup

### Dockerfile

```dockerfile
FROM python:3.13-slim

WORKDIR /app

# Install UV for fast dependency management
COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /bin/

# Install dependencies first (layer caching)
COPY pyproject.toml uv.lock ./
RUN uv sync --frozen --no-install-project

# Copy application code
COPY . .

# Set Python path
ENV PYTHONPATH=/app

# Run startup script
CMD ["bash", "start.sh"]
```

### docker-compose.yaml

```yaml
services:
  web:
    build: .
    ports:
      - "8000:8000"
      - "5555:5555"  # Debug port
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
      - app-network

  db:
    image: postgres:17-alpine
    environment:
      POSTGRES_DB: my_app
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
      - app-network

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
      - app-network

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
      - app-network

  mailhog:
    image: mailhog/mailhog
    ports:
      - "1025:1025"  # SMTP
      - "8025:8025"  # Web UI
    networks:
      - app-network

networks:
  app-network:
    driver: bridge

volumes:
  postgres_data:
  redis_data:
```

### Startup Scripts

```bash
# start.sh
#!/bin/bash
set -e

# Run pre-start (migrations, seed data)
if [ -f prestart.sh ]; then
    bash prestart.sh
fi

# Start uvicorn with reload for development
exec uv run uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload
```

```bash
# prestart.sh
#!/bin/bash
set -e

# Wait for database
python app/backend_pre_start.py

# Run migrations
alembic upgrade head

# Seed initial data (if needed)
python app/initial_data.py
```

---

## Scaling Strategies

### Horizontal Scaling (Multiple Workers)

```bash
# Production startup with multiple Uvicorn workers
uvicorn app.main:app --host 0.0.0.0 --port 8000 --workers 4

# Or with Gunicorn + Uvicorn workers
gunicorn app.main:app -w 4 -k uvicorn.workers.UvicornWorker --bind 0.0.0.0:8000
```

### Module-Level Scaling

The modular monolith allows targeted optimization:

| Module | Scaling Strategy |
|--------|-----------------|
| Auth | Rate limiting + Redis session cache |
| Articles | Read replica DB + Redis caching for popular articles |
| Comments | Write-heavy → separate write/read endpoints |
| Notifications | Offload to Taskiq background workers |

### Caching with Redis

```python
# app/core/services/cache/provider.py
from aiocache import Cache
from aiocache.serializers import JsonSerializer

cache = Cache(
    Cache.REDIS,
    endpoint="localhost",
    port=6379,
    serializer=JsonSerializer(),
    namespace="my_app",
)

# Usage in service
class ArticleService:
    async def get_by_slug(self, slug: str):
        # Check cache first
        cached = await cache.get(f"article:{slug}")
        if cached:
            return cached

        article = await self._repo.get_by_slug(slug)
        if article:
            await cache.set(f"article:{slug}", article.to_dict(), ttl=300)
        return article
```

### Background Task Processing

```python
# Heavy operations offloaded to Taskiq workers
# This keeps the API responsive while processing happens async

@broker.task(task_name="process_article_images")
async def process_article_images(article_id: int):
    """Resize and optimize article images in the background."""
    ...

@broker.task(task_name="send_notification_batch")
async def send_notification_batch(user_ids: list[int], message: str):
    """Send notifications to multiple users."""
    ...
```

---

## Cloud Deployment Options

### AWS

```
                    ┌─────────────┐
                    │   Route 53  │
                    └──────┬──────┘
                           │
                    ┌──────┴──────┐
                    │     ALB     │
                    └──────┬──────┘
                           │
              ┌────────────┼────────────┐
              │            │            │
        ┌─────┴─────┐ ┌───┴───┐ ┌─────┴─────┐
        │  ECS/EKS  │ │  ECS  │ │  ECS/EKS  │
        │  FastAPI  │ │ Worker│ │  FastAPI  │
        └─────┬─────┘ └───┬───┘ └─────┬─────┘
              │            │            │
              └────────────┼────────────┘
                           │
              ┌────────────┼────────────┐
              │                         │
        ┌─────┴─────┐           ┌──────┴──────┐
        │  RDS      │           │ ElastiCache │
        │ PostgreSQL│           │    Redis    │
        └───────────┘           └─────────────┘
```

| Component | AWS Service |
|-----------|-------------|
| FastAPI App | ECS Fargate / EKS |
| PostgreSQL | RDS (Aurora) |
| Redis | ElastiCache |
| Task Queue | ECS Fargate (worker) |
| Load Balancer | ALB |
| DNS | Route 53 |
| Secrets | Secrets Manager |
| CI/CD | CodePipeline / GitHub Actions |

### Google Cloud

| Component | GCP Service |
|-----------|-------------|
| FastAPI App | Cloud Run / GKE |
| PostgreSQL | Cloud SQL |
| Redis | Memorystore |
| Task Queue | Cloud Tasks / worker in Cloud Run |
| Load Balancer | Cloud Load Balancing |

---

## CI/CD Pipeline

### GitHub Actions

```yaml
# .github/workflows/ci.yml
name: CI

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  test:
    runs-on: ubuntu-latest
    services:
      postgres:
        image: postgres:17-alpine
        env:
          POSTGRES_DB: test_db
          POSTGRES_USER: postgres
          POSTGRES_PASSWORD: postgres
        ports:
          - 5432:5432
        options: >-
          --health-cmd pg_isready
          --health-interval 10s
          --health-timeout 5s
          --health-retries 5
      redis:
        image: redis:8.0-alpine
        ports:
          - 6379:6379

    steps:
      - uses: actions/checkout@v4
      - uses: astral-sh/setup-uv@v4

      - name: Install dependencies
        run: uv sync

      - name: Run linter
        run: uv run ruff check .

      - name: Run type checker
        run: uv run mypy app/

      - name: Run tests
        run: uv run pytest --cov=app tests/
        env:
          POSTGRES_HOST: localhost
          POSTGRES_PORT: 5432
          POSTGRES_USER: postgres
          POSTGRES_PASSWORD: postgres
          POSTGRES_DB: test_db

      - name: Run architecture tests
        run: uv run pytest tests/architecture/

  build:
    needs: test
    runs-on: ubuntu-latest
    if: github.ref == 'refs/heads/main'
    steps:
      - uses: actions/checkout@v4
      - name: Build Docker image
        run: docker build -t my-app .
```

---

## Observability

### Structured Logging

```python
# app/core/services/log/provider.py
import structlog

structlog.configure(
    processors=[
        structlog.contextvars.merge_contextvars,
        structlog.processors.add_log_level,
        structlog.processors.TimeStamper(fmt="iso"),
        structlog.dev.ConsoleRenderer(),  # Use JSONRenderer in production
    ],
)

logger = structlog.get_logger()

# Usage
await logger.a_info("article.created", article_id=article.id, author_id=user_id)
```

### Request Logging Middleware

```python
# app/core/middlewares.py
import time
from starlette.middleware.base import BaseHTTPMiddleware
from starlette.requests import Request

class LoggingMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request: Request, call_next):
        start = time.time()
        response = await call_next(request)
        duration = round((time.time() - start) * 1000, 2)

        await logger.a_info(
            "request.completed",
            method=request.method,
            url=str(request.url),
            status=response.status_code,
            duration_ms=duration,
        )
        return response
```

### Health Checks

```python
# In app/main.py or a dedicated health module
from fastapi import APIRouter

health_router = APIRouter(tags=["Health"])

@health_router.get("/health")
async def health_check():
    return {"status": "healthy"}

@health_router.get("/health/ready")
async def readiness_check(db: DBSessionDep):
    try:
        await db.execute("SELECT 1")
        return {"status": "ready", "database": "connected"}
    except Exception:
        return {"status": "not_ready", "database": "disconnected"}
```

---

## Environment Configuration

```bash
# docker/.env.example
ENVIRONMENT=local

# Database
POSTGRES_HOST=db
POSTGRES_PORT=5432
POSTGRES_USER=postgres
POSTGRES_PASSWORD=postgres
POSTGRES_DB=my_app

# Redis
REDIS_HOST=redis
REDIS_PORT=6379

# Auth
AUTH_JWT_SECRET_KEY=change-me-in-production
AUTH_ACCESS_TOKEN_EXPIRE_MINUTES=30
AUTH_REFRESH_TOKEN_EXPIRE_DAYS=7

# Email
SMTP_HOST=mailhog
SMTP_PORT=1025
SMTP_USER=
SMTP_PASSWORD=

# Logging
LOG_LEVEL=INFO
SQL_ECHO=false

# Rate Limiting
RATE_LIMIT_ENABLED=true
```

---

## Production Checklist

- [ ] Set strong `JWT_SECRET_KEY` (min 32 chars, random)
- [ ] Enable HTTPS (TLS termination at load balancer)
- [ ] Configure CORS for allowed origins only
- [ ] Set `SQL_ECHO=false` in production
- [ ] Use connection pooling (`pool_size=20`, `max_overflow=40`)
- [ ] Set up database backups (automated daily)
- [ ] Configure Redis persistence (AOF or RDB)
- [ ] Set up monitoring (Prometheus + Grafana)
- [ ] Configure log aggregation (ELK or CloudWatch)
- [ ] Set up alerting for error rates and latency
- [ ] Run database migrations in CI/CD pipeline
- [ ] Use Docker multi-stage builds for smaller images
- [ ] Set resource limits on containers (CPU, memory)
