#!/usr/bin/env bash
# Print the visible buffer of the target CC tab.
# v5.0.7 H3 — if $CCBRIDGE_DIR/target_window_id exists (persisted by
# launch_cc.sh at spawn), read THAT window directly instead of the front
# window. Kills the front-window russian roulette when two Terminal windows
# are open (v4.6-H1 deliberately opens a second window for a second CC).
# Falls back to front window when the id file is absent or the window is
# gone (user closed it).
# Respects $TERMINAL_APP (default "Terminal"; e.g. "iTerm2").
APP="${TERMINAL_APP:-Terminal}"
DEST="${CCBRIDGE_DIR:-$HOME/.cache/ccbridge}"
WIN_ID=""
[ -f "$DEST/target_window_id" ] && WIN_ID=$(cat "$DEST/target_window_id" 2>/dev/null)
case "$WIN_ID" in *[!0-9]*|'') WIN_ID="" ;; esac

case "$APP" in
  Terminal|Terminal.app)
    if [ -n "$WIN_ID" ]; then
      OUT=$(/usr/bin/osascript -e "tell application \"Terminal\" to return contents of selected tab of window id $WIN_ID" 2>/dev/null)
      if [ -n "$OUT" ]; then
        printf '%s\n' "$OUT"
        exit 0
      fi
      # Window gone — fall through to front window.
    fi
    /usr/bin/osascript -e "tell application \"Terminal\" to return contents of selected tab of front window"
    ;;
  iTerm2|iTerm)
    /usr/bin/osascript -e "tell application \"$APP\" to tell current window to tell current session to return contents"
    ;;
  *)
    /usr/bin/osascript -e "tell application \"$APP\" to return contents of selected tab of front window"
    ;;
esac
