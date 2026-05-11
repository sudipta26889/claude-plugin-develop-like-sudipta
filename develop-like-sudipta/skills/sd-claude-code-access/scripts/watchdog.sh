#!/usr/bin/env bash
# Auto-approve CC permission prompts UNLESS the prompt mentions a danger pattern.
# Polls the active Terminal tab every ~4s. On detecting a known prompt:
#   - If the visible buffer also matches any danger_patterns.txt regex,
#     log LOUDLY, refuse to press Enter, wait for human.
#   - Otherwise press Enter (default-highlighted = "Yes").
# Idempotent per fingerprint - won't re-press for the same on-screen prompt.
# If $WORKSPACE is set, also logs structured state events to <workspace>/.cc/state.json.
DEST="${CCBRIDGE_DIR:-$HOME/.cache/ccbridge}"
LOG="$DEST/watchdog.log"
DANGER="$DEST/danger_patterns.txt"
echo "[$(date)] watchdog started, pid=$$, danger=$DANGER, workspace=${WORKSPACE:-<unset>}" >>"$LOG"
last_seen=""
PROMPT_PATTERN='Do you want to (proceed|make this edit|allow|continue)'
while true; do
  buf=$("$DEST/read.sh" 2>/dev/null | tail -50)
  if echo "$buf" | grep -qE "$PROMPT_PATTERN" ; then
    fp=$(echo "$buf" | shasum -a 256 | cut -c1-12)
    if [ "$fp" != "$last_seen" ]; then
      blocked=""
      if [ -f "$DANGER" ]; then
        while IFS= read -r pat; do
          [ -z "$pat" ] && continue
          [[ "$pat" =~ ^[[:space:]]*# ]] && continue
          if echo "$buf" | grep -qiE "$pat" ; then
            blocked="$pat"
            break
          fi
        done < "$DANGER"
      fi
      if [ -n "$blocked" ]; then
        echo "[$(date)] DANGER fp=$fp matched=$blocked - REFUSING to auto-approve" >>"$LOG"
        echo "[$(date)] buffer head:" >>"$LOG"
        echo "$buf" | head -20 >>"$LOG"
        if [ -n "${WORKSPACE:-}" ] && [ -x "$DEST/state.sh" ]; then
          "$DEST/state.sh" "$WORKSPACE" danger_blocked "fp=$fp" "pattern=$blocked" >/dev/null 2>&1 || true
        fi
      else
        echo "[$(date)] prompt fp=$fp - pressing return" >>"$LOG"
        "$DEST/keys.sh" return >>"$LOG" 2>&1
        if [ -n "${WORKSPACE:-}" ] && [ -x "$DEST/state.sh" ]; then
          "$DEST/state.sh" "$WORKSPACE" prompt_approved "fp=$fp" >/dev/null 2>&1 || true
        fi
      fi
      last_seen="$fp"
      sleep 3
    fi
  fi
  sleep 4
done
