#!/usr/bin/env bash
# Send a single named key (or printable char) to the front Terminal tab.
# Usage: keys.sh <key>    where <key> is one of: return | esc | tab | up | down | <printable>
# Respects $TERMINAL_APP env var (default "Terminal"; can be set to "iTerm2").
set -euo pipefail
KEY="${1:?usage: keys.sh <return|esc|tab|up|down|printable>}"
APP="${TERMINAL_APP:-Terminal}"
case "$KEY" in
  return) /usr/bin/osascript -e "tell application \"$APP\" to activate" \
                             -e 'delay 0.2' \
                             -e 'tell application "System Events" to key code 36' ;;
  esc)    /usr/bin/osascript -e "tell application \"$APP\" to activate" \
                             -e 'delay 0.2' \
                             -e 'tell application "System Events" to key code 53' ;;
  tab)    /usr/bin/osascript -e "tell application \"$APP\" to activate" \
                             -e 'delay 0.2' \
                             -e 'tell application "System Events" to key code 48' ;;
  up)     /usr/bin/osascript -e "tell application \"$APP\" to activate" \
                             -e 'delay 0.2' \
                             -e 'tell application "System Events" to key code 126' ;;
  down)   /usr/bin/osascript -e "tell application \"$APP\" to activate" \
                             -e 'delay 0.2' \
                             -e 'tell application "System Events" to key code 125' ;;
  *)      /usr/bin/osascript -e "tell application \"$APP\" to activate" \
                             -e 'delay 0.2' \
                             -e "tell application \"System Events\" to keystroke \"$KEY\"" ;;
esac
