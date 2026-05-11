---
description: At-a-glance health check of the v4.3+ closed-loop runtime-learning system on this machine — plugin version, bridge install state, watchdog status, scheduled tasks (with next-run times), recent learnings per category, distillation report, autoresearch baselines, and a one-word verdict.
allowed-tools:
  - mcp__Desktop_Commander__start_process
  - mcp__Desktop_Commander__read_file
  - mcp__scheduled-tasks__list_scheduled_tasks
---

# /ccbridge-status — one-screen health check

Output a compact ground-truth report of the closed loop on this Mac. No state mutations. Safe to run any time.

## Substrate

`mcp__Desktop_Commander__*` for the shell side. Cowork sandbox bash CANNOT read `~/.cache/ccbridge/`.

## Procedure

### Step 1 — run the backing script

```bash
PLUGIN_ROOT=~/Workspace/personal/claude-plugin-develop-like-sudipta/develop-like-sudipta
bash ~/.cache/ccbridge/ccbridge_status.sh "$PLUGIN_ROOT"
```

If `~/.cache/ccbridge/ccbridge_status.sh` is missing (pre-v4.5 install), tell the user to run `/ccbridge-init` then retry.

Pass the plugin path so it can read autoresearch baselines too. If the user's plugin lives elsewhere, adjust `$PLUGIN_ROOT` accordingly.

### Step 2 — merge in Cowork scheduled-task data

Call `mcp__scheduled-tasks__list_scheduled_tasks`. From the response, filter to tasks whose `taskId` starts with `ccbridge-` OR contains `autoresearch`. For each, render one line:

```
  - <taskId> (cron <expr>) — next: <YYYY-MM-DD HH:MM local>, last: <YYYY-MM-DD HH:MM | never>, enabled: <bool>
```

Insert this BLOCK as a new section titled `SCHEDULED TASKS` immediately after the `WATCHDOG` section in the script output.

### Step 3 — emit the final merged report

Print the assembled report verbatim. Do not add summary paragraphs. The shell script's `HEALTH` section already provides a one-word verdict — don't override it.

### Step 4 — when problems are detected

If the shell script exit code was non-zero (problems detected), surface the FIRST problem prominently. Suggest one of:

- `MISSING: <scripts>` → run `/ccbridge-init`
- `MISSING: $CCBRIDGE/` → run `/ccbridge-init`
- `watchdog: not running` AND a workspace is being driven → run `bash ~/.cache/ccbridge/start_watchdog.sh` from that workspace
- scheduled tasks missing → run `/ccbridge-init`

## When NOT to use

- This command is read-only. Do NOT use it to fix anything — just to diagnose. For actual fixes, route to `/ccbridge-init`.
- Don't use it as part of `/cc-drive`'s pre-flight; `diagnose.sh` already does a quicker substrate-only check there. `/ccbridge-status` is for the WHOLE closed loop, not just the driving setup.

## Output format example

```
================================================================
 ccbridge-status @ Sudipta-MBA-M4 @ 2026-05-11T20:50:00Z
================================================================

PLUGIN
  version: 4.5.0
  install: /Users/sudipta/Workspace/personal/claude-plugin-develop-like-sudipta/develop-like-sudipta

BRIDGE (~/.cache/ccbridge/)
  scripts: 22 / 22 present
  subdirs: learnings/ aggregated/ distillation/
  registered projects: 3

WATCHDOG
  status: running
  pid=42118 WORKSPACE=/Users/sudipta/Workspace/personal/prodevs.in

SCHEDULED TASKS
  - ccbridge-aggregate-learnings  (cron 15 2 * * *) — next: 2026-05-12 02:15, last: 2026-05-11 02:22, enabled: true
  - ccbridge-distill-and-propose  (cron 30 3 * * 0) — next: 2026-05-17 03:30, last: 2026-05-11 03:37, enabled: true
  - autoresearch-sd-cc-access     (Manual only)      — last: 2026-05-11 12:20, enabled: true

LEARNINGS (last 7 days, all projects)
  total: 42 events across 3 workspace(s)
    permission_pattern             18
    audit_finding                  12
    substrate_choice                6
    watchdog_recovery               4
    bug_reproduction                2

DISTILLATION
  latest: ~/.cache/ccbridge/distillation/last-7days.md
  cross-project signatures: 2
  recent decisions:
    2026-05-11T14:27:33Z CROSS_N=0 action=exit

AUTORESEARCH baselines
  sd-claude-code-access: 0.8421
  develop-like-sudipta: 47.9100
  code-hacker: 0.3100

HEALTH
  green — bridge is intact.
```
