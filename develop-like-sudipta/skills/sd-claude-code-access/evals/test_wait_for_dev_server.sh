#!/usr/bin/env bash
# test_wait_for_dev_server.sh — smoke test for wait_for_dev_server.sh.
#
# Background: browser-test directives need the dev server up before they
# can drive Chrome. wait_for_dev_server.sh handles three scenarios:
#
#   1. Already running     -> exit 0, "already-running"
#   2. Started successfully -> exit 0, "started-and-ready"
#   3. Not started / no cmd -> exit 2, "not-running-no-start-cmd"
#   4. Start command failed -> exit 1, "start-failed"
#   5. misconfiguration    -> exit 3
#
# Cases covered here:
#   1. Already running       (python http.server pre-launched on free port)
#   2. Started via package.json scripts.dev
#   3. Started via .cc/config.json dev_server_start_cmd (overrides pkg.json)
#   4. Times out             (start cmd is `sleep`, never opens a port)
#   5. No start command      (empty workspace)
#   6. Custom --health-path  (server only serves /health, root 404s)
#
# Bash 3.2 compatible. No `mapfile`, `wait -n`, associative arrays.
#
# Usage: ./test_wait_for_dev_server.sh
# Exit 0 on PASS, non-zero on any failed assertion.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WAIT="$SCRIPT_DIR/../scripts/wait_for_dev_server.sh"

if [ ! -f "$WAIT" ]; then
  echo "FAIL: wait_for_dev_server.sh not found at $WAIT"
  exit 2
fi

TMP_ROOT="${TMPDIR:-/tmp}"
fails=0
cleanup_dirs=""
cleanup_pids=""
cleanup_ports=""

fail() { fails=$((fails + 1)); echo "  FAIL: $*"; }
pass() { echo "  PASS: $*"; }

# Best-effort recursive process-tree kill (same logic as the SUT).
kill_tree() {
  local root="$1"
  [ -z "$root" ] && return 0
  local to_visit="$root"
  local all="$root"
  while [ -n "$to_visit" ]; do
    local next=""
    for p in $to_visit; do
      local kids
      kids="$(ps -A -o pid,ppid 2>/dev/null | awk -v pp="$p" '$2==pp{print $1}')"
      if [ -n "$kids" ]; then
        next="$next $kids"
        all="$all $kids"
      fi
    done
    to_visit="$next"
  done
  local rev=""
  for p in $all; do rev="$p $rev"; done
  for p in $rev; do kill "$p" 2>/dev/null || true; done
  sleep 1
  for p in $rev; do kill -9 "$p" 2>/dev/null || true; done
}

# Kill anything listening on a given TCP port. lsof is the most portable
# way to discover that on macOS.
kill_port() {
  local port="$1"
  [ -z "$port" ] && return 0
  command -v lsof >/dev/null 2>&1 || return 0
  local pids
  pids="$(lsof -ti tcp:"$port" 2>/dev/null || true)"
  for p in $pids; do
    kill "$p" 2>/dev/null || true
  done
  sleep 1
  pids="$(lsof -ti tcp:"$port" 2>/dev/null || true)"
  for p in $pids; do
    kill -9 "$p" 2>/dev/null || true
  done
}

cleanup() {
  # Recursive kill for any pids we tracked.
  for p in $cleanup_pids; do
    [ -n "$p" ] && kill_tree "$p"
  done
  # Walk pid files left by the SUT in test dirs.
  for d in $cleanup_dirs; do
    if [ -n "$d" ] && [ -f "$d/.cc/dev-server.pid" ]; then
      pid="$(cat "$d/.cc/dev-server.pid" 2>/dev/null || echo "")"
      [ -n "$pid" ] && kill_tree "$pid"
    fi
  done
  # Catch orphans that were re-parented to launchd: kill anything still
  # listening on a port a test bound to.
  for port in $cleanup_ports; do
    [ -n "$port" ] && kill_port "$port"
  done
  # Now remove the temp dirs.
  for d in $cleanup_dirs; do
    [ -n "$d" ] && [ -d "$d" ] && rm -rf "$d"
  done
}
trap cleanup EXIT INT TERM

mkws() {
  ws="$(mktemp -d "$TMP_ROOT/wait-devsvr-XXXXXX")"
  cleanup_dirs="$cleanup_dirs $ws"
  mkdir -p "$ws/.cc"
  printf '%s\n' "$ws"
}

# Pick a free TCP port via python3.
free_port() {
  python3 - <<'PY'
import socket
s = socket.socket()
s.bind(("127.0.0.1", 0))
print(s.getsockname()[1])
s.close()
PY
}

# Wait until URL responds 2xx or timeout (used to sync test setup, not
# the SUT). Returns 0 if reachable within $2 seconds, 1 otherwise.
wait_until_up() {
  local url="$1"; local max="$2"; local i=0
  while [ $i -lt "$max" ]; do
    if curl -fsS -o /dev/null "$url" 2>/dev/null; then
      return 0
    fi
    sleep 1
    i=$((i + 1))
  done
  return 1
}

