#!/usr/bin/env bash
# test_state_salvage.sh — smoke test for state_salvage.sh.
#
# Background: <workspace>/.cc/state.json is the resume-after-crash record
# (JSONL events written by state.sh). If a write is interrupted, the file
# may carry a truncated tail or trailing junk. state_salvage.sh detects
# corruption, backs up the original, drops malformed lines, and rewrites
# a clean state.json so cc-resume can read it again.
#
# Cases:
#   1. No file present              -> exits 0, "no state.json to salvage"
#   2. Already-clean JSONL          -> exits 0, "nothing to do", file unchanged
#   3. Partial corruption           -> exits 0, N good + M bad counted,
#                                      backup exists, clean file has only good
#   4. All lines corrupt            -> exits 0, N=0, M=all, file is empty,
#                                      backup exists
#   5. Empty (zero-byte) file       -> exits 0, "nothing to do" (an empty
#                                      JSONL stream is trivially valid)
#   6. (code-review) TMP file is created in same dir as state.json — see
#      `mktemp "$STATE_DIR/.state-salvage.XXXXXX"` in state_salvage.sh.
#      Verified by inspection; an integration assertion would require
#      racing the script which is too flaky for a smoke test.
#   7. python3 missing on PATH      -> exits 2 with "python3 required"
#                                      message, state.json untouched, no
#                                      backup created (silent-destruction
#                                      regression guard)
#   8. (code-review) Backup name embeds the salvage process PID
#      (`${STATE_FILE}.bak.${TS}.${$}`) so two invocations in the same
#      UTC second produce distinct backups. Verified by inspection.
#
# Bash 3.2 compatible. No `wait -n`, no `mapfile`, no associative arrays.
#
# Usage: ./test_state_salvage.sh
# Exit 0 on PASS, non-zero on any failed assertion.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SALVAGE="$SCRIPT_DIR/../scripts/state_salvage.sh"

if [ ! -f "$SALVAGE" ]; then
  echo "FAIL: state_salvage.sh not found at $SALVAGE"
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
  ws="$(mktemp -d "$TMP_ROOT/state-salvage-XXXXXX")"
  cleanup_dirs="$cleanup_dirs $ws"
  mkdir -p "$ws/.cc"
  printf '%s\n' "$ws"
}

# ---------------------------------------------------------------------------
# Case 1 — no state.json file at all
# ---------------------------------------------------------------------------
echo "-- Case 1: missing state.json (idempotent no-op) --"
WS1="$(mkws)"
OUT1="$(bash "$SALVAGE" "$WS1" 2>&1)"
RC1=$?
if [ $RC1 -eq 0 ]; then
  pass "exit code 0 for missing file (got $RC1)"
else
  fail "expected exit 0, got $RC1"
fi
if printf '%s' "$OUT1" | grep -qi "no state.json"; then
  pass "output mentions 'no state.json'"
else
  fail "output did not mention 'no state.json': $OUT1"
fi
if [ ! -e "$WS1/.cc/state.json" ]; then
  pass "no state.json was created"
else
  fail "state.json should not be present"
fi

# ---------------------------------------------------------------------------
# Case 2 — clean, valid JSONL
# ---------------------------------------------------------------------------
echo "-- Case 2: clean valid JSONL (nothing to do) --"
WS2="$(mkws)"
cat > "$WS2/.cc/state.json" <<'EOF'
{"ts":"2026-05-09T19:23:18Z","event":"phase_start","phase":"7"}
{"ts":"2026-05-09T19:23:50Z","event":"prompt_approved","fp":"a1b2c3d4"}
{"ts":"2026-05-09T19:30:01Z","event":"phase_complete","phase":"7","commits":"5","tests":"280"}
EOF
EXPECTED_SHA="$(shasum "$WS2/.cc/state.json" 2>/dev/null | awk '{print $1}')"
OUT2="$(bash "$SALVAGE" "$WS2" 2>&1)"
RC2=$?
if [ $RC2 -eq 0 ]; then
  pass "exit code 0 for clean file"
else
  fail "expected exit 0, got $RC2 (output: $OUT2)"
fi
if printf '%s' "$OUT2" | grep -qi "nothing to do"; then
  pass "output mentions 'nothing to do'"
