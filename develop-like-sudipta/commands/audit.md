---
description: Run a full code quality audit-fix cycle on recent changes or specified files.
---

# Audit Command

Invoke the `code-reviewer` agent on current changes.

1. Run `git diff --name-only` to identify changed files
2. Dispatch `code-reviewer` agent with the file list
3. Agent runs full SOLID/DRY/KISS/defensive/docs audit
4. Output: P0-P3 findings with fix examples
5. Fix by priority. Tests must pass between each wave.
6. Re-audit until findings = 0.
