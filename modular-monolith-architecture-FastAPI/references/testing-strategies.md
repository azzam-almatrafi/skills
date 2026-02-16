# FastAPI Testing Strategies

Comprehensive testing patterns for FastAPI Modular Monoliths using pytest, httpx AsyncClient, factory-boy, and architecture boundary tests.

---

## Testing Pyramid for FastAPI Modular Monoliths

```
            ┌─────────────┐
            │   E2E Tests  │  Few — critical user flows only
            ├─────────────┤
         ┌──┤  Integration │  Per module — test routes with real DB
         │  ├─────────────┤
         │  │  Contract    │  Cross-module — verify gateway APIs stay stable
         │  ├─────────────┤
         │  │ Architecture │  Automated — enforce module boundaries in CI
         │  ├─────────────┤
         └──┤  Unit Tests  │  Many — services, repositories, domain logic
            └─────────────┘
```

---

## Test Setup & Fixtures

### conftest.py (Root)

```python
# tests/conftest.py
import asyncio
import pytest
from httpx import AsyncClient, ASGITransport
from sqlalchemy.ext.asyncio import create_async_engine, async_sessionmaker, AsyncSession
from faker import Faker

from app.main import create_app
from app.core.db.base_model import BaseModel
from app.core.db.session import get_session
import app.core.models  # noqa: F401 — ensure models are imported

TEST_DATABASE_URL = "postgresql+asyncpg://postgres:postgres@localhost:5432/test_db"


@pytest.fixture(scope="session")
def event_loop():
    loop = asyncio.new_event_loop()
    yield loop
    loop.close()


@pytest.fixture(scope="session")
async def db_engine():
    engine = create_async_engine(TEST_DATABASE_URL, echo=False)
    async with engine.begin() as conn:
        await conn.run_sync(BaseModel.metadata.create_all)
    yield engine
    async with engine.begin() as conn:
        await conn.run_sync(BaseModel.metadata.drop_all)
    await engine.dispose()


@pytest.fixture
async def db(db_engine):
    session_factory = async_sessionmaker(bind=db_engine, class_=AsyncSession, expire_on_commit=False)
    async with session_factory() as session:
        yield session
        await session.rollback()


@pytest.fixture
async def client(db):
    app = create_app()

    async def override_get_session():
        yield db

    app.dependency_overrides[get_session] = override_get_session

    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as ac:
        yield ac


@pytest.fixture
def faker():
    return Faker()
```

### pytest Configuration (pyproject.toml)

```toml
[tool.pytest.ini_options]
asyncio_mode = "auto"
testpaths = ["tests"]
python_files = ["test_*.py"]
python_classes = ["Test*"]
python_functions = ["test_*"]
filterwarnings = ["ignore::DeprecationWarning"]
```

---

## 1. Unit Tests (Per Module)

Test services and repositories in isolation. Mock external dependencies.

### Service Layer Tests

```python
# tests/auth/unit/test_auth_service.py
import pytest
from unittest.mock import AsyncMock, MagicMock, patch
from app.auth.services.auth import AuthService
from app.auth.exceptions import InvalidCredentials


class TestAuthService:
    def setup_method(self):
        self.user_repo = AsyncMock()
        self.refresh_token_repo = AsyncMock()
        self.events = MagicMock()
        self.mail = AsyncMock()
        self.service = AuthService(
            user_repo=self.user_repo,
            refresh_token_repo=self.refresh_token_repo,
            events=self.events,
            mail=self.mail,
        )

    async def test_login_with_valid_credentials(self):
        mock_user = MagicMock()
        mock_user.id = 1
        mock_user.is_active.return_value = True
        self.user_repo.authenticate.return_value = mock_user

        result = await self.service.generate_token("user@example.com", "password123")

        assert result.access_token is not None
        assert result.refresh_token is not None
        self.user_repo.authenticate.assert_called_once_with("user@example.com", "password123")

    async def test_login_with_invalid_credentials(self):
        self.user_repo.authenticate.return_value = None

        with pytest.raises(InvalidCredentials):
            await self.service.generate_token("user@example.com", "wrong-password")

    async def test_register_creates_user_and_dispatches_event(self):
        mock_user = MagicMock()
        mock_user.id = 1
        mock_user.email = "new@example.com"
        self.user_repo.create.return_value = mock_user

        await self.service.register("new@example.com", "password123", "New User")

        self.user_repo.create.assert_called_once()
        self.user_repo.commit.assert_called_once()
        self.events.dispatch.assert_called_once()
        self.mail.queue.assert_called_once()
```

### Repository Tests

