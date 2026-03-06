# Performance & Database Reference

Detailed guidance for performance optimization and database best practices. Read this when optimizing queries, implementing caching, designing indexes, or managing migrations.

## The Cardinal Rule: Profile Before Optimizing

Never optimize without measurement. Profiling identifies actual bottlenecks — intuition is usually wrong.

**Tools by layer:**

| Layer | Tool | What It Shows |
|-------|------|---------------|
| Python | `cProfile`, `py-spy`, Scalene | CPU time, memory, line-by-line |
| Node.js | `--inspect`, clinic.js | CPU, event loop, I/O |
| SQL | `EXPLAIN ANALYZE` | Query plan, actual vs estimated rows |
| HTTP | Lighthouse, WebPageTest | LCP, INP, CLS, TTFB |
| APM | Datadog, New Relic, Jaeger | Distributed traces, latency breakdown |

**Enforcement:** Any PR labeled "performance" must include profiling evidence (flame graph, EXPLAIN output, before/after benchmarks).

## N+1 Query Problem

### The Problem

```python
# ❌ N+1 — This executes 101 queries for 100 users
users = await db.execute(select(User).limit(100))
for user in users.scalars():
    orders = await db.execute(select(Order).where(Order.user_id == user.id))
    # Query 1: SELECT * FROM users LIMIT 100
    # Query 2-101: SELECT * FROM orders WHERE user_id = ? (for each user)
```

### The Fix

```python
# ✅ Eager loading — 1 or 2 queries total
from sqlalchemy.orm import selectinload, joinedload

# Option 1: selectinload (separate IN query — good for collections)
users = await db.execute(
    select(User).options(selectinload(User.orders)).limit(100)
)
# Query 1: SELECT * FROM users LIMIT 100
# Query 2: SELECT * FROM orders WHERE user_id IN (1, 2, 3, ..., 100)

# Option 2: joinedload (single JOIN — good for one-to-one)
users = await db.execute(
    select(User).options(joinedload(User.profile)).limit(100)
)
# Query 1: SELECT * FROM users JOIN profiles ON users.id = profiles.user_id LIMIT 100
```

### Detection

```python
# Python — use nplusone library
# pip install nplusone
NPLUSONE_RAISE = True  # Raises exception on N+1 in dev/test

# Or manual detection via SQL logging
import logging
logging.getLogger("sqlalchemy.engine").setLevel(logging.INFO)
# Watch for repeated similar queries in logs
```

## Multi-Layer Caching Strategy

```
Request → CDN Cache (static assets, ~95% hit rate target)
        → Application Cache (Redis/Memcached, hot data)
        → Database Query Cache (materialized views, query result cache)
        → Database (source of truth)
```

### Redis Caching Pattern

```python
import json
from datetime import timedelta

class CacheService:
    """
    WHY: Database queries for frequently-accessed data (user profiles,
    config, popular items) add 5-50ms latency per query. Redis serves
    from memory in <1ms, reducing load on DB by 80-90%.
    """

    def __init__(self, redis: Redis):
        self.redis = redis

    async def get_or_set(
        self,
        key: str,
        fetch_fn,
        ttl: timedelta = timedelta(minutes=5),
    ):
        """Cache-aside pattern: check cache first, fetch + store on miss."""
        cached = await self.redis.get(key)
        if cached:
            return json.loads(cached)

        result = await fetch_fn()
        await self.redis.setex(key, int(ttl.total_seconds()), json.dumps(result))
        return result

    async def invalidate(self, pattern: str):
        """
        WHY: Invalidation on write ensures stale data doesn't persist.
        Use patterns for related keys (e.g., user:123:* clears all user cache).
        """
        keys = await self.redis.keys(pattern)
        if keys:
            await self.redis.delete(*keys)
```

### Cache Invalidation Strategies

| Strategy | When | Trade-off |
|----------|------|-----------|
| **TTL-based** | Data tolerates staleness | Simple; stale for TTL duration |
| **Write-through** | Write updates cache immediately | Always fresh; write latency higher |
| **Write-behind** | Batch cache updates | High throughput; data loss risk |
| **Event-driven** | Pub/sub invalidation on change | Near-real-time; added complexity |

### HTTP Cache Headers

```python
# Static assets — long cache with content hashing
# /static/app.a1b2c3.js
Cache-Control: public, max-age=31536000, immutable

# API responses — short cache with revalidation
Cache-Control: private, max-age=60
ETag: "abc123"

# Never cache — sensitive or real-time data
Cache-Control: no-store
```

## Connection Pooling

### Why

Each new database connection costs 50-200ms (TCP handshake + TLS + auth). Under load, connection storms can exhaust DB connection limits.

### Configuration

```python
# SQLAlchemy async pool
from sqlalchemy.ext.asyncio import create_async_engine

engine = create_async_engine(
    DATABASE_URL,
    pool_size=10,              # Steady-state connections
    max_overflow=20,           # Burst capacity above pool_size
    pool_timeout=30,           # Seconds to wait for connection
    pool_recycle=3600,         # Recycle connections after 1 hour
    pool_pre_ping=True,        # Verify connection is alive before use
)

# Sizing heuristic (PostgreSQL):
# pool_size = (cpu_cores × 2) + effective_spindle_count
# For 4 cores, SSD: pool_size = (4 × 2) + 1 = 9 ≈ 10
```

