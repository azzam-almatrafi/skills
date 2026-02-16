# FastAPI Authentication & Security Patterns

JWT authentication, OAuth2, password hashing, and security best practices for FastAPI Modular Monoliths.

---

## Authentication Architecture

```
Client → Request with Bearer Token
   ↓
FastAPI OAuth2PasswordBearer
   ↓
decode_access_token() → extract user_id
   ↓
CurrentUserGetter (Depends) → fetch User from DB
   ↓
ActiveUserGetter (Depends) → verify user.is_active
   ↓
Route Handler receives validated user
```

---

## Password Hashing (Argon2 + Bcrypt Fallback)

```python
# app/auth/security.py
from passlib.context import CryptContext
import jwt
from datetime import datetime, timedelta
from app.auth.config import auth_config
import secrets

pwd_context = CryptContext(
    schemes=["argon2", "bcrypt"],
    deprecated="auto",
)

def generate_hash(password: str) -> str:
    return pwd_context.hash(password)

def verify_hash(plain_password: str, hashed_password: str) -> bool:
    return pwd_context.verify(plain_password, hashed_password)
```

---

## JWT Token Management

```python
# app/auth/security.py (continued)

def generate_access_token(
    data: dict,
    expires_delta: timedelta | None = None,
) -> str:
    to_encode = data.copy()
    expire = datetime.utcnow() + (
        expires_delta or timedelta(minutes=auth_config.ACCESS_TOKEN_EXPIRE_MINUTES)
    )
    to_encode.update({"exp": expire})
    return jwt.encode(to_encode, auth_config.JWT_SECRET_KEY, algorithm=auth_config.JWT_ALGORITHM)

def decode_access_token(token: str) -> dict | None:
    try:
        payload = jwt.decode(
            token,
            auth_config.JWT_SECRET_KEY,
            algorithms=[auth_config.JWT_ALGORITHM],
        )
        return payload
    except jwt.ExpiredSignatureError:
        return None
    except jwt.InvalidTokenError:
        return None

def generate_refresh_token(length: int = 48) -> str:
    return secrets.token_urlsafe(length)

def generate_password_reset_token(email: str) -> str:
    data = {"sub": email, "type": "password_reset"}
    expire = datetime.utcnow() + timedelta(hours=auth_config.PASSWORD_RESET_TOKEN_EXPIRE_HOURS)
    data["exp"] = expire
    return jwt.encode(data, auth_config.JWT_SECRET_KEY, algorithm=auth_config.JWT_ALGORITHM)

def decode_password_reset_token(token: str) -> str | None:
    try:
        payload = jwt.decode(
            token,
            auth_config.JWT_SECRET_KEY,
            algorithms=[auth_config.JWT_ALGORITHM],
        )
        if payload.get("type") != "password_reset":
            return None
        return payload.get("sub")
    except jwt.InvalidTokenError:
        return None
```

---

## OAuth2 Password Bearer Scheme

```python
# app/auth/dependencies/services.py
from typing import Annotated
from fastapi import Depends, HTTPException, status
from fastapi.security import OAuth2PasswordBearer
from app.auth.security import decode_access_token
from app.auth.repositories.user import UserRepository
from app.auth.schemas.dtos import UserDTO
from app.core.deps import DBSessionDep

oauth2_scheme = OAuth2PasswordBearer(tokenUrl="/api/v1/auth/login")

class CurrentUserGetter:
    """Dependency that extracts and validates the current user from JWT."""

    def __init__(self, user_repo: UserRepository):
        self._repo = user_repo

    async def __call__(self, token: str = Depends(oauth2_scheme)) -> UserDTO:
        payload = decode_access_token(token)
        if payload is None:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Invalid or expired token",
                headers={"WWW-Authenticate": "Bearer"},
            )

        user_id = payload.get("sub")
        if user_id is None:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Invalid token payload",
            )

        user = await self._repo.get(int(user_id))
        if user is None:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="User not found",
            )

        return UserDTO.model_validate(user)


class ActiveUserGetter:
    """Dependency that ensures the user is active."""

    def __init__(self, current_user_getter: CurrentUserGetter):
        self._getter = current_user_getter

    async def __call__(self, token: str = Depends(oauth2_scheme)) -> UserDTO:
        user = await self._getter(token)
        if not user.is_active:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Inactive user account",
            )
        return user


# Dependency setup functions
def get_current_user_getter(db: DBSessionDep) -> CurrentUserGetter:
    return CurrentUserGetter(UserRepository(db))

def get_active_user_getter(db: DBSessionDep) -> ActiveUserGetter:
    return ActiveUserGetter(CurrentUserGetter(UserRepository(db)))

# Annotated types for use in routes
CurrentUser = Annotated[UserDTO, Depends(get_current_user_getter)]
ActiveUser = Annotated[UserDTO, Depends(get_active_user_getter)]
```

---

## Auth Service

