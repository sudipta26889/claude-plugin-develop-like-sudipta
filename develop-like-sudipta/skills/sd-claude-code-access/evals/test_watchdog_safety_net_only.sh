#!/usr/bin/env bash
# Eval: watchdog default mode is safety-net-only.
# When a non-danger prompt appears, watchdog must emit prompt_pending
# (NOT press Enter) when WATCHDOG_AUTO_APPROVE is unset or 0.
#
# Test mechanics — must run on macOS where `timeout` is not on PATH:
#   - Background the watchdog, sleep 5s, kill it. v5.0.1 watchdog handles
#     SIGTERM cleanly via the on_signal trap → SIGKILL is no longer needed,
#     but we keep it here as a belt-and-suspenders cleanup in case a future
#     regression re-introduces BUG-2. SIGTERM dedicated coverage lives in
#     test_watchdog_sigterm_exits.sh.
#   - CCBRIDGE_HOME pinned to the temp DEST so learning.sh / register_project.sh
#     don't pollute the user's real ~/.cache/ccbridge during the test run.
set -uo pipefail
DEST=$(mktemp -d)
KEY_LOG=$(mktemp)
WS=$(mktemp -d)
WD_PID=""
trap 'kill -KILL ${WD_PID:-0} 2>/dev/null; pkill -KILL -P "${WD_PID:-0}" 2>/dev/null; rm -rf "$DEST" "$KEY_LOG" "$WS"' EXIT

# Pretend to be the bridge dir
cp "$(dirname "$0")/../scripts/"{watchdog,read,keys,state,learning,register_project,escalate}.sh "$DEST/"
cp "$(dirname "$0")/../scripts/danger_patterns.txt" "$DEST/"
chmod +x "$DEST"/*.sh

# Mock read.sh to emit a known non-danger prompt
cat > "$DEST/read.sh" <<'MOCK'
#!/usr/bin/env bash
echo "Do you want to proceed with editing src/foo.py?"
echo "  1. Yes"
echo "  2. No"
MOCK
chmod +x "$DEST/read.sh"

# Mock keys.sh to record any presses
cat > "$DEST/keys.sh" <<MOCK
#!/usr/bin/env bash
echo "\$1" >> "$KEY_LOG"
MOCK
chmod +x "$DEST/keys.sh"

mkdir -p "$WS/.cc"
# Disable job-control notices so the SIGKILL we issue below doesn't print
# "Killed: 9" to stderr (visual noise; doesn't affect assertions).
set +m
CCBRIDGE_DIR="$DEST" CCBRIDGE_HOME="$DEST" WORKSPACE="$WS" \
  bash "$DEST/watchdog.sh" >/dev/null 2>&1 &
WD_PID=$!
sleep 5
{ kill -KILL "$WD_PID" 2>/dev/null; pkill -KILL -P "$WD_PID" 2>/dev/null; wait "$WD_PID" 2>/dev/null; } 2>/dev/null
true

# Default mode assertion: no keypress (KEY_LOG empty), state.json has prompt_pending event
if [ -s "$KEY_LOG" ]; then
  echo "FAIL: watchdog pressed a key without consent: $(tr '\n' ' ' < "$KEY_LOG")"
  exit 1
fi
if ! grep -q '"event":"prompt_pending"' "$WS/.cc/state.json" 2>/dev/null; then
  echo "FAIL: no prompt_pending event in state.json"
  [ -f "$WS/.cc/state.json" ] && { echo "  state.json contents:"; sed 's/^/    /' "$WS/.cc/state.json"; }
  exit 1
fi

echo "PASS"
