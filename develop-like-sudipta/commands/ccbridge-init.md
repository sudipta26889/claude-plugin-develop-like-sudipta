---
description: One-shot self-bootstrap of the runtime-learning loop on this machine — installs bridge scripts, copies bundled scheduled-task SKILLs into Cowork's scan dir, and registers the three Cowork scheduled tasks (aggregate-learnings nightly + distill-and-propose Sunday + propose-fix-pr Monday). Idempotent. Run once per machine after `develop-like-sudipta` plugin update.
allowed-tools:
  - mcp__Desktop_Commander__start_process
  - mcp__Desktop_Commander__read_file
  - mcp__scheduled-tasks__list_scheduled_tasks
  - mcp__scheduled-tasks__create_scheduled_task
  - mcp__scheduled-tasks__update_scheduled_task
---

# /ccbridge-init — single command to wire the closed loop on this machine

Run this once per machine after pulling/updating the `develop-like-sudipta` plugin. It is fully idempotent — re-runs are safe and quick.

## What it does

1. Runs `setup_ccbridge.sh` (via Desktop_Commander shell):
   - Calls `install.sh` to copy the latest bridge scripts into `~/.cache/ccbridge/` (watchdog, audit, learning, register_project, ...).
   - Creates `~/.cache/ccbridge/{learnings,aggregated,distillation}/` subdirs.
   - Copies the two bundled scheduled-task SKILL folders from `assets/scheduled-tasks/` to `~/Documents/Claude/Scheduled/`.

2. Calls `mcp__scheduled-tasks__list_scheduled_tasks` to inspect Cowork's current task registry.

3. For each of the five required tasks (`ccbridge-aggregate-learnings`, `ccbridge-distill-and-propose`, `ccbridge-propose-fix-pr`, `cc-orchestrator`, `cc-coordinator-keepalive`):
   - If NOT present → call `mcp__scheduled-tasks__create_scheduled_task` to register it with the recommended cron.
   - If present → call `mcp__scheduled-tasks__update_scheduled_task` to refresh the prompt from the latest SKILL.md (so plugin updates flow into Cowork without manual edits).

4. Reports final state: which scripts were refreshed, which tasks are now registered, when they next run.

## Substrate

Use `mcp__Desktop_Commander__*` for the shell step. Cowork's sandbox bash cannot write to `~/.cache/` or `~/Documents/Claude/Scheduled/`.

## Procedure (do not improvise)

### Step 1 — Run the shell bootstrap

```bash
bash ~/Workspace/personal/claude-plugin-develop-like-sudipta/develop-like-sudipta/skills/sd-claude-code-access/scripts/setup_ccbridge.sh
```

`~` resolves to each machine's home dir, so this works portably as long as the plugin is cloned to `Workspace/personal/claude-plugin-develop-like-sudipta` under the user's home. On any machine where the plugin lives elsewhere, resolve via `${CLAUDE_PLUGIN_ROOT}` or query the plugin install dir manually.

Capture stdout. Confirm both `[install]` lines AND `scheduled-task SKILL installed: <name>` lines are present.

### Step 2 — Inventory Cowork scheduled tasks

Call `mcp__scheduled-tasks__list_scheduled_tasks`. Look for entries with `taskId` matching:

- `ccbridge-aggregate-learnings`
- `ccbridge-distill-and-propose`
- `ccbridge-propose-fix-pr`
- `cc-orchestrator`
- `cc-coordinator-keepalive`

### Step 3 — Read the bundled SKILL.md as the source of truth

For each required task, read the SKILL.md from `~/Documents/Claude/Scheduled/<taskId>/SKILL.md`. The **entire body** below the YAML frontmatter is the `prompt` argument for the MCP call. The frontmatter `description:` is the `description` argument.

### Step 4 — Register or refresh

**For `ccbridge-aggregate-learnings`:**

- Recommended cron: `15 2 * * *` (every day at 2:15 AM local).
- If absent → `mcp__scheduled-tasks__create_scheduled_task` with:
  - `taskId: "ccbridge-aggregate-learnings"`
  - `cronExpression: "15 2 * * *"`
  - `description: <from frontmatter>`
  - `prompt: <body below frontmatter>`
