# Python Best Practices

## Tooling Stack (2025)

| Tool | Replaces | Purpose |
|------|----------|---------|
| **Ruff** | flake8, isort, Black | Linting + formatting (Rust-based, 10-100x faster) |
| **uv** | pip, poetry, virtualenv | Package management (Rust-based, 20x faster) |
| **mypy --strict** | — | Static type checking |
| **pytest** | unittest | Testing |
| **structlog** | logging | Structured logging |

## Banned Legacy Packages (New Projects)

| Don't Use | Use Instead | Why |
|---|---|---|
| `requests` | `httpx` | Async-native, HTTP/2, drop-in compatible |
| `flask` | `fastapi` | Async, Pydantic validation, auto-OpenAPI |
| `pip` / `poetry` | `uv` | 20x faster, unified workflow |
| `flake8` + `black` + `isort` | `ruff` | Single Rust-based tool |
| `unittest` | `pytest` | Modern fixtures, parametrize, plugins |
| `logging` (stdlib) | `structlog` | Structured JSON, context binding |
| `virtualenv` / manual `venv` | `uv` (manages automatically) | Integrated workflow |
| `SQLAlchemy <2.0` | `SQLAlchemy 2.0+` | Async-native, new query style |
| `celery` (simple queues) | Research `arq` / `taskiq` first | Celery valid for complex; verify need |
| `os.path` (new code) | `pathlib` | Object-oriented, cleaner API |

**Exception:** Existing codebases — don't rewrite working deps. Apply to NEW additions only.
**Rule:** Before ANY `uv add` / `pip install`, run Package Selection Gate (Pillar 10 in SKILL.md).

## Project Setup

```bash
uv init my-project && cd my-project
uv add fastapi pydantic sqlalchemy[asyncio] structlog
uv add --dev pytest pytest-asyncio ruff mypy
uv run pytest
```

## Project Structure (src layout)

```
my-project/
├── src/my_package/
│   ├── __init__.py
│   ├── main.py
│   ├── api/routes/
│   ├── services/
│   ├── models/
│   ├── core/ (config.py, database.py, security.py)
│   └── repositories/
├── tests/ (conftest.py, unit/, integration/)
├── pyproject.toml
├── uv.lock (commit this)
└── .python-version
```

**WHY src layout:** Prevents accidental working-directory imports. Tests run against installed package.

## pyproject.toml

```toml
[project]
name = "my-project"
version = "0.1.0"
requires-python = ">=3.12"
dependencies = [
    "fastapi>=0.115,<1",
    "pydantic>=2.10,<3",
    "sqlalchemy[asyncio]>=2.0,<3",
    "structlog>=24.0",
]

[tool.ruff]
line-length = 88
target-version = "py312"

[tool.ruff.lint]
select = [
    "E", "F", "UP", "I", "SIM", "B", "C4", "DTZ", "T20", "RUF",
]

[tool.mypy]
strict = true
python_version = "3.12"
plugins = ["pydantic.mypy"]

[tool.pytest.ini_options]
testpaths = ["tests"]
asyncio_mode = "auto"
```

## Type Hints (Mandatory)

```python
# Modern syntax (3.10+)
def process(items: list[str], count: int | None = None) -> dict[str, int]: ...

# Annotated for metadata-rich types
from typing import Annotated
from fastapi import Depends, Query

UserId = Annotated[str, Query(min_length=3, max_length=50)]
CurrentUser = Annotated[User, Depends(get_current_user)]

@router.get("/users/{user_id}")
async def get_user(user_id: UserId, user: CurrentUser) -> UserResponse: ...
```

## Pydantic at Boundaries, Dataclasses in Core

```python
# API boundary — Pydantic (validates, coerces, generates schema)
class CreateOrderRequest(BaseModel):
    model_config = ConfigDict(strict=True)
    product_id: str = Field(min_length=1)
    quantity: int = Field(ge=1, le=100)
    notes: str | None = Field(default=None, max_length=500)

# Domain core — dataclass (zero dependency overhead)
@dataclass(frozen=True)  # Immutable value object
class Money:
    amount: int  # Cents to avoid float precision
    currency: str
```

## Async Patterns

```python
# ✅ Gather for concurrent independent I/O
async def get_dashboard(user_id: str) -> Dashboard:
    profile, orders, notifications = await asyncio.gather(
        get_profile(user_id),
        get_recent_orders(user_id),
        get_notifications(user_id),
    )
    return Dashboard(profile=profile, orders=orders, notifications=notifications)

# ✅ Use httpx for async HTTP (never requests in async context)
async with httpx.AsyncClient() as client:
    response = await client.get(url)

# ✅ selectinload for eager loading (avoids N+1)
users = await db.execute(
    select(User).options(selectinload(User.orders)).limit(100)
)
```

## FastAPI Patterns

```python
# Dependency Injection (modern Annotated style)
async def get_user_service(
    db: Annotated[AsyncSession, Depends(get_db)],
    cache: Annotated[Redis, Depends(get_redis)],
) -> UserService:
    return UserService(db=db, cache=cache)

UserServiceDep = Annotated[UserService, Depends(get_user_service)]

# Route — thin, delegates to service
@router.post("/users", response_model=UserResponse, status_code=201)
async def create_user(
    request: CreateUserRequest,
    service: UserServiceDep,
    current_user: CurrentUser,
) -> UserResponse:
    """No business logic here — delegate to service."""
    return await service.create_user(request, actor=current_user)
```

## Python-Specific Rules

| Rule | Standard |
|------|----------|
| Formatter | `ruff format` |
| Linter | `ruff check` |
| Type checker | `mypy --strict` |
| Runtime validation | Pydantic at boundaries |
| Package manager | uv |
| Lockfile | uv.lock (commit) |
| CI install | `uv sync --frozen` |
| Ban in production | `print()` (use T20 rule) |
| Test runner | pytest |
| Ban | `any` type, `# type: ignore` without comment |
