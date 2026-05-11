---
description: Resume a paused or crashed autoresearch run from the last accepted experiment
argument-hint: <target-skill-name>
---

Pick up an interrupted run.

## Procedure
1. Verify `<plugin>/skills/<$1>/autoresearch/` has wiring.
2. Read .baselines.json — find last accepted entry → that's the baseline.
3. Check for `.lock` — if stale (dead PID), remove it; if live, abort and tell user.
4. Read program.md — refresh the goal/constraints in your head.
5. Read .proposed.* files (if any) — these are in-flight experiments that didn't complete; resolve them (commit if score is recorded, discard if not).
6. Invoke `/autoresearch <$1>` with remaining budget. Pass `--budget <REMAINING>` based on how many experiments are left from the original target (or default if unknown).
7. Report the resume decision before sending the first new experiment trigger.

## Don't
- Don't replay rejected experiments
- Don't lose .baselines.json — it's the history
- Don't resume if program.md has been edited since the run started (the goal changed; treat as new run)
