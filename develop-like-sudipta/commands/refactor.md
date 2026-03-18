---
description: >
  Safe refactoring with Preservation Protocol. Apply best practices, code quality
  improvements, and structural changes WITHOUT breaking existing functionality.
  Baseline → atomic change → verify → rollback on failure. Every single time.
---

# Refactor Command — Safe Refactoring Protocol

**RULE: A refactor that breaks functionality is not a refactor — it's damage.**

This command exists because applying "best practices" and "improvements" to working code
has repeatedly broken systems. Every refactoring change must PROVE it preserves behavior.

## Procedure

### Phase 0 — Baseline Capture (NON-NEGOTIABLE)

```bash
# Run full test suite and capture results
pytest --tb=short -q 2>&1 | tee .claude/baseline-test-results.txt   # Python
npm test 2>&1 | tee .claude/baseline-test-results.txt                # Node

# Record the pass/fail counts
echo "Baseline captured at $(date)" >> .claude/baseline-test-results.txt
```

If NO tests exist:
1. **STOP** — do NOT refactor untested code
2. Write **characterization tests** first that capture current behavior
3. Verify characterization tests PASS
4. THEN proceed with refactoring

### Phase 1 — Assess and Prioritize

1. Identify refactoring targets (code smells, SOLID violations, DRY violations, etc.)
2. Prioritize by impact: highest value, lowest risk first
3. Create a list of atomic changes — each one independently verifiable
4. Estimate risk for each: LOW (rename, extract) / MEDIUM (restructure) / HIGH (rewrite)

### Phase 2 — Atomic Refactoring Loop

For EACH change in the list:

```
1. DESCRIBE  → What exactly will change? What should NOT change?
2. CHANGE    → Make exactly ONE logical change
3. VERIFY    → Run full test suite
4. COMPARE   → Same or better pass count vs baseline?
   ✅ YES → git add + continue to next change
   ❌ NO  → ROLLBACK (git checkout -- <files>), document why it broke, try alternative
5. COMMIT    → Atomic commit for this one refactoring change
```

**NEVER batch multiple refactoring changes before verification.**

### Phase 3 — Final Verification

After all refactoring is complete:
```bash
# Run full suite one more time
pytest --tb=short -q   # or npm test

# Compare against original baseline
# Pass count MUST be >= baseline pass count
```

## What Counts as "Atomic"

| Atomic (ONE change) | NOT Atomic (batch — SPLIT IT) |
|---------------------|-------------------------------|
| Rename one variable/function | Rename + restructure + add validation |
| Extract one method | Extract method + change its callers + add tests |
| Move one function to better module | Move function + update imports + refactor callers |
| Replace one magic number with constant | Replace constants + add config + change behavior |
| Add input validation to one function | Add validation to 5 functions at once |

## Rollback Protocol

When a refactoring change breaks a test:

```bash
# 1. See what changed
git diff <file>

# 2. Revert the breaking change
git checkout -- <file>

# 3. Verify baseline is restored
pytest --tb=short -q

# 4. Document
echo "FAILED: <what was attempted> broke <which test> because <why>" >> .claude/refactor-log.txt
```

Then either:
- Try an alternative approach for the same improvement
- Skip this refactoring if too risky — document as tech debt
- Break it into smaller atomic changes

## Anti-Patterns (REJECT these)

| Shortcut | Why It's Wrong |
|----------|---------------|
| "Apply all SOLID fixes at once" | Batch changes = untraceable breakage |
| "Refactor untested code" | No tests = no safety net = guaranteed breakage |
| "The tests are wrong, update them" | Tests define the contract. If tests break, you broke the contract. |
| "This is just renaming" | Renaming can break imports, reflection, serialization, configs |
| "Best practices can't hurt" | Best practices applied without verification destroy working systems |
| "I'll verify at the end" | Verifying at the end means you can't identify which change broke things |
