#!/usr/bin/env bash
# Detect a hung CC (buffer hash unchanged for STUCK_SECONDS) and Esc-interrupt.
# Confirmation: requires the same fingerprint across 3 consecutive checks before pressing Esc,
# so a genuinely-slow Docker build doesn't trigger a false interrupt.
# Logs nudge events to state.json if $WORKSPACE is set.
# Usage: nudge_if_stuck.sh [STUCK_SECONDS=600] [POLL_SECONDS=30]
set -euo pipefail
DEST="${CCBRIDGE_DIR:-$HOME/.cache/ccbridge}"
STUCK_SECONDS="${1:-600}"
POLL_SECONDS="${2:-30}"
LOG="$DEST/nudge.log"
prev=""
prev_at=0
confirms=0
echo "[$(date)] nudge_if_stuck started, stuck_after=${STUCK_SECONDS}s poll=${POLL_SECONDS}s" >>"$LOG"
while true; do
  buf=$("$DEST/read.sh" 2>/dev/null | tail -50)
  cur=$(echo "$buf" | shasum -a 256 | cut -c1-12)
  now=$(date +%s)
  if [ "$cur" = "$prev" ]; then
    elapsed=$((now - prev_at))
    if [ "$elapsed" -ge "$STUCK_SECONDS" ]; then
      confirms=$((confirms + 1))
      echo "[$(date)] hung for ${elapsed}s, confirms=$confirms/3" >>"$LOG"
      if [ "$confirms" -ge 3 ]; then
        echo "[$(date)] confirmed hang, pressing esc" >>"$LOG"
        "$DEST/keys.sh" esc >>"$LOG" 2>&1
        if [ -n "${WORKSPACE:-}" ] && [ -x "$DEST/state.sh" ]; then
          "$DEST/state.sh" "$WORKSPACE" nudge_sent "elapsed=${elapsed}s" >/dev/null 2>&1 || true
        fi
        sleep 5
        prev=""
        prev_at=$now
        confirms=0
      fi
    fi
  else
    prev="$cur"
    prev_at=$now
    confirms=0
  fi
  sleep "$POLL_SECONDS"
done
