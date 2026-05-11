#!/usr/bin/env bash
# Launch the watchdog in nohup background. Idempotent — refuses to start a 2nd one.
#
# WORKSPACE resolution (v4.3.2 — three-layer defense):
#   1. If $WORKSPACE is set in env → use it (back-compat; explicit caller wins).
#   2. Else auto-detect from a running `claude` process's cwd via `lsof -d cwd`.
#      Robust on macOS — lsof always knows a live process's cwd.
#   3. Else FAIL-FAST with a loud message. Silent learning-loss is worse than
#      no watchdog: a watchdog without WORKSPACE pretends to work but drops
#      every state.sh / learning.sh event because of the guard inside
#      watchdog.sh. v4.3.1 and earlier hit this foot-gun silently.
#
# When WORKSPACE is known (env or auto-detected):
#   - Acquire driver lock
#   - Pre-register the workspace in ~/.cache/ccbridge/projects.json (so v4.3
#     learning aggregation sees it from second zero, not lazily on first event)
#   - Export WORKSPACE to the watchdog process

set -euo pipefail
DEST="${CCBRIDGE_DIR:-$HOME/.cache/ccbridge}"

# Layer 1 — honor explicit env (back-compat).
if [ -z "${WORKSPACE:-}" ]; then
  # Layer 2 — auto-detect from a running Claude-Code-in-Terminal process.
  #
  # We want to find a `claude` CLI binary running in a terminal session — NOT
  # the Cowork-embedded CC instances under /Applications/Claude.app/Contents/.
  # Filter rules:
  #   1. command line starts with a `claude` binary path
  #   2. path does NOT contain "Claude.app/Contents/" (those are Cowork-internal)
  #   3. command line does NOT contain "--output-format stream-json" (also Cowork-internal)
  # If multiple terminal-mode CC processes match, head -1 picks the oldest —
  # typically the one the user actually launched in their Terminal tab.
  # ps -axo emits PID + full command. Use awk on $2 (the executable path,
  # i.e. argv[0]) — NOT anywhere in the command line. This avoids matching
  # bash processes that happen to be running a script whose path contains
  # the word "claude". Filters:
  #   - $2 ends in /claude  → it's a Claude binary invocation
  #   - $2 does NOT contain Claude.app/  → exclude Cowork-embedded CC
  # Pick the LAST match (most recently started — typically the user's tab),
  # not the first (which on macOS tends to be the longest-running instance).
  CC_PID=$(ps -axo pid=,command= 2>/dev/null \
    | awk '$2 ~ /\/claude$/ && $2 !~ /Claude\.app\// {pid=$1} END{print pid}')
  if [ -n "${CC_PID:-}" ]; then
    # macOS lsof: line 2 of `-d cwd` output's last column is the cwd path.
    # Wrap in `|| true` because lsof can exit non-zero on transient race with
    # the target process; we treat that as "no detection" and fall to layer 3.
    CC_CWD=$(lsof -a -p "$CC_PID" -d cwd 2>/dev/null | awk 'NR==2 {print $NF}' || true)
    if [ -n "${CC_CWD:-}" ] && [ -d "$CC_CWD" ]; then
      WORKSPACE="$CC_CWD"
      echo "[ccbridge] WORKSPACE auto-detected: $WORKSPACE (from claude pid $CC_PID)"
    fi
  fi
fi

# Layer 3 — fail-fast. No silent learning-loss.
if [ -z "${WORKSPACE:-}" ]; then
  cat >&2 <<EOF
[ccbridge] ERROR: WORKSPACE not set and no running 'claude' process found.

  The watchdog needs to know WHICH workspace it's driving so it can:
    - Acquire the per-workspace driver lock
    - Emit state events for resume-after-crash
    - Emit v4.3 learning events for cross-project autoresearch

  Fix one of:
    1. Start Claude Code FIRST, then re-run start_watchdog.sh. Auto-detect
       will pick up its cwd via lsof.
    2. Pass WORKSPACE explicitly:
         WORKSPACE=/path/to/your/project bash $0
    3. (Not recommended) export WORKSPACE=__bare__ to opt into the legacy
       silent-no-state behavior. This will be removed in v5.

  See: develop-like-sudipta/skills/sd-claude-code-access/SKILL.md
       (Step 5 — Acquire driver lock + start watchdog)
EOF
  exit 1
fi

# Sanity: workspace must be a directory we can write into.
if [ ! -d "$WORKSPACE" ]; then
  echo "[ccbridge] ERROR: WORKSPACE=$WORKSPACE is not a directory" >&2
  exit 1
fi

# Driver-lock acquire — fails if another Cowork session owns this workspace.
if [ -x "$DEST/lock.sh" ]; then
  "$DEST/lock.sh" acquire "$WORKSPACE" || {
    echo "[ccbridge] cannot start: lock held by another driver" >&2
    exit 2
  }
fi

# v4.3.2 — eagerly register the workspace so the aggregator/distiller see it
# immediately, before any actual learning event fires. Idempotent.
if [ -x "$DEST/register_project.sh" ]; then
  WS_ID=$("$DEST/register_project.sh" "$WORKSPACE" 2>/dev/null || echo "")
  if [ -n "$WS_ID" ]; then
    echo "[ccbridge] workspace registered: id=$WS_ID"
  fi
fi

if pgrep -f "$DEST/watchdog.sh" >/dev/null; then
  echo "[ccbridge] watchdog already running (pid: $(pgrep -f "$DEST/watchdog.sh" | tr '\n' ' '))"
  exit 0
fi

# Pass WORKSPACE + dryrun toggle + escalation hook through to background
# process. Explicit forwarding (rather than relying on inherited env) makes
# the dryrun example in danger_pattern_governance.md and the
# ESCALATE_CMD example in failure_modes.md unambiguous.
WORKSPACE="$WORKSPACE" CCBRIDGE_DIR="$DEST" \
  WATCHDOG_DRYRUN="${WATCHDOG_DRYRUN:-}" \
  ESCALATE_CMD="${ESCALATE_CMD:-}" \
  nohup "$DEST/watchdog.sh" >/dev/null 2>&1 &
disown
sleep 1
PID=$(pgrep -f "$DEST/watchdog.sh" | head -1)
echo "[ccbridge] watchdog started, pid=$PID"
echo "[ccbridge] WORKSPACE=$WORKSPACE"
echo "[ccbridge] tail log with: tail -f $DEST/watchdog.log"
if [ -x "$DEST/state.sh" ]; then
  "$DEST/state.sh" "$WORKSPACE" watchdog_started "pid=$PID" >/dev/null 2>&1 || true
fi
# v4.3.2 — emit the watchdog-start as a learning event too, so cross-project
# aggregation can spot how often watchdogs are spawned per project.
if [ -x "$DEST/learning.sh" ]; then
  "$DEST/learning.sh" "$WORKSPACE" watchdog_recovery \
    "outcome=started" "pid=$PID" "source=start_watchdog" >/dev/null 2>&1 || true
fi
