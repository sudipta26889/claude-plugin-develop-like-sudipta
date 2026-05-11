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

# v4.5.1 — pick verification fragment from ASCII-only runs.
# Why: pbcopy ⇄ osascript paste ⇄ Terminal scrollback can re-encode some
# Unicode (em-dashes U+2014, smart quotes U+2018-201F, ellipsis U+2026, any
# char above U+007E). Literal byte-level grep then false-negatives even
# though the paste landed correctly. The fix is to pick the verification
# fragment from a printable-ASCII-only stretch (chars in [!-~ ]).
#
# Algorithm: extract all maximal ASCII-printable runs of ≥15 chars, take
# the longest one, slice up to 30 chars from its middle. Fall back to the
# old "middle 30 of first 80" if no ASCII-only run of usable length exists.
FRAG=$(printf '%s' "$MSG" \
  | LC_ALL=C grep -oE '[!-~ ]{15,200}' 2>/dev/null \
  | awk '{ print length, $0 }' \
  | sort -rn \
  | head -1 \
  | cut -d' ' -f2- \
  | awk '{
      n = length($0)
      if (n <= 30) print $0
      else print substr($0, int((n-30)/2) + 1, 30)
    }' \
  | head -c 30)
if [ -z "$FRAG" ]; then
  # Fallback: legacy slice. Rarely reached — only if message is purely non-ASCII.
  FRAG="$(printf '%s' "$MSG" | head -c 80 | tail -c 30)"
fi
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
