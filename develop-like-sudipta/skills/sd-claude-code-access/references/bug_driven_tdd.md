# Bug-driven TDD — red-test-first, every fix, no exceptions

## The rule

> **No fix lands without a failing test first.** A bug you can't reproduce is a guess. A fix you can't prove green is wishful thinking.

When ANY test goes red — unit, integration, or browser — the bug-found protocol is the only path forward. Skip a step and the fix is at best lucky, at worst it papers over the real defect.

> **Before invoking bug-found protocol:** verify_gate's flake-retry layer (see `references/verify_gate.md`) re-runs the failing test up to `flake_retries` times. If it recovers, it's a flake — no bug. If it's in `flake_whitelist`, the failure is logged but doesn't trigger the bug-found protocol. Only persistently-red tests not on the whitelist arrive here.

## The sequence (memorize this)

```
       ┌────────────────────────┐
       │ Test went red          │
       └───────────┬────────────┘
                   ▼
       ┌────────────────────────┐
       │ 1. CAPTURE evidence    │  → .cc/bugs/<bug-id>.md
       └───────────┬────────────┘
                   ▼
       ┌────────────────────────┐
       │ 2. REPRODUCE in code   │
       │   a. NEW failing unit  │  → tests/...  (red, bug-specific reason)
       │   b. NEW failing e2e   │  → specs/...  (red, user-visible)
       └───────────┬────────────┘
                   ▼
       ┌────────────────────────┐
       │ 3. FIX                 │  → .cc/phase-<N>-fix.md → send to CC
       └───────────┬────────────┘
                   ▼
       ┌────────────────────────┐
       │ 4. CONFIRM 4 greens    │
       │   a. new unit  → green │
       │   b. new e2e   → green │
       │   c. FULL gate → green │
       │   d. original  → green │
       └───────────┬────────────┘
                   ▼
       ┌────────────────────────┐
       │ 5. LOG + commit        │
       └────────────────────────┘
```

If any of 4a–4d red on the same fix → loop back to step 2 (the repro might be wrong, OR the fix introduced regression). After **3 consecutive failed fix attempts on the same bug** → escalate.

## Step 1 — CAPTURE

Goal: turn the raw failure into a portable artifact. Other humans (and future-you) will read this without context.

Run the failing test command and save raw output (stdout+stderr) to a file. Pipe that file through `scripts/parse_test_output.py` (see `references/test_output_parsing.md`) to get a structured JSON document with the failure's `file`, `line`, `assertion`, `expected`, `actual`, and verbatim `traceback` — the parser auto-detects pytest / jest / vitest / cargo / go / maven. The parsed fields map 1:1 to the "Captured evidence" section of `assets/bug_report_template.md`. If the parser returns empty `failures` (runner not recognized or output format changed), fall back to manual extraction. Write the capture into `<workspace>/.cc/bugs/<bug-id>.md` using `assets/bug_report_template.md`. `<bug-id>` is `phase-<N>-bug-<short-slug>` — e.g. `phase-3-bug-cart-total-off-by-tax`.

Must include:
- **Exact failing command** (the shell command that produced the red)
- **Verbatim last 200 lines** of stdout+stderr (no editorializing, no `...truncated...`)
- **Failing assertion** with line number
- **Expected vs actual** (parsed from the assertion)
- **For browser bugs:** screenshot path, console messages, network responses, DOM excerpt
- **Files implicated** by the stack trace, resolved to relative paths
- **Phase number** + the phase directive's relevant acceptance criterion

## Step 2 — REPRODUCE in code

**Two layers**, both red, before any fix. Either layer alone is insufficient.

### 2a. Unit-layer reproduction

Write a NEW test in the project's test dir:

- **Naming:** `test_<bug-id>_<intent>` for pytest, `bug-<id>: <intent>` describe block for Jest/Vitest, `#[test] fn <bug_id>_<intent>` for Rust, `Test_<BugId>_<Intent>` for Go.
- **Scope:** smallest possible. If the bug is in a 5-line function, the test calls that function directly — not the whole HTTP handler.
- **Assertion:** asserts the CORRECT behavior. The test is red because the CURRENT behavior is wrong.
- **No mocks for the broken layer.** If `calculate_tax()` is broken, test it directly. Don't mock it.