# ---------------------------------------------------------------------------
# Case 1 — already running
# ---------------------------------------------------------------------------
echo "-- Case 1: already running --"
WS1="$(mkws)"
PORT1="$(free_port)"
cleanup_ports="$cleanup_ports $PORT1"
# Start a tiny http server.
( cd "$WS1" && python3 -m http.server "$PORT1" >/dev/null 2>&1 ) &
PID1=$!
cleanup_pids="$cleanup_pids $PID1"
if wait_until_up "http://127.0.0.1:$PORT1/" 10; then
  OUT1="$(bash "$WAIT" "$WS1" --url "http://127.0.0.1:$PORT1" --max-wait 5 2>&1)"
  RC1=$?
  if [ $RC1 -eq 0 ]; then
    pass "exit 0 for already-running (got $RC1)"
  else
    fail "expected exit 0, got $RC1 (output: $OUT1)"
  fi
  if printf '%s' "$OUT1" | grep -q "already-running"; then
    pass "stdout reports 'already-running'"
  else
    fail "expected 'already-running' in stdout: $OUT1"
  fi
else
  fail "test setup failed: server on $PORT1 never came up"
fi
kill "$PID1" 2>/dev/null || true
wait "$PID1" 2>/dev/null || true

# ---------------------------------------------------------------------------
# Case 2 — start via package.json scripts.dev
# ---------------------------------------------------------------------------
echo "-- Case 2: start via package.json scripts.dev --"
WS2="$(mkws)"
PORT2="$(free_port)"
cleanup_ports="$cleanup_ports $PORT2"
cat > "$WS2/package.json" <<EOF
{
  "name": "test-pkg",
  "scripts": {
    "dev": "python3 -m http.server $PORT2"
  }
}
EOF
# Pre-flight: ensure 'npm' exists. If not, swap the start cmd via config to
# bypass the package.json route. Otherwise this case can't run on this host.
if command -v npm >/dev/null 2>&1; then
  OUT2="$(bash "$WAIT" "$WS2" --url "http://127.0.0.1:$PORT2" --max-wait 15 2>&1)"
  RC2=$?
  if [ $RC2 -eq 0 ]; then
    pass "exit 0 for started-and-ready (got $RC2)"
  else
    fail "expected exit 0, got $RC2 (output: $OUT2; log: $(cat "$WS2/.cc/dev-server.log" 2>/dev/null || true))"
  fi
  if printf '%s' "$OUT2" | grep -q "started-and-ready"; then
    pass "stdout reports 'started-and-ready'"
  else
    fail "expected 'started-and-ready' in stdout: $OUT2"
  fi
  # Track the started pid for cleanup.
  if [ -f "$WS2/.cc/dev-server.pid" ]; then
    PID2="$(cat "$WS2/.cc/dev-server.pid")"
    cleanup_pids="$cleanup_pids $PID2"
  fi
else
  echo "  SKIP: npm not on PATH (case 2 needs it)"
fi

# ---------------------------------------------------------------------------
# Case 3 — start via .cc/config.json dev_server_start_cmd (overrides pkg.json)
# ---------------------------------------------------------------------------
echo "-- Case 3: start via .cc/config.json dev_server_start_cmd --"
WS3="$(mkws)"
PORT3="$(free_port)"
cleanup_ports="$cleanup_ports $PORT3"
# package.json with an intentionally-broken dev cmd, then config override
# should take precedence and the override should succeed.
cat > "$WS3/package.json" <<'EOF'
{
  "name": "test-pkg",
  "scripts": {
    "dev": "false"
  }
}
EOF
cat > "$WS3/.cc/config.json" <<EOF
{
  "dev_server_start_cmd": "python3 -m http.server $PORT3"
}
EOF
OUT3="$(bash "$WAIT" "$WS3" --url "http://127.0.0.1:$PORT3" --max-wait 15 2>&1)"
RC3=$?
if [ $RC3 -eq 0 ]; then
  pass "exit 0 for config override (got $RC3)"
else
  fail "expected exit 0, got $RC3 (output: $OUT3; log: $(cat "$WS3/.cc/dev-server.log" 2>/dev/null || true))"
fi
if printf '%s' "$OUT3" | grep -q "started-and-ready"; then
  pass "stdout reports 'started-and-ready' via config"
else
  fail "expected 'started-and-ready' in stdout: $OUT3"
fi
if [ -f "$WS3/.cc/dev-server.pid" ]; then
  PID3="$(cat "$WS3/.cc/dev-server.pid")"
  cleanup_pids="$cleanup_pids $PID3"
fi

# ---------------------------------------------------------------------------
# Case 4 — times out (sleep never opens a port)
# ---------------------------------------------------------------------------
echo "-- Case 4: times out --"
WS4="$(mkws)"
PORT4="$(free_port)"
cat > "$WS4/.cc/config.json" <<EOF
{
  "dev_server_start_cmd": "sleep 30"
}
EOF
START_TS="$(date +%s)"
OUT4="$(bash "$WAIT" "$WS4" --url "http://127.0.0.1:$PORT4" --max-wait 3 2>&1)"
RC4=$?
END_TS="$(date +%s)"
ELAPSED=$((END_TS - START_TS))
if [ $RC4 -eq 1 ]; then
  pass "exit 1 for start-failed (got $RC4)"
