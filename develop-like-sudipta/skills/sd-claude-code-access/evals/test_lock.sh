#!/usr/bin/env bash
# Smoke eval: lock.sh status / acquire / stale-recovery / held-by-live.
#
# lock.sh is the driver-session semaphore. The contracts this smoke pins:
#
#   status (no lock)              → exits 0, prints `[lock] free`
#   acquire (no lock)             → exits 0, creates the lock file
#   status (after acquire)        → exits 0, prints `[lock] holder:` line
#   acquire (DEAD-pid same host)  → STALE branch — silently steals + exits 0
#   acquire (LIVE-pid same host)  → exits 2, prints `[lock] HELD by:`
#
# Note on release: lock.sh's release path checks `$OWNER_PID = $$ || $PPID`
# where OWNER_PID was lock.sh-acquire's own $$ (now dead). In normal shell
# usage no caller's $$ or $PPID will ever match that dead pid, so release
# routinely exits 3 with "not ours". stop_watchdog.sh accepts the failure
# via `|| true` and relies on the next acquire's stale-recovery to clear
# the dead lock. The smoke doesn't bake the quirky behavior into an
# assertion; if the release design changes, this comment is the marker.
set -uo pipefail

SCRIPT="$(dirname "$0")/../scripts/lock.sh"
[ -x "$SCRIPT" ] || { echo "FAIL: $SCRIPT not executable"; exit 1; }

WS=$(mktemp -d)
trap 'rm -rf "$WS"' EXIT
LOCK_FILE="$WS/.cc/.driver.lock"

# 1. status (free)
out=$("$SCRIPT" status "$WS")
case "$out" in
  '[lock] free') ;;
  *) echo "FAIL (status free): expected '[lock] free', got: $out"; exit 1 ;;
esac
[ -f "$LOCK_FILE" ] && { echo "FAIL: status created a lock file"; exit 1; }

# 2. acquire on free workspace
"$SCRIPT" acquire "$WS" >/dev/null
[ -f "$LOCK_FILE" ] || { echo "FAIL (acquire): lock file not created"; exit 1; }

# 3. status after acquire — holder line
out=$("$SCRIPT" status "$WS")
case "$out" in
  '[lock] holder:'*) ;;
  *) echo "FAIL (status after acquire): expected '[lock] holder: …', got: $out"; exit 1 ;;
esac

# 4. Stale-lock recovery: simulate a same-host lock from a definitely-dead
#    pid. lock.sh's acquire checks `kill -0 $OWNER_PID`; on dead pid it
#    enters the STALE branch, silently steals the lock, exits 0. This is
#    the workhorse path for cleanup across crashed / killed drivers.
DEAD_PID=2147483646
echo "$(hostname):$DEAD_PID:$(date -u +%s)" > "$LOCK_FILE"
rc=0; out=$("$SCRIPT" acquire "$WS" 2>&1) || rc=$?
[ "$rc" -eq 0 ] || { echo "FAIL (stale recovery): expected exit 0, got $rc: $out"; exit 1; }
case "$out" in
  *'stale lock'*) ;;
  *) echo "FAIL (stale recovery): expected 'stale lock' message, got: $out"; exit 1 ;;
esac
grep -q ":$DEAD_PID:" "$LOCK_FILE" && { echo "FAIL: stale recovery didn't rewrite the lock"; exit 1; }

# 5. Held by live driver — write a lock with this test script's own pid
#    (guaranteed alive while the test runs). acquire must refuse with
#    exit 2 and the HELD message. This is the multi-driver-collision
#    case the semaphore exists to handle.
echo "$(hostname):$$:$(date -u +%s)" > "$LOCK_FILE"
rc=0; out=$("$SCRIPT" acquire "$WS" 2>&1) || rc=$?
[ "$rc" -eq 2 ] || { echo "FAIL (held by live): expected exit 2, got $rc: $out"; exit 1; }
case "$out" in
  *'HELD by:'*) ;;
  *) echo "FAIL (held by live): expected 'HELD by:' message, got: $out"; exit 1 ;;
esac

echo "PASS"
