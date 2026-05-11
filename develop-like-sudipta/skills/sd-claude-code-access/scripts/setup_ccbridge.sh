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
# v4.3.4 — STEP 0: self-update. If the plugin lives in a git clone, run
# `git pull --ff-only --tags` first so we install the LATEST version, not
# whatever happens to be checked out. If THIS script was updated by the
# pull, re-exec ourselves so the new version runs. Skipped on dirty trees
# (refuses to touch uncommitted local work) and on .plugin-style installs
# (no .git/ at repo root).
#
# Flags:
#   --no-pull   skip the git pull step (also: SETUP_CCBRIDGE_NO_PULL=1)
#
# Idempotent. Safe to re-run after every plugin update.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
ASSETS_DIR="$PLUGIN_ROOT/assets/scheduled-tasks"
SCHEDULED_DIR="$HOME/Documents/Claude/Scheduled"
# Git repo root is one level above PLUGIN_ROOT (claude-plugin-develop-like-sudipta/
# contains develop-like-sudipta/, .git/ lives at the outer level when cloned).
REPO_ROOT="$(cd "$PLUGIN_ROOT/.." && pwd)"

NO_PULL="${SETUP_CCBRIDGE_NO_PULL:-0}"
for arg in "$@"; do
  case "$arg" in
    --no-pull) NO_PULL=1 ;;
    *) ;;
  esac
done

echo "[setup-ccbridge] plugin root: $PLUGIN_ROOT"
echo "[setup-ccbridge] repo root:   $REPO_ROOT"

# Step 0 — self-update via git pull.
if [ "$NO_PULL" = "1" ]; then
  echo "[setup-ccbridge] --no-pull set, skipping git pull"
elif [ ! -d "$REPO_ROOT/.git" ]; then
  echo "[setup-ccbridge] no .git/ at $REPO_ROOT — likely a .plugin install, not a git clone. Skipping pull."
else
  # Refuse to pull on dirty tree — protects uncommitted local work.
  if [ -n "$(git -C "$REPO_ROOT" status --porcelain 2>/dev/null)" ]; then
    echo "[setup-ccbridge] WARN: uncommitted changes in $REPO_ROOT — skipping git pull"
    echo "[setup-ccbridge]   commit or stash first, OR re-run with --no-pull to acknowledge"
  else
    # Capture this script's hash so we can detect if pull updated it.
    OLD_HASH=$(shasum -a 256 "${BASH_SOURCE[0]}" 2>/dev/null | awk '{print $1}')

    echo "[setup-ccbridge] git pull --ff-only --tags (in $REPO_ROOT)"
    if git -C "$REPO_ROOT" pull --ff-only --tags 2>&1 | sed 's/^/[git] /'; then
      NEW_HASH=$(shasum -a 256 "${BASH_SOURCE[0]}" 2>/dev/null | awk '{print $1}')
      if [ -n "$OLD_HASH" ] && [ "$OLD_HASH" != "$NEW_HASH" ]; then
        echo "[setup-ccbridge] setup_ccbridge.sh itself was updated by git pull — re-executing"
        # Avoid pull loop: pass --no-pull to the re-exec.
        exec bash "${BASH_SOURCE[0]}" --no-pull "$@"
      fi
    else
      echo "[setup-ccbridge] WARN: git pull failed — continuing with existing copy"
      echo "[setup-ccbridge]   common causes: detached HEAD, diverged branch, network down"
    fi
  fi
fi

# Step 1 — install bridge scripts (canonical step; also creates cache subdirs).
#
# v4.3.4 — DO NOT pipe install.sh directly through sed. Under `set -euo pipefail`
# a SIGPIPE inside install.sh's own pipeline (`diagnose.sh | head -25`) propagates
# upward, killing setup_ccbridge.sh BEFORE it reaches step 2 (the SKILL copy).
# The other Cowork's machine hit exactly this — script reported "done" with
# exit 0, the SKILL-copy lines never printed, and the user lost half the setup
# silently. Fix: capture install.sh output to a tmpfile, then sed-print it.
# Tmpfile is created with mktemp + trap-cleanup so it doesn't leak.
if [ -x "$SCRIPT_DIR/install.sh" ]; then
  echo "[setup-ccbridge] running install.sh ..."
  INSTALL_LOG=$(mktemp -t ccbridge_install.XXXXXX)
  trap 'rm -f "$INSTALL_LOG"' EXIT
  if "$SCRIPT_DIR/install.sh" > "$INSTALL_LOG" 2>&1; then
    sed 's/^/[install] /' "$INSTALL_LOG"
  else
    INSTALL_RC=$?
    sed 's/^/[install] /' "$INSTALL_LOG" >&2
    echo "[setup-ccbridge] ERROR: install.sh failed (exit $INSTALL_RC)" >&2
    exit "$INSTALL_RC"
  fi
else
  echo "[setup-ccbridge] ERROR: install.sh missing at $SCRIPT_DIR/install.sh" >&2
  exit 1
fi

# Step 2 — copy bundled scheduled-task SKILLs into Cowork's scan dir.
mkdir -p "$SCHEDULED_DIR"
if [ ! -d "$ASSETS_DIR" ]; then
  # v4.3.4 — loud failure mode. Pre-v4.3.1 installs lack the bundled assets
  # dir. Without it the scheduled tasks would silently fail at cron time.
  # Telling the user EXACTLY what to do is cheaper than letting them
  # debug a stale clone three weeks from now.
  cat >&2 <<EOF
[setup-ccbridge] ERROR: bundled scheduled-task assets not found at:
   $ASSETS_DIR

This plugin clone is older than v4.3.1 (when assets/scheduled-tasks/
was introduced). The scheduled tasks would silently fail at cron time
without the bundled SKILL.md files.

Fix:
  cd $REPO_ROOT && git pull --tags
  bash $SCRIPT_DIR/setup_ccbridge.sh

If --no-pull was passed: that's why the pull was skipped. Remove it
and re-run, or do the pull manually.
EOF
  exit 1
fi

for d in "$ASSETS_DIR"/*/; do
  [ -d "$d" ] || continue
  task=$(basename "$d")
  dest="$SCHEDULED_DIR/$task"
  mkdir -p "$dest"
  # Always overwrite — latest plugin is source of truth.
  cp -f "$d/SKILL.md" "$dest/SKILL.md"
  echo "[setup-ccbridge] scheduled-task SKILL installed: $task"
done

echo
echo "[setup-ccbridge] done."
echo "Next: run /ccbridge-init in Cowork to bind scheduled tasks to cron."