Run it. Confirm it's red **for the bug-specific reason**:
- Wrong assertion message? → repro is right ✓
- Import error / missing fixture / type error? → repro is broken; fix the repro, not the bug.
- Test passes? → repro is wrong; rewrite.

### 2b. Browser-layer reproduction

Extend `docs/e2e-testing/phase-<N>-<slug>.md` with:

```markdown
## Bug repro: <bug-id>
**Date opened:** YYYY-MM-DD HH:MM
**Linked unit test:** `<path>::<test_name>`
**Reproduction steps:**
1. Navigate to /...
2. ...
**Expected:** <observable correct behavior>
**Actual:** <observable broken behavior>
**Evidence:** screenshots/phase-<N>/bug-<id>-s<n>.png
```

And add to `specs/phase-<N>.spec.ts`:

```typescript
test.step('bug-<id>: <intent>', async () => {
  // exercise the broken flow
  await page.goto('...');
  // ...
  // assertion that captures the CORRECT behavior
  await expect(page.getByText('Total: $11.00')).toBeVisible();
});
```

Run the spec. Confirm red.

### If either repro passes accidentally

Stop. The repro is wrong. Possibilities:
- The bug only manifests with specific data/state — your repro doesn't set up that state.
- The bug is in a code path your repro doesn't reach.
- The original red was a flake, not a real bug.

Rewrite until both layers are red. If after careful inspection neither repro can be made red → the bug doesn't exist; close the bug report with `## Result: not reproducible` and the evidence that convinced you.

## Step 3 — FIX

Write `<workspace>/.cc/phase-<N>-fix.md`:

```markdown
# Phase <N> — fix for <bug-id>

## Bug summary
<one paragraph; link to .cc/bugs/<bug-id>.md for evidence>

## Failing tests (must go green)
- `<path/to/test_<bug-id>_<intent>>` — unit
- `docs/e2e-testing/specs/phase-<N>.spec.ts::bug-<id>: <intent>` — browser

## Acceptance
1. Both tests above turn green.
2. Full verify-gate stays green (no regression).
3. Original `phase-<N>` browser test stays green.

## What changed (suggested — CC may improve)
<short hypothesis; let CC investigate; don't over-prescribe>

## Out of scope
<anything CC should NOT touch in this fix>
```

Send the trigger to CC:
```
Read `.cc/phase-<N>-fix.md` and apply the fix per the bug-driven-TDD protocol.
The two failing tests are the contract. Do NOT modify them — they are the
bug's signature. Make them green by changing implementation only.
```

## Step 4 — CONFIRM (four greens, in order)

**Order matters** — each green is a different guarantee:

| Light | What it proves | Command |
|---|---|---|
| 4a. New unit test → green | Fix addresses the root cause at the smallest scope | re-run JUST the new unit test |
| 4b. New browser test → green | Fix is visible to the user | re-run JUST the new test.step |
| 4c. **Full verify-gate** → green | Fix didn't break anything else (regression guard) | full static + all unit + all integration |
| 4d. Phase's original browser test → green | The original phase still works (not just the bug) | re-run the original phase spec |

If 4a–4b green but 4c red → you fixed the bug but introduced regression. Loop back to step 2 with the regression as the new bug.
If 4a green but 4b red → unit test passes but user still sees the bug → the unit test was wrong-scoped. Rewrite the unit test to actually capture the user-visible failure.
If 4a–4d all green → done.

## Step 5 — LOG and commit

```bash
~/.cache/ccbridge/state.sh "$WORKSPACE" bug_resolved bug=<id> phase=<N>
```

Append to `docs/e2e-testing/phase-<N>-<slug>.md`:

```markdown
## Re-run YYYY-MM-DD HH:MM — bug-<id> resolved
- **Status:** pass
- **Trigger:** fix applied via `.cc/phase-<N>-fix.md`
- **CC commit:** `<sha>`
- **New tests now passing:** `<unit-test-path>`, `phase-<N>.spec.ts::bug-<id>`
- **Notes:** <what changed in the implementation>
```

CC should commit the new tests + the fix as ONE logical change with a Conventional Commits `fix:` prefix:

```
fix(<scope>): <description> (bug-<id>)

Adds failing tests at unit and browser layer, then fixes <root cause>.
Closes: .cc/bugs/<bug-id>.md
```

## Worked examples

### Example A — Unit-only bug (no UI surface)

