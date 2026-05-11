---
description: Run the bug-driven-TDD protocol on demand — capture evidence, write failing pytest + failing Playwright test (both red), produce a fix directive, then confirm four greens after the fix lands
argument-hint: <workspace-path> <one-line bug summary>
---

Apply the bug-driven-TDD protocol to a discovered bug. **No fix lands without a failing test first.**

**You MUST invoke the `sd-claude-code-access` skill before doing anything else** — specifically `references/bug_driven_tdd.md` (the protocol), `references/verify_gate.md` (how to run the unit suite), and `references/browser_testing.md` (how to drive Chrome MCP).

## Inputs

- `$1` — workspace path (required)
- Remaining args — one-line bug summary (e.g. `cart total off by tax rate`)

## Procedure (sequence is mandatory; do not skip)

### 1. CAPTURE
- Generate a `<bug-id>` of the form `phase-<N>-bug-<short-slug>`. Infer phase from the most recent `phase_complete` event in `$1/.cc/state.json`, or ask the user if ambiguous.
- Ask the user (only what's needed): observed symptom, repro command, dev-server state, any error message they saw.
- If the bug was found by `/cc-drive` or `/browser-test`, evidence is already in the test-step output — capture it directly.
- Write `$1/.cc/bugs/<bug-id>.md` using `assets/bug_report_template.md`. Fill in: metadata, symptom, failing command, exit code, last 200 lines of output, failing assertion, stack trace, screenshot path (if any), console + network observations, files implicated.

### 2. REPRODUCE in code (red first, two layers)

**a. Unit-layer reproduction**
- Choose the project's test framework (auto-detect via the verify-gate logic: pytest / jest / vitest / cargo test / go test / mvn test).
- Write a NEW test at the smallest scope that captures the bug. Name: `test_<bug-id>_<intent>`.
- Place under the project's existing test tree (e.g. `tests/unit/` for pytest, `__tests__/` for Jest, etc. — match existing conventions).
- Run JUST that test. Confirm RED **for the bug-specific reason** (not import errors or fixture problems).
- If it passes accidentally: the repro is wrong. Rewrite.

**b. Browser-layer reproduction**
- Open `$1/docs/e2e-testing/phase-<N>-<slug>.md`. Append a `## Bug repro: <bug-id>` block per `references/bug_driven_tdd.md`.
- Open `$1/docs/e2e-testing/specs/phase-<N>.spec.ts`. Add a new `test.step('bug-<id>: <intent>', ...)` block that drives Chrome through the failing scenario and asserts the CORRECT behavior.
- Run the spec. Confirm RED.
- If it passes accidentally: rewrite.

**Both must be red before proceeding.**

### 3. FIX directive
- Write `$1/.cc/phase-<N>-fix.md` with:
  - Bug summary (link to `.cc/bugs/<bug-id>.md`)
  - Both failing test paths (relative)
  - Acceptance: both tests green + full verify-gate green + original phase test green
  - Optional hypothesis (one paragraph max)
  - Out-of-scope list
- Send to CC:
  ```
  Read `.cc/phase-<N>-fix.md` and apply the fix per the bug-driven-TDD
  protocol. The two failing tests are the contract. Do NOT modify them.
  ```

### 4. CONFIRM four greens, IN ORDER
After CC commits the fix:
- **a.** Re-run the new unit test only → must be green.
- **b.** Re-run the new browser test step only → must be green.
- **c.** Re-run the FULL verify-gate (every static check + every project test) → must be green. *This catches regressions the fix introduced.*
- **d.** Re-run the phase's original browser test → must be green.

If any of 4a–4d red → loop back to step 2 with the new failure as evidence. After 3 consecutive failed fix attempts → escalate.

### 5. LOG and report
- `bash ~/.cache/ccbridge/state.sh "$1" bug_resolved bug=<bug-id> phase=<N>`
- Append `## Re-run YYYY-MM-DD HH:MM — bug-<bug-id> resolved` section to the per-phase browser-test md.
- Report to the user: bug-id, four-green checklist, new test file paths, commit sha of the fix.

## Don't

- **Don't write the fix before the failing tests.** That defeats the entire protocol.
- **Don't mock the broken layer in the repro test.** Test the real function.
- **Don't put repro tests in a `sandbox/` or `WIP/` directory.** They're real tests; they live in the main test tree.
- **Don't delete the repro tests after the fix lands.** They are the regression guard.
- **Don't claim resolved without 4c.** A green-on-the-new-test fix that breaks something else is not a fix.
- **Don't escalate before 3 attempts** — but DO escalate after 3.
