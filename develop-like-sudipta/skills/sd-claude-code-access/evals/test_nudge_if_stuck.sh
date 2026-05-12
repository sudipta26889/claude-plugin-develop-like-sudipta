#!/usr/bin/env bash
# Smoke eval: nudge_if_stuck.sh detects a hung CC and presses Esc after
# 3 consecutive same-fingerprint polls past the STUCK_SECONDS threshold.
#
# The script polls the CC terminal via $DEST/read.sh, hashes the visible
# buffer, and compares to the previous hash. Same hash + elapsed >=
# STUCK_SECONDS increments a `confirms` counter; once confirms reaches 3
# it fires `keys.sh esc` to interrupt CC and emits a `nudge_sent` state
# event.
#
# Test mechanics — must run on macOS where `timeout` is not on PATH and
# nudge_if_stuck.sh has no SIGTERM trap (so we use SIGKILL):
#   - mktemp DEST. Copy the real nudge_if_stuck.sh into it.
#   - Mock read.sh to return constant content → every poll produces the
#     same hash → STUCK condition.
#   - Mock keys.sh + state.sh to record invocations to log files.
#   - Set STUCK_SECONDS=1 + POLL_SECONDS=1 so the eval finishes in ~6s
#     instead of the default 10 minutes.
#   - Run, sleep enough for 3 confirms (4 poll cycles), SIGKILL, assert.
set -uo pipefail

SCRIPTS_DIR="$(cd "$(dirname "$0")/../scripts" && pwd)"
SCRIPT="$SCRIPTS_DIR/nudge_if_stuck.sh"
[ -x "$SCRIPT" ] || { echo "FAIL: $SCRIPT not executable"; exit 1; }

DEST=$(mktemp -d)
WS=$(mktemp -d)
KEY_LOG=$(mktemp)
STATE_LOG=$(mktemp)
NUDGE_PID=""
trap '{ kill -KILL ${NUDGE_PID:-0} 2>/dev/null; pkill -KILL -P "${NUDGE_PID:-0}" 2>/dev/null; rm -rf "$DEST" "$WS" "$KEY_LOG" "$STATE_LOG"; } 2>/dev/null; true' EXIT

# Copy the script under test into the fake DEST so $DEST/read.sh + keys.sh
# resolve against the mocks below.
cp "$SCRIPT" "$DEST/nudge_if_stuck.sh"
mkdir -p "$WS/.cc"

# Mock read.sh — constant buffer → constant hash → STUCK is the only
# possible classification.
cat > "$DEST/read.sh" <<'MOCK'
#!/usr/bin/env bash
printf 'stuck buffer\nline 2\nline 3\n'
MOCK
chmod +x "$DEST/read.sh"

# Mock keys.sh — record every press to KEY_LOG so the eval can verify
# `keys.sh esc` was fired exactly once.
cat > "$DEST/keys.sh" <<MOCK
#!/usr/bin/env bash
echo "\$1" >> "$KEY_LOG"
MOCK
chmod +x "$DEST/keys.sh"

# Mock state.sh — record every event to STATE_LOG so we can verify a
# nudge_sent event fired with a non-empty elapsed= field.
cat > "$DEST/state.sh" <<MOCK
#!/usr/bin/env bash
echo "\$@" >> "$STATE_LOG"
MOCK
chmod +x "$DEST/state.sh"

# Disable job-control notices so SIGKILL doesn't print 'Killed: 9' to stderr.
set +m

# Launch with STUCK=1s, POLL=1s. Trace: ~4 poll cycles to reach confirms=3,
# then the script fires Esc on the 4th iteration and sleeps 5s before
# resuming — we kill it before the second cycle's nudge can fire.
CCBRIDGE_DIR="$DEST" WORKSPACE="$WS" \
  bash "$DEST/nudge_if_stuck.sh" 1 1 >/dev/null 2>&1 &
NUDGE_PID=$!
sleep 6
{ kill -KILL "$NUDGE_PID" 2>/dev/null; pkill -KILL -P "$NUDGE_PID" 2>/dev/null; wait "$NUDGE_PID" 2>/dev/null; } 2>/dev/null
true

# Assertion 1: nudge.log was created in DEST (the script writes there).
[ -f "$DEST/nudge.log" ] || { echo "FAIL: nudge.log not created in DEST"; exit 1; }
grep -q "nudge_if_stuck started" "$DEST/nudge.log" || {
  echo "FAIL: nudge.log missing the 'started' breadcrumb"
  exit 1
}

# Assertion 2: confirms counter reached 3 (the script logs each increment).
grep -q "confirms=3/3" "$DEST/nudge.log" || {
  echo "FAIL: confirms never reached 3/3 in 6s — STUCK/POLL timing broken?"
  echo "  --- nudge.log ---"
  sed 's/^/    /' "$DEST/nudge.log"
  exit 1
}

# Assertion 3: keys.sh esc was fired at least once.
if ! grep -qx 'esc' "$KEY_LOG"; then
  echo "FAIL: keys.sh esc was not fired despite 3 confirms"
  echo "  KEY_LOG contents:"
  sed 's/^/    /' "$KEY_LOG"
  exit 1
fi

# Assertion 4: nudge_sent state event fired with a non-empty elapsed.
grep -qE 'nudge_sent .*elapsed=[0-9]+s' "$STATE_LOG" || {
  echo "FAIL: nudge_sent state event missing or elapsed= empty"
  echo "  STATE_LOG contents:"
  sed 's/^/    /' "$STATE_LOG"
  exit 1
}

echo "PASS"