Pillar 3 (env-sync) bug: `DATABASE_URL` changed in `.env` but not in `docker-compose.yml`. Integration tests pass locally, fail in Docker.

- **Capture:** failing `pytest tests/integration/test_db.py::test_connect` with `psycopg2.OperationalError: could not translate host name "db" to address`.
- **Repro 2a:** write `test_db_url_consistency` — asserts `os.getenv("DATABASE_URL")` in container matches `compose.services.db.environment.POSTGRES_DB`. Currently red.
- **Repro 2b:** browser layer — the app's `/health` endpoint returns 500 because DB conn fails. Add a Playwright step: `await expect(page.goto('/health')).resolves.toHaveProperty('status', 200)`. Red.
- **Fix:** update `docker-compose.yml` env block to match.
- **Confirm:** 2a green, 2b green, full gate green, phase browser test green.

### Example B — Browser-only bug (visual/UX)

Submit button stays disabled after form is valid. Unit tests for form validation all pass.

- **Capture:** screenshot of submit button still grayed out, console clean, network silent. The unit `test_form_validator.test_valid_input` passes because validation logic is right — the bug is in the binding to the disabled state.
- **Repro 2a:** add `test_submit_button_state_reflects_validity` — render the form component with valid input, assert `submit.disabled === false`. Currently red.
- **Repro 2b:** add `test.step('bug-<id>: submit enables on valid input', ...)` — fill the form with valid data, `await expect(getByRole('button', { name: /submit/i })).toBeEnabled()`. Red.
- **Fix:** the disabled state was reading `formik.isValid` but the form was using `react-hook-form`. Swap to `!formState.isValid`.
- **Confirm:** both new tests green, full gate green, phase test green.

### Example C — Both-layer bug

Cart total calculation is off by tax rate. User sees wrong price; backend `calculate_total()` returns the wrong number; both layers need fixing because the test that should have caught this was mocked too aggressively.

- **Capture:** "Total: $10.00" displayed; expected "$11.00 ($10 + $1 tax)". Unit test passes because it mocked `tax_rate=0`.
- **Repro 2a:** `test_calculate_total_includes_tax` with `tax_rate=0.10`, expected `11.00`. Currently red — function returns `10.00`.
- **Repro 2b:** browser — add product to cart, navigate to checkout, `await expect(page.getByText('Total: $11.00')).toBeVisible()`. Red.
- **Fix:** `calculate_total()` was returning `subtotal` instead of `subtotal * (1 + tax_rate)`.
- **Confirm:** both new tests green, full gate green, phase test green.

## Anti-patterns

- **"I'll write the test after the fix" — NO.** The point of red-first is that you prove the test catches THIS bug. A green test after a fix proves nothing about whether the test would have caught the bug.
- **Mocking the broken layer.** If `calculate_tax` is broken, don't mock it in your repro test.
- **Repro tests in `tests/sandbox/` or other quarantined dirs.** The repro tests are real tests — they belong in the project's main test tree.
- **Deleting the repro after the fix.** Don't. The repro IS the regression guard. It stays in the suite forever.
- **One test covering five bugs.** One bug, one repro (or one bug, two repros — unit + browser). Don't bundle.
- **Skipping 4c "to save time".** Then you don't know the fix didn't regress. Run the full gate.

## Audit pattern — did they write the failing test first?

When auditing a phase that closed a bug, verify the discipline was followed:

```bash
# 1. Find the fix commit
git log --grep "bug-<id>" --oneline

# 2. Get its parent
PARENT=$(git rev-parse <fix-sha>^)

# 3. Check the new test exists at PARENT (red) AND at fix-sha (green)
git show $PARENT:tests/.../<new-test-file> 2>/dev/null | head -5   # ← should show the test at red state

# Actually the strict check: the test FILE should have been added in the
# fix commit OR the commit immediately before. Run:
git log --diff-filter=A --pretty=format:"%h %s" -- '**/test_<bug-id>*' '**/<bug-id>*'

# Both the new pytest file AND the Playwright addition should appear here.
```

If the new test files are missing → the fix bypassed bug-driven TDD. Surface this in `/cc-audit`.

## Don't (one more time)

- Don't fix without a failing test.
- Don't claim green without 4c.
- Don't delete the repro tests.
- Don't escalate before 3 fix attempts — but DO escalate after 3.
