#!/usr/bin/env bash
# Launch the watchdog in nohup background. Idempotent - refuses to start a 2nd one.
# If $WORKSPACE is set in env, exports it so the watchdog logs state events.
# If $WORKSPACE is set, also acquires the driver lock first.
set -euo pipefail
DEST="${CCBRIDGE_DIR:-$HOME/.cache/ccbridge}"

# Optional driver-lock acquire when workspace is set
if [ -n "${WORKSPACE:-}" ] && [ -x "$DEST/lock.sh" ]; then
  "$DEST/lock.sh" acquire "$WORKSPACE" || {
    echo "[ccbridge] cannot start: lock held by another driver" >&2
    exit 2
  }
fi

if pgrep -f "$DEST/watchdog.sh" >/dev/null; then
  echo "[ccbridge] watchdog already running (pid: $(pgrep -f "$DEST/watchdog.sh" | tr '\n' ' '))"
  exit 0
fi

# Pass WORKSPACE + dryrun toggle through to background process.
# Explicit forwarding (rather than relying on inherited env) makes the
# dryrun example in danger_pattern_governance.md unambiguous.
WORKSPACE="${WORKSPACE:-}" CCBRIDGE_DIR="$DEST" \
  WATCHDOG_DRYRUN="${WATCHDOG_DRYRUN:-}" \
  nohup "$DEST/watchdog.sh" >/dev/null 2>&1 &
disown
sleep 1
PID=$(pgrep -f "$DEST/watchdog.sh" | head -1)
echo "[ccbridge] watchdog started, pid=$PID"
echo "[ccbridge] tail log with: tail -f $DEST/watchdog.log"
if [ -n "${WORKSPACE:-}" ] && [ -x "$DEST/state.sh" ]; then
  "$DEST/state.sh" "$WORKSPACE" watchdog_started "pid=$PID" >/dev/null 2>&1 || true
fi