```python
# tests/auth/unit/test_user_repository.py
import pytest
from app.auth.repositories.user import UserRepository
from app.auth.models.user import User
from tests.factories.user import UserFactory


class TestUserRepository:
    async def test_create_user(self, db):
        repo = UserRepository(db)
        user_data = UserFactory.build_create_schema()

        user = await repo.create(user_data)
        await repo.commit()

        assert user.id is not None
        assert user.email == user_data.email

    async def test_get_user_by_email(self, db):
        repo = UserRepository(db)
        user_data = UserFactory.build_create_schema()
        await repo.create(user_data)
        await repo.commit()

        found = await repo.get_by_email(user_data.email)

        assert found is not None
        assert found.email == user_data.email

    async def test_soft_delete_user(self, db):
        repo = UserRepository(db)
        user_data = UserFactory.build_create_schema()
        user = await repo.create(user_data)
        await repo.commit()

        await repo.delete(model=user, is_soft=True)
        await repo.commit()

        # Should not be found without with_deleted flag
        found = await repo.get(user.id)
        assert found is None

        # Should be found with with_deleted flag
        found = await repo.get(user.id, with_deleted=True)
        assert found is not None
        assert found.is_deleted
```

---

## 2. Integration Tests (Per Module)

Test complete request-response flow with real database.

```python
# tests/auth/integration/test_auth_routes.py
import pytest
from httpx import AsyncClient


class TestAuthRoutes:
    async def test_register_user(self, client: AsyncClient):
        response = await client.post("/api/v1/auth/register", json={
            "email": "test@example.com",
            "password": "SecurePass123!",
            "username": "testuser",
        })

        assert response.status_code == 201
        data = response.json()
        assert data["code"] == 0
        assert data["data"]["email"] == "test@example.com"

    async def test_login_returns_tokens(self, client: AsyncClient):
        # Register first
        await client.post("/api/v1/auth/register", json={
            "email": "login@example.com",
            "password": "SecurePass123!",
            "username": "loginuser",
        })

        # Login
        response = await client.post("/api/v1/auth/login", data={
            "username": "login@example.com",
            "password": "SecurePass123!",
        })

        assert response.status_code == 200
        data = response.json()
        assert "access_token" in data["data"]
        assert "refresh_token" in data["data"]

    async def test_login_with_wrong_password(self, client: AsyncClient):
        await client.post("/api/v1/auth/register", json={
            "email": "fail@example.com",
            "password": "SecurePass123!",
            "username": "failuser",
        })

        response = await client.post("/api/v1/auth/login", data={
            "username": "fail@example.com",
            "password": "WrongPassword!",
        })

        assert response.status_code == 401


class TestProfileRoutes:
    async def test_get_profile_requires_auth(self, client: AsyncClient):
        response = await client.get("/api/v1/profile")
        assert response.status_code in (401, 403)

    async def test_get_profile_with_valid_token(self, client: AsyncClient):
        # Register and login
        await client.post("/api/v1/auth/register", json={
            "email": "profile@example.com",
            "password": "SecurePass123!",
            "username": "profileuser",
        })
        login_resp = await client.post("/api/v1/auth/login", data={
            "username": "profile@example.com",
            "password": "SecurePass123!",
        })
        token = login_resp.json()["data"]["access_token"]

        # Get profile
        response = await client.get(
            "/api/v1/profile",
            headers={"Authorization": f"Bearer {token}"},
        )

        assert response.status_code == 200
        assert response.json()["data"]["email"] == "profile@example.com"
```

---

## 3. Test Data Factories

```python
# tests/factories/user.py
import factory
from faker import Faker
from app.auth.models.user import User
from app.auth.schemas.dtos import UserCreate
from app.auth.security import generate_hash

fake = Faker()


class UserFactory(factory.Factory):
    class Meta:
        model = User

    email = factory.LazyFunction(fake.email)
    username = factory.LazyFunction(fake.user_name)
    password_hash = factory.LazyFunction(lambda: generate_hash("TestPass123!"))
    status_id = 1  # Active

    @classmethod
    def build_create_schema(cls, **kwargs) -> UserCreate:
        return UserCreate(
            email=kwargs.get("email", fake.email()),
            username=kwargs.get("username", fake.user_name()),
            password="TestPass123!",
        )
```

---

## 4. Architecture Boundary Tests

Automated tests that fail when module boundaries are violated. Run in CI.

