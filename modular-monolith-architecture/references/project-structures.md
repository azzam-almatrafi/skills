# Project Structure Reference

Detailed directory structures for Modular Monolith projects across frameworks.

---

## .NET / ASP.NET Core (C#)

```
MyApp/
├── src/
│   ├── MyApp.Host/                          # Entry point & composition root
│   │   ├── Program.cs                       # Wires all modules together
│   │   ├── appsettings.json                 # Shared configuration
│   │   ├── Middleware/                       # Global middleware (auth, error handling)
│   │   └── MyApp.Host.csproj
│   │
│   ├── MyApp.Shared/                        # Shared kernel
│   │   ├── Abstractions/
│   │   │   ├── IEntity.cs
│   │   │   ├── IDomainEvent.cs
│   │   │   └── IEventBus.cs
│   │   ├── ValueObjects/
│   │   │   ├── Money.cs
│   │   │   └── Email.cs
│   │   ├── Events/                          # Integration event contracts
│   │   │   ├── OrderPlacedEvent.cs
│   │   │   └── PaymentCompletedEvent.cs
│   │   └── MyApp.Shared.csproj
│   │
│   ├── Modules/
│   │   ├── Product/
│   │   │   ├── MyApp.Modules.Product.Domain/
│   │   │   │   ├── Entities/
│   │   │   │   │   └── Product.cs
│   │   │   │   ├── ValueObjects/
│   │   │   │   │   └── ProductId.cs
│   │   │   │   ├── Repositories/
│   │   │   │   │   └── IProductRepository.cs
│   │   │   │   └── Events/
│   │   │   │       └── ProductCreatedDomainEvent.cs
│   │   │   │
│   │   │   ├── MyApp.Modules.Product.Application/
│   │   │   │   ├── Commands/
│   │   │   │   │   ├── CreateProduct/
│   │   │   │   │   │   ├── CreateProductCommand.cs
│   │   │   │   │   │   └── CreateProductHandler.cs
│   │   │   │   │   └── UpdateProduct/
│   │   │   │   ├── Queries/
│   │   │   │   │   └── GetProducts/
│   │   │   │   │       ├── GetProductsQuery.cs
│   │   │   │   │       └── GetProductsHandler.cs
│   │   │   │   ├── DTOs/
│   │   │   │   │   └── ProductDto.cs
│   │   │   │   └── Contracts/               # PUBLIC interface for other modules
│   │   │   │       └── IProductModule.cs
│   │   │   │
│   │   │   ├── MyApp.Modules.Product.Infrastructure/
│   │   │   │   ├── Persistence/
│   │   │   │   │   ├── ProductDbContext.cs
│   │   │   │   │   ├── ProductRepository.cs
│   │   │   │   │   └── Configurations/
│   │   │   │   │       └── ProductConfiguration.cs
│   │   │   │   ├── Migrations/
│   │   │   │   └── ProductModuleInstaller.cs  # DI registration
│   │   │   │
│   │   │   └── MyApp.Modules.Product.Api/
│   │   │       ├── Controllers/
│   │   │       │   └── ProductsController.cs
│   │   │       └── Requests/
│   │   │           └── CreateProductRequest.cs
│   │   │
│   │   ├── Order/                           # Same structure as Product
│   │   │   ├── MyApp.Modules.Order.Domain/
│   │   │   ├── MyApp.Modules.Order.Application/
│   │   │   ├── MyApp.Modules.Order.Infrastructure/
│   │   │   └── MyApp.Modules.Order.Api/
│   │   │
│   │   └── Payment/                         # Same structure
│   │       └── ...
│   │
│   └── MyApp.Infrastructure/               # Shared infrastructure
│       ├── EventBus/
│       │   ├── InMemoryEventBus.cs          # In-process (upgradeable to RabbitMQ)
│       │   └── EventBusRegistration.cs
│       ├── Persistence/
│       │   └── DatabaseMigrator.cs
│       └── MyApp.Infrastructure.csproj
│
├── tests/
│   ├── Modules/
│   │   ├── Product.UnitTests/
│   │   ├── Product.IntegrationTests/
│   │   ├── Order.UnitTests/
│   │   └── Order.IntegrationTests/
│   └── MyApp.ArchitectureTests/             # Enforce module boundaries
│       └── ModuleBoundaryTests.cs
│
├── docker-compose.yml
├── Dockerfile
├── MyApp.sln
└── README.md
```

