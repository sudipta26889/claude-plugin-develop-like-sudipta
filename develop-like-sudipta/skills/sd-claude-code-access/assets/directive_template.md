# Phase <N> — <one-line title>

> Replace ALL placeholders. Keep section structure; CC keys off the headers.

## Scope

<2-4 sentences. Why does this phase exist? What gap does it close? What
invariant does it preserve? Set the model's frame BEFORE the tasks.>

## Tasks (<M> commits)

### <N>.1 <Short imperative title>

**Why:** <One sentence — the load-bearing reason this task exists.>

**Where:** <Exact file paths, function names, line numbers if known.>

**How:**
- <Bullet list of the actual changes>
- <Include code snippets for non-obvious bits>
- <Name specific patterns: `asyncio.gather(... return_exceptions=True)`,
  `clock_timestamp()` not `now()`, etc.>

**Failure modes:**
- <Things that have bitten in similar code>
- <What to do when each one happens>

**Tests:**
- <Test names you expect to see>
- <Edge cases: empty / error path / concurrency / boundary>

### <N>.2 <Short imperative title>

[same shape]

## Acceptance

The gate that has to clear before checkpoint.
- pytest clean (cumulative count: <NNN>)
- ruff + mypy clean
- (if applicable) <integration check>

## Commit pattern

- `feat(<area>): <what>`
- `feat(<area>): <what>`
- `chore: <what>`

## Out of scope

<What you EXPLICITLY don't want CC to expand into. Example: "Don't add
dashboard UI for this; that lands in Phase 10. Just expose the API
endpoint.">
