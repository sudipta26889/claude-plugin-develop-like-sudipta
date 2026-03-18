---
description: Comprehensive code review — quality, security, test coverage, and git hygiene.
---

# Review Command

Run a full review combining multiple agents in parallel:

0. **BASELINE CAPTURE** — Run full test suite, record pass/fail counts BEFORE any remediation
1. **Code quality** — dispatch `code-reviewer` agent on changed files
2. **Security** — dispatch `security-reviewer` agent on changed files
3. **Test coverage** — run `pytest --cov` or `vitest --coverage`, check ≥80%
4. **Git hygiene** — verify Conventional Commits, atomic commits, PR <400 lines
5. **No AI co-author** — verify no `Co-authored-by` with Claude/Cursor/Copilot

Synthesize all findings into a single report ordered by severity.
Include the 7-dimension Engineering Verdict from code-reviewer.

**REMEDIATION (if requested):** Apply fixes ONE at a time using `/fix` command.
After EACH fix, run full test suite. If any baseline test breaks → ROLLBACK immediately.
Never batch-fix findings — one change, one verification, one commit.

For deeper security analysis, suggest `/hack` (full 23-category red-team audit).