### Key .NET Implementation Notes
- Use **separate DbContext per module** with schema isolation (`modelBuilder.HasDefaultSchema("product")`)
- **MediatR** for CQRS command/query handling within modules
- **Module installer pattern**: Each module has an `Install(IServiceCollection)` method called from Host
- **Architecture tests** with NetArchTest or ArchUnitNET to enforce boundaries at build time

---

## Java / Spring Boot

```
my-app/
├── src/main/java/com/myapp/
│   ├── MyAppApplication.java                # Entry point
│   │
│   ├── shared/                              # Shared kernel
│   │   ├── domain/
│   │   │   ├── BaseEntity.java
│   │   │   ├── DomainEvent.java
│   │   │   └── ValueObject.java
│   │   ├── events/
│   │   │   ├── EventBus.java
│   │   │   ├── OrderPlacedEvent.java
│   │   │   └── PaymentCompletedEvent.java
│   │   └── infrastructure/
│   │       └── InMemoryEventBus.java
│   │
│   └── modules/
│       ├── product/
│       │   ├── domain/
│       │   │   ├── Product.java
│       │   │   ├── ProductId.java
│       │   │   └── ProductRepository.java   # Interface
│       │   ├── application/
│       │   │   ├── ProductService.java
│       │   │   ├── CreateProductCommand.java
│       │   │   └── ProductDto.java
│       │   ├── api/                          # PUBLIC contract for other modules
│       │   │   └── ProductModuleApi.java     # Interface
│       │   ├── infrastructure/
│       │   │   ├── JpaProductRepository.java
│       │   │   ├── ProductJpaEntity.java
│       │   │   └── ProductModuleConfiguration.java
│       │   └── web/
│       │       ├── ProductController.java
│       │       └── CreateProductRequest.java
│       │
│       ├── order/                            # Same structure
│       │   ├── domain/
│       │   ├── application/
│       │   ├── api/
│       │   ├── infrastructure/
│       │   └── web/
│       │
│       └── payment/
│           └── ...
│
├── src/main/resources/
│   ├── application.yml
│   └── db/migration/
│       ├── product/
│       │   └── V1__create_products.sql
│       └── order/
│           └── V1__create_orders.sql
│
├── src/test/java/com/myapp/
│   ├── modules/
│   │   ├── product/
│   │   │   ├── ProductServiceTest.java
│   │   │   └── ProductIntegrationTest.java
│   │   └── order/
│   ├── architecture/
│   │   └── ModuleBoundaryTest.java          # ArchUnit tests
│   └── MyAppApplicationTests.java
│
├── pom.xml (or build.gradle)
├── docker-compose.yml
├── Dockerfile
└── README.md
```

### Key Spring Boot Notes
- Use **Spring Modulith** for module boundary validation and documentation
- **Flyway/Liquibase** with per-module migration directories
- **`@ApplicationModuleTest`** for module-scoped integration tests
- **Package-private** classes for internal module types (Java access modifiers enforce boundaries)
- **Spring Events** for in-process inter-module communication

---

## TypeScript / NestJS

