# .NET / ASP.NET Core — Example Scaffold

A concrete example of a generated Modular Monolith for an e-commerce application with Product, Order, and Payment modules.

---

## Generated File Tree

```
ECommerceApp/
├── src/
│   ├── ECommerceApp.Host/
│   │   ├── Program.cs
│   │   ├── appsettings.json
│   │   ├── appsettings.Development.json
│   │   ├── Middleware/
│   │   │   └── GlobalExceptionMiddleware.cs
│   │   └── ECommerceApp.Host.csproj
│   │
│   ├── ECommerceApp.Shared/
│   │   ├── Abstractions/
│   │   │   ├── IEntity.cs
│   │   │   ├── IAuditableEntity.cs
│   │   │   ├── IDomainEvent.cs
│   │   │   └── IEventBus.cs
│   │   ├── ValueObjects/
│   │   │   ├── Money.cs
│   │   │   └── Email.cs
│   │   ├── Contracts/
│   │   │   ├── Events/
│   │   │   │   ├── OrderPlacedEvent.cs
│   │   │   │   ├── PaymentCompletedEvent.cs
│   │   │   │   └── ProductCreatedEvent.cs
│   │   │   └── DTOs/
│   │   │       ├── ProductDto.cs
│   │   │       ├── OrderDto.cs
│   │   │       └── PaymentDto.cs
│   │   └── ECommerceApp.Shared.csproj
│   │
│   ├── ECommerceApp.Infrastructure/
│   │   ├── EventBus/
│   │   │   ├── InMemoryEventBus.cs
│   │   │   └── EventBusRegistration.cs
│   │   ├── Persistence/
│   │   │   └── DatabaseMigrator.cs
│   │   └── ECommerceApp.Infrastructure.csproj
│   │
│   └── Modules/
│       ├── Product/
│       │   ├── ECommerceApp.Modules.Product.Domain/
│       │   │   ├── Entities/
│       │   │   │   └── Product.cs
│       │   │   ├── ValueObjects/
│       │   │   │   ├── ProductId.cs
│       │   │   │   └── Sku.cs
│       │   │   ├── Repositories/
│       │   │   │   └── IProductRepository.cs
│       │   │   ├── Events/
│       │   │   │   └── ProductCreatedDomainEvent.cs
│       │   │   └── ECommerceApp.Modules.Product.Domain.csproj
│       │   │
│       │   ├── ECommerceApp.Modules.Product.Application/
│       │   │   ├── Commands/
│       │   │   │   ├── CreateProduct/
│       │   │   │   │   ├── CreateProductCommand.cs
│       │   │   │   │   ├── CreateProductHandler.cs
│       │   │   │   │   └── CreateProductValidator.cs
│       │   │   │   └── UpdateProduct/
│       │   │   │       ├── UpdateProductCommand.cs
│       │   │   │       └── UpdateProductHandler.cs
│       │   │   ├── Queries/
│       │   │   │   ├── GetProductById/
│       │   │   │   │   ├── GetProductByIdQuery.cs
│       │   │   │   │   └── GetProductByIdHandler.cs
│       │   │   │   └── GetProducts/
│       │   │   │       ├── GetProductsQuery.cs
│       │   │   │       └── GetProductsHandler.cs
│       │   │   ├── Contracts/
│       │   │   │   └── IProductModule.cs
│       │   │   ├── Mappings/
│       │   │   │   └── ProductMappings.cs
│       │   │   └── ECommerceApp.Modules.Product.Application.csproj
│       │   │
│       │   ├── ECommerceApp.Modules.Product.Infrastructure/
│       │   │   ├── Persistence/
│       │   │   │   ├── ProductDbContext.cs
│       │   │   │   ├── ProductRepository.cs
│       │   │   │   └── Configurations/
│       │   │   │       └── ProductConfiguration.cs
│       │   │   ├── Migrations/
│       │   │   │   └── 001_CreateProductsTable.cs
│       │   │   ├── ProductModuleInstaller.cs
│       │   │   └── ECommerceApp.Modules.Product.Infrastructure.csproj
│       │   │
│       │   └── ECommerceApp.Modules.Product.Api/
│       │       ├── Controllers/
│       │       │   └── ProductsController.cs
│       │       ├── Requests/
│       │       │   ├── CreateProductRequest.cs
│       │       │   └── UpdateProductRequest.cs
│       │       └── ECommerceApp.Modules.Product.Api.csproj
│       │
│       ├── Order/
│       │   ├── ECommerceApp.Modules.Order.Domain/
│       │   │   ├── Entities/
│       │   │   │   ├── Order.cs
│       │   │   │   └── OrderItem.cs
│       │   │   ├── ValueObjects/
│       │   │   │   ├── OrderId.cs
│       │   │   │   └── OrderStatus.cs
│       │   │   ├── Repositories/
│       │   │   │   └── IOrderRepository.cs
│       │   │   └── Events/
│       │   │       └── OrderPlacedDomainEvent.cs
│       │   │
│       │   ├── ECommerceApp.Modules.Order.Application/
│       │   │   ├── Commands/
│       │   │   │   └── PlaceOrder/
│       │   │   │       ├── PlaceOrderCommand.cs
│       │   │   │       ├── PlaceOrderHandler.cs
│       │   │   │       └── PlaceOrderValidator.cs
│       │   │   ├── Queries/
│       │   │   │   └── GetOrderById/
│       │   │   │       ├── GetOrderByIdQuery.cs
│       │   │   │       └── GetOrderByIdHandler.cs
│       │   │   ├── Contracts/
│       │   │   │   └── IOrderModule.cs
│       │   │   └── EventHandlers/
│       │   │       └── OnPaymentCompleted.cs
│       │   │
│       │   ├── ECommerceApp.Modules.Order.Infrastructure/
│       │   │   ├── Persistence/
│       │   │   │   ├── OrderDbContext.cs
│       │   │   │   ├── OrderRepository.cs
│       │   │   │   └── Configurations/
│       │   │   │       ├── OrderConfiguration.cs
│       │   │   │       └── OrderItemConfiguration.cs
│       │   │   ├── Migrations/
│       │   │   │   └── 001_CreateOrdersTables.cs
│       │   │   └── OrderModuleInstaller.cs
│       │   │
│       │   └── ECommerceApp.Modules.Order.Api/
│       │       ├── Controllers/
│       │       │   └── OrdersController.cs
│       │       └── Requests/
│       │           └── PlaceOrderRequest.cs
│       │
│       └── Payment/
│           ├── ECommerceApp.Modules.Payment.Domain/
│           │   ├── Entities/
│           │   │   └── Payment.cs
│           │   ├── ValueObjects/
│           │   │   ├── PaymentId.cs
│           │   │   └── PaymentStatus.cs
│           │   └── Repositories/
│           │       └── IPaymentRepository.cs
│           │
│           ├── ECommerceApp.Modules.Payment.Application/
│           │   ├── Commands/
│           │   │   └── InitiatePayment/
│           │   │       ├── InitiatePaymentCommand.cs
│           │   │       └── InitiatePaymentHandler.cs
│           │   ├── Contracts/
│           │   │   └── IPaymentModule.cs
│           │   └── EventHandlers/
│           │       └── OnOrderPlaced.cs
│           │
│           ├── ECommerceApp.Modules.Payment.Infrastructure/
│           │   ├── Persistence/
│           │   │   ├── PaymentDbContext.cs
│           │   │   ├── PaymentRepository.cs
│           │   │   └── Configurations/
│           │   │       └── PaymentConfiguration.cs
│           │   ├── Migrations/
│           │   │   └── 001_CreatePaymentsTable.cs
│           │   └── PaymentModuleInstaller.cs
│           │
│           └── ECommerceApp.Modules.Payment.Api/
│               ├── Controllers/
│               │   └── PaymentsController.cs
│               └── Requests/
│                   └── InitiatePaymentRequest.cs
│
├── tests/
│   ├── Modules/
│   │   ├── Product.UnitTests/
│   │   │   ├── Domain/
│   │   │   │   └── ProductTests.cs
│   │   │   └── Application/
│   │   │       └── CreateProductHandlerTests.cs
│   │   ├── Order.UnitTests/
│   │   │   ├── Domain/
│   │   │   │   └── OrderTests.cs
│   │   │   └── Application/
│   │   │       └── PlaceOrderHandlerTests.cs
│   │   └── Payment.UnitTests/
│   │       └── Application/
│   │           └── InitiatePaymentHandlerTests.cs
│   │
│   ├── Modules.IntegrationTests/
│   │   ├── Product/
│   │   │   └── ProductModuleTests.cs
│   │   └── Order/
│   │       └── OrderModuleTests.cs
│   │
│   └── ECommerceApp.ArchitectureTests/
│       ├── ModuleBoundaryTests.cs
│       ├── DomainLayerTests.cs
│       └── SharedKernelTests.cs
│
├── docker-compose.yml
├── Dockerfile
├── ECommerceApp.sln
└── README.md
```

