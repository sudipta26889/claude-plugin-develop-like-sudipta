---
description: >
  Run a full red-team security audit on the codebase using the code-hacker skill.
  23 attack categories, CWE/CVSS mapping, exploit chains, PoC validation.
  Use for comprehensive pen-testing — heavier than /secure.
---

# Hack Command — Full Red-Team Audit

This command delegates to the `code-hacker` skill for a comprehensive 23-category
security audit. This is the HEAVY option — use `/secure` for lightweight reviews.

## Procedure

1. **Verify code-hacker skill is available** — check `skills/code-hacker/SKILL.md` exists
   - Verify by checking file exists AND is readable: `test -r skills/code-hacker/SKILL.md`
   - If skill is missing or unreadable, output: "[HACK] ❌ code-hacker skill not found. Install the develop-like-sudipta plugin first."
2. **Load the code-hacker skill** — follow its execution protocol exactly
3. **Run all 6 phases:**
   - Phase 0: Setup & Reconnaissance (attack surface mapping)
   - Phase 1: Automated Scan (23 scripts in parallel)
   - Phase 2: Coverage Verification (identify gaps)
   - Phase 3: Agent Fallback (manual audit for every gap category)
   - Phase 4: Deep Semantic Analysis (business logic, second-order injection, exploit chains)
   - Phase 5: Language-Specific Deep Dive
4. **Generate breach report** with:
   - Executive summary
   - All 23 categories explicitly addressed
   - CWE/CVSS for every finding
   - Exploit chain narratives
   - Hacker's Verdict (7-dimension score)
   - Prioritized remediation roadmap

## When to Use /hack vs /secure

| | `/secure` | `/hack` |
|---|---|---|
| Scope | Changed files only | Entire codebase |
| Time | Seconds | Minutes to hours |
| Depth | OWASP Top 10 checklist | 23 attack categories + DAST |
| Output | Finding list | Full breach report |
| Cost | Low (1 agent) | High (23 scripts + agent fallbacks) |
| When | Every code change | Before release, after major changes |
