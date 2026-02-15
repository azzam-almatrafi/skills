# Testing Strategies for Modular Monoliths

Comprehensive testing patterns for ensuring module correctness, boundary enforcement, and inter-module contract stability.

---

## Testing Pyramid for Modular Monoliths

```
            ┌─────────────┐
            │   E2E Tests  │  Few — critical user flows only
            ├─────────────┤
         ┌──┤  Integration │  Per module — test with real DB/dependencies
         │  ├─────────────┤
         │  │  Contract    │  Cross-module — verify module APIs stay stable
         │  ├─────────────┤
         │  │ Architecture │  Automated — enforce module boundaries in CI
         │  ├─────────────┤
         └──┤  Unit Tests  │  Many — domain logic, application services
            └─────────────┘
```

---

## 1. Unit Tests (Per Module)

Test domain logic and application services in isolation. Mock all external dependencies (repositories, event bus, other module contracts).

### Domain Layer

```typescript
// order/domain/__tests__/order.spec.ts
describe('Order', () => {
  it('should calculate total from line items', () => {
    const order = Order.create({ customerId: 'cust-1' });
    order.addItem({ productId: 'prod-1', quantity: 2, unitPrice: 25.00 });
    order.addItem({ productId: 'prod-2', quantity: 1, unitPrice: 10.00 });

    expect(order.total).toBe(60.00);
  });

  it('should not allow empty orders to be placed', () => {
    const order = Order.create({ customerId: 'cust-1' });

    expect(() => order.place()).toThrow(EmptyOrderError);
  });

  it('should emit OrderPlacedEvent when placed', () => {
    const order = Order.create({ customerId: 'cust-1' });
    order.addItem({ productId: 'prod-1', quantity: 1, unitPrice: 10.00 });
    order.place();

    expect(order.domainEvents).toContainEqual(
      expect.objectContaining({ type: 'order.placed' })
    );
  });
});
```

### Application Layer

```typescript
// order/application/__tests__/place-order.handler.spec.ts
describe('PlaceOrderHandler', () => {
  let handler: PlaceOrderHandler;
  let orderRepo: jest.Mocked<IOrderRepository>;
  let productModule: jest.Mocked<IProductModule>;
  let eventBus: jest.Mocked<IEventBus>;

  beforeEach(() => {
    orderRepo = { save: jest.fn(), findById: jest.fn() };
    productModule = { checkAvailability: jest.fn(), getProductById: jest.fn() };
    eventBus = { publish: jest.fn(), subscribe: jest.fn() };
    handler = new PlaceOrderHandler(orderRepo, productModule, eventBus);
  });

  it('should reject order when product is unavailable', async () => {
    productModule.checkAvailability.mockResolvedValue(false);

    await expect(handler.handle({
      customerId: 'cust-1',
      items: [{ productId: 'prod-1', quantity: 100 }],
    })).rejects.toThrow(InsufficientStockError);

    expect(orderRepo.save).not.toHaveBeenCalled();
  });

  it('should save order and publish event when valid', async () => {
    productModule.checkAvailability.mockResolvedValue(true);
    productModule.getProductById.mockResolvedValue({ id: 'prod-1', price: 25.00 });

    await handler.handle({
      customerId: 'cust-1',
      items: [{ productId: 'prod-1', quantity: 2 }],
    });

    expect(orderRepo.save).toHaveBeenCalled();
    expect(eventBus.publish).toHaveBeenCalledWith(
      expect.objectContaining({ type: 'order.placed' })
    );
  });
});
```

### C# Example

```csharp
public class PlaceOrderHandlerTests
{
    private readonly Mock<IOrderRepository> _orderRepo = new();
    private readonly Mock<IProductModule> _productModule = new();
    private readonly Mock<IMediator> _mediator = new();

    [Fact]
    public async Task Should_RejectOrder_When_ProductUnavailable()
    {
        _productModule.Setup(m => m.CheckAvailability("prod-1", 100))
            .ReturnsAsync(false);

        var handler = new PlaceOrderHandler(_orderRepo.Object, _productModule.Object, _mediator.Object);

        await Assert.ThrowsAsync<InsufficientStockException>(
            () => handler.Handle(new PlaceOrderCommand("cust-1", new[] {
                new OrderItemDto("prod-1", 100)
            }), CancellationToken.None)
        );

        _orderRepo.Verify(r => r.SaveAsync(It.IsAny<Order>()), Times.Never);
    }
}
```

