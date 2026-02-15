# TypeScript / NestJS — Example Scaffold

A concrete example of a generated Modular Monolith for a SaaS application with Tenant, Billing, and Notification modules.

---

## Generated File Tree

```
saas-app/
├── src/
│   ├── main.ts
│   ├── app.module.ts
│   │
│   ├── shared/
│   │   ├── domain/
│   │   │   ├── base-entity.ts
│   │   │   ├── domain-event.ts
│   │   │   ├── value-object.ts
│   │   │   └── aggregate-root.ts
│   │   ├── events/
│   │   │   ├── event-bus.interface.ts
│   │   │   ├── in-memory-event-bus.ts
│   │   │   └── event-bus.module.ts
│   │   ├── contracts/
│   │   │   ├── events/
│   │   │   │   ├── tenant-created.event.ts
│   │   │   │   ├── subscription-activated.event.ts
│   │   │   │   └── payment-received.event.ts
│   │   │   └── dtos/
│   │   │       ├── tenant.dto.ts
│   │   │       ├── billing.dto.ts
│   │   │       └── pagination.dto.ts
│   │   └── shared.module.ts
│   │
│   └── modules/
│       ├── tenant/
│       │   ├── domain/
│       │   │   ├── entities/
│       │   │   │   ├── tenant.entity.ts
│       │   │   │   └── tenant-settings.entity.ts
│       │   │   ├── value-objects/
│       │   │   │   ├── tenant-id.vo.ts
│       │   │   │   └── tenant-plan.vo.ts
│       │   │   ├── repositories/
│       │   │   │   └── tenant.repository.interface.ts
│       │   │   └── events/
│       │   │       └── tenant-created.domain-event.ts
│       │   ├── application/
│       │   │   ├── commands/
│       │   │   │   ├── create-tenant/
│       │   │   │   │   ├── create-tenant.command.ts
│       │   │   │   │   ├── create-tenant.handler.ts
│       │   │   │   │   └── create-tenant.validator.ts
│       │   │   │   └── update-tenant/
│       │   │   │       ├── update-tenant.command.ts
│       │   │   │       └── update-tenant.handler.ts
│       │   │   ├── queries/
│       │   │   │   ├── get-tenant-by-id.query.ts
│       │   │   │   └── get-tenant-by-id.handler.ts
│       │   │   └── dtos/
│       │   │       └── tenant-response.dto.ts
│       │   ├── infrastructure/
│       │   │   ├── persistence/
│       │   │   │   ├── tenant.schema.ts
│       │   │   │   └── tenant.repository.ts
│       │   │   └── tenant-infrastructure.module.ts
│       │   ├── api/
│       │   │   └── tenant-module.interface.ts
│       │   ├── controllers/
│       │   │   └── tenant.controller.ts
│       │   └── tenant.module.ts
│       │
│       ├── billing/
│       │   ├── domain/
│       │   │   ├── entities/
│       │   │   │   ├── subscription.entity.ts
│       │   │   │   └── invoice.entity.ts
│       │   │   ├── value-objects/
│       │   │   │   ├── subscription-id.vo.ts
│       │   │   │   ├── billing-cycle.vo.ts
│       │   │   │   └── money.vo.ts
│       │   │   └── repositories/
│       │   │       ├── subscription.repository.interface.ts
│       │   │       └── invoice.repository.interface.ts
│       │   ├── application/
│       │   │   ├── commands/
│       │   │   │   ├── activate-subscription/
│       │   │   │   │   ├── activate-subscription.command.ts
│       │   │   │   │   └── activate-subscription.handler.ts
│       │   │   │   └── process-payment/
│       │   │   │       ├── process-payment.command.ts
│       │   │   │       └── process-payment.handler.ts
│       │   │   ├── queries/
│       │   │   │   └── get-subscription/
│       │   │   │       ├── get-subscription.query.ts
│       │   │   │       └── get-subscription.handler.ts
│       │   │   └── event-handlers/
│       │   │       └── on-tenant-created.handler.ts
│       │   ├── infrastructure/
│       │   │   ├── persistence/
│       │   │   │   ├── subscription.schema.ts
│       │   │   │   ├── invoice.schema.ts
│       │   │   │   ├── subscription.repository.ts
│       │   │   │   └── invoice.repository.ts
│       │   │   └── billing-infrastructure.module.ts
│       │   ├── api/
│       │   │   └── billing-module.interface.ts
│       │   ├── controllers/
│       │   │   ├── subscription.controller.ts
│       │   │   └── invoice.controller.ts
│       │   └── billing.module.ts
│       │
│       └── notification/
│           ├── domain/
│           │   ├── entities/
│           │   │   └── notification.entity.ts
│           │   ├── value-objects/
│           │   │   └── notification-channel.vo.ts
│           │   └── repositories/
│           │       └── notification.repository.interface.ts
│           ├── application/
│           │   ├── commands/
│           │   │   └── send-notification/
│           │   │       ├── send-notification.command.ts
│           │   │       └── send-notification.handler.ts
│           │   └── event-handlers/
│           │       ├── on-tenant-created.handler.ts
│           │       ├── on-subscription-activated.handler.ts
│           │       └── on-payment-received.handler.ts
│           ├── infrastructure/
│           │   ├── persistence/
│           │   │   ├── notification.schema.ts
│           │   │   └── notification.repository.ts
│           │   ├── providers/
│           │   │   ├── email.provider.ts
│           │   │   └── slack.provider.ts
│           │   └── notification-infrastructure.module.ts
│           ├── api/
│           │   └── notification-module.interface.ts
│           ├── controllers/
│           │   └── notification.controller.ts
│           └── notification.module.ts
│
├── database/
│   └── migrations/
│       ├── tenant/
│       │   └── 001_create_tenants.ts
│       ├── billing/
│       │   ├── 001_create_subscriptions.ts
│       │   └── 002_create_invoices.ts
│       └── notification/
│           └── 001_create_notifications.ts
│
├── test/
│   ├── modules/
│   │   ├── tenant/
│   │   │   ├── tenant.service.spec.ts
│   │   │   └── tenant.e2e-spec.ts
│   │   ├── billing/
│   │   │   ├── subscription.service.spec.ts
│   │   │   └── billing.e2e-spec.ts
│   │   └── notification/
│   │       └── notification.service.spec.ts
│   ├── contracts/
│   │   ├── tenant-module-contract.spec.ts
│   │   └── billing-module-contract.spec.ts
│   └── architecture/
│       └── module-boundaries.spec.ts
│
├── package.json
├── tsconfig.json
├── tsconfig.build.json
├── nest-cli.json
├── docker-compose.yml
├── Dockerfile
├── .eslintrc.js
└── README.md
```

