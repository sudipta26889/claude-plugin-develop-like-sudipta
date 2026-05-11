#!/usr/bin/env bash
# Install the bridge scripts into ~/.cache/ccbridge/. Idempotent.
# Persistent across reboots (unlike /tmp). Run once per machine.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEST="${CCBRIDGE_DIR:-$HOME/.cache/ccbridge}"
mkdir -p "$DEST"

SCRIPTS=(
  send.sh read.sh read_history.sh keys.sh
  watchdog.sh start_watchdog.sh stop_watchdog.sh
  nudge_if_stuck.sh audit.sh
  state.sh state_salvage.sh lock.sh diagnose.sh run_summary.sh
  install_precommit.sh
  escalate.sh
)

for f in "${SCRIPTS[@]}"; do
  cp -f "$HERE/$f" "$DEST/$f"
  chmod +x "$DEST/$f"
done

# Copy the danger-pattern allow/deny list (consulted by watchdog).
cp -f "$HERE/danger_patterns.txt" "$DEST/danger_patterns.txt"

# Backwards-compat symlink so old docs still work.
if [ ! -L /tmp/ccbridge ] && [ ! -e /tmp/ccbridge ]; then
  ln -s "$DEST" /tmp/ccbridge
elif [ -L /tmp/ccbridge ]; then
  ln -snf "$DEST" /tmp/ccbridge
fi

echo "[ccbridge] installed to $DEST"
echo "[ccbridge] /tmp/ccbridge -> $DEST (compat symlink)"
echo
echo "Quick health check:"
"$DEST/diagnose.sh" 2>/dev/null | head -25