---

## Key Generated Files

### Program.cs (Composition Root)

```csharp
var builder = WebApplication.CreateBuilder(args);

// Shared infrastructure
builder.Services.AddSharedInfrastructure(builder.Configuration);

// Register modules
builder.Services.AddProductModule(builder.Configuration);
builder.Services.AddOrderModule(builder.Configuration);
builder.Services.AddPaymentModule(builder.Configuration);

// Common middleware
builder.Services.AddControllers();
builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen();

var app = builder.Build();

app.UseMiddleware<GlobalExceptionMiddleware>();
app.UseSwagger();
app.UseSwaggerUI();
app.MapControllers();
app.MapHealthChecks("/health");

app.Run();
```

### Module Contract (IProductModule.cs)

```csharp
namespace ECommerceApp.Modules.Product.Application.Contracts;

public interface IProductModule
{
    Task<ProductDto?> GetProductByIdAsync(string id, CancellationToken ct = default);
    Task<IReadOnlyList<ProductDto>> GetProductsByIdsAsync(IEnumerable<string> ids, CancellationToken ct = default);
    Task<bool> CheckAvailabilityAsync(string productId, int quantity, CancellationToken ct = default);
}
```

### Module Installer (ProductModuleInstaller.cs)

```csharp
namespace ECommerceApp.Modules.Product.Infrastructure;

public static class ProductModuleInstaller
{
    public static IServiceCollection AddProductModule(this IServiceCollection services, IConfiguration config)
    {
        // Domain services
        services.AddScoped<IProductRepository, ProductRepository>();
        services.AddScoped<IProductModule, ProductService>();

        // Database
        services.AddDbContext<ProductDbContext>(options =>
            options.UseNpgsql(config.GetConnectionString("Default")));

        // MediatR handlers
        services.AddMediatR(cfg => cfg.RegisterServicesFromAssembly(typeof(ProductModuleInstaller).Assembly));

        // Event handlers
        services.AddScoped<INotificationHandler<OrderPlacedEvent>, OnOrderPlacedHandler>();

        return services;
    }
}
```

