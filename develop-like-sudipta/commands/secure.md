---
description: Run OWASP security review on current changes or specified endpoints.
---

# Secure Command

Invoke the `security-reviewer` agent on current changes.

1. Run `git diff --name-only` to identify changed files
2. Filter for files touching routes, auth, input handling, secrets
3. Dispatch `security-reviewer` agent
4. Agent runs full OWASP Top 10 checklist
5. Output: CRITICAL/HIGH/MEDIUM/INFO findings with fix examples
6. Load `references/security.md` for additional checks if needed

For full 23-category red-team audit, use `/hack` instead.