---

## 2. Integration Tests (Per Module)

Test a single module with its real database and infrastructure. Other modules remain mocked.

### Setup: Test Database per Module

```typescript
// test/helpers/module-test-harness.ts
export async function createModuleTestHarness(moduleClass: Type) {
  const module = await Test.createTestingModule({
    imports: [
      moduleClass,
      TypeOrmModule.forRoot({
        type: 'postgres',
        host: 'localhost',
        database: 'test_db',
        synchronize: true,  // OK for tests only
      }),
    ],
  })
    .overrideProvider('IEventBus').useValue(new InMemoryEventBus())
    .compile();

  return module.createNestApplication();
}
```

### Module Integration Test

```typescript
// order/test/order-module.integration.spec.ts
describe('Order Module Integration', () => {
  let app: INestApplication;
  let orderService: OrderService;

  beforeAll(async () => {
    app = await createModuleTestHarness(OrderModule);
    orderService = app.get(OrderService);
    await app.init();
  });

  afterAll(async () => {
    await app.close();
  });

  it('should persist and retrieve an order', async () => {
    const orderId = await orderService.createOrder({
      customerId: 'cust-1',
      items: [{ productId: 'prod-1', quantity: 2, unitPrice: 25.00 }],
    });

    const order = await orderService.getOrderById(orderId);

    expect(order).toBeDefined();
    expect(order.items).toHaveLength(1);
    expect(order.total).toBe(50.00);
  });
});
```

### Spring Boot — `@ApplicationModuleTest`

```java
@ApplicationModuleTest
class OrderModuleIntegrationTest {

    @Autowired
    private OrderService orderService;

    @MockBean
    private ProductModuleApi productModule;

    @Test
    void shouldCreateAndRetrieveOrder() {
        when(productModule.checkAvailability("prod-1", 2)).thenReturn(true);
        when(productModule.getProductById("prod-1"))
            .thenReturn(new ProductDto("prod-1", "Widget", BigDecimal.valueOf(25.00)));

        String orderId = orderService.placeOrder(new PlaceOrderCommand(
            "cust-1", List.of(new OrderItemDto("prod-1", 2))
        ));

        Order order = orderService.getOrderById(orderId);
        assertThat(order.getTotal()).isEqualByComparingTo(BigDecimal.valueOf(50.00));
    }
}
```

---

## 3. Contract Tests (Cross-Module)

Verify that module public APIs (contracts) remain stable. When Module A depends on Module B's contract, a contract test ensures Module B's implementation still satisfies it.

### What to Test

| Aspect | Example |
|--------|---------|
| Method signatures | `getProductById(id)` still returns `ProductDto` |
| Return types | Fields haven't been removed or renamed |
| Error behavior | Still throws the expected exceptions |
| Event schemas | `OrderPlacedEvent` still has `orderId`, `total`, `items` |

### Contract Test Example (TypeScript)

```typescript
// test/contracts/product-module-contract.spec.ts
describe('Product Module Contract', () => {
  let productModule: IProductModule;

  beforeAll(async () => {
    // Use the REAL implementation, not a mock
    const app = await createModuleTestHarness(ProductModule);
    productModule = app.get<IProductModule>('IProductModule');

    // Seed test data
    await seedProduct({ id: 'prod-1', name: 'Widget', price: 25.00 });
  });

  it('getProductById should return ProductDto with required fields', async () => {
    const product = await productModule.getProductById('prod-1');

    expect(product).toEqual(expect.objectContaining({
      id: expect.any(String),
      name: expect.any(String),
      price: expect.any(Number),
    }));
  });

  it('getProductById should return null for non-existent product', async () => {
    const product = await productModule.getProductById('non-existent');

    expect(product).toBeNull();
  });

  it('checkAvailability should return boolean', async () => {
    const result = await productModule.checkAvailability('prod-1', 1);

    expect(typeof result).toBe('boolean');
  });
});
```

### Event Contract Test