else
  fail "expected exit 1, got $RC4 (output: $OUT4)"
fi
if printf '%s' "$OUT4" | grep -q "start-failed"; then
  pass "stdout reports 'start-failed'"
else
  fail "expected 'start-failed' in stdout: $OUT4"
fi
if [ "$ELAPSED" -le 8 ]; then
  pass "timed out in ~${ELAPSED}s (expected ~3s, max 8s)"
else
  fail "took ${ELAPSED}s — expected <=8s for max-wait=3"
fi
# The sleep should have been killed by the script — verify .cc/dev-server.pid
# was cleaned up.
if [ ! -f "$WS4/.cc/dev-server.pid" ]; then
  pass "pid file removed after failed start"
else
  # Belt and braces: even if the file is still there, the process should be dead.
  pid4="$(cat "$WS4/.cc/dev-server.pid")"
  if ! kill -0 "$pid4" 2>/dev/null; then
    pass "pid file present but process is gone"
  else
    fail "process $pid4 still alive after timeout"
    cleanup_pids="$cleanup_pids $pid4"
  fi
fi

# ---------------------------------------------------------------------------
# Case 5 — no start command + not running
# ---------------------------------------------------------------------------
echo "-- Case 5: no start command + not running --"
WS5="$(mkws)"
PORT5="$(free_port)"
# Empty workspace — no package.json, no docker-compose, no config.
OUT5="$(bash "$WAIT" "$WS5" --url "http://127.0.0.1:$PORT5" --max-wait 3 2>&1)"
RC5=$?
if [ $RC5 -eq 2 ]; then
  pass "exit 2 for not-running-no-start-cmd (got $RC5)"
else
  fail "expected exit 2, got $RC5 (output: $OUT5)"
fi
if printf '%s' "$OUT5" | grep -q "not-running-no-start-cmd"; then
  pass "stdout reports 'not-running-no-start-cmd'"
else
  fail "expected 'not-running-no-start-cmd' in stdout: $OUT5"
fi

# ---------------------------------------------------------------------------
# Case 6 — custom --health-path
#
# Approach: serve a temp dir that contains a single file `health` (so
# `GET /health` returns 200 from python's SimpleHTTPRequestHandler), and a
# root path `/` that ALSO returns 200 (directory listing). To prove the
# health-path is being honored, we point --health-path at a path that
# definitely 404s and assert we fall through to not-running / timeout
# behavior. Then a second sub-case verifies the happy /health path passes.
# ---------------------------------------------------------------------------
echo "-- Case 6a: --health-path that 404s (server up but path missing) --"
WS6="$(mkws)"
PORT6="$(free_port)"
cleanup_ports="$cleanup_ports $PORT6"
mkdir -p "$WS6/htdocs"
echo "ok" > "$WS6/htdocs/health"
( cd "$WS6/htdocs" && python3 -m http.server "$PORT6" >/dev/null 2>&1 ) &
PID6=$!
cleanup_pids="$cleanup_pids $PID6"
if wait_until_up "http://127.0.0.1:$PORT6/" 10; then
  # Workspace has no start cmd. So with a 404 health-path, the probe fails
  # on the already-running check, falls to start-cmd resolution, finds
  # none, and exits 2 with not-running-no-start-cmd. That proves the
  # health-path was respected (otherwise the probe of `/` would have
  # returned 200 and we'd see already-running).
  OUT6A="$(bash "$WAIT" "$WS6" --url "http://127.0.0.1:$PORT6" --health-path "/definitely-not-here" --max-wait 2 2>&1)"
  RC6A=$?
  if [ $RC6A -eq 2 ]; then
    pass "exit 2 with health-path=/definitely-not-here (got $RC6A) — proves health-path was probed"
  else
    fail "expected exit 2 (probe failed because path 404s), got $RC6A (output: $OUT6A)"
  fi
else
  fail "test setup failed: server on $PORT6 never came up"
fi

echo "-- Case 6b: --health-path that resolves (200 on /health) --"
if wait_until_up "http://127.0.0.1:$PORT6/" 5; then
  OUT6B="$(bash "$WAIT" "$WS6" --url "http://127.0.0.1:$PORT6" --health-path "/health" --max-wait 2 2>&1)"
  RC6B=$?
  if [ $RC6B -eq 0 ]; then
    pass "exit 0 with health-path=/health (got $RC6B)"
  else
    fail "expected exit 0, got $RC6B (output: $OUT6B)"
  fi
  if printf '%s' "$OUT6B" | grep -q "already-running"; then
    pass "stdout reports 'already-running' on valid health-path"
  else
    fail "expected 'already-running' in stdout: $OUT6B"
  fi
fi
kill "$PID6" 2>/dev/null || true
wait "$PID6" 2>/dev/null || true

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo
if [ $fails -eq 0 ]; then
  echo "ALL PASS"
  exit 0
else
  echo "$fails assertion(s) FAILED"
  exit 1
fi
