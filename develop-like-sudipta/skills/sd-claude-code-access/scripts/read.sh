#!/usr/bin/env bash
# Print the visible buffer of the selected tab of the front Terminal window.
# Respects $TERMINAL_APP (default "Terminal"; e.g. "iTerm2").
APP="${TERMINAL_APP:-Terminal}"
case "$APP" in
  Terminal)
    /usr/bin/osascript -e "tell application \"$APP\" to return contents of selected tab of front window"
    ;;
  iTerm2|iTerm)
    /usr/bin/osascript -e "tell application \"$APP\" to tell current window to tell current session to return contents"
    ;;
  *)
    /usr/bin/osascript -e "tell application \"$APP\" to return contents of selected tab of front window"
    ;;
esac
