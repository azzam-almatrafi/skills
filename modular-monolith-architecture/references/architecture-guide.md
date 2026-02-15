# Architecture Decision Guide

When to use Modular Monolith vs. other architectures, and how to make the transition.

---

## Decision Framework

### Choose Modular Monolith When:

| Signal | Why Modular Monolith Fits |
|--------|--------------------------|
| Team size 2–30 developers | Microservices overhead not justified |
| Greenfield project, unclear domains | Learn boundaries before committing to service splits |
| Strong data consistency required | ACID transactions across modules are trivial |
| On-premise deployment | Single binary vastly simpler for customers |
| Modernizing a legacy monolith | Incremental refactoring without big-bang rewrite |
| Startup/early-stage product | Ship fast, defer infrastructure complexity |
| Shared database is acceptable | No regulatory requirement for data isolation |

### Choose Microservices When:

| Signal | Why Microservices Fits |
|--------|----------------------|
| 50+ developers, 5+ independent teams | Need full deployment autonomy |
| Polyglot tech stack required | Python ML + Go APIs + Java enterprise |
| Extreme per-service scaling | One component needs 100x the resources |
| Regulatory data isolation | PCI/HIPAA requires process-level boundaries |
| Mature DevOps (K8s, CI/CD, observability) | Infrastructure already exists |
| Well-understood domain boundaries | Bounded contexts are proven and stable |

### Choose Simple Monolith When:

| Signal | Why Simple Monolith Fits |
|--------|-------------------------|
| Solo developer or 1–3 person team | Module overhead not needed |
| Prototype / MVP / proof of concept | Speed over structure |
| Fewer than 3 business domains | Not enough boundaries to justify modules |
| Throwaway or short-lived project | Won't need to maintain it |

---

## Modular Monolith vs. Microservices Comparison

| Aspect | Modular Monolith | Microservices |
|--------|-----------------|---------------|
| **Deployment** | Single unit | Independent per service |
| **Communication** | In-process calls (ns latency) | Network calls (ms latency) |
| **Data** | Shared DB, isolated schemas | Database per service |
| **Consistency** | ACID transactions | Sagas, eventual consistency |
| **Ops Complexity** | Low — 1 binary, 1 deploy pipeline | High — K8s, service mesh, tracing |
| **Team Autonomy** | Moderate — shared codebase/release | High — independent stacks/releases |
| **Tech Stack** | Single | Polyglot |
| **Fault Isolation** | Bug can crash entire app | Failures contained per service |
| **Testing** | Easy E2E, standard integration tests | Contract tests, distributed tracing |
| **Time to Market** | Fast (simple infra) | Slower (infra setup overhead) |
| **Migration Path** | Extract modules → microservices | Already decomposed |
| **Best For** | Early-to-mid stage, <30 devs | Large orgs, mature DevOps |

---

## Migration Path: Modular Monolith → Microservices

### Phase 1: Start Modular
1. Build the application as a Modular Monolith
2. Enforce strict module boundaries (architecture tests)
3. Use module contracts (interfaces) for all inter-module communication
4. Use an in-process event bus with the same interface as a message broker

### Phase 2: Identify Extraction Candidates
Extract a module when you observe one or more of these signals:
- **Scaling divergence**: Module needs 10x the resources of others
- **Tech stack mismatch**: Module needs Python for ML but app is in Java
- **Team autonomy demand**: Team wants independent deployment cadence
- **Performance bottleneck**: Module slows down the entire application
- **Regulatory requirement**: Data must be in a separate process/network

### Phase 3: Extract
1. Replace module contract (in-process interface) with HTTP/gRPC client
2. Swap in-process event bus for RabbitMQ/Kafka for that module's events
3. Migrate module's database schema to a separate database
4. Deploy the extracted module as a standalone service
5. Keep remaining modules as a monolith (no need to extract everything)

### Phase 4: Stabilize
- Add circuit breakers for the new network calls
- Set up distributed tracing (OpenTelemetry)
- Monitor latency and error rates at the boundary
- Roll back if extraction creates more problems than it solves

---

## Real-World Precedents

| Company | Approach | Why |
|---------|----------|-----|
| **Shopify** | Modular Monolith (Ruby on Rails) | 1000+ developers, chose modules over microservices for cohesion |
| **GitHub** | Modular Monolith (Ruby on Rails) | Modular components (repos, issues, PRs) in single codebase |
| **Appsmith** | Modular Monolith | On-premise deployment requires single binary |
| **Gusto** | Modular Monolith | Cheaper to fix wrong boundaries in monolith than microservices |
| **Google** | Service Weaver (Go) | Framework to write modular code, deploy as microservices |
| **Basecamp** | Modular Monolith (Rails) | Rapid iteration with modular components |

---

## Framework Recommendations by Language

| Language | Recommended Framework | Module Boundary Enforcement |
|----------|----------------------|---------------------------|
| **C# / .NET** | ASP.NET Core + MediatR | NetArchTest, separate assemblies per module |
| **Java** | Spring Boot + Spring Modulith | ArchUnit, package-private access modifiers |
| **TypeScript** | NestJS | @Module imports/exports, eslint-plugin-import |
| **Go** | Standard library or Service Weaver | `internal/` directories, interface contracts |
| **Python** | Django (apps) or FastAPI | Import analysis tests, contracts.py pattern |
| **PHP** | Laravel (service providers) | Dependency injection, package contracts |
| **Ruby** | Rails (engines) | Packwerk gem for boundary enforcement |

---

## Anti-Patterns to Avoid

### 1. The "Distributed Monolith"
**Symptom**: You have microservices, but they all share a database and deploy together.
**Fix**: That's a modular monolith with network overhead. Remove the network calls and embrace the monolith.

### 2. The "Shared Domain" Trap
**Symptom**: Your shared kernel grows to contain business logic used by multiple modules.
**Fix**: If two modules need the same business logic, one module owns it and the other uses the contract.

### 3. The "Leaky Boundary"
**Symptom**: Modules reference each other's internal types instead of contracts.
**Fix**: Add architecture tests that fail on direct internal imports. Run them in CI.

### 4. The "God Module"
**Symptom**: One module contains 60% of the code and touches every other module.
**Fix**: Split it. If you can identify sub-domains within it, they should be separate modules.

### 5. The "Premature Extraction"
**Symptom**: Extracting modules to microservices "just in case" before proving the need.
**Fix**: Extract only when you have measurable evidence (scaling, team autonomy, tech stack).

### 6. The "Cross-Schema Query"
**Symptom**: Writing SQL JOINs across module schemas for reporting or convenience.
**Fix**: Use module contracts to fetch data, or create a dedicated Reporting module with read replicas.
