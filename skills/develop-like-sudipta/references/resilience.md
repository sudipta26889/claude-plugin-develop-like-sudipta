# Resilience & Observability Reference

Detailed guidance for Pillar 6. Read this when implementing logging, error handling, retry logic, circuit breakers, health checks, or observability.

## Structured Logging

### Log Format (JSON)

Every log entry must include these fields:

```json
{
  "timestamp": "2025-12-15T10:30:45.123Z",
  "level": "ERROR",
  "message": "Payment processing failed",
  "service": "payment-service",
  "traceId": "abc123def456",
  "spanId": "span789",
  "userId": "usr_123",
  "context": {
    "orderId": "ord_456",
    "gateway": "stripe",
    "errorCode": "card_declined"
  }
}
```

### Python Implementation (structlog)

```python
import structlog

structlog.configure(
    processors=[
        structlog.contextvars.merge_contextvars,
        structlog.processors.add_log_level,
        structlog.processors.TimeStamper(fmt="iso"),
        structlog.processors.StackInfoRenderer(),
        structlog.processors.JSONRenderer(),
    ],
)

logger = structlog.get_logger()

# Bind context once, carry through request lifecycle
logger = logger.bind(service="payment-service", trace_id=request.trace_id)
logger.info("processing_payment", order_id=order.id, amount=order.total)
logger.error("payment_failed", order_id=order.id, error_code="card_declined")
```

### Log Level Guidelines

| Level | When | Production? | Example |
|-------|------|-------------|---------|
| DEBUG | Detailed diagnostic info | ❌ Disabled | Variable values, query params |
| INFO | Normal operations | ✅ Yes | Request served, job completed |
| WARN | Unexpected but recoverable | ✅ Yes | Retry triggered, cache miss |
| ERROR | Failure requiring attention | ✅ Yes + Alert | Payment failed, DB timeout |
| CRITICAL | System-level failure | ✅ Yes + Page | DB down, out of memory |

### What NEVER to Log

```python
# ❌ NEVER log these
logger.info("login", password=user.password)           # Credentials
logger.info("payment", card_number=card.number)         # PII/financial
logger.info("token", access_token=token)                # Auth tokens
logger.info("request", headers=dict(request.headers))   # May contain auth

# ✅ Log sanitized versions
logger.info("login", user_email=mask_email(user.email))
logger.info("payment", card_last4=card.number[-4:])
```

## Retry with Exponential Backoff + Jitter

### Algorithm

```
delay = min(max_delay, base_delay × 2^attempt) + random(0, jitter_max)
```

### Python Implementation

```python
import asyncio
import random
from typing import TypeVar, Callable, Awaitable

T = TypeVar("T")

async def retry_with_backoff(
    func: Callable[..., Awaitable[T]],
    *args,
    max_retries: int = 3,
    base_delay: float = 1.0,
    max_delay: float = 60.0,
    jitter_max: float = 1.0,
    retryable_exceptions: tuple = (TimeoutError, ConnectionError),
) -> T:
    """
    WHY: External services fail transiently. Exponential backoff with jitter
    prevents thundering herd while allowing recovery. AWS research shows
    full jitter reduces total call count by >50% vs no-jitter backoff.

    THOUGHT: Only retry on transient errors (5xx, timeouts, connection errors).
    Never retry on client errors (4xx) — those won't succeed on retry.
    """
    for attempt in range(max_retries + 1):
        try:
            return await func(*args)
        except retryable_exceptions as e:
            if attempt == max_retries:
                logger.error(
                    "retry_exhausted",
                    function=func.__name__,
                    attempts=max_retries + 1,
                    final_error=str(e),
                )
                raise

            delay = min(max_delay, base_delay * (2 ** attempt))
            delay += random.uniform(0, jitter_max)

            logger.warn(
                "retry_scheduled",
                function=func.__name__,
                attempt=attempt + 1,
                delay_seconds=round(delay, 2),
                error=str(e),
            )
            await asyncio.sleep(delay)
```

### When to Retry vs When NOT to

| Retry ✅ | Don't Retry ❌ |
|----------|----------------|
| HTTP 500, 502, 503, 504 | HTTP 400, 401, 403, 404, 422 |
| HTTP 429 (respect Retry-After) | Business logic errors |
| Connection timeout | Validation failures |
| DNS resolution failure | Authentication failures |
| Connection reset | Payload too large (413) |

## Circuit Breaker Pattern

### State Machine

```
CLOSED (normal) ──[failure threshold exceeded]──→ OPEN (fail-fast)
     ↑                                                  │
     │                                          [timeout expires]
     │                                                  ↓
     └──────[probe succeeds]──────── HALF-OPEN (probe) ─┘
                                          │
                                   [probe fails]
                                          ↓
                                    OPEN (reset timeout)
```

### Python Implementation

