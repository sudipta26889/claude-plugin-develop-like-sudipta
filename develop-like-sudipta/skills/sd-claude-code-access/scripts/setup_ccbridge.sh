#!/usr/bin/env bash
# setup_ccbridge.sh — one-shot per-machine setup for the v4.3 closed loop.
#
# Why: after a plugin update on a new machine, two things have to happen
# before the runtime-learning loop starts capturing AND the scheduled tasks
# become discoverable to Cowork:
#
#   1. ~/.cache/ccbridge/ has the LATEST bridge scripts (delegated to install.sh
#      which is the canonical script-copy step) PLUS the v4.3 cache subdirs.
#   2. ~/Documents/Claude/Scheduled/ contains the two bundled SKILL folders
#      (ccbridge-aggregate-learnings, ccbridge-distill-and-propose).
#
# The actual SCHEDULED-TASK REGISTRATION (binding a folder to a cron) happens
# from inside Cowork via `mcp__scheduled-tasks__create_scheduled_task`. That
# step is driven by the /ccbridge-init slash command, which calls THIS script
# first, then talks to its own MCP. Only Cowork can register Cowork tasks.
#
# Idempotent. Safe to re-run after every plugin update.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
ASSETS_DIR="$PLUGIN_ROOT/assets/scheduled-tasks"
SCHEDULED_DIR="$HOME/Documents/Claude/Scheduled"

echo "[setup-ccbridge] plugin root: $PLUGIN_ROOT"

# Step 1 — install bridge scripts (canonical step; also creates cache subdirs).
if [ -x "$SCRIPT_DIR/install.sh" ]; then
  echo "[setup-ccbridge] running install.sh ..."
  "$SCRIPT_DIR/install.sh" | sed 's/^/[install] /'
else
  echo "[setup-ccbridge] ERROR: install.sh missing at $SCRIPT_DIR/install.sh" >&2
  exit 1
fi

# Step 2 — copy bundled scheduled-task SKILLs into Cowork's scan dir.
mkdir -p "$SCHEDULED_DIR"
if [ ! -d "$ASSETS_DIR" ]; then
  echo "[setup-ccbridge] WARN: no bundled scheduled-task assets at $ASSETS_DIR"
else
  for d in "$ASSETS_DIR"/*/; do
    [ -d "$d" ] || continue
    task=$(basename "$d")
    dest="$SCHEDULED_DIR/$task"
    mkdir -p "$dest"
    # Always overwrite — latest plugin is source of truth.
    cp -f "$d/SKILL.md" "$dest/SKILL.md"
    echo "[setup-ccbridge] scheduled-task SKILL installed: $task"
  done
fi

echo
echo "[setup-ccbridge] done."
echo "Next: run /ccbridge-init in Cowork to bind scheduled tasks to cron."
