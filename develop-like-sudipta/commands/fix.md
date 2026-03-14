---
description: >
  Fix a bug using TDD regression cycle. NEVER fix directly.
  Write regression test FIRST → verify FAILS → fix → verify PASSES.
  Use for any bug from audits, reviews, user reports, or discovered during development.
---

# Fix Command — TDD Bug-Fix Protocol

**NEVER apply a fix without a failing regression test. No exceptions.**

A fix without a test is a fix that will break again. The regression test is the
permanent guard that prevents the same bug from silently returning.

## Procedure

1. **IDENTIFY** the bug — read the finding/report/description
   - What is the expected behavior?
   - What is the actual (buggy) behavior?
   - Which file(s) and line(s) are involved?

2. **REPRODUCE** — confirm the bug exists
   - Run the relevant code path or write a minimal reproduction
   - Document: expected vs actual behavior

3. **REGRESSION TEST (RED)** — dispatch `test-writer` agent
   - Write a test that captures the EXACT bug behavior
   - Test should assert the EXPECTED (correct) behavior
   - The test MUST FAIL because the bug still exists
   - If the test passes immediately → it doesn't capture the bug. Rewrite.

4. **VERIFY RED** — run the test
   ```bash
   pytest tests/test_<module>.py::<test_name> -v  # Python
   vitest run <test_file> -t "<test_name>"          # TypeScript
   ```
   - ✅ Test FAILS → proceed to step 5
   - ❌ Test PASSES → go back to step 3. The test is wrong.

5. **FIX (GREEN)** — dispatch `implementer` agent (bug-fix mode)
   - Write MINIMUM code change to make the regression test pass
   - No extra refactoring, no feature additions — just the fix

6. **VERIFY GREEN** — run the test again
   ```bash
   pytest tests/test_<module>.py::<test_name> -v  # Python
   vitest run <test_file> -t "<test_name>"          # TypeScript
   ```
   - ✅ Test PASSES → proceed to step 7
   - ❌ Test FAILS → fix is incomplete. Return to step 5.

7. **FULL SUITE** — run ALL tests to check for regressions
   ```bash
   pytest --tb=short   # Python
   vitest run           # TypeScript
   ```
   - ✅ All pass → bug is fixed with regression protection
   - ❌ Some fail → fix introduced a regression. Investigate.

## Usage

```
/fix <description of bug or finding reference>
/fix "IDOR vulnerability in GET /api/users/:id — missing ownership check"
/fix "TypeError when input is None in calculate_total()"
/fix finding from /hack audit, CWE-89 in src/db/queries.py:42
```

## Integration with Other Commands

| Source | Flow |
|--------|------|
| `/hack` findings | Each CRITICAL/HIGH finding → `/fix` |
| `/secure` findings | Each finding with fix needed → `/fix` |
| `/review` findings | Each P0/P1 finding → `/fix` |
| User-reported bug | `/fix` directly |

## Anti-Patterns (REJECT these)

| Shortcut | Why It's Wrong |
|----------|---------------|
| "Fix is one line, skip the test" | One-line fixes regress most often. Test it. |
| "I'll add the test after the fix" | Post-fix tests are biased — they test the fix, not the bug. |
| "The existing tests cover this" | If existing tests didn't catch the bug, they don't cover it. |
| "It's just a typo" | Typo-level bugs need typo-level regression tests. 30 seconds. |