---

## Key Generated Files

### app.module.ts (Composition Root)

```typescript
import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { SharedModule } from './shared/shared.module';
import { TenantModule } from './modules/tenant/tenant.module';
import { BillingModule } from './modules/billing/billing.module';
import { NotificationModule } from './modules/notification/notification.module';

@Module({
  imports: [
    TypeOrmModule.forRoot({
      type: 'postgres',
      host: process.env.DB_HOST || 'localhost',
      port: parseInt(process.env.DB_PORT || '5432'),
      username: process.env.DB_USER || 'postgres',
      password: process.env.DB_PASSWORD || 'postgres',
      database: process.env.DB_NAME || 'saas_app',
      autoLoadEntities: true,
    }),
    SharedModule,
    TenantModule,
    BillingModule,
    NotificationModule,
  ],
})
export class AppModule {}
```

### Module Contract (tenant-module.interface.ts)

```typescript
export interface ITenantModule {
  getTenantById(id: string): Promise<TenantDto | null>;
  getTenantsByIds(ids: string[]): Promise<TenantDto[]>;
  isTenantActive(tenantId: string): Promise<boolean>;
}
```

### Module Definition (tenant.module.ts)

```typescript
import { Module } from '@nestjs/common';
import { CqrsModule } from '@nestjs/cqrs';
import { SharedModule } from '../../shared/shared.module';
import { TenantInfrastructureModule } from './infrastructure/tenant-infrastructure.module';
import { TenantController } from './controllers/tenant.controller';
import { CreateTenantHandler } from './application/commands/create-tenant/create-tenant.handler';
import { GetTenantByIdHandler } from './application/queries/get-tenant-by-id.handler';
import { TenantService } from './application/tenant.service';

const CommandHandlers = [CreateTenantHandler, UpdateTenantHandler];
const QueryHandlers = [GetTenantByIdHandler];

@Module({
  imports: [CqrsModule, SharedModule, TenantInfrastructureModule],
  controllers: [TenantController],
  providers: [
    TenantService,
    ...CommandHandlers,
    ...QueryHandlers,
  ],
  exports: [TenantService], // Public contract only
})
export class TenantModule {}
```

