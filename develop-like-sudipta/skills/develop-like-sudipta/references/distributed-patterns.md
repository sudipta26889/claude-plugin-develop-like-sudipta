# Distributed Patterns Reference

Patterns for building reliable distributed systems: idempotency beyond REST APIs,
transaction management across services, concurrency safety, and zero-downtime migrations.

---

## Idempotency Patterns (All Layers)

### 1. Database Idempotency — Upserts & Natural Keys

**Problem:** Duplicate inserts from retries, race conditions, or queue redelivery.

**Pattern: ON CONFLICT / Upsert**

```python
# PostgreSQL — idempotent insert
async def upsert_order(order: Order) -> Order:
    """Idempotent: safe to call multiple times with same order_id."""
    result = await db.execute(
        text("""
            INSERT INTO orders (order_id, user_id, amount, status)
            VALUES (:order_id, :user_id, :amount, :status)
            ON CONFLICT (order_id) DO UPDATE SET
                status = EXCLUDED.status,
                updated_at = NOW()
            RETURNING *
        """),
        order.dict()
    )
    return Order(**result.first()._mapping)
```

**Pattern: Deduplication Column**

```python
# Add unique constraint on natural key
# Migration (idempotent itself — uses IF NOT EXISTS):
ALTER TABLE payments ADD COLUMN IF NOT EXISTS idempotency_key VARCHAR(64);
CREATE UNIQUE INDEX IF NOT EXISTS idx_payments_idempotency
    ON payments (idempotency_key) WHERE idempotency_key IS NOT NULL;
```

**When to use:** Any table receiving writes from external sources, webhooks, or queue consumers.

### 2. Message Queue Idempotency — Consumer Dedup

**Problem:** At-least-once delivery means consumers WILL receive duplicates.

**Pattern: Processed Events Table**

```python
class IdempotentConsumer:
    """Tracks processed message IDs to skip duplicates."""

    async def handle(self, message: Message) -> None:
        # Check if already processed
        existing = await self.db.execute(
            text("SELECT 1 FROM processed_events WHERE event_id = :id"),
            {"id": message.id}
        )
        if existing.first():
            logger.info("Skipping duplicate", event_id=message.id)
            return

        async with self.db.begin():
            # Process + record in SAME transaction
            await self._process(message)
            await self.db.execute(
                text("INSERT INTO processed_events (event_id, processed_at) VALUES (:id, NOW())"),
                {"id": message.id}
            )
```

**Celery-Specific Dedup:**

```python
from celery import Task
import redis

class IdempotentTask(Task):
    """Base class for idempotent Celery tasks."""

    def before_start(self, task_id, args, kwargs):
        r = redis.from_url(settings.REDIS_URL)
        lock_key = f"task:done:{self.name}:{task_id}"
        if r.exists(lock_key):
            raise Ignore()  # Skip — already processed
        # Set lock with TTL (prevents stale locks)
        r.setex(lock_key, 86400, "1")  # 24h TTL

@app.task(base=IdempotentTask, bind=True)
def process_payment(self, payment_id: str):
    """Safe to retry — idempotent via base class."""
    ...
```

### 3. Webhook Idempotency — Event ID Dedup

**Problem:** Webhook providers (Xsolla, Stripe, etc.) retry on timeouts → duplicate processing.

```python
async def handle_webhook(request: Request) -> JSONResponse:
    event = await request.json()
    event_id = event["id"]  # Provider's unique event ID

    # Idempotency check
    if await is_event_processed(event_id):
        return JSONResponse({"status": "already_processed"}, status_code=200)

    async with db.begin():
        await process_event(event)
        await mark_event_processed(event_id)

    # ALWAYS return 200 — even on duplicate. Prevents provider retry storms.
    return JSONResponse({"status": "ok"}, status_code=200)
```

**Key rule:** Always respond 200 to webhooks after dedup check — non-200 triggers retry storms.

### 4. Idempotent Migrations — Re-runnable DDL

**Problem:** Alembic migrations fail midway → partial state → can't re-run.

```sql
-- GOOD: Idempotent — safe to re-run
CREATE TABLE IF NOT EXISTS users (...);
CREATE INDEX IF NOT EXISTS idx_users_email ON users (email);
ALTER TABLE orders ADD COLUMN IF NOT EXISTS discount DECIMAL(10,2) DEFAULT 0;
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'order_status') THEN
        CREATE TYPE order_status AS ENUM ('pending', 'paid', 'shipped');
    END IF;
END $$;

-- BAD: Non-idempotent — fails on re-run
CREATE TABLE users (...);            -- ERROR: already exists
ALTER TABLE orders ADD COLUMN discount DECIMAL;  -- ERROR: column exists
```

