#!/usr/bin/env bash
# Kill any running watchdog instance. Releases lock if $WORKSPACE is set.
DEST="${CCBRIDGE_DIR:-$HOME/.cache/ccbridge}"
PIDS=$(pgrep -f "$DEST/watchdog.sh" || true)
if [ -z "$PIDS" ]; then
  echo "[ccbridge] no watchdog running"
else
  for p in $PIDS; do
    kill "$p" 2>/dev/null && echo "[ccbridge] killed $p"
  done
fi
# v5.0.7 M2 — nudge_if_stuck.sh had no stopper at all; orphan nudge loops
# accumulated across sessions (each one polling the terminal every 30s and
# willing to press Esc). Sweep them here — SIGTERM now works because
# nudge_if_stuck.sh gained an INT/TERM trap in the same release.
NPIDS=$(pgrep -f "$DEST/nudge_if_stuck.sh" || true)
if [ -n "$NPIDS" ]; then
  for p in $NPIDS; do
    kill "$p" 2>/dev/null && echo "[ccbridge] killed nudge $p"
  done
fi
if [ -n "${WORKSPACE:-}" ] && [ -x "$DEST/lock.sh" ]; then
  "$DEST/lock.sh" release "$WORKSPACE" || true
fi
if [ -n "${WORKSPACE:-}" ] && [ -x "$DEST/state.sh" ]; then
  "$DEST/state.sh" "$WORKSPACE" watchdog_stopped >/dev/null 2>&1 || true
fi
