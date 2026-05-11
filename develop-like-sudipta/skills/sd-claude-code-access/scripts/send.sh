#!/usr/bin/env bash
# Reliable paste-to-Terminal-then-Enter with verification.
# Reads message from stdin. Clears any existing input via Cmd+A + Delete first
# (so it doesn't append to text the user already typed). Then pastes + Returns.
# After submit, polls Terminal scrollback for a unique fragment of the message
# to confirm it actually landed. Exits non-zero on verification failure.
# Respects $TERMINAL_APP env var.
# If $WORKSPACE is set, logs to <workspace>/.cc/state.json.
set -euo pipefail
APP="${TERMINAL_APP:-Terminal}"
DEST="${CCBRIDGE_DIR:-$HOME/.cache/ccbridge}"
MSG="$(cat)"
LEN=${#MSG}
FRAG="$(printf '%s' "$MSG" | head -c 80 | tail -c 30)"
printf '%s' "$MSG" | pbcopy
/usr/bin/osascript <<APPLESCRIPT >/dev/null
tell application "$APP" to activate
delay 0.5
tell application "System Events"
  keystroke "a" using {command down}
  delay 0.3
  key code 51
  delay 0.3
  keystroke "v" using {command down}
  delay 0.6
  key code 36
end tell
APPLESCRIPT
echo "[send] $LEN chars, frag='$FRAG'"

# Optional state event
if [ -n "${WORKSPACE:-}" ] && [ -x "$DEST/state.sh" ]; then
  "$DEST/state.sh" "$WORKSPACE" message_sent "len=$LEN" "frag=$FRAG" >/dev/null 2>&1 || true
fi

sleep 4
HIST=$("$DEST/read.sh" 2>/dev/null)
if echo "$HIST" | grep -qF "$FRAG"; then
  echo "[send] OK (visible buffer)"
  exit 0
fi
FULL=$("$DEST/read_history.sh" 2>/dev/null)
if echo "$FULL" | grep -qF "$FRAG"; then
  echo "[send] OK (scrollback)"
  exit 0
fi
echo "[send] FAIL: fragment '$FRAG' not found in buffer or scrollback"
if [ -n "${WORKSPACE:-}" ] && [ -x "$DEST/state.sh" ]; then
  "$DEST/state.sh" "$WORKSPACE" message_send_failed "frag=$FRAG" >/dev/null 2>&1 || true
fi
exit 2
