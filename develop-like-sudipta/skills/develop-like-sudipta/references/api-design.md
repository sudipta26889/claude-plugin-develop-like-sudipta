# API Design Reference

Detailed API design guidance for Pillar 7. Read this when designing endpoints, implementing pagination, error handling, or rate limiting.

## RESTful Resource Design

### URL Conventions

```
✅ CORRECT                          ❌ WRONG
GET    /v1/users                    GET    /v1/getUsers
GET    /v1/users/{id}               GET    /v1/user/getById
POST   /v1/users                    POST   /v1/createUser
PUT    /v1/users/{id}               POST   /v1/updateUser
PATCH  /v1/users/{id}               POST   /v1/user/partialUpdate
DELETE /v1/users/{id}               POST   /v1/deleteUser
GET    /v1/users/{id}/orders        GET    /v1/getUserOrders
POST   /v1/users/{id}/orders        POST   /v1/user/createOrder
```

### HTTP Status Codes (Use Correctly)

| Code | When | Example |
|------|------|---------|
| 200 OK | Successful GET/PUT/PATCH | Retrieved/updated resource |
| 201 Created | Successful POST creating resource | Include `Location` header |
| 204 No Content | Successful DELETE or action with no body | |
| 400 Bad Request | Malformed request syntax | Invalid JSON |
| 401 Unauthorized | Missing/invalid authentication | Bad/expired token |
| 403 Forbidden | Authenticated but insufficient permissions | Wrong role |
| 404 Not Found | Resource doesn't exist | Unknown ID |
| 409 Conflict | State conflict | Duplicate email |
| 422 Unprocessable Entity | Valid syntax but semantic errors | Validation failures |
| 429 Too Many Requests | Rate limit exceeded | Include `Retry-After` |
| 500 Internal Server Error | Unexpected server failure | Never expose internals |

## Cursor-Based Pagination

### Why Cursor Over Offset

Offset = O(N) per page, shifts under mutations (duplicates/gaps). Cursor = O(1), stable at any depth.

### Implementation Pattern

**Request:**
```
GET /v1/users?limit=20&cursor=eyJpZCI6MTAwfQ==
```

**Response:**
```json
{
  "data": [...],
  "pagination": {
    "hasNext": true,
    "nextCursor": "eyJpZCI6MTIwfQ==",
    "limit": 20
  }
}
```

**Backend (Python/FastAPI):**
```python
import base64
import json

async def list_users(
    limit: int = Query(default=20, ge=1, le=100),
    cursor: str | None = Query(default=None),
    db: AsyncSession = Depends(get_db),
) -> PaginatedResponse[UserResponse]:
    """
    WHY: Cursor pagination for consistent O(1) performance at any depth.
    THOUGHT: Opaque base64 cursor hides implementation (column, direction)
    from clients, allowing backend changes without breaking API contract.
    """
    query = select(User).order_by(User.id)

    if cursor:
        decoded = json.loads(base64.b64decode(cursor))
        query = query.where(User.id > decoded["id"])

    query = query.limit(limit + 1)  # Fetch one extra to detect hasNext
    results = (await db.execute(query)).scalars().all()

    has_next = len(results) > limit
    items = results[:limit]

    next_cursor = None
    if has_next and items:
        next_cursor = base64.b64encode(
            json.dumps({"id": items[-1].id}).encode()
        ).decode()

    return PaginatedResponse(
        data=[UserResponse.model_validate(u) for u in items],
        pagination=PaginationMeta(
            has_next=has_next,
            next_cursor=next_cursor,
            limit=limit,
        ),
    )
```

**Critical:** Always index the cursor column. Always enforce max page size.

## Idempotency Keys

### Why

Retrying `POST /orders` without idempotency = duplicate orders. Network failures and client retries are inevitable.

### Implementation

```python
from uuid import UUID

IDEMPOTENCY_TTL = 86400  # 24 hours

@router.post("/v1/orders", status_code=201)
async def create_order(
    request: CreateOrderRequest,
    idempotency_key: UUID = Header(alias="Idempotency-Key"),
    redis: Redis = Depends(get_redis),
    service: OrderService = Depends(get_order_service),
):
    """
    WHY: Idempotency key prevents duplicate orders on retry.
    Client generates UUIDv4, sends in header. We cache key → response.
    """
    cache_key = f"idempotency:{idempotency_key}"

    # Check if this key was already processed
    cached = await redis.get(cache_key)
    if cached:
        return json.loads(cached)  # Return same response as original

    # Process the request
    result = await service.create_order(request)
    response = OrderResponse.model_validate(result).model_dump_json()

    # Cache the response
    await redis.setex(cache_key, IDEMPOTENCY_TTL, response)

    return result
```

**Client usage:**
```typescript
const response = await fetch("/v1/orders", {
  method: "POST",
  headers: {
    "Content-Type": "application/json",
    "Idempotency-Key": crypto.randomUUID(), // Client generates
  },
  body: JSON.stringify(orderData),
});
```

## RFC 7807 Error Responses

### Standard Format

```json
{
  "type": "https://api.yourapp.com/errors/validation-failed",
  "title": "Validation Failed",
  "status": 422,
  "detail": "The 'email' field must be a valid email address.",
  "instance": "/v1/users",
  "errors": [
    {
      "field": "email",
      "message": "Invalid email format",
      "value": "not-an-email"
    }
  ]
}
```

### Implementation

```python
from fastapi.responses import JSONResponse

class ProblemDetail(BaseModel):
    type: str = Field(description="URI identifying the problem type")
    title: str = Field(description="Short human-readable summary")
    status: int = Field(description="HTTP status code")
    detail: str = Field(description="Human-readable explanation")
    instance: str = Field(description="URI of the specific occurrence")

@app.exception_handler(RequestValidationError)
async def validation_exception_handler(request: Request, exc: RequestValidationError):
    return JSONResponse(
        status_code=422,
        content=ProblemDetail(
            type="https://api.yourapp.com/errors/validation-failed",
            title="Validation Failed",
            status=422,
            detail=str(exc),
            instance=str(request.url.path),
        ).model_dump(),
        headers={"Content-Type": "application/problem+json"},
    )
```

## Rate Limiting

### Token Bucket Configuration

```python
# Per-endpoint rate limits
RATE_LIMITS = {
    "default": "100/minute",
    "auth/login": "5/minute",       # Brute-force protection
    "auth/register": "3/minute",    # Spam prevention
    "search": "30/minute",          # Expensive queries
    "export": "5/hour",             # Heavy operations
}

# Response headers (always include)
# X-RateLimit-Limit: 100
# X-RateLimit-Remaining: 73
# X-RateLimit-Reset: 1699999999 (Unix timestamp)
# Retry-After: 30 (seconds, only on 429)
```

### Tiered Limits

| Tier | Rate | Audience |
|------|------|----------|
| Anonymous | 20/min | Unauthenticated requests |
| Authenticated | 100/min | Regular users |
| Premium | 500/min | Paid plans |
| Internal | 1000/min | Service-to-service |

## API Versioning Strategy

```
/v1/users    — Current stable version
/v2/users    — New version (coexists during migration)
/v1/users    — Deprecated (return Deprecation + Sunset headers)
```

**Deprecation headers:**
```
Deprecation: true
Sunset: Sat, 01 Mar 2026 00:00:00 GMT
Link: </v2/users>; rel="successor-version"
```

**Rules:**
- Never break existing v1 contracts (additive changes only within a version)
- New version required for: removing fields, renaming fields, changing types, changing behavior
- Minimum 6-12 month deprecation window with sunset date
- Monitor v1 traffic — don't remove until usage drops below threshold
