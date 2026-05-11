#!/usr/bin/env bash
# test_check_auth_state.sh — smoke test for check_auth_state.sh.
#
# Background: <workspace>/.cc/auth/storage-state.json holds the persisted
# Playwright/Chrome MCP storage state for an auth-gated app. Browser tests
# rely on it staying fresh across runs. check_auth_state.sh validates
# freshness by inspecting file mtime, cookie expiry, and (optionally) a
# health endpoint. It must classify the state into one of five reasons:
#
#   fresh                  exit 0  storage state is recent + cookies valid
#   missing                exit 1  no storage-state.json on disk
#   stale-by-age           exit 2  mtime older than auth_max_age_minutes
#   stale-by-cookie-expiry exit 3  critical session cookie has expired
#   stale-by-401           exit 4  liveness check returned 401/403
#
# Cases covered here:
#   1. Missing file                  -> exit 1, "missing"
#   2. Fresh file                    -> exit 0, "fresh"
#   3. Stale by age (default 30)     -> exit 2, "stale-by-age"
#   4. Cookie expired in the past    -> exit 3, "stale-by-cookie-expiry"
#   5. Custom auth_max_age_minutes   -> exit 2, "stale-by-age" with override
#   6. Liveness 401                  -> documented; verified by manual test.
#      Rationale: portable mocking of curl across bash 3.2 / macOS / CI
#      without network is fragile (PATH-shim, function-shadow, etc all
#      introduce flake into the smoke run). The 401 code path is
#      straightforward (single curl invocation, status-code branch) and
#      is exercised manually against an httpbin.org/status/401 endpoint.
#
# Bash 3.2 compatible. No `mapfile`, `wait -n`, associative arrays.
#
# Usage: ./test_check_auth_state.sh
# Exit 0 on PASS, non-zero on any failed assertion.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CHECK="$SCRIPT_DIR/../scripts/check_auth_state.sh"

if [ ! -f "$CHECK" ]; then
  echo "FAIL: check_auth_state.sh not found at $CHECK"
  exit 2
fi

TMP_ROOT="${TMPDIR:-/tmp}"
fails=0
cleanup_dirs=""

fail() { fails=$((fails + 1)); echo "  FAIL: $*"; }
pass() { echo "  PASS: $*"; }

cleanup() {
  for d in $cleanup_dirs; do
    [ -n "$d" ] && [ -d "$d" ] && rm -rf "$d"
  done
}
trap cleanup EXIT INT TERM

mkws() {
  ws="$(mktemp -d "$TMP_ROOT/check-auth-XXXXXX")"
  cleanup_dirs="$cleanup_dirs $ws"
  mkdir -p "$ws/.cc/auth"
  printf '%s\n' "$ws"
}

# A storage-state.json with a single cookie expiring 7 days in the future.
# Playwright shape: {"cookies":[{...}], "origins":[]}.
write_fresh_state() {
  local target="$1"
  # 7 days = 604800 seconds. Use python3 for portable UTC math.
  local future_ts
  future_ts="$(python3 -c 'import time; print(int(time.time()) + 7*86400)')"
  cat > "$target" <<EOF
{
  "cookies": [
    {
      "name": "session",
      "value": "abc123",
      "domain": "example.com",
      "path": "/",
      "expires": $future_ts,
      "httpOnly": true,
      "secure": true,
      "sameSite": "Lax"
    }
  ],
  "origins": []
}
EOF
}

write_expired_cookie_state() {
  local target="$1"
  # 1000000000 = 2001-09-09 UTC — well in the past.
  cat > "$target" <<'EOF'
{
  "cookies": [
    {
      "name": "session",
      "value": "abc123",
      "domain": "example.com",
      "path": "/",
      "expires": 1000000000,
      "httpOnly": true,
      "secure": true,
      "sameSite": "Lax"
    }
  ],
  "origins": []
}
EOF
}

# ---------------------------------------------------------------------------
# Case 1 — missing storage-state.json
# ---------------------------------------------------------------------------
echo "-- Case 1: missing storage-state.json --"
WS1="$(mkws)"
OUT1="$(bash "$CHECK" "$WS1" 2>&1)"
RC1=$?
if [ $RC1 -eq 1 ]; then
  pass "exit code 1 for missing (got $RC1)"
else
  fail "expected exit 1, got $RC1 (output: $OUT1)"
fi
if printf '%s' "$OUT1" | grep -q "missing"; then
  pass "stdout reports 'missing'"
else
  fail "expected 'missing' in stdout: $OUT1"
fi

# ---------------------------------------------------------------------------
# Case 2 — fresh file with non-expired cookie
# ---------------------------------------------------------------------------
echo "-- Case 2: fresh file with non-expired cookie --"
WS2="$(mkws)"
write_fresh_state "$WS2/.cc/auth/storage-state.json"
OUT2="$(bash "$CHECK" "$WS2" 2>&1)"
RC2=$?
if [ $RC2 -eq 0 ]; then
  pass "exit code 0 for fresh (got $RC2)"
