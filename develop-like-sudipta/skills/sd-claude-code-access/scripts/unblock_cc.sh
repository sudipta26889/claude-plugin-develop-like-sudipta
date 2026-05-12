#!/usr/bin/env bash
# unblock_cc.sh — detect+navigate CC permission prompts safely.
#
# Purpose (BUG-4 fix, v5.0.2):
# CC's "Do you want to proceed?" multi-option prompts default the cursor to the
# LAST option (often "3. No"). The v5.0 cc-orchestrator pressed return blindly
# and ended up rejecting safe actions, then aborted ("abort_safe"). Every
# subsequent orchestrator fire saw the same stuck prompt and bailed → CC
# silently blocked for tens of minutes with no manager intervention.
#
# This script encapsulates the detect-and-navigate contract:
#   1. DETECT — read the buffer; is CC actually paused at a permission prompt?
#   2. REFUSE — if the buffer matches a danger pattern, bail with exit 2.
#   3. PARSE  — find the cursor line (`❯ N. <text>`), extract option number N.
#   4. NAVIGATE — press `up` (N - TARGET) times, then `return`.
#   5. LOG    — emit manager_decision state event for the audit trail.
#
# Exit codes (consumed by cc-orchestrator):
#   0 — unblocked successfully (or DRYRUN simulated)
#   2 — refused (danger pattern matched)
#   3 — no prompt detected (CC isn't blocked; nothing to do)
#   4 — empty buffer (read.sh returned nothing)
#   5 — cursor line could not be parsed (defensive bail)
#   6 — target option is below current cursor (no down-press path yet)
#
# Env overrides:
#   CCBRIDGE_DIR        bridge install root (default: ~/.cache/ccbridge)
#   WORKSPACE           workspace path (enables state_event logging)
#   UNBLOCK_TARGET      target option number (default: 1 = "Yes")
#   UNBLOCK_DRYRUN      if =1, print decision but don't press keys

set -uo pipefail
DEST="${CCBRIDGE_DIR:-$HOME/.cache/ccbridge}"
DANGER="$DEST/danger_patterns.txt"
WS="${WORKSPACE:-}"
TARGET_OPTION="${UNBLOCK_TARGET:-1}"
DRYRUN="${UNBLOCK_DRYRUN:-0}"

# Use the script-local read.sh if running from test fixtures, otherwise the
# canonical bridge path. Both resolve to $DEST/read.sh — tests rebind DEST.
BUF=$(bash "$DEST/read.sh" 2>/dev/null | tail -80)
[ -n "$BUF" ] || { echo "[unblock] empty buffer"; exit 4; }

# Step 1 — detect blocked state. Match the prompt families CC uses for
# permission gates. The cursor glyph alone isn't enough (CC's idle input box
# also shows `❯`); we need the prompt question OR a numbered option list with
# `❯`.
if ! echo "$BUF" | grep -qE "Do you want to (proceed|make this edit|allow|continue|create|write|edit|delete|run)" \
   && ! echo "$BUF" | grep -qE "^[[:space:]]*❯[[:space:]]+[0-9]+\.[[:space:]]*(Yes|Continue|Allow|Proceed|No)"; then
  echo "[unblock] no prompt detected — CC not blocked"
  exit 3
fi

# Step 2 — refuse on danger. The watchdog already does this on its own
# 4-second poll; we duplicate the check here so callers can use unblock_cc.sh
# directly without trusting that the watchdog ran first.
if [ -f "$DANGER" ]; then
  while IFS= read -r pat; do
    [ -z "$pat" ] && continue
    case "$pat" in \#*) continue ;; esac
    if echo "$BUF" | grep -qiE "$pat"; then
      echo "[unblock] REFUSING — danger pattern matched: $pat"
      if [ -n "$WS" ] && [ -x "$DEST/state.sh" ]; then
        "$DEST/state.sh" "$WS" manager_decision \
          "action=refused_unblock" \
          "reason=danger_pattern" \
          "pattern=$pat" >/dev/null 2>&1 || true
      fi
      exit 2
    fi
  done < "$DANGER"
fi

# Step 3 — parse cursor position. Find the line starting with whitespace,
# then `❯`, then an option number + period. Take the LAST such line (CC's
# scrollback may have older prompts; we want the current one).
CURSOR_LINE=$(echo "$BUF" | grep -E "^[[:space:]]*❯[[:space:]]+[0-9]+\." | tail -1)
if [ -z "$CURSOR_LINE" ]; then
  echo "[unblock] could not parse cursor line"
  exit 5
fi

CURSOR_OPT=$(echo "$CURSOR_LINE" | sed -E 's/^[[:space:]]*❯[[:space:]]+([0-9]+)\..*/\1/')
case "$CURSOR_OPT" in
  ''|*[!0-9]*) echo "[unblock] could not parse option number from: $CURSOR_LINE"; exit 5 ;;
esac

echo "[unblock] cursor on option $CURSOR_OPT; target option $TARGET_OPTION"

# Step 4 — compute navigation. Only handles up-navigation (target <= cursor).
# Down-navigation isn't needed for the "default safe = option 1" doctrine.
STEPS=$((CURSOR_OPT - TARGET_OPTION))
if [ "$STEPS" -lt 0 ]; then
  echo "[unblock] target $TARGET_OPTION below cursor $CURSOR_OPT — refusing (down-nav not implemented)"
  exit 6
fi

if [ "$DRYRUN" = "1" ]; then
  echo "[unblock-dryrun] WOULD press up x$STEPS then return"
  exit 0
fi

# Step 5 — execute navigation
i=0
while [ "$i" -lt "$STEPS" ]; do
  bash "$DEST/keys.sh" up
  sleep 0.3
  i=$((i + 1))
done
# Small settle delay before return so CC's tab UI registers the final cursor
# position before we commit.
sleep 0.2
bash "$DEST/keys.sh" return

# Step 6 — log for audit + autoresearch
if [ -n "$WS" ] && [ -x "$DEST/state.sh" ]; then
  "$DEST/state.sh" "$WS" manager_decision \
    "action=unblock" \
    "method=up_x${STEPS}_return" \
    "cursor_was=$CURSOR_OPT" \
    "target=$TARGET_OPTION" >/dev/null 2>&1 || true
fi
if [ -n "$WS" ] && [ -x "$DEST/learning.sh" ]; then
  "$DEST/learning.sh" "$WS" permission_pattern \
    "outcome=unblocked" \
    "cursor_was=$CURSOR_OPT" \
    "target=$TARGET_OPTION" >/dev/null 2>&1 || true
fi

echo "[unblock] sent up x$STEPS, return — cursor moved to option $TARGET_OPTION"
exit 0