```
my-app/
├── src/
│   ├── main.ts                              # Entry point
│   ├── app.module.ts                        # Root module — imports all feature modules
│   │
│   ├── shared/                              # Shared kernel
│   │   ├── domain/
│   │   │   ├── base-entity.ts
│   │   │   ├── domain-event.ts
│   │   │   └── value-object.ts
│   │   ├── events/
│   │   │   ├── event-bus.interface.ts
│   │   │   ├── event-bus.module.ts
│   │   │   └── in-memory-event-bus.ts
│   │   ├── contracts/                       # Cross-module DTOs/interfaces
│   │   │   ├── order-placed.event.ts
│   │   │   └── payment-completed.event.ts
│   │   └── shared.module.ts
│   │
│   └── modules/
│       ├── product/
│       │   ├── domain/
│       │   │   ├── entities/
│       │   │   │   └── product.entity.ts
│       │   │   ├── value-objects/
│       │   │   │   └── product-id.vo.ts
│       │   │   └── repositories/
│       │   │       └── product.repository.interface.ts
│       │   ├── application/
│       │   │   ├── commands/
│       │   │   │   ├── create-product.command.ts
│       │   │   │   └── create-product.handler.ts
│       │   │   ├── queries/
│       │   │   │   └── get-products.handler.ts
│       │   │   └── dtos/
│       │   │       └── product.dto.ts
│       │   ├── infrastructure/
│       │   │   ├── persistence/
│       │   │   │   ├── product.schema.ts         # TypeORM/Prisma entity
│       │   │   │   └── product.repository.ts     # Implementation
│       │   │   └── product-infrastructure.module.ts
│       │   ├── api/                              # PUBLIC contract
│       │   │   └── product-module.interface.ts
│       │   ├── controllers/
│       │   │   └── product.controller.ts
│       │   └── product.module.ts                 # NestJS module definition
│       │
│       ├── order/                                # Same structure
│       └── payment/
│
├── database/
│   └── migrations/
│       ├── product/
│       └── order/
│
├── test/
│   ├── modules/
│   │   ├── product/
│   │   │   ├── product.service.spec.ts
│   │   │   └── product.e2e-spec.ts
│   │   └── order/
│   └── architecture/
│       └── module-boundaries.spec.ts
│
├── package.json
├── tsconfig.json
├── nest-cli.json
├── docker-compose.yml
├── Dockerfile
└── README.md
```

### Key NestJS Notes
- NestJS modules naturally enforce boundaries via `@Module({ imports, exports })`
- Only export the public contract interface — never internal services
- Use **CQRS module** (`@nestjs/cqrs`) for command/query separation within modules
- **TypeORM** or **Prisma** with schema-per-module isolation

---

## Go

```
my-app/
├── cmd/
│   └── server/
│       └── main.go                              # Entry point & composition root
│
├── internal/
│   ├── shared/                                  # Shared kernel
│   │   ├── events/
│   │   │   ├── bus.go                           # EventBus interface
│   │   │   └── inmemory_bus.go                  # In-process implementation
│   │   ├── contracts/                           # Integration events: publisher & subscriber both import here, so neither couples to the other
│   │   │   └── order_events.go                  # OrderPlaced, PaymentCaptured, ...
│   │   └── valueobjects/
│   │       ├── money.go
│   │       └── email.go
│   │
│   └── modules/
│       ├── product/
│       │   ├── api/                             # PUBLIC contract for OTHER modules; name the package "productapi" (not bare "api") to avoid clashes
│       │   │   └── product_contract.go          # ProductAPI interface + DTOs + command/query in/out types (NOT HTTP)
│       │   ├── internal/                        # per-module internal/ → compiler blocks cross-module imports
│       │   │   ├── domain/
│       │   │   │   ├── product.go
│       │   │   │   └── product_repository.go    # Repository port (interface)
│       │   │   ├── application/
│       │   │   │   ├── commands/
│       │   │   │   │   ├── create_product.go    # CreateProductCommand + handler
│       │   │   │   │   └── update_product.go    # UpdateProductCommand + handler
│       │   │   │   ├── queries/
│       │   │   │   │   ├── get_products.go      # GetProductsQuery + handler
│       │   │   │   │   └── search_products.go   # SearchProductsQuery + handler
│       │   │   │   └── product_service.go       # implements productapi.ProductAPI; delegates to handlers
│       │   │   ├── infrastructure/
│       │   │   │   ├── product_repository_adapter.go  # sqlc / GORM / Ent adapter
│       │   │   │   └── migrations/              # managed by database migration tool (Atlas, golang-migrate, Skeema)
│       │   │   │       └── 001_create_products.sql
│       │   │   └── handler/
│       │   │       ├── product_handler.go       # HTTP handlers (consumer of the contract)
│       │   │       ├── product_requests.go      # request DTOs: decode + validate input
│       │   │       └── product_responses.go     # response DTOs: shape JSON output
│       │   └── product_module.go                # Factory: New(db, bus) builds the graph; exposes API() + RegisterRoutes()
│       │
│       ├── order/                               # Same structure as product
│       │   └── ...
│       └── payment/                             # Same structure
│           └── ...
│
├── pkg/                                         # Public shared utilities (optional)
│   └── httputil/
│       └── response.go
│
├── tests/
│   ├── integration/
│   │   └── wiring_test.go
│   └── architecture/
│       └── boundaries_test.go               # optional in Go: the compiler already enforces cross-module internals
│
├── go.mod
├── go.sum
├── docker-compose.yml
├── Dockerfile
├── Makefile
└── README.md
```