else
  fail "output did not mention 'nothing to do': $OUT2"
fi
ACTUAL_SHA="$(shasum "$WS2/.cc/state.json" 2>/dev/null | awk '{print $1}')"
if [ "$EXPECTED_SHA" = "$ACTUAL_SHA" ]; then
  pass "file unchanged (sha matches)"
else
  fail "file was modified (sha drifted)"
fi
# No backup should be made when nothing to do.
if ls "$WS2/.cc/"state.json.bak.* >/dev/null 2>&1; then
  fail "unexpected backup file created"
else
  pass "no backup file (correct)"
fi

# ---------------------------------------------------------------------------
# Case 3 — partial corruption (3 good, 2 bad: truncation + trailing garbage)
# ---------------------------------------------------------------------------
echo "-- Case 3: partial corruption (drop bad lines, keep good) --"
WS3="$(mkws)"
# 3 valid lines, 2 invalid (one truncated mid-write, one trailing garbage).
{
  printf '%s\n' '{"ts":"2026-05-09T19:23:18Z","event":"phase_start","phase":"7"}'
  printf '%s\n' '{"ts":"2026-05-09T19:23:50Z","event":"prompt_app'
  printf '%s\n' '{"ts":"2026-05-09T19:24:10Z","event":"prompt_approved","fp":"e5f6"}'
  printf '%s\n' 'NOT JSON AT ALL <<< garbage >>>'
  printf '%s\n' '{"ts":"2026-05-09T19:30:01Z","event":"phase_complete","phase":"7"}'
} > "$WS3/.cc/state.json"
OUT3="$(bash "$SALVAGE" "$WS3" 2>&1)"
RC3=$?
if [ $RC3 -eq 0 ]; then
  pass "exit code 0 on partial corruption"
else
  fail "expected exit 0, got $RC3 (output: $OUT3)"
fi
if printf '%s' "$OUT3" | grep -qE "3 events salvaged"; then
  pass "output reports 3 events salvaged"
else
  fail "expected '3 events salvaged' in output: $OUT3"
fi
if printf '%s' "$OUT3" | grep -qE "2 dropped"; then
  pass "output reports 2 dropped"
else
  fail "expected '2 dropped' in output: $OUT3"
fi
# Backup exists?
BAKS3="$(ls "$WS3/.cc/"state.json.bak.* 2>/dev/null | head -1)"
if [ -n "$BAKS3" ] && [ -f "$BAKS3" ]; then
  pass "backup file exists at $BAKS3"
else
  fail "backup file missing"
fi
# Clean state.json should have exactly 3 lines, all parseable JSON.
N_CLEAN3="$(wc -l < "$WS3/.cc/state.json" | tr -d ' ')"
if [ "$N_CLEAN3" = "3" ]; then
  pass "clean state.json has 3 lines"
else
  fail "clean state.json has $N_CLEAN3 lines, expected 3"
fi
# Sanity: every surviving line should parse as JSON.
ALL_OK=1
while IFS= read -r line; do
  if ! python3 -c "import json,sys; json.loads(sys.stdin.read())" <<EOF >/dev/null 2>&1
$line
EOF
  then
    ALL_OK=0
    break
  fi
done < "$WS3/.cc/state.json"
if [ $ALL_OK -eq 1 ]; then
  pass "every surviving line parses as JSON"
else
  fail "some surviving line does not parse as JSON"
fi
# The truncated line should NOT be in the salvaged file.
if grep -q '^{"ts":"2026-05-09T19:23:50Z","event":"prompt_app$' "$WS3/.cc/state.json" 2>/dev/null; then
  fail "truncated line survived salvage"
else
  pass "truncated line was dropped"
fi
if grep -q 'NOT JSON AT ALL' "$WS3/.cc/state.json" 2>/dev/null; then
  fail "trailing garbage line survived salvage"
else
  pass "trailing garbage line was dropped"
fi

