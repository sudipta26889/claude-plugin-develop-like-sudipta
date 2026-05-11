---
name: ccbridge-distill-and-propose
description: Weekly distillation — turn aggregated learnings into a candidate-mutations markdown report and (if signals are strong) trigger an autoresearch run with those priors (subscription, no ANTHROPIC_API_KEY)
---

Weekly: convert the last 7 days of aggregated learnings into a markdown distillation report. If the report contains at least one **cross-project signature** (same pattern in ≥2 workspaces), append it as priors to the next autoresearch trigger and invoke `autoresearch-sd-cc-access`.

## Substrate

`mcp__Desktop_Commander__*`. Subscription only — DO NOT call api.anthropic.com.

## Procedure

1. **Probe**: ensure `~/.cache/ccbridge/aggregated/` has files from the last 7 days.

2. **Distill**:
   ```bash
   bash /Users/sudipta/Workspace/personal/claude-plugin-develop-like-sudipta/develop-like-sudipta/skills/autoresearch/scripts/distill_learnings.sh --last-days 7
   ```
   Read its stdout AND the file it writes (`~/.cache/ccbridge/distillation/last-7days.md`).

3. **Scan for cross-project signals**: grep the report for rows where `cross-project? = **YES**`. Count them as `CROSS_N`.

4. **Decision**:
   - `CROSS_N == 0` → no priors strong enough; exit with a one-line summary ("no cross-project signal this week").
   - `CROSS_N >= 1` → produce a short priors file:
     ```bash
     PRIORS=~/.cache/ccbridge/distillation/priors-$(date -u +%Y%m%d).md
     ```
     Write the cross-project signatures (one per line, in the form `category: signature`) into PRIORS.

5. **Trigger autoresearch with priors**: invoke the `autoresearch-sd-cc-access` scheduled task and, in the proposal step, instruct Claude to:
   - Read `$PRIORS` before generating each mutation
   - Bias mutations toward addressing the highest-frequency cross-project signature
   - Skip mutation strategies that the priors have already validated (don't re-test what scored well)

6. **Log decision**: append one line to `~/.cache/ccbridge/distillation/.decisions.log`:
   ```
   <ts> CROSS_N=<n> action=<exit|triggered_autoresearch>
   ```

## When you have nothing to do

If `CROSS_N == 0` for 4 consecutive weeks, suggest in the user-facing summary that the user manually expand the trigger fixture with new adversarial queries — the loop has plateaued and needs new data.

## Don't

- Don't trigger autoresearch on single-project signals; that's overfitting one workspace's quirks into the plugin's global description.
- Don't write the priors directly into the plugin source — they live under `~/.cache/ccbridge/`. Promotion to plugin source is a deliberate user action, never automatic.
- Don't read `api.anthropic.com`. All reasoning is local Claude (subscription).
