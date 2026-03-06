---
description: Research packages before installing. Runs Package Selection Gate via dep-researcher agent.
---

# Research Deps Command

Invoke the `dep-researcher` agent before ANY package installation.

1. User specifies package name or category (e.g., "HTTP client for Python")
2. Dispatch `dep-researcher` agent
3. Agent runs 5-step Package Selection Gate:
   - STOP (don't install from memory)
   - SEARCH (web_search latest alternatives)
   - VERIFY (maintained? deprecated? superseded?)
   - COMPARE (check banned lists)
   - RECOMMEND (package + version + evidence)
4. Output: recommendation with evidence
5. Only after approval → install with pinned version