```typescript
// test/contracts/events/order-placed-event.contract.spec.ts
describe('OrderPlacedEvent Contract', () => {
  it('should have the required schema', () => {
    const event = new OrderPlacedEvent({
      orderId: 'order-1',
      customerId: 'cust-1',
      items: [{ productId: 'prod-1', quantity: 2 }],
      total: 50.00,
    });

    // Verify all required fields exist and have correct types
    expect(event.type).toBe('order.placed');
    expect(event.orderId).toBeDefined();
    expect(event.customerId).toBeDefined();
    expect(event.items).toBeInstanceOf(Array);
    expect(event.total).toEqual(expect.any(Number));
    expect(event.occurredAt).toBeInstanceOf(Date);
  });
});
```

---

## 4. Architecture Boundary Tests

Automated tests that fail when module boundaries are violated. Run in CI to prevent boundary erosion.

### .NET — NetArchTest

```csharp
[Collection("Architecture")]
public class ModuleBoundaryTests
{
    private static readonly Assembly[] ModuleAssemblies = new[]
    {
        typeof(ProductService).Assembly,
        typeof(OrderService).Assembly,
        typeof(PaymentService).Assembly,
    };

    [Theory]
    [InlineData("Product", "Order")]
    [InlineData("Product", "Payment")]
    [InlineData("Order", "Payment")]
    [InlineData("Payment", "Product")]
    public void Module_ShouldNotReferenceOtherModuleInternals(string source, string target)
    {
        var result = Types.InAssembly(GetAssembly(source))
            .ShouldNot()
            .HaveDependencyOn($"MyApp.Modules.{target}.Domain")
            .And()
            .ShouldNot()
            .HaveDependencyOn($"MyApp.Modules.{target}.Infrastructure")
            .GetResult();

        result.IsSuccessful.Should().BeTrue(
            $"{source} module should not reference {target} internals. " +
            $"Violations: {string.Join(", ", result.FailingTypeNames ?? Array.Empty<string>())}");
    }

    [Fact]
    public void SharedKernel_ShouldNotReferenceAnyModule()
    {
        var result = Types.InAssembly(typeof(IDomainEvent).Assembly)
            .ShouldNot()
            .HaveDependencyOn("MyApp.Modules")
            .GetResult();

        result.IsSuccessful.Should().BeTrue();
    }

    [Fact]
    public void DomainLayer_ShouldNotDependOnInfrastructure()
    {
        foreach (var assembly in ModuleAssemblies)
        {
            var domainTypes = Types.InAssembly(assembly)
                .That().ResideInNamespaceContaining(".Domain");

            var result = domainTypes
                .ShouldNot()
                .HaveDependencyOn("Microsoft.EntityFrameworkCore")
                .And()
                .ShouldNot()
                .HaveDependencyOnAny("Infrastructure")
                .GetResult();

            result.IsSuccessful.Should().BeTrue();
        }
    }
}
```

### Java — ArchUnit

```java
@AnalyzeClasses(packages = "com.myapp.modules")
public class ModuleBoundaryTests {

    @ArchTest
    static final ArchRule modules_should_not_access_other_module_internals =
        slices().matching("com.myapp.modules.(*)..")
            .should().notDependOnEachOther()
            .ignoreDependency(
                resideInAPackage("..api.."),    // API packages are OK
                alwaysTrue()
            );

    @ArchTest
    static final ArchRule domain_should_not_depend_on_infrastructure =
        noClasses()
            .that().resideInAPackage("..domain..")
            .should().dependOnClassesThat()
            .resideInAPackage("..infrastructure..");

    @ArchTest
    static final ArchRule shared_kernel_should_not_reference_modules =
        noClasses()
            .that().resideInAPackage("com.myapp.shared..")
            .should().dependOnClassesThat()
            .resideInAPackage("com.myapp.modules..");
}
```

### TypeScript — Import Analysis

