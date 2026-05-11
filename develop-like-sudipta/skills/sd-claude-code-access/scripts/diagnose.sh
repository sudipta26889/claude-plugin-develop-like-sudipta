#!/usr/bin/env bash
# diagnose.sh — health check for the bridge. Run when something feels off.
# Reports: terminal app + window/tab count, watchdog status, lock holder,
# danger-pattern count, last 10 state.json events, claude binary path.
set -euo pipefail
WS="${1:-}"
DEST="${CCBRIDGE_DIR:-$HOME/.cache/ccbridge}"
TERM_APP="${TERMINAL_APP:-Terminal}"

echo "=== CCBRIDGE DIAGNOSTIC ==="
echo
echo "Date: $(date)"
echo "Host: $(uname -n)"
echo "User: $(whoami)"
echo
echo "--- Bridge install ---"
echo "DEST: $DEST"
if [ -d "$DEST" ]; then
  echo "Installed scripts:"
  ls "$DEST" | sed 's/^/  /'
else
  echo "  NOT INSTALLED — run install.sh"
fi
echo
echo "--- Terminal app ---"
echo "TERMINAL_APP env: $TERM_APP"
if osascript -e "tell application \"$TERM_APP\" to return (count of windows)" >/dev/null 2>&1; then
  # v4.5.1 — wrap each osascript in `|| echo "?"` so a single permission
  # denial or transient AppleScript failure can't propagate out of $(...)
  # and abort the script under set -euo pipefail. The if-guard above ONLY
  # protects entry into the block; the inner calls each need their own
  # fallback. Without this, diagnose.sh died silently mid-run on the M1 Max.
  WIN=$(osascript -e "tell application \"$TERM_APP\" to return (count of windows)" 2>/dev/null || echo "?")
  TAB=$(osascript -e "tell application \"$TERM_APP\" to return (count of tabs of front window)" 2>/dev/null || echo "?")
  TITLE=$(osascript -e "tell application \"$TERM_APP\" to return name of selected tab of front window" 2>/dev/null || echo "<no-front-tab>")
  echo "  windows: $WIN, tabs in front window: $TAB"
  echo "  selected tab title: $TITLE"
  if [ "$WIN" != "1" ] || [ "$TAB" != "1" ]; then
    echo "  ⚠ Multiple windows/tabs detected — keystroke routing may be wrong."
  fi
else
  echo "  ⚠ $TERM_APP not running or AppleScript permission denied"
fi
echo
echo "--- Watchdog ---"
if pgrep -f "$DEST/watchdog.sh" >/dev/null; then
  PIDS=$(pgrep -f "$DEST/watchdog.sh" | tr '\n' ' ')
  echo "  Running pid(s): $PIDS"
  if [ -f "$DEST/watchdog.log" ]; then
    echo "  Last 5 log lines:"
    tail -5 "$DEST/watchdog.log" | sed 's/^/    /'
  fi
else
  echo "  Not running. Start with: bash $DEST/start_watchdog.sh"
fi
echo
echo "--- Danger patterns ---"
if [ -f "$DEST/danger_patterns.txt" ]; then
  N=$(grep -cv '^#\|^$' "$DEST/danger_patterns.txt" || echo 0)
  echo "  $N active patterns"
else
  echo "  ⚠ danger_patterns.txt missing — watchdog will auto-approve EVERYTHING"
fi
echo
echo "--- Claude CLI ---"
if command -v claude >/dev/null 2>&1; then
  echo "  $(which claude) — $(claude --version 2>/dev/null | head -1)"
else
  CC=~/.local/bin/claude
  if [ -x "$CC" ]; then
    echo "  $CC (not on PATH) — $($CC --version 2>/dev/null | head -1)"
  else
    echo "  ⚠ claude not found on PATH or ~/.local/bin"
  fi
fi
echo
if [ -n "$WS" ]; then
  echo "--- Workspace ($WS) ---"
  if [ -d "$WS/.cc" ]; then
    echo "  .cc/ contents:"
    ls -la "$WS/.cc" | tail -n +2 | sed 's/^/    /'
    if [ -f "$WS/.cc/.driver.lock" ]; then
      echo "  Lock holder: $(cat "$WS/.cc/.driver.lock")"
    fi
    if [ -f "$WS/.cc/state.json" ]; then
      echo "  Last 10 state events:"
      tail -10 "$WS/.cc/state.json" | sed 's/^/    /'
    fi
  else
    echo "  No .cc/ directory yet."
  fi
  echo
  echo "  Recent commits:"
  cd "$WS" 2>/dev/null && git log --oneline -5 2>/dev/null | sed 's/^/    /'
  echo
fi
echo "=== END DIAGNOSTIC ==="
