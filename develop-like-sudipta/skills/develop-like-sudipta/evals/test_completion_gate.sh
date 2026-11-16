#!/usr/bin/env bash
# Eval for hooks/completion-gate.sh (Stop hook).
# Contract: it never runs the project's test suite unless COMPLETION_GATE_RUN_TESTS=1,
# and when opted in it judges the suite by exit code, not by grepping output.
# Bash 3.2 compatible. Cleans up after itself.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$(cd "$SCRIPT_DIR/../../../hooks" && pwd)/completion-gate.sh"

PASS=0
FAIL=0
note_pass() { PASS=$((PASS + 1)); echo "PASS: $1"; }
note_fail() { FAIL=$((FAIL + 1)); echo "FAIL: $1"; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# make_repo <dir> <test-script-body>: git repo whose npm test writes a marker.
make_repo() {
  local dir="$1" body="$2"
  mkdir -p "$dir"
  (
    cd "$dir" || exit 1
    git init -q .
    git config user.email t@example.invalid
    git config user.name t
    printf '{"name":"x","version":"1.0.0","scripts":{"test":"%s"}}\n' "$body" > package.json
    git add package.json
    git commit -q -m init
  )
}

run_hook() { # <dir> [env assignments...]
  local dir="$1"; shift
  ( cd "$dir" && env "$@" bash "$HOOK" 2>&1 )
}

# 1. default: suite not run, no output, exit 0
R1="$TMP/r1"
make_repo "$R1" "touch marker && exit 1"
OUT="$(run_hook "$R1" -u COMPLETION_GATE_RUN_TESTS)"; RC=$?
[ "$RC" -eq 0 ] && note_pass "default exits 0" || note_fail "default exit $RC"
[ ! -e "$R1/marker" ] && note_pass "default does not run npm test" || note_fail "default ran npm test"
[ -z "$OUT" ] && note_pass "default prints nothing" || note_fail "default printed: $OUT"

# 2. opted in + failing suite: runs and warns
RUN1="$TMP/r2"
make_repo "$RUN1" "touch marker && exit 1"
OUT="$(run_hook "$RUN1" COMPLETION_GATE_RUN_TESTS=1)"; RC=$?
[ "$RC" -eq 0 ] && note_pass "opt-in failing exits 0" || note_fail "opt-in failing exit $RC"
[ -e "$RUN1/marker" ] && note_pass "opt-in runs npm test" || note_fail "opt-in did not run npm test"
case "$OUT" in *"tests FAILING"*) note_pass "opt-in failing warns";; *) note_fail "opt-in failing no warning: $OUT";; esac

# 3. opted in + passing suite whose output says "error": no warning
R3="$TMP/r3"
make_repo "$R3" "touch marker && echo error fail FAILED ERROR"
OUT="$(run_hook "$R3" COMPLETION_GATE_RUN_TESTS=1)"; RC=$?
[ "$RC" -eq 0 ] && note_pass "opt-in passing exits 0" || note_fail "opt-in passing exit $RC"
[ -e "$R3/marker" ] && note_pass "opt-in passing ran npm test" || note_fail "opt-in passing did not run npm test"
case "$OUT" in *FAILING*) note_fail "passing suite with 'error' text warned: $OUT";; *) note_pass "passing suite with 'error' text gives no warning";; esac

# 4. hooks.json gives the Stop entry a timeout of 120
HJ="$(cd "$SCRIPT_DIR/../../../hooks" && pwd)/hooks.json"
if python3 -c "
import json,sys
d=json.load(open(sys.argv[1]))
h=d['hooks']['Stop'][0]['hooks'][0]
sys.exit(0 if h.get('timeout')==120 else 1)" "$HJ"; then
  note_pass "hooks.json Stop timeout is 120"
else
  note_fail "hooks.json Stop timeout missing or not 120"
fi

echo "---"
echo "passed=$PASS failed=$FAIL"
[ "$FAIL" -eq 0 ]
