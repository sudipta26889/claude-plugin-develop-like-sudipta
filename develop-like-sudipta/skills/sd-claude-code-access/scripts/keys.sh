#!/usr/bin/env bash
# Send a single named key (or printable char) to the target CC tab.
# Usage: keys.sh <key>    where <key> is one of: return | esc | tab | up | down | <printable>
# Respects $TERMINAL_APP env var (default "Terminal"; can be set to "iTerm2").
#
# v5.0.7 H3 — keystrokes via System Events always go to the FOCUSED window;
# there is no per-window keystroke API. So before typing, re-front the
# persisted target window ($CCBRIDGE_DIR/target_window_id, written by
# launch_cc.sh at spawn). With two Terminal windows open, bare `activate`
# focused whichever window was last used — keystrokes went to the wrong CC.
set -euo pipefail
KEY="${1:?usage: keys.sh <return|esc|tab|up|down|printable>}"
APP="${TERMINAL_APP:-Terminal}"
DEST="${CCBRIDGE_DIR:-$HOME/.cache/ccbridge}"

_focus_target() {
  local win_id=""
  [ -f "$DEST/target_window_id" ] && win_id=$(cat "$DEST/target_window_id" 2>/dev/null)
  case "$win_id" in *[!0-9]*|'') win_id="" ;; esac
  if [ -n "$win_id" ] && [ "$APP" = "Terminal" -o "$APP" = "Terminal.app" ]; then
    # Bring the recorded window to the front. `set index ... to 1` fails
    # silently if the window is gone; plain activate is the fallback either way.
    /usr/bin/osascript \
      -e "tell application \"Terminal\"" \
      -e "  try" \
      -e "    set index of window id $win_id to 1" \
      -e "  end try" \
      -e "  activate" \
      -e "end tell" 2>/dev/null || \
      /usr/bin/osascript -e "tell application \"$APP\" to activate"
  else
    /usr/bin/osascript -e "tell application \"$APP\" to activate"
  fi
}

_focus_target
case "$KEY" in
  return) /usr/bin/osascript -e 'delay 0.2' -e 'tell application "System Events" to key code 36' ;;
  esc)    /usr/bin/osascript -e 'delay 0.2' -e 'tell application "System Events" to key code 53' ;;
  tab)    /usr/bin/osascript -e 'delay 0.2' -e 'tell application "System Events" to key code 48' ;;
  up)     /usr/bin/osascript -e 'delay 0.2' -e 'tell application "System Events" to key code 126' ;;
  down)   /usr/bin/osascript -e 'delay 0.2' -e 'tell application "System Events" to key code 125' ;;
  *)      /usr/bin/osascript -e 'delay 0.2' -e "tell application \"System Events\" to keystroke \"$KEY\"" ;;
esac
