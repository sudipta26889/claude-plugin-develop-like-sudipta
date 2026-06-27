#!/usr/bin/env bash
# Detect a hung CC (buffer hash unchanged for STUCK_SECONDS) and Esc-interrupt.
# Confirmation: requires the same fingerprint across 3 consecutive checks before pressing Esc,
# so a genuinely-slow Docker build doesn't trigger a false interrupt.
#
# v5.0.5 FAILURE 10 — BEFORE pressing Esc on a confirmed hang, scan the last
# 20 lines of the buffer for any pattern in `$DEST/skip_nudge_patterns.txt`
# (one literal substring per line). If any matches, suppress the nudge,
# emit `nudge_skipped` state event, reset confirms. Rationale: docker pull
# / pip install / npm install legitimately stall the buffer for minutes;
# an Esc would kill the operation and corrupt CC's state. Per-project
# extras: `<workspace>/.cc/skip_nudge_patterns_extra.txt`.
#
# Logs nudge events to state.json if $WORKSPACE is set.
# Usage: nudge_if_stuck.sh [STUCK_SECONDS=600] [POLL_SECONDS=30]
set -euo pipefail
DEST="${CCBRIDGE_DIR:-$HOME/.cache/ccbridge}"
STUCK_SECONDS="${1:-600}"
POLL_SECONDS="${2:-30}"
LOG="$DEST/nudge.log"
SKIP_PATTERNS="$DEST/skip_nudge_patterns.txt"
SKIP_EXTRA=""
if [ -n "${WORKSPACE:-}" ]; then
  SKIP_EXTRA="$WORKSPACE/.cc/skip_nudge_patterns_extra.txt"
fi

_buffer_matches_skip_pattern() {
  # Return 0 if last 20 lines of $1 match any pattern in skip files; 1 otherwise.
  # Patterns are literal substrings (grep -F), one per line, # = comment.
  local buf="$1"
  local tail20; tail20=$(echo "$buf" | tail -20)
  local f
  for f in "$SKIP_PATTERNS" "$SKIP_EXTRA"; do
    [ -z "$f" ] && continue
    [ -f "$f" ] || continue
    while IFS= read -r pat; do
      [ -z "$pat" ] && continue
      case "$pat" in \#*) continue ;; esac
      if echo "$tail20" | grep -qF "$pat"; then
        echo "$pat"
        return 0
      fi
    done < "$f"
  done
  return 1
}

prev=""
prev_at=0
confirms=0
echo "[$(date)] nudge_if_stuck started, stuck_after=${STUCK_SECONDS}s poll=${POLL_SECONDS}s skip_patterns=$([ -f "$SKIP_PATTERNS" ] && echo present || echo missing)" >>"$LOG"
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
        # v5.0.5 FAILURE 10: check skip-patterns BEFORE pressing Esc.
        matched_pat=$(_buffer_matches_skip_pattern "$buf" || true)
        if [ -n "$matched_pat" ]; then
          echo "[$(date)] SKIPPING nudge — buffer matches skip pattern: $matched_pat" >>"$LOG"
          if [ -n "${WORKSPACE:-}" ] && [ -x "$DEST/state.sh" ]; then
            "$DEST/state.sh" "$WORKSPACE" nudge_skipped "elapsed=${elapsed}s" "pattern=$matched_pat" >/dev/null 2>&1 || true
          fi
          # Reset confirms but keep prev_at advancing — we don't reset
          # the timer to zero, because the long-I/O op may legitimately
          # take another full STUCK_SECONDS window. confirms=0 means we
          # need 3 more confirmations to even re-evaluate.
          confirms=0
          sleep "$POLL_SECONDS"
          continue
        fi
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