```python
# tests/architecture/test_module_boundaries.py
import ast
import os
import pytest

APP_DIR = os.path.join(os.path.dirname(__file__), "../../app")

# Define modules — add new modules here as they are created
MODULES = ["auth", "articles", "comments"]

# Core directory
CORE_DIR = "core"


def get_python_files(directory: str) -> list[str]:
    """Recursively get all .py files in a directory."""
    files = []
    for root, _, filenames in os.walk(directory):
        for f in filenames:
            if f.endswith(".py"):
                files.append(os.path.join(root, f))
    return files


def get_imports(filepath: str) -> list[str]:
    """Extract all import statements from a Python file."""
    with open(filepath) as f:
        try:
            tree = ast.parse(f.read())
        except SyntaxError:
            return []

    imports = []
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            for alias in node.names:
                imports.append(alias.name)
        elif isinstance(node, ast.ImportFrom) and node.module:
            imports.append(node.module)
    return imports


class TestModuleBoundaries:
    """Ensure modules only communicate through gateways and events."""

    @pytest.mark.parametrize("source,target", [
        (s, t) for s in MODULES for t in MODULES if s != t
    ])
    def test_module_does_not_import_other_module_internals(self, source, target):
        source_dir = os.path.join(APP_DIR, source)
        if not os.path.isdir(source_dir):
            pytest.skip(f"Module {source} directory not found")

        for filepath in get_python_files(source_dir):
            for imp in get_imports(filepath):
                if f"app.{target}" in imp:
                    # Allow imports from gateway and events (public contract)
                    allowed = (
                        f"app.{target}.gateway" in imp
                        or f"app.{target}.events" in imp
                        or f"app.{target}.schemas.dtos" in imp
                    )
                    assert allowed, (
                        f"{filepath} imports '{imp}' from {target} module — "
                        f"only gateway, events, and DTOs are allowed"
                    )

    def test_core_does_not_import_from_any_module(self):
        core_dir = os.path.join(APP_DIR, CORE_DIR)
        if not os.path.isdir(core_dir):
            pytest.skip("Core directory not found")

        # models.py is exempt — it imports all models for Alembic
        exempt_files = {"models.py", "routers.py", "listeners.py", "tasks.py"}

        for filepath in get_python_files(core_dir):
            filename = os.path.basename(filepath)
            if filename in exempt_files:
                continue

            for imp in get_imports(filepath):
                for module in MODULES:
                    assert f"app.{module}" not in imp, (
                        f"{filepath} imports '{imp}' from {module} module — "
                        f"core must not depend on business modules"
                    )

    def test_no_circular_dependencies(self):
        """Detect circular import chains between modules."""
        deps = {module: set() for module in MODULES}

        for module in MODULES:
            module_dir = os.path.join(APP_DIR, module)
            if not os.path.isdir(module_dir):
                continue

            for filepath in get_python_files(module_dir):
                for imp in get_imports(filepath):
                    for target in MODULES:
                        if target != module and f"app.{target}" in imp:
                            deps[module].add(target)

        # Check for cycles (simple DFS)
        for start in MODULES:
            visited = set()
            stack = [start]
            while stack:
                current = stack.pop()
                if current in visited:
                    if current == start and len(visited) > 0:
                        cycle = " → ".join(sorted(visited)) + f" → {start}"
                        pytest.fail(f"Circular dependency detected: {cycle}")
                    continue
                visited.add(current)
                stack.extend(deps.get(current, set()))
```

---

## 5. Contract Tests (Cross-Module Gateway)

```python
# tests/contracts/test_auth_gateway_contract.py
import pytest
from app.auth.gateway import AuthGateway


class TestAuthGatewayContract:
    """Verify that the Auth gateway's public API remains stable."""

    async def test_get_user_by_id_returns_dto_or_none(self, db, seed_user):
        gateway = AuthGateway(user_service=get_real_user_service(db))

        user = await gateway.get_user_by_id(seed_user.id)

        assert user is not None
        assert hasattr(user, "id")
        assert hasattr(user, "email")
        assert hasattr(user, "username")

    async def test_get_user_by_id_returns_none_for_nonexistent(self, db):
        gateway = AuthGateway(user_service=get_real_user_service(db))

        user = await gateway.get_user_by_id(99999)

        assert user is None

    async def test_is_user_active_returns_boolean(self, db, seed_user):
        gateway = AuthGateway(user_service=get_real_user_service(db))

        result = await gateway.is_user_active(seed_user.id)

        assert isinstance(result, bool)
```

---

## 6. End-to-End Tests

```python
# tests/e2e/test_article_flow.py

class TestArticlePublishFlow:
    """Test complete article creation flow spanning Auth and Articles modules."""

    async def test_create_and_retrieve_article(self, client: AsyncClient):
        # 1. Register and login
        await client.post("/api/v1/auth/register", json={
            "email": "author@example.com",
            "password": "SecurePass123!",
            "username": "author",
        })
        login_resp = await client.post("/api/v1/auth/login", data={
            "username": "author@example.com",
            "password": "SecurePass123!",
        })
        token = login_resp.json()["data"]["access_token"]
        headers = {"Authorization": f"Bearer {token}"}

        # 2. Create an article
        create_resp = await client.post("/api/v1/articles/", json={
            "title": "My First Article",
            "body": "This is the article body.",
            "description": "A test article",
        }, headers=headers)

        assert create_resp.status_code == 201
        slug = create_resp.json()["data"]["slug"]

        # 3. Retrieve the article
        get_resp = await client.get(f"/api/v1/articles/{slug}")

        assert get_resp.status_code == 200
        assert get_resp.json()["data"]["title"] == "My First Article"
```

---

## Testing Checklist for New Modules

| Category | Files to Generate | What to Test |
|----------|------------------|-------------|
| Unit (service) | `tests/module/unit/test_service.py` | Business logic with mocked dependencies |
| Unit (repository) | `tests/module/unit/test_repository.py` | Custom queries with real DB session |
| Integration | `tests/module/integration/test_routes.py` | Full HTTP request → response with real DB |
| Contract | `tests/contracts/test_gateway.py` | Gateway API stability (return types, fields) |
| Factory | `tests/factories/entity.py` | Test data generation for the module |
| Architecture | `tests/architecture/test_module_boundaries.py` | Update MODULES list with new module |
