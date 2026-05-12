#!/usr/bin/env bash
# BUG-2 regression — watchdog must exit cleanly on SIGTERM.
#
# Why this test exists: prior to v5.0.1, `trap cleanup EXIT INT TERM` removed
# the DENY_SRC tmpfile on signal, but did NOT exit the `while true` loop.
# Result: SIGTERM was effectively ignored; the only way to stop the watchdog
# was SIGKILL (which bypasses traps and prevents tmpfile cleanup). This made
# orderly shutdown impossible — wrappers (launch_cc, start_watchdog, test
# harnesses) all had to escalate to SIGKILL.
#
# Contract this test guards:
#   - Send SIGTERM to a running watchdog.
#   - Within 5 seconds, the process MUST have exited.
#   - If still alive after 5s → BUG-2 has regressed.
#
# Test mechanics: macOS lacks `timeout`. We background watchdog, sleep briefly
# to let it enter the poll loop, send SIGTERM, sleep 5s, then assert the PID
# is gone. We do NOT use SIGKILL anywhere — that would mask the bug.
set -uo pipefail
DEST=$(mktemp -d)
WS=$(mktemp -d)
WD_PID=""
# Cleanup uses SIGKILL ONLY as a last-resort safety net if the test fails;
# the assertion below proves SIGTERM alone was sufficient.
trap 'kill -KILL ${WD_PID:-0} 2>/dev/null; pkill -KILL -P "${WD_PID:-0}" 2>/dev/null; rm -rf "$DEST" "$WS"' EXIT

# Pretend to be the bridge dir
cp "$(dirname "$0")/../scripts/"{watchdog,read,keys,state,learning,register_project,escalate}.sh "$DEST/"
cp "$(dirname "$0")/../scripts/danger_patterns.txt" "$DEST/"
chmod +x "$DEST"/*.sh

# Mock read.sh — quiet (no prompts; we only care about loop termination)
cat > "$DEST/read.sh" <<'MOCK'
#!/usr/bin/env bash
echo "idle screen"
MOCK
chmod +x "$DEST/read.sh"

# Mock keys.sh — no-op
cat > "$DEST/keys.sh" <<'MOCK'
#!/usr/bin/env bash
exit 0
MOCK
chmod +x "$DEST/keys.sh"

mkdir -p "$WS/.cc"
set +m
CCBRIDGE_DIR="$DEST" CCBRIDGE_HOME="$DEST" WORKSPACE="$WS" \
  bash "$DEST/watchdog.sh" >/dev/null 2>&1 &
WD_PID=$!

# Give the loop one full poll cycle (4s sleep inside loop)
sleep 2

# Send SIGTERM ONLY. No SIGKILL fallback inside the assertion window.
kill -TERM "$WD_PID" 2>/dev/null

# Wait up to 5 seconds for clean exit.
for i in 1 2 3 4 5; do
  if ! kill -0 "$WD_PID" 2>/dev/null; then
    echo "PASS"
    exit 0
  fi
  sleep 1
done

# Still alive after 5s → BUG-2 has regressed.
echo "FAIL: watchdog did not exit within 5s of SIGTERM (BUG-2 regression)"
echo "  pid=$WD_PID still running:"
ps -p "$WD_PID" -o pid,ppid,stat,command 2>/dev/null | sed 's/^/    /'
exit 1