### Key Go Notes
- **`api/` is a standalone subpackage** (sibling of `internal/`) that imports nothing; put the contract here, not in the facade/root package. `internal/handler/` holds the HTTP API.
- **The facade (`product_module.go`) is the only public assembler** — its inputs and outputs must be public types, never `internal/...` types.
- **Keep file names unique across modules** — use `product_contract.go`, `product_handler.go`, etc., not bare `contract.go`/`module.go`, which collide once you have many modules.
- **A module imports its OWN `internal/...` freely** — the facade and layers wire each other; the nested `internal/` only blocks OTHER modules from reaching in.
- **A small module may be a single package** (exported names = its contract, unexported = its internals); add `internal/` layers only as it grows.

---

## Python / Django

```
my_app/
├── manage.py
├── config/                                  # Project configuration
│   ├── __init__.py
│   ├── settings.py                          # INSTALLED_APPS registers all modules
│   ├── urls.py                              # Root URL conf includes module URLs
│   └── wsgi.py
│
├── shared/                                  # Shared kernel (Django app)
│   ├── __init__.py
│   ├── models.py                            # Base models (TimeStampedModel, etc.)
│   ├── events/
│   │   ├── __init__.py
│   │   ├── bus.py                           # EventBus interface
│   │   └── in_memory.py                     # In-process implementation
│   └── value_objects/
│       ├── __init__.py
│       └── money.py
│
├── modules/
│   ├── __init__.py
│   ├── product/                             # Django app per module
│   │   ├── __init__.py
│   │   ├── apps.py                          # AppConfig
│   │   ├── domain/
│   │   │   ├── __init__.py
│   │   │   └── entities.py
│   │   ├── application/
│   │   │   ├── __init__.py
│   │   │   ├── services.py
│   │   │   └── dtos.py
│   │   ├── contracts.py                     # PUBLIC interface for other modules
│   │   ├── models.py                        # Django ORM models
│   │   ├── views.py
│   │   ├── urls.py
│   │   ├── serializers.py                   # DRF serializers
│   │   ├── migrations/
│   │   └── tests/
│   │       ├── __init__.py
│   │       ├── test_services.py
│   │       └── test_views.py
│   │
│   ├── order/                               # Same structure
│   └── payment/
│
├── tests/
│   └── architecture/
│       └── test_boundaries.py               # Import boundary tests
│
├── requirements.txt
├── docker-compose.yml
├── Dockerfile
└── README.md
```

### Key Django Notes
- Each module is a **Django app** registered in `INSTALLED_APPS`
- Use **Django database routers** for per-module schema isolation
- **`contracts.py`** in each module defines the public API — other modules import only from this file
- Write import boundary tests to enforce that modules only use each other's contracts
