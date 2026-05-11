# Phase <N> — <one-line title>

> Replace ALL placeholders. Keep section structure; CC keys off the headers.

## Operating mode (v4.6 — read FIRST)

You are operating in **continuous-driver mode**. The plugin manager (Cowork or
human) writes one phase directive at a time and triggers you. You do NOT wait
for a confirmation ping between sub-tasks within a phase. After finishing the
last task of this phase:

1. Run the phase's verify-gate (static checks + tests) yourself before
   declaring it done. The plugin will audit; don't rely on it to catch red.
2. Append `state.sh phase_complete phase=<N>` if `~/.cache/ccbridge/state.sh`
   is on PATH (it is by default after `/cc-drive` ran).
3. STOP and emit a one-line summary on stdout. Do NOT start the next phase —
   the manager will trigger phase N+1 with a new directive file.

If you encounter a bug at ANY step (red unit test, red browser test, runtime
exception that breaks a documented contract): apply the bug-driven TDD
protocol in `references/bug_driven_tdd.md` — write a failing test FIRST,
confirm red, then fix, then confirm green. No fix lands without a failing test.

If you get stuck (>3 failed attempts on the same problem, or a required
external resource is genuinely unreachable): emit a one-line `BLOCKED:` summary
explaining the blocker. The manager will escalate. Do NOT loop indefinitely.

## Scope

<2-4 sentences. Why does this phase exist? What gap does it close? What
invariant does it preserve? Set the model's frame BEFORE the tasks.>

## UI conventions (apply to any task that adds or modifies UI components)

Every interactive element (button, input, link, form, dialog, tab, etc.)
MUST have a stable `data-testid` attribute. Naming convention:
`<feature>-<element>-<action-or-state>`, kebab-case. Examples:

- `login-email-input`
- `login-password-input`
- `login-submit-button`
- `nav-dashboard-link`
- `cart-checkout-button`
- `dialog-confirm-yes` / `dialog-confirm-no`

This is non-negotiable. Browser tests reference elements by testid first;
without testids, selectors fall back to text/role and become brittle.

If you skip a testid because "this element is for layout only" — fine,
but call it out in the commit so the browser-test step doesn't waste
time looking for it.

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
