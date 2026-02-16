# FastAPI Architecture Decision Guide

When to use FastAPI Modular Monolith vs. other architectures and frameworks.

---

## Why FastAPI for Modular Monoliths?

| FastAPI Strength | How It Enables Modular Monoliths |
|-----------------|----------------------------------|
| **Performance** | Starlette + Pydantic: one of the fastest Python web frameworks |
| **Async-First** | Native `async/await` for non-blocking I/O across modules |
| **Dependency Injection** | `Depends()` naturally enforces module boundaries and loose coupling |
| **Type Hints** | Pydantic v2 ensures data contracts between modules are explicit and validated |
| **Auto Documentation** | OpenAPI/Swagger generated per module via router tags |
| **Router System** | Hierarchical routers map cleanly to module → version → resource |
| **Lifespan Events** | Startup/shutdown hooks for initializing module services |

---

## Decision Framework

### Choose FastAPI Modular Monolith When:

| Signal | Why It Fits |
|--------|-------------|
| Team size 2–20 Python developers | Module boundaries without microservice overhead |
| API-centric application | FastAPI excels at REST/GraphQL APIs, not server-rendered HTML |
| Greenfield project, unclear domains | Learn boundaries before committing to service splits |
| Strong data consistency required | ACID transactions across modules with SQLAlchemy |
| Async workloads (I/O heavy) | FastAPI's async nature handles concurrent requests efficiently |
| Rapid development needed | Auto docs, type safety, hot reload accelerate iteration |
| Python ML/AI integration | Same language for API and ML model serving |

### Choose Django Modular Monolith When:

| Signal | Why Django Fits Better |
|--------|----------------------|
| Full-stack with server-rendered templates | Django's template engine + admin panel |
| ORM-heavy with complex queries | Django ORM's mature query API and admin |
| Team already proficient in Django | Familiarity reduces onboarding time |
| Built-in admin panel needed | Django Admin is unmatched for data management |
| Batteries-included preference | Auth, forms, sessions built-in |

### Choose Microservices When:

| Signal | Why Microservices Fits |
|--------|----------------------|
| 50+ developers, 5+ independent teams | Need full deployment autonomy |
| Polyglot tech stack required | Python ML + Go APIs + Java enterprise |
| Extreme per-service scaling | One component needs 100x the resources |
| Regulatory data isolation | PCI/HIPAA requires process-level boundaries |
| Mature DevOps (K8s, CI/CD, observability) | Infrastructure already exists |

### Choose Simple FastAPI Monolith When:

| Signal | Why Simple Monolith Fits |
|--------|-------------------------|
| Solo developer or 1–3 person team | Module overhead not needed |
| Prototype / MVP / proof of concept | Speed over structure |
| Fewer than 3 business domains | Not enough boundaries to justify modules |
| Simple CRUD API | No complex business logic |

---

## FastAPI vs. Other Python Frameworks for Modular Monoliths

| Aspect | FastAPI | Django | Flask |
|--------|---------|--------|-------|
| **Performance** | Excellent (async, Starlette) | Good (sync by default) | Good (sync, lightweight) |
| **Async Support** | Native, first-class | Added in 3.1+ (ASGI) | Via extensions (Quart) |
| **Dependency Injection** | Built-in `Depends()` | Implicit (middleware, decorators) | Manual or Flask-Inject |
| **Type Safety** | Pydantic v2 + type hints | Serializers (DRF) | Marshmallow |
| **Auto API Docs** | Built-in (OpenAPI/Swagger) | Via DRF + drf-spectacular | Via Flask-RESTX |
| **Module Boundaries** | Routers + DI enforcement | Django apps + INSTALLED_APPS | Blueprints |
| **ORM** | SQLAlchemy (choice) | Django ORM (built-in) | SQLAlchemy (choice) |
| **Admin Panel** | Third-party (SQLAdmin) | Built-in (powerful) | Flask-Admin |
| **Best For** | API-first, async, high-perf | Full-stack, admin-heavy | Lightweight, flexible |

---

## Migration Path: FastAPI Modular Monolith → Microservices

### Phase 1: Start Modular
1. Build the application as a FastAPI Modular Monolith
2. Enforce strict module boundaries (architecture tests with `ast` import analysis)
3. Use gateway contracts for all inter-module communication
4. Use `fastapi-events` with the same interface pattern as a message broker

### Phase 2: Identify Extraction Candidates
Extract a module when you observe:
- **Scaling divergence**: Module needs 10x the resources of others
- **Tech stack mismatch**: Module needs Go/Rust for performance
- **Team autonomy demand**: Team wants independent deployment cadence
- **Performance bottleneck**: Module's async workload saturates the event loop
- **Regulatory requirement**: Data must be in a separate process/network

### Phase 3: Extract
1. Replace gateway contract (in-process call) with HTTP client (httpx async)
2. Swap `fastapi-events` for Kafka/RabbitMQ for that module's events
3. Migrate module's SQLAlchemy models and Alembic migrations to a separate database
4. Deploy the extracted module as a standalone FastAPI service
5. Keep remaining modules as a monolith

### Phase 4: Stabilize
- Add circuit breakers (tenacity for retries)
- Set up distributed tracing (OpenTelemetry + Jaeger)
- Monitor latency and error rates at the boundary
- Roll back if extraction creates more problems than it solves

---

## Real-World Precedents

| Company/Project | Approach | Why |
|----------------|----------|-----|
| **Shopify** | Modular Monolith (Rails) | 1000+ devs, chose modules over microservices |
| **GitHub** | Modular Monolith (Rails) | Modular components in single codebase |
| **Netflix** | Started monolith → extracted | Microservices only when scale demanded |
| **CodeSwiftr** | FastAPI Modular Monolith | Blueprint for Conduit Medium clone |
| **Google Service Weaver** | Modular → microservices | Write modular, deploy as microservices |

---

## Anti-Patterns to Avoid

### 1. The "Distributed Monolith"
**Symptom**: Microservices that share a database and deploy together.
**Fix**: That's a modular monolith with network overhead. Remove the network calls.

### 2. The "Fat Core"
**Symptom**: `app/core/` grows to contain business logic used by multiple modules.
**Fix**: If two modules need the same business logic, one module owns it and the other uses the gateway.

### 3. The "Leaky Boundary"
**Symptom**: Modules import each other's internal models/services directly.
**Fix**: Add architecture tests that fail on direct internal imports. Run in CI.

### 4. The "God Module"
**Symptom**: One module has 60% of the code and touches every other module.
**Fix**: Split it into sub-domains.

### 5. The "Sync Everything"
**Symptom**: Using synchronous database calls in an async FastAPI app.
**Fix**: Use `SQLAlchemy async`, `aiosmtplib`, `aiocache` — keep the event loop free.

### 6. The "Premature Extraction"
**Symptom**: Extracting modules to microservices before proving the need.
**Fix**: Extract only with measurable evidence (scaling, team autonomy, tech stack).