```typescript
// test/architecture/module-boundaries.spec.ts
import * as fs from 'fs';
import * as path from 'path';

const MODULES_DIR = path.join(__dirname, '../../src/modules');
const modules = fs.readdirSync(MODULES_DIR).filter(f =>
  fs.statSync(path.join(MODULES_DIR, f)).isDirectory()
);

function getAllTsFiles(dir: string): string[] {
  const files: string[] = [];
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const fullPath = path.join(dir, entry.name);
    if (entry.isDirectory()) files.push(...getAllTsFiles(fullPath));
    else if (entry.name.endsWith('.ts')) files.push(fullPath);
  }
  return files;
}

describe('Module Boundaries', () => {
  for (const sourceModule of modules) {
    for (const targetModule of modules) {
      if (sourceModule === targetModule) continue;

      it(`${sourceModule} should not import ${targetModule} internals`, () => {
        const files = getAllTsFiles(path.join(MODULES_DIR, sourceModule));
        for (const file of files) {
          const content = fs.readFileSync(file, 'utf-8');
          // Allow imports from the target's api/ directory (public contract)
          const internalImportPattern = new RegExp(
            `from ['"].*modules/${targetModule}/(?!api/)`,
          );
          expect(content).not.toMatch(internalImportPattern);
        }
      });
    }
  }

  it('shared kernel should not import from any module', () => {
    const sharedFiles = getAllTsFiles(path.join(__dirname, '../../src/shared'));
    for (const file of sharedFiles) {
      const content = fs.readFileSync(file, 'utf-8');
      expect(content).not.toMatch(/from ['"].*modules\//);
    }
  });
});
```

### Python — Import Boundary Tests

```python
# tests/architecture/test_boundaries.py
import ast
import os
import pytest

MODULES_DIR = os.path.join(os.path.dirname(__file__), '../../modules')

def get_python_files(directory):
    for root, _, files in os.walk(directory):
        for f in files:
            if f.endswith('.py'):
                yield os.path.join(root, f)

def get_imports(filepath):
    with open(filepath) as f:
        tree = ast.parse(f.read())
    imports = []
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            for alias in node.names:
                imports.append(alias.name)
        elif isinstance(node, ast.ImportFrom) and node.module:
            imports.append(node.module)
    return imports

modules = [d for d in os.listdir(MODULES_DIR)
           if os.path.isdir(os.path.join(MODULES_DIR, d)) and d != '__pycache__']

@pytest.mark.parametrize("source,target", [
    (s, t) for s in modules for t in modules if s != t
])
def test_module_does_not_import_other_module_internals(source, target):
    for filepath in get_python_files(os.path.join(MODULES_DIR, source)):
        for imp in get_imports(filepath):
            # Allow imports from target's contracts.py only
            if f'modules.{target}' in imp:
                assert 'contracts' in imp, (
                    f"{filepath} imports {imp} — only contracts allowed"
                )
```

---

## 5. End-to-End Tests

Test complete user flows that span multiple modules. Keep these few and focused on critical paths.

```typescript
// test/e2e/place-order.e2e-spec.ts
describe('Place Order (E2E)', () => {
  let app: INestApplication;

  beforeAll(async () => {
    app = await createFullAppTestHarness();
  });

  it('should place an order, trigger payment, and send notification', async () => {
    // 1. Create a product
    const product = await request(app.getHttpServer())
      .post('/api/products')
      .send({ name: 'Widget', price: 25.00, stock: 100 })
      .expect(201);

    // 2. Place an order
    const order = await request(app.getHttpServer())
      .post('/api/orders')
      .send({
        customerId: 'cust-1',
        items: [{ productId: product.body.id, quantity: 2 }],
      })
      .expect(201);

    // 3. Verify order was created
    const orderDetails = await request(app.getHttpServer())
      .get(`/api/orders/${order.body.id}`)
      .expect(200);

    expect(orderDetails.body.status).toBe('placed');
    expect(orderDetails.body.total).toBe(50.00);

    // 4. Verify payment was initiated (via Payment module API)
    const payment = await request(app.getHttpServer())
      .get(`/api/payments?orderId=${order.body.id}`)
      .expect(200);

    expect(payment.body[0].status).toBe('pending');

    // 5. Verify stock was reduced
    const updatedProduct = await request(app.getHttpServer())
      .get(`/api/products/${product.body.id}`)
      .expect(200);

    expect(updatedProduct.body.stock).toBe(98);
  });
});
```

---

## Testing Checklist for New Modules

When generating a new module, include these test categories:

| Category | Files to Generate | What to Test |
|----------|------------------|-------------|
| Unit (domain) | `module/domain/__tests__/*.spec.ts` | Entity behavior, value object validation, domain event emission |
| Unit (application) | `module/application/__tests__/*.spec.ts` | Command/query handlers with mocked dependencies |
| Integration | `module/test/*.integration.spec.ts` | Full module with real DB, mocked external modules |
| Contract | `test/contracts/module-contract.spec.ts` | Public API stability (method signatures, return types) |
| Architecture | `test/architecture/boundaries.spec.ts` | No imports from other module internals |
