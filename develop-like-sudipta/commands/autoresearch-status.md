---
description: Show current autoresearch state — best scores per skill, latest experiments, drift from baseline
argument-hint: [target-skill-name]
---

Report autoresearch progress.

## Procedure
1. If `$1` is given, focus on that skill. Otherwise enumerate every skill with an `autoresearch/.baselines.json`.
2. For each skill:
   - Read `.baselines.json` (JSONL of `{ts, target_hash, score, accepted}`)
   - Report: total experiments, best score, latest score, % accepted, last activity timestamp
   - Surface any locks (`autoresearch/.lock`) — running, stale, or clean
3. Optionally print the top-3 best target hashes + their scores for the focused skill.

## Don't
- Don't modify any files — read-only.