**Alembic rule:** Every `upgrade()` must use `IF NOT EXISTS` / `IF EXISTS` guards.
Every `downgrade()` must be similarly guarded.

---

## Transaction Patterns for Distributed Systems

### 5. The Transactional Outbox Pattern

**Problem:** Need to update DB AND publish event atomically. DB commit + message publish
can partially fail → inconsistency.

**Solution:** Write event to outbox table in SAME DB transaction. Separate process polls
and publishes.

```python
async def create_order(order: OrderCreate) -> Order:
    async with db.begin():
        # Business logic
        db_order = await order_repo.create(order)

        # Write event to outbox in SAME transaction
        await outbox_repo.create(OutboxEvent(
            aggregate_type="Order",
            aggregate_id=str(db_order.id),
            event_type="OrderCreated",
            payload=db_order.dict(),
        ))

    return db_order  # Event published by OutboxPublisher process
```

**Outbox Publisher (separate process/worker):**

```python
class OutboxPublisher:
    """Polls outbox table and publishes to message broker."""

    async def run(self):
        while True:
            events = await outbox_repo.get_unpublished(limit=100)
            for event in events:
                try:
                    await broker.publish(event.event_type, event.payload)
                    await outbox_repo.mark_published(event.id)
                except Exception:
                    logger.error("Outbox publish failed", event_id=event.id)
                    # Will retry on next poll — idempotent consumers handle dupes
            await asyncio.sleep(1)
```

**When to use:** Any time you need DB write + event publish atomically. Replaces 2PC.

### 6. SAGA Pattern — Orchestration Style

**Problem:** Multi-service transaction (order → payment → inventory → shipping).
Can't use DB transaction across services.

**Solution:** Orchestrator coordinates steps. Each step has a compensating action for rollback.

```python
class OrderSaga:
    steps = [
        SagaStep(action=reserve_inventory, compensate=release_inventory),
        SagaStep(action=charge_payment,    compensate=refund_payment),
        SagaStep(action=create_shipment,   compensate=cancel_shipment),
    ]

    async def execute(self, order: Order):
        completed = []
        for step in self.steps:
            try:
                await step.action(order)
                completed.append(step)
            except Exception as e:
                logger.error("SAGA step failed", step=step.action.__name__)
                # Compensate in reverse order
                for s in reversed(completed):
                    await s.compensate(order)
                raise SagaFailed(f"Failed at {step.action.__name__}") from e
```

**SAGA Rules:**
- Every action MUST have a compensating action
- Compensations must be idempotent (may run multiple times)
- Log every step for debugging/audit
- Consider using Temporal/Inngest for complex orchestration

### 7. Distributed Locks — Redis SETNX

**Problem:** Multiple instances processing same resource → race conditions.

```python
import redis
from contextlib import asynccontextmanager

@asynccontextmanager
async def distributed_lock(key: str, ttl: int = 30):
    """Redis-based distributed lock with auto-expiry."""
    r = redis.from_url(settings.REDIS_URL)
    lock_key = f"lock:{key}"
    token = str(uuid4())

    acquired = r.set(lock_key, token, nx=True, ex=ttl)
    if not acquired:
        raise LockNotAcquired(f"Resource {key} is locked")

    try:
        yield
    finally:
        # Only release if WE hold the lock (compare token)
        if r.get(lock_key) == token.encode():
            r.delete(lock_key)

# Usage
async with distributed_lock(f"order:{order_id}"):
    await process_order(order_id)  # Only one instance at a time
```

**Critical rules:**
- ALWAYS set TTL — prevents deadlocks if holder crashes
- Use token comparison on release — prevents releasing someone else's lock
- For long operations: use lock extension (refresh TTL periodically)

---

## Concurrency Patterns

### 8. Async Concurrency Safety

**Semaphore for rate-limiting concurrent operations:**

```python
import asyncio

# Limit concurrent API calls to external service
semaphore = asyncio.Semaphore(10)

async def call_external_api(item):
    async with semaphore:  # Max 10 concurrent
        async with httpx.AsyncClient() as client:
            return await client.post(url, json=item, timeout=30.0)

# Process batch with controlled concurrency
results = await asyncio.gather(
    *[call_external_api(item) for item in items],
    return_exceptions=True  # Don't let one failure kill all
)
```