### Module Boundary Test (module-boundaries.spec.ts)

```typescript
import * as fs from 'fs';
import * as path from 'path';

const MODULES_DIR = path.join(__dirname, '../../src/modules');

function getAllTsFiles(dir: string): string[] {
  const files: string[] = [];
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const fullPath = path.join(dir, entry.name);
    if (entry.isDirectory()) files.push(...getAllTsFiles(fullPath));
    else if (entry.name.endsWith('.ts') && !entry.name.endsWith('.spec.ts'))
      files.push(fullPath);
  }
  return files;
}

const modules = fs.readdirSync(MODULES_DIR).filter(f =>
  fs.statSync(path.join(MODULES_DIR, f)).isDirectory()
);

describe('Module Boundaries', () => {
  for (const source of modules) {
    for (const target of modules) {
      if (source === target) continue;

      it(`${source} should not import ${target} internals`, () => {
        const files = getAllTsFiles(path.join(MODULES_DIR, source));
        for (const file of files) {
          const content = fs.readFileSync(file, 'utf-8');
          const internalImport = new RegExp(
            `from ['"].*modules/${target}/(?!api/)`,
          );
          expect(content).not.toMatch(internalImport);
        }
      });
    }
  }

  it('shared kernel should not import from any module', () => {
    const sharedDir = path.join(__dirname, '../../src/shared');
    const files = getAllTsFiles(sharedDir);
    for (const file of files) {
      const content = fs.readFileSync(file, 'utf-8');
      expect(content).not.toMatch(/from ['"].*modules\//);
    }
  });
});
```

### docker-compose.yml

```yaml
services:
  app:
    build: .
    ports:
      - "3000:3000"
    environment:
      - DB_HOST=db
      - DB_PORT=5432
      - DB_USER=postgres
      - DB_PASSWORD=postgres
      - DB_NAME=saas_app
      - NODE_ENV=development
    depends_on:
      db:
        condition: service_healthy

  db:
    image: postgres:16-alpine
    environment:
      POSTGRES_DB: saas_app
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

volumes:
  postgres_data:
```

### package.json (Key Dependencies)

```json
{
  "name": "saas-app",
  "version": "1.0.0",
  "scripts": {
    "build": "nest build",
    "start": "nest start",
    "start:dev": "nest start --watch",
    "test": "jest",
    "test:e2e": "jest --config ./test/jest-e2e.json",
    "test:arch": "jest --testPathPattern=architecture",
    "lint": "eslint \"{src,test}/**/*.ts\" --fix",
    "migration:run": "typeorm migration:run",
    "migration:generate": "typeorm migration:generate"
  },
  "dependencies": {
    "@nestjs/common": "^10.0.0",
    "@nestjs/core": "^10.0.0",
    "@nestjs/cqrs": "^10.0.0",
    "@nestjs/typeorm": "^10.0.0",
    "@nestjs/terminus": "^10.0.0",
    "typeorm": "^0.3.0",
    "pg": "^8.11.0",
    "class-validator": "^0.14.0",
    "class-transformer": "^0.5.0"
  },
  "devDependencies": {
    "@nestjs/testing": "^10.0.0",
    "jest": "^29.0.0",
    "ts-jest": "^29.0.0",
    "typescript": "^5.0.0",
    "@types/jest": "^29.0.0",
    "supertest": "^6.0.0"
  }
}
```
