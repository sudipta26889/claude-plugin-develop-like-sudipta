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
if [ -n "${WORKSPACE:-}" ] && [ -x "$DEST/lock.sh" ]; then
  "$DEST/lock.sh" release "$WORKSPACE" || true
fi
if [ -n "${WORKSPACE:-}" ] && [ -x "$DEST/state.sh" ]; then
  "$DEST/state.sh" "$WORKSPACE" watchdog_stopped >/dev/null 2>&1 || true
fi