### Architecture Test (ModuleBoundaryTests.cs)

```csharp
namespace ECommerceApp.ArchitectureTests;

public class ModuleBoundaryTests
{
    [Theory]
    [InlineData("Product", "Order")]
    [InlineData("Product", "Payment")]
    [InlineData("Order", "Payment")]
    [InlineData("Payment", "Product")]
    [InlineData("Payment", "Order")]
    [InlineData("Order", "Product")]
    public void Module_ShouldNotDependOnOtherModuleInternals(string source, string target)
    {
        var sourceAssembly = GetModuleAssembly(source);

        var result = Types.InAssembly(sourceAssembly)
            .ShouldNot()
            .HaveDependencyOn($"ECommerceApp.Modules.{target}.Domain")
            .And()
            .ShouldNot()
            .HaveDependencyOn($"ECommerceApp.Modules.{target}.Infrastructure")
            .GetResult();

        result.IsSuccessful.Should().BeTrue(
            $"{source} module must not reference {target} internals");
    }

    [Fact]
    public void SharedKernel_ShouldNotDependOnAnyModule()
    {
        var result = Types.InAssembly(typeof(IDomainEvent).Assembly)
            .ShouldNot()
            .HaveDependencyOn("ECommerceApp.Modules")
            .GetResult();

        result.IsSuccessful.Should().BeTrue();
    }
}
```

### docker-compose.yml

```yaml
services:
  app:
    build: .
    ports:
      - "5000:8080"
    environment:
      - ConnectionStrings__Default=Host=db;Database=ecommerce;Username=postgres;Password=postgres
      - ASPNETCORE_ENVIRONMENT=Development
    depends_on:
      db:
        condition: service_healthy

  db:
    image: postgres:16-alpine
    environment:
      POSTGRES_DB: ecommerce
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
