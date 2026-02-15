# {{PROJECT_NAME}} — Modular Monolithic Architecture

> A production-ready application built with Modular Monolithic Architecture.

## Architecture Overview

This project follows the **Modular Monolith** pattern: a single deployable application organized into independent, loosely coupled modules. Each module represents a bounded context and owns its domain logic, data access, and API surface.

```
┌─────────────────────────────────────────────────────┐
│                     Application                      │
│                                                     │
│  ┌───────────┐  ┌───────────┐  ┌───────────┐      │
│  │  Module A  │  │  Module B  │  │  Module C  │      │
│  │           │  │           │  │           │      │
│  │  Domain   │  │  Domain   │  │  Domain   │      │
│  │  App      │  │  App      │  │  App      │      │
│  │  Infra    │  │  Infra    │  │  Infra    │      │
│  │  API      │  │  API      │  │  API      │      │
│  └───────────┘  └───────────┘  └───────────┘      │
│         │              │              │             │
│         └──────────────┼──────────────┘             │
│                        │ (contracts only)            │
│  ┌─────────────────────┴─────────────────────────┐  │
│  │              Shared Kernel                     │  │
│  │  (base entities, events, value objects)         │  │
│  └────────────────────────────────────────────────┘  │
│                        │                             │
│  ┌─────────────────────┴─────────────────────────┐  │
│  │              Database (RDBMS)                   │  │
│  │  ┌──────────┐ ┌──────────┐ ┌──────────┐       │  │
│  │  │ Schema A │ │ Schema B │ │ Schema C │       │  │
│  │  └──────────┘ └──────────┘ └──────────┘       │  │
│  └────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────┘
```

## Modules

| Module | Description | Schema |
|--------|-------------|--------|
{{MODULE_TABLE}}

## Key Rules

1. **Modules communicate only through contracts** — never reference another module's internal types
2. **Each module owns its data** — separate database schema, no cross-schema foreign keys
3. **Shared kernel is thin** — only cross-cutting concerns, never business logic
4. **Architecture tests enforce boundaries** — run in CI to prevent boundary erosion

## Getting Started

### Prerequisites
{{PREREQUISITES}}

### Running Locally

```bash
{{RUN_COMMANDS}}
```

### Running with Docker

```bash
docker-compose up -d
```

## How to Add a New Module

1. Create the module directory structure:
   ```
   modules/new-module/
   ├── domain/        # Entities, value objects, repository interfaces
   ├── application/   # Use cases, commands, queries, DTOs
   ├── infrastructure/ # Repository implementations, DB config
   └── api/           # Controllers, public contract interface
   ```

2. Define the public contract (the interface other modules can use)

3. Create database migrations in the module's migration folder

4. Register the module in the composition root ({{COMPOSITION_FILE}})

5. Add architecture boundary tests for the new module

## Testing

```bash
# Unit tests
{{UNIT_TEST_CMD}}

# Integration tests
{{INTEGRATION_TEST_CMD}}

# Architecture boundary tests
{{ARCH_TEST_CMD}}
```

## Migration to Microservices

When a module needs independent scaling or deployment:

1. Replace the in-process module contract with an HTTP/gRPC client
2. Swap the in-memory event bus for RabbitMQ/Kafka for that module
3. Migrate the module's schema to a separate database
4. Deploy as a standalone service

The module boundaries are designed to make this extraction low-risk.
