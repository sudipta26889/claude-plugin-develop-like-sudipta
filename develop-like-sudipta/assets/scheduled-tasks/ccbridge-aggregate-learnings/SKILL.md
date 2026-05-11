---
name: ccbridge-aggregate-learnings
description: Nightly sweep — aggregate per-project learning tails into dated jsonl files for autoresearch consumption (subscription, no ANTHROPIC_API_KEY)
---

Sweep every registered project's `~/.cache/ccbridge/learnings/<id>.jsonl` tail and append new entries to `~/.cache/ccbridge/aggregated/<YYYY-MM-DD>.jsonl`. Idempotent — re-running on the same day is a no-op past the cursor.

## Substrate

Use `mcp__Desktop_Commander__*` for shell ops. Cowork's sandbox bash cannot reach `~/.cache/ccbridge/` reliably.

## Procedure

1. **Probe**: `bash -lc 'ls ~/.cache/ccbridge/ 2>/dev/null'`. If empty, exit cleanly.

2. **Confirm script is present**:
   ```bash
   ls -l ~/.cache/ccbridge/aggregate_learnings.sh
   ```
   If missing → plugin was installed pre-v4.3.3 or install.sh didn't complete. Tell user to run `/ccbridge-init`, then exit.

3. **Run aggregator** — canonical per-machine path, independent of plugin install location:
   ```bash
   bash ~/.cache/ccbridge/aggregate_learnings.sh
   ```

4. **Show counts**: one short paragraph — events aggregated, distinct ws_ids contributing.

5. **DO NOT distill**. Distillation is a separate weekly task.

## Don't

- Don't call the Anthropic API — no reasoning needed; this is mechanical.
- Don't modify the per-project tails — they are append-only.
- Don't touch the cursor file (`~/.cache/ccbridge/.aggregate_cursor`).
- Don't hardcode plugin-relative paths. The stable path is `~/.cache/ccbridge/aggregate_learnings.sh` regardless of where the plugin lives on this machine.