```python
# app/auth/services/auth.py
from app.auth.security import (
    generate_access_token,
    generate_refresh_token,
    generate_hash,
    verify_hash,
)
from app.auth.schemas.dtos import TokenGroup
from app.auth.events import UserCreated
from app.auth.exceptions import InvalidCredentials, UserAlreadyExists

class AuthService:
    def __init__(self, user_repo, refresh_token_repo, events, mail):
        self._users = user_repo
        self._tokens = refresh_token_repo
        self._events = events
        self._mail = mail

    async def generate_token(self, email: str, password: str) -> TokenGroup:
        user = await self._users.authenticate(email, password)
        if user is None:
            raise InvalidCredentials()

        if not user.is_active:
            raise InvalidCredentials("Account is inactive")

        access_token = generate_access_token({"sub": str(user.id)})
        refresh_token = generate_refresh_token()

        # Store hashed refresh token
        await self._tokens.upsert(user.id, generate_hash(refresh_token))
        await self._tokens.commit()

        return TokenGroup(
            access_token=access_token,
            refresh_token=refresh_token,
            token_type="bearer",
        )

    async def register(self, email: str, password: str, username: str):
        existing = await self._users.get_by_email(email)
        if existing:
            raise UserAlreadyExists(email)

        user = await self._users.create_user(
            email=email,
            password_hash=generate_hash(password),
            username=username,
        )
        await self._users.commit()

        self._events.dispatch(UserCreated(user_id=user.id, email=user.email))
        await self._mail.queue(to=email, subject="Welcome!", template="welcome.html")

        return user

    async def refresh_access_token(self, refresh_token: str) -> TokenGroup:
        token_record = await self._tokens.get_valid_token(refresh_token)
        if token_record is None:
            raise InvalidCredentials("Invalid refresh token")

        access_token = generate_access_token({"sub": str(token_record.user_id)})
        new_refresh_token = generate_refresh_token()

        await self._tokens.upsert(token_record.user_id, generate_hash(new_refresh_token))
        await self._tokens.commit()

        return TokenGroup(
            access_token=access_token,
            refresh_token=new_refresh_token,
            token_type="bearer",
        )
```

---

## Auth Routes

```python
# app/auth/routes/v1/auth.py
from fastapi import APIRouter, Depends, status
from fastapi.security import OAuth2PasswordRequestForm
from app.auth.dependencies.services import AuthServiceDep
from app.auth.schemas.requests import UserCreateRequest, RefreshTokenRequest
from app.auth.schemas.responses import TokenGroupResponse, UserResponse
from app.core.api.schemas import Response
from app.core.api.rate_limiter import ConfigurableRateLimiter

router = APIRouter()
login_limiter = ConfigurableRateLimiter(times=5, seconds=60)

@router.post("/login")
async def login(
    form_data: OAuth2PasswordRequestForm = Depends(),
    service: AuthServiceDep = None,
    _: None = Depends(login_limiter),
) -> Response[TokenGroupResponse]:
    tokens = await service.generate_token(form_data.username, form_data.password)
    return Response(data=TokenGroupResponse.model_validate(tokens))

@router.post("/register", status_code=status.HTTP_201_CREATED)
async def register(
    request: UserCreateRequest,
    service: AuthServiceDep,
) -> Response[UserResponse]:
    user = await service.register(request.email, request.password, request.username)
    return Response(data=UserResponse.model_validate(user))

@router.post("/refresh")
async def refresh_token(
    request: RefreshTokenRequest,
    service: AuthServiceDep,
) -> Response[TokenGroupResponse]:
    tokens = await service.refresh_access_token(request.refresh_token)
    return Response(data=TokenGroupResponse.model_validate(tokens))
```

---

## Security Best Practices

| Practice | Implementation |
|----------|---------------|
| **Password hashing** | Argon2 (primary) with bcrypt fallback via Passlib |
| **JWT secret rotation** | Separate `JWT_SECRET_KEY` from app secret for independent rotation |
| **Token expiry** | Access tokens: 30 min, Refresh tokens: 7 days |
| **Refresh token storage** | Hash refresh tokens before storing (never store plaintext) |
| **Rate limiting** | `ConfigurableRateLimiter` on login/register endpoints |
| **CORS** | Configure allowed origins in middleware |
| **Input validation** | Pydantic v2 with `Field(min_length, max_length, regex)` |
| **SQL injection** | SQLAlchemy parameterized queries (never raw SQL) |
| **Dependency injection** | Auth guards via `Depends()` — no global state |
| **Error messages** | Generic auth errors — never reveal if email exists |

---

## Rate Limiting

```python
# app/core/api/rate_limiter.py
from fastapi import Request, HTTPException, status

class ConfigurableRateLimiter:
    """Rate limiter that can be toggled via configuration."""

    def __init__(self, times: int = 10, seconds: int = 60, enabled: bool = True):
        self.times = times
        self.seconds = seconds
        self.enabled = enabled

    async def __call__(self, request: Request) -> None:
        if not self.enabled:
            return
        # Implementation using Redis sliding window
        # or slowapi integration
        ...
```

---

## Exception Handling

```python
# app/auth/exceptions.py
from app.core.api.exceptions import GeneralException
from fastapi import status

class InvalidCredentials(GeneralException):
    def __init__(self, message: str = "Invalid email or password"):
        super().__init__(
            status_code=status.HTTP_401_UNAUTHORIZED,
            message=message,
        )

class UserAlreadyExists(GeneralException):
    def __init__(self, email: str):
        super().__init__(
            status_code=status.HTTP_409_CONFLICT,
            message=f"User with email '{email}' already exists",
        )

class UserNotFound(GeneralException):
    def __init__(self):
        super().__init__(
            status_code=status.HTTP_404_NOT_FOUND,
            message="User not found",
        )
```