# ---------------------------------------------------------------------------
# Case 4 — every line is invalid JSON
# ---------------------------------------------------------------------------
echo "-- Case 4: every line corrupt (file becomes empty) --"
WS4="$(mkws)"
{
  printf '%s\n' 'not json'
  printf '%s\n' '{also not json'
  printf '%s\n' '%%%'
} > "$WS4/.cc/state.json"
OUT4="$(bash "$SALVAGE" "$WS4" 2>&1)"
RC4=$?
if [ $RC4 -eq 0 ]; then
  pass "exit code 0 when all lines corrupt"
else
  fail "expected exit 0, got $RC4 (output: $OUT4)"
fi
if printf '%s' "$OUT4" | grep -qE "0 events salvaged"; then
  pass "output reports 0 events salvaged"
else
  fail "expected '0 events salvaged': $OUT4"
fi
if printf '%s' "$OUT4" | grep -qE "3 dropped"; then
  pass "output reports 3 dropped"
else
  fail "expected '3 dropped': $OUT4"
fi
BAKS4="$(ls "$WS4/.cc/"state.json.bak.* 2>/dev/null | head -1)"
if [ -n "$BAKS4" ] && [ -f "$BAKS4" ]; then
  pass "backup exists"
else
  fail "backup missing"
fi
if [ -f "$WS4/.cc/state.json" ] && [ ! -s "$WS4/.cc/state.json" ]; then
  pass "clean state.json is empty (zero bytes)"
else
  SIZE4="$(wc -c < "$WS4/.cc/state.json" 2>/dev/null | tr -d ' ')"
  fail "clean state.json should be empty (got $SIZE4 bytes)"
fi

# ---------------------------------------------------------------------------
# Case 5 — empty (zero-byte) state.json
# ---------------------------------------------------------------------------
echo "-- Case 5: empty zero-byte state.json (trivially clean) --"
WS5="$(mkws)"
: > "$WS5/.cc/state.json"
OUT5="$(bash "$SALVAGE" "$WS5" 2>&1)"
RC5=$?
if [ $RC5 -eq 0 ]; then
  pass "exit code 0 for empty file"
else
  fail "expected exit 0, got $RC5 (output: $OUT5)"
fi
if printf '%s' "$OUT5" | grep -qi "nothing to do"; then
  pass "output mentions 'nothing to do' for empty file"
else
  fail "expected 'nothing to do' for empty file: $OUT5"
fi
if ls "$WS5/.cc/"state.json.bak.* >/dev/null 2>&1; then
  fail "unexpected backup for empty file"
else
  pass "no backup made for empty file"
fi

# ---------------------------------------------------------------------------
# Case 7 — python3 missing on PATH (regression guard against silent destruction)
# ---------------------------------------------------------------------------
echo "-- Case 7: python3 missing on PATH (must refuse, must not modify) --"
WS7="$(mkws)"
cat > "$WS7/.cc/state.json" <<'EOF'
{"ts":"2026-05-10T01:00:00Z","event":"phase_start","phase":"3"}
{"ts":"2026-05-10T01:00:30Z","event":"prompt_approved","fp":"deadbeef"}
EOF
EXPECTED_SHA7="$(shasum "$WS7/.cc/state.json" 2>/dev/null | awk '{print $1}')"
# Empty PATH means no commands resolve, including python3. We still
# invoke bash by absolute path. Capture stderr to inspect the message.
OUT7="$(PATH="" /bin/bash "$SALVAGE" "$WS7" 2>&1)"
RC7=$?
if [ $RC7 -eq 2 ]; then
  pass "exit code 2 when python3 missing (got $RC7)"
else
  fail "expected exit 2, got $RC7 (output: $OUT7)"
fi
if printf '%s' "$OUT7" | grep -qi "python3"; then
  pass "stderr mentions python3 requirement"
else
  fail "expected python3 message in stderr: $OUT7"
fi
ACTUAL_SHA7="$(shasum "$WS7/.cc/state.json" 2>/dev/null | awk '{print $1}')"
if [ "$EXPECTED_SHA7" = "$ACTUAL_SHA7" ]; then
  pass "state.json NOT modified (sha matches)"
else
  fail "state.json was modified — silent-destruction regression!"
fi
if ls "$WS7/.cc/"state.json.bak.* >/dev/null 2>&1; then
  fail "unexpected backup created when python3 missing"
else
  pass "no backup created (correct — we refused before writing)"
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
