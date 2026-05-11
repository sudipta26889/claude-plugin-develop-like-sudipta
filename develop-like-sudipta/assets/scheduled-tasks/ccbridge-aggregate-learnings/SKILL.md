---
name: ccbridge-aggregate-learnings
description: Nightly sweep — aggregate per-project learning tails into dated jsonl files for autoresearch consumption (subscription, no ANTHROPIC_API_KEY)
---

Sweep every registered project's `~/.cache/ccbridge/learnings/<id>.jsonl` tail and append new entries to `~/.cache/ccbridge/aggregated/<YYYY-MM-DD>.jsonl`. Idempotent — re-running on the same day is a no-op past the cursor.

## Substrate

Use `mcp__Desktop_Commander__*` for shell ops. Cowork's sandbox bash cannot reach `~/.cache/ccbridge/` reliably.

## Procedure

1. **Probe**: `bash -lc 'ls ~/.cache/ccbridge/ 2>/dev/null'`. If empty, exit cleanly.

2. **Run aggregator**:
   ```bash
   bash /Users/sudipta/Workspace/personal/claude-plugin-develop-like-sudipta/develop-like-sudipta/skills/autoresearch/scripts/aggregate_learnings.sh
   ```

3. **Show counts**: one short paragraph — events aggregated, distinct ws_ids contributing.

4. **DO NOT distill**. Distillation is a separate weekly task.

## Don't

- Don't call the Anthropic API — no reasoning needed; this is mechanical.
- Don't modify the per-project tails — they are append-only.
- Don't touch the cursor file (`~/.cache/ccbridge/.aggregate_cursor`).
