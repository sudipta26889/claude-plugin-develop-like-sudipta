#!/usr/bin/env bash
# Print the FULL scrollback of the selected tab.
# Used for verifying paste landed — grep for a unique fragment.
# Respects $TERMINAL_APP. iTerm2 doesn't expose the equivalent property
# directly so we fall back to a larger contents read on iTerm.
APP="${TERMINAL_APP:-Terminal}"
case "$APP" in
  Terminal)
    /usr/bin/osascript -e "tell application \"$APP\" to return history of selected tab of front window"
    ;;
  iTerm2|iTerm)
    # iTerm2 has no full history accessor via AppleScript; contents is the best we have.
    /usr/bin/osascript -e "tell application \"$APP\" to tell current window to tell current session to return contents"
    ;;
  *)
    /usr/bin/osascript -e "tell application \"$APP\" to return history of selected tab of front window"
    ;;
esac