- If present → `mcp__scheduled-tasks__update_scheduled_task` with the same `taskId`, refreshed `prompt` and `description`. Leave `cronExpression` untouched if the user has already customized it (preserves human-set schedules).

**For `ccbridge-distill-and-propose`:**

- Recommended cron: `30 3 * * 0` (every Sunday at 3:30 AM local — runs after Saturday's last aggregate).
- Otherwise identical pattern to above.

**For `ccbridge-propose-fix-pr`:**

- Recommended cron: `0 9 * * 1` (every Monday at 09:00 local — runs after Sunday's distill, during waking hours so the maintainer sees draft PRs land in real time).
- Otherwise identical pattern to above.

**For `cc-orchestrator`:**

- Recommended cron: `* * * * *` (every minute — re-spawning fresh each tick is the v5.0 L2 model). The task's Step 1 early-exits when no `<workspace>/.cc/active-job.json` exists, so the per-minute cadence is quota-safe on idle machines.
- Otherwise identical pattern to above.

**For `cc-coordinator-keepalive`:**

- Recommended cron: `*/5 * * * *` (every five minutes — watchdog over the orchestrator). Detects stalls (orchestrator heartbeat > 7 min stale), escalates via Slack/email if `<ws>/.cc/active-job.json` has `notify_*` channels set, and self-disables both this task AND `cc-orchestrator` via `mcp__scheduled-tasks__update_scheduled_task enabled=false` once every active job has reached its `done_criteria`. Like `cc-orchestrator`, Step 1 early-exits on idle machines.
- Otherwise identical pattern to above.

### Step 5 — Report

Print a compact summary:

```
[ccbridge-init] machine: <hostname>
[ccbridge-init] bridge scripts: refreshed at ~/.cache/ccbridge/ (N files)
[ccbridge-init] scheduled tasks:
  - ccbridge-aggregate-learnings — registered (next run: 2026-MM-DD HH:MM)
  - ccbridge-distill-and-propose — registered (next run: 2026-MM-DD HH:MM)
  - ccbridge-propose-fix-pr      — registered (next run: 2026-MM-DD HH:MM)
  - cc-orchestrator              — registered (next run: 2026-MM-DD HH:MM, every minute)
  - cc-coordinator-keepalive     — registered (next run: 2026-MM-DD HH:MM, every 5 minutes)
[ccbridge-init] done. The closed loop is now live on this machine.
```

## Idempotency contract

Re-running `/ccbridge-init` on the same machine must NEVER:

- Create duplicate scheduled tasks (always check `list_scheduled_tasks` first)
- Overwrite a user-customized `cronExpression` (preserve it)
- Truncate `~/.cache/ccbridge/projects.json` (install.sh's bootstrap line uses `[ -f ] || echo ...`)
- Delete any per-workspace `<ws>/.cc/learnings.jsonl` content

The ONLY thing each re-run mutates is:

- Latest plugin scripts copied into `~/.cache/ccbridge/` (via `cp -f`)
- Latest plugin SKILL.md contents copied into `~/Documents/Claude/Scheduled/<taskId>/SKILL.md`
- Cowork scheduled-task PROMPT refreshed to match the new SKILL.md (description too)

## When NOT to use

- If `Desktop_Commander` MCP is not available → abort. Cowork sandbox bash cannot complete step 1.
- If the user is on a machine that already has the two scheduled tasks running and they are happy with the schedule → safe to skip; the runtime loop already works.

## After running

You're done. New workspaces auto-register on first use of any plugin command. Learnings flow into `~/.cache/ccbridge/learnings/<id>.jsonl` automatically. The nightly aggregator and weekly distiller now run themselves via Cowork.

To verify on the same machine 24h later:
- Check `~/.cache/ccbridge/aggregated/<today>.jsonl` exists with >0 lines.
- Check `mcp__scheduled-tasks__list_scheduled_tasks` shows non-empty `lastRunAt` for both.