#### Async Connection Pool Adjustment

For async frameworks (FastAPI + asyncpg, SQLAlchemy async):
- Async connections are multiplexed — each connection handles multiple queries via coroutines
- Pool size formula: `pool_size = num_cpu_cores * 2` (NOT `* 2 + disk_spindles`)
- Set `max_overflow = pool_size` (allows temporary bursts up to 2x)
- Always set `pool_timeout = 30` and `pool_recycle = 3600`
- Monitor `pool.checkedout()` — if consistently at max, increase pool size

### External Pooler (PgBouncer)

For PostgreSQL at scale, use PgBouncer in front of the database:

```ini
# pgbouncer.ini
[databases]
myapp = host=db-server port=5432 dbname=myapp

[pgbouncer]
pool_mode = transaction      # Release connection after each transaction
default_pool_size = 20
max_client_conn = 200
```

## Database Indexing

### The ESR Rule (Equality → Sort → Range)

For composite indexes, order columns as:
1. **Equality** columns first (exact match in WHERE)
2. **Sort** columns next (ORDER BY)
3. **Range** columns last (>, <, BETWEEN, LIKE)

```sql
-- Query: WHERE status = 'active' AND created_at > '2025-01-01' ORDER BY name
-- ESR order: status (E), name (S), created_at (R)
CREATE INDEX idx_users_status_name_created ON users (status, name, created_at);
```

### Indexing Rules

```sql
-- ✅ Always index
ALTER TABLE orders ADD INDEX idx_orders_user_id (user_id);      -- Foreign keys
ALTER TABLE orders ADD INDEX idx_orders_status (status);         -- Frequent WHERE
ALTER TABLE orders ADD INDEX idx_orders_created (created_at);    -- ORDER BY / range

-- ✅ Covering index (avoids table lookup)
CREATE INDEX idx_users_email_name ON users (email, name);
-- SELECT name FROM users WHERE email = ? -- served entirely from index

-- ❌ Don't index
-- Low-cardinality columns (boolean, gender) — unless in composite
-- Columns rarely used in WHERE/JOIN/ORDER
-- Tables with <1000 rows (full scan is fast enough)
```

### Monitoring Index Usage

```sql
-- PostgreSQL: Find unused indexes
SELECT indexrelname, idx_scan, idx_tup_read
FROM pg_stat_user_indexes
WHERE idx_scan = 0
ORDER BY pg_relation_size(indexrelid) DESC;

-- Find missing indexes (slow queries)
SELECT query, calls, mean_exec_time, rows
FROM pg_stat_statements
ORDER BY mean_exec_time DESC
LIMIT 20;
```

## Database Migration Best Practices

### Tools

| Language | Tool | Key Command |
|----------|------|-------------|
| Python | Alembic | `alembic revision --autogenerate -m "add_users_table"` |
| Node.js | Knex / Prisma | `npx prisma migrate dev --name add_users` |
| General | Flyway / Liquibase | `flyway migrate` |

### The Expand-Contract Pattern

For breaking schema changes, split into backward-compatible phases:

```
Phase 1 (Expand): Add new column/table alongside old
  → Deploy code that writes to BOTH old and new
  → Backfill new column from old data

Phase 2 (Migrate): Update code to read from new column
  → Deploy, verify everything works
  → Monitor for issues

Phase 3 (Contract): Remove old column/table
  → Only after confirming new structure is stable
  → New migration to drop old column
```

**Example: Renaming `full_name` to `display_name`**

```python
# Migration 1 (Expand): Add new column
op.add_column("users", sa.Column("display_name", sa.String(200)))
op.execute("UPDATE users SET display_name = full_name")

# Deploy code that writes to BOTH columns

# Migration 2 (Contract): Remove old column (weeks later)
op.drop_column("users", "full_name")
```

### Migration Rules

1. **Never modify applied migrations** — always create new ones to roll forward.
2. **Make migrations backward-compatible** — old code must work during rollout.
3. **Test migrations** against prod-like data in CI (Testcontainers).
4. **Include rollback** (`downgrade`) in every migration.
5. **Review migrations like code** — they run against production data.

## The 3-2-1 Backup Rule

**3** copies of data, on **2** different media types, with **1** off-site.

| Copy | Type | Example |
|------|------|---------|
| Primary | Production DB | PostgreSQL on server |
| Backup 1 | Automated snapshot | Daily pg_dump to local storage |
| Backup 2 | Off-site/cloud | Replicated to S3/GCS with versioning |

**Schedule:**
- Full backup: daily
- Incremental/WAL: continuous or hourly
- Retention: 30 days minimum
- **Monthly restore test** — backups that haven't been tested are not backups.

## Core Web Vitals (Frontend Performance)

| Metric | What | Good | Needs Work | Poor |
|--------|------|------|------------|------|
| **LCP** | Largest Contentful Paint | ≤2.5s | ≤4.0s | >4.0s |
| **INP** | Interaction to Next Paint | ≤200ms | ≤500ms | >500ms |
| **CLS** | Cumulative Layout Shift | ≤0.1 | ≤0.25 | >0.25 |

**Enforcement:** Lighthouse CI performance budgets in deploy pipeline. Block deploys that regress CWV.