else
  fail "expected exit 0, got $RC2 (output: $OUT2)"
fi
if printf '%s' "$OUT2" | grep -q "fresh"; then
  pass "stdout reports 'fresh'"
else
  fail "expected 'fresh' in stdout: $OUT2"
fi

# ---------------------------------------------------------------------------
# Case 3 — stale by age (mtime 60 min ago, default max_age=30)
# ---------------------------------------------------------------------------
echo "-- Case 3: stale by age (default 30 min) --"
WS3="$(mkws)"
write_fresh_state "$WS3/.cc/auth/storage-state.json"
# `touch -t` accepts [[CC]YY]MMDDhhmm[.ss]. Build a timestamp 60 min ago.
STAMP3="$(python3 -c 'import time; print(time.strftime("%Y%m%d%H%M", time.localtime(time.time() - 60*60)))')"
touch -t "$STAMP3" "$WS3/.cc/auth/storage-state.json"
OUT3="$(bash "$CHECK" "$WS3" 2>&1)"
RC3=$?
if [ $RC3 -eq 2 ]; then
  pass "exit code 2 for stale-by-age (got $RC3)"
else
  fail "expected exit 2, got $RC3 (output: $OUT3)"
fi
if printf '%s' "$OUT3" | grep -q "stale-by-age"; then
  pass "stdout reports 'stale-by-age'"
else
  fail "expected 'stale-by-age' in stdout: $OUT3"
fi

# ---------------------------------------------------------------------------
# Case 4 — cookie expired in the past
# ---------------------------------------------------------------------------
echo "-- Case 4: cookie expired (expires=1000000000) --"
WS4="$(mkws)"
write_expired_cookie_state "$WS4/.cc/auth/storage-state.json"
OUT4="$(bash "$CHECK" "$WS4" 2>&1)"
RC4=$?
if [ $RC4 -eq 3 ]; then
  pass "exit code 3 for stale-by-cookie-expiry (got $RC4)"
else
  fail "expected exit 3, got $RC4 (output: $OUT4)"
fi
if printf '%s' "$OUT4" | grep -q "stale-by-cookie-expiry"; then
  pass "stdout reports 'stale-by-cookie-expiry'"
else
  fail "expected 'stale-by-cookie-expiry' in stdout: $OUT4"
fi

# ---------------------------------------------------------------------------
# Case 5 — custom auth_max_age_minutes from .cc/config.json
# mtime 20 min ago, override max_age=10 -> still stale.
# ---------------------------------------------------------------------------
echo "-- Case 5: custom auth_max_age_minutes (override=10, mtime=20min ago) --"
WS5="$(mkws)"
write_fresh_state "$WS5/.cc/auth/storage-state.json"
cat > "$WS5/.cc/config.json" <<'EOF'
{
  "auth_max_age_minutes": 10
}
EOF
STAMP5="$(python3 -c 'import time; print(time.strftime("%Y%m%d%H%M", time.localtime(time.time() - 20*60)))')"
touch -t "$STAMP5" "$WS5/.cc/auth/storage-state.json"
OUT5="$(bash "$CHECK" "$WS5" 2>&1)"
RC5=$?
if [ $RC5 -eq 2 ]; then
  pass "exit code 2 with custom override (got $RC5)"
else
  fail "expected exit 2, got $RC5 (output: $OUT5)"
fi
if printf '%s' "$OUT5" | grep -q "stale-by-age"; then
  pass "stdout reports 'stale-by-age' with override"
else
  fail "expected 'stale-by-age' in stdout: $OUT5"
fi

# Sanity: same WS with override=60 and mtime=20min ago should be fresh.
echo "-- Case 5b: custom override=60, mtime=20min ago -> fresh --"
WS5B="$(mkws)"
write_fresh_state "$WS5B/.cc/auth/storage-state.json"
cat > "$WS5B/.cc/config.json" <<'EOF'
{
  "auth_max_age_minutes": 60
}
EOF
STAMP5B="$(python3 -c 'import time; print(time.strftime("%Y%m%d%H%M", time.localtime(time.time() - 20*60)))')"
touch -t "$STAMP5B" "$WS5B/.cc/auth/storage-state.json"
OUT5B="$(bash "$CHECK" "$WS5B" 2>&1)"
RC5B=$?
if [ $RC5B -eq 0 ]; then
  pass "exit code 0 with override=60 (got $RC5B)"
else
  fail "expected exit 0, got $RC5B (output: $OUT5B)"
fi
if printf '%s' "$OUT5B" | grep -q "fresh"; then
  pass "stdout reports 'fresh' with generous override"
else
  fail "expected 'fresh' in stdout: $OUT5B"
fi

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