**Thread safety for shared state:**

```python
# BAD — race condition in async
counter = 0
async def increment():
    global counter
    counter += 1  # Not atomic!

# GOOD — use asyncio.Lock for shared mutable state
lock = asyncio.Lock()
async def safe_increment():
    async with lock:
        global counter
        counter += 1
```

**Rules:**
- Use `asyncio.Semaphore` to bound concurrent I/O (API calls, DB connections)
- Use `asyncio.Lock` for shared mutable state within a process
- Use Redis distributed locks for cross-process/cross-instance coordination
- Always set `timeout` on external calls — no unbounded waits
- Use `return_exceptions=True` in `asyncio.gather` to prevent cascade failures

---

## Zero-Downtime Database Migrations

### 9. Zero-Downtime Schema Migrations

> **Full Expand/Contract 3-phase procedure with Alembic examples:** See `references/performance-db.md` → "The Expand-Contract Pattern"

**Key rules:** Each phase = separate deployment. Phase 1 and Phase 3 never in same PR. Backfill in batches (1000-5000 rows). Add NOT NULL after backfill, not during expand.

### 10. Feature Flags Lifecycle

**Problem:** Long-lived branches diverge. Feature flags enable trunk-based development.

**Lifecycle:**

```
CREATE  → Define flag in config (default: OFF)
DEVELOP → Code behind flag: if feature_flags.is_enabled("new_checkout"): ...
TEST    → Enable in staging, run full test suite
RELEASE → Gradual rollout: 1% → 10% → 50% → 100%
CLEAN   → After 100% stable: remove flag code, remove flag definition
```

**Implementation:**

```python
# Simple file-based flags (small projects)
class FeatureFlags:
    _flags: dict[str, bool] = {}

    @classmethod
    def is_enabled(cls, flag: str, default: bool = False) -> bool:
        return cls._flags.get(flag, default)

# Usage in code
if FeatureFlags.is_enabled("new_payment_flow"):
    result = await new_payment_handler(order)
else:
    result = await legacy_payment_handler(order)
```

**Stale flag cleanup SLA:**
- Flag enabled at 100% for >30 days → create cleanup ticket
- Flag not touched in >90 days → mandatory removal
- Cleanup PR: remove flag checks, remove else branches, remove flag definition

#### Feature Flag Removal Checklist

When removing a feature flag after full rollout:
1. **Verify 100% rollout** — confirm flag is ON for all cohorts for ≥7 days
2. **Search codebase** — `rg "FLAG_NAME"` to find all references
3. **Remove flag evaluation** — replace `if flag_enabled("X")` with the enabled branch
4. **Remove dead branch** — delete the disabled code path
5. **Remove flag definition** — delete from flag config/database
6. **Update tests** — remove flag-conditional test cases
7. **Deploy and verify** — ensure no regressions
8. **Document** — note removal in changelog

---

## Decision Matrix — When to Use What

| Problem | Pattern | Key Trade-off |
|---|---|---|
| Duplicate writes from retries | DB upsert (ON CONFLICT) | Requires natural/unique key |
| Duplicate queue messages | Consumer dedup table | Extra DB write per message |
| Duplicate webhooks | Event ID dedup + always 200 | Must track event IDs |
| DB + event publish atomically | Transactional Outbox | Extra table + poller process |
| Multi-service transaction | SAGA (orchestration) | Must define compensating actions |
| Cross-instance resource access | Redis distributed lock | TTL tuning, lock extension |
| Concurrent I/O control | asyncio.Semaphore | Must choose right concurrency limit |
| Column rename/type change | Expand/Contract (3-phase) | 3 deployments instead of 1 |
| Incomplete features on main | Feature flags | Must clean up stale flags |
| Re-runnable schema changes | Idempotent DDL (IF NOT EXISTS) | Slightly more verbose SQL |

## Red Flags in Distributed Systems

- Queue consumer without dedup → processes payments twice
- Webhook handler returning non-200 on known events → retry storm
- DB transaction wrapping external API call → holding locks during network I/O
- No TTL on distributed locks → deadlock when holder crashes
- `asyncio.gather` without `return_exceptions=True` → one failure kills batch
- Single-phase destructive migration → breaks running code during deploy
- Feature flag alive >90 days → permanent tech debt
- Outbox table without cleanup → unbounded growth