```python
import time
from dataclasses import dataclass, field
from enum import Enum

class CircuitState(Enum):
    CLOSED = "closed"
    OPEN = "open"
    HALF_OPEN = "half_open"

@dataclass
class CircuitBreaker:
    """
    WHY: When a downstream service is down, continuing to send requests
    wastes resources and increases latency. Circuit breaker fails fast,
    giving the downstream time to recover.

    THOUGHT: Thresholds are configurable per-service. Payment gateways
    get lower thresholds (3 failures) than search (10 failures) because
    payment failures have higher business impact.
    """
    failure_threshold: int = 5
    recovery_timeout: float = 30.0  # seconds
    half_open_max_calls: int = 3

    state: CircuitState = field(default=CircuitState.CLOSED)
    failure_count: int = field(default=0)
    last_failure_time: float = field(default=0.0)
    half_open_calls: int = field(default=0)

    def can_execute(self) -> bool:
        if self.state == CircuitState.CLOSED:
            return True
        if self.state == CircuitState.OPEN:
            if time.time() - self.last_failure_time >= self.recovery_timeout:
                self.state = CircuitState.HALF_OPEN
                self.half_open_calls = 0
                return True
            return False  # Fail fast
        # HALF_OPEN — allow limited probes
        return self.half_open_calls < self.half_open_max_calls

    def record_success(self):
        if self.state == CircuitState.HALF_OPEN:
            self.half_open_calls += 1
            if self.half_open_calls >= self.half_open_max_calls:
                self.state = CircuitState.CLOSED
                self.failure_count = 0
        self.failure_count = max(0, self.failure_count - 1)

    def record_failure(self):
        self.failure_count += 1
        self.last_failure_time = time.time()
        if self.failure_count >= self.failure_threshold:
            self.state = CircuitState.OPEN
            logger.error("circuit_opened", breaker=self.__class__.__name__)
```

## Health Check Endpoints

```python
from fastapi import APIRouter
from datetime import datetime

health_router = APIRouter(tags=["health"])

@health_router.get("/healthz")
async def liveness():
    """
    WHY: Liveness probe — is the process running and responsive?
    Kubernetes restarts the pod if this fails.
    Do NOT check dependencies here (that's readiness).
    """
    return {"status": "alive", "timestamp": datetime.utcnow().isoformat()}

@health_router.get("/ready")
async def readiness(db: AsyncSession = Depends(get_db), redis: Redis = Depends(get_redis)):
    """
    WHY: Readiness probe — can this instance serve traffic?
    Checks all critical dependencies. Kubernetes removes from
    load balancer if this fails (but doesn't restart).
    """
    checks = {}
    try:
        await db.execute(text("SELECT 1"))
        checks["database"] = "ok"
    except Exception as e:
        checks["database"] = f"failed: {e}"

    try:
        await redis.ping()
        checks["redis"] = "ok"
    except Exception as e:
        checks["redis"] = f"failed: {e}"

    all_ok = all(v == "ok" for v in checks.values())
    return JSONResponse(
        status_code=200 if all_ok else 503,
        content={"status": "ready" if all_ok else "degraded", "checks": checks},
    )
```

## OpenTelemetry Setup

```python
# WHY: Vendor-neutral observability standard (CNCF graduated).
# Instrument once, export to any backend (Jaeger, Datadog, Grafana).

from opentelemetry import trace
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanExporter
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter
from opentelemetry.instrumentation.fastapi import FastAPIInstrumentor
from opentelemetry.instrumentation.sqlalchemy import SQLAlchemyInstrumentor
from opentelemetry.instrumentation.httpx import HTTPXClientInstrumentor

def setup_telemetry(app: FastAPI):
    provider = TracerProvider()
    provider.add_span_processor(
        BatchSpanExporter(OTLPSpanExporter(endpoint="http://otel-collector:4317"))
    )
    trace.set_tracer_provider(provider)

    # Auto-instrument frameworks
    FastAPIInstrumentor.instrument_app(app)
    SQLAlchemyInstrumentor().instrument(engine=engine)
    HTTPXClientInstrumentor().instrument()
```

## Graceful Degradation Patterns

| Dependency Failure | Degradation Strategy |
|-------------------|---------------------|
| Cache (Redis) down | Fall through to DB (slower but functional) |
| Search service down | Return recent/popular results from cache |
| Payment gateway down | Queue payment, notify user of delay |
| AI/ML service down | Return rule-based fallback |
| CDN down | Serve from origin (slower) |
| External API down | Return cached last-known-good data |

**Implementation pattern:**
```python
async def get_recommendations(user_id: str) -> list[Item]:
    try:
        return await ml_service.recommend(user_id)
    except (TimeoutError, CircuitOpenError):
        logger.warn("ml_fallback", user_id=user_id)
        # WHY: Popular items as fallback — still useful, not blank page
        return await cache.get("popular_items") or []
```

## The Four Golden Signals (Google SRE)

| Signal | What to Measure | Alert Threshold |
|--------|----------------|-----------------|
| **Latency** | p50, p95, p99 response times | p99 > 2× baseline for 5min |
| **Traffic** | Requests per second | >30% deviation from prediction |
| **Errors** | Error rate (5xx / total) | >1% error rate for 5min |
| **Saturation** | CPU, memory, disk, connections | >80% utilization for 10min |
