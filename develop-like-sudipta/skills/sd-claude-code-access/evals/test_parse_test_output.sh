#!/usr/bin/env bash
# Smoke test for scripts/parse_test_output.py.
#
# Cases:
#   1. Auto-detect runner from each fixture's name.
#   2. summary.failed matches the digit in the fixture filename (N_failures).
#   3. failures[0].test is non-empty for each failing fixture.
#   4. --runner override is honored even when the fixture isn't that format.
#   5. Parser exits 0 even when input shows failures.
#   6. All-pass fixture: summary.failed == 0, failures == [].

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PARSER="$ROOT/scripts/parse_test_output.py"
FIXDIR="$SCRIPT_DIR/fixtures"

PASS=0
FAIL=0
FAILED_CASES=()

ok()   { PASS=$((PASS + 1)); printf '  PASS  %s\n' "$1"; }
nope() { FAIL=$((FAIL + 1)); FAILED_CASES+=("$1"); printf '  FAIL  %s\n' "$1"; if [ -n "${2:-}" ]; then printf '        %s\n' "$2"; fi; }

# python3 helper that reads JSON from stdin and extracts a field.
jget() {
  python3 -c "
import json, sys
data = json.load(sys.stdin)
keys = sys.argv[1].split('.')
v = data
for k in keys:
    if k.endswith(']'):
        name, idx = k[:-1].split('[')
        v = v.get(name) if isinstance(v, dict) else v
        v = v[int(idx)]
    else:
        v = v.get(k) if isinstance(v, dict) else v
print('' if v is None else v)
" "$1"
}

# Map fixture filename -> expected runner.
declare -a CASES=(
  "pytest_3_failures.txt|pytest|3"
  "pytest_all_pass.txt|pytest|0"
  "jest_2_failures.txt|jest|2"
  "vitest_1_failure.txt|vitest|1"
  "cargo_1_failure.txt|cargo|1"
  "go_2_failures.txt|go|2"
  "maven_1_failure.txt|maven|1"
)

echo "== Case 1+2+3: auto-detect, failed-count, non-empty test name =="

for entry in "${CASES[@]}"; do
  IFS='|' read -r fname expected_runner expected_failed <<< "$entry"
  path="$FIXDIR/$fname"
  if [ ! -f "$path" ]; then
    nope "fixture-exists: $fname" "missing file"
    continue
  fi

  out=$(python3 "$PARSER" < "$path" 2>/dev/null)
  rc=$?
  if [ $rc -ne 0 ]; then
    nope "exit-zero: $fname" "parser exited $rc"
    continue
  fi
  ok "exit-zero: $fname"

  # JSON must be valid.
  if ! echo "$out" | python3 -m json.tool >/dev/null 2>&1; then
    nope "valid-json: $fname" "$out"
    continue
  fi
  ok "valid-json: $fname"

  # Runner detection.
  got_runner=$(echo "$out" | jget runner)
  if [ "$got_runner" = "$expected_runner" ]; then
    ok "auto-detect: $fname -> $expected_runner"
  else
    nope "auto-detect: $fname (expected $expected_runner, got $got_runner)"
  fi

  # Failed count.
  got_failed=$(echo "$out" | jget summary.failed)
  if [ "$got_failed" = "$expected_failed" ]; then
    ok "failed-count: $fname -> $expected_failed"
  else
    nope "failed-count: $fname (expected $expected_failed, got $got_failed)"
  fi

  # First-failure test name populated (only for fixtures with failures).
  if [ "$expected_failed" -gt 0 ]; then
    got_test=$(echo "$out" | jget 'failures[0].test')
    if [ -n "$got_test" ]; then
      ok "first-failure-test: $fname -> '$got_test'"
    else
      nope "first-failure-test: $fname (empty)"
    fi
  fi
done

echo
echo "== Case 4: forced --runner override =="

out=$(python3 "$PARSER" --runner jest < "$FIXDIR/pytest_3_failures.txt" 2>/dev/null)
rc=$?
if [ $rc -ne 0 ]; then
  nope "override-exit-zero" "rc=$rc"
else
  ok "override-exit-zero"
fi
got_runner=$(echo "$out" | jget runner)
if [ "$got_runner" = "jest" ]; then
  ok "override-runner: forced jest honored"
else
  nope "override-runner: got '$got_runner'"
fi

echo
echo "== Case 6: all-pass fixture has empty failures =="

out=$(python3 "$PARSER" < "$FIXDIR/pytest_all_pass.txt" 2>/dev/null)
got_failed=$(echo "$out" | jget summary.failed)
got_failures_len=$(echo "$out" | python3 -c "import json,sys; print(len(json.load(sys.stdin)['failures']))")
if [ "$got_failed" = "0" ]; then
  ok "all-pass-failed-zero"
else
  nope "all-pass-failed-zero (got $got_failed)"
fi
if [ "$got_failures_len" = "0" ]; then
  ok "all-pass-failures-empty"
else
  nope "all-pass-failures-empty (got len=$got_failures_len)"
fi

echo
echo "== Case 5 (also): unknown input still exits 0 =="
echo "this is not a test output at all" | python3 "$PARSER" >/dev/null 2>&1
if [ $? -eq 0 ]; then
  ok "unknown-input-exit-zero"
else
  nope "unknown-input-exit-zero"
fi

echo
echo "------------------------------------------------------------"
echo "  $PASS passed, $FAIL failed"
if [ $FAIL -gt 0 ]; then
  echo "  Failed cases:"
  for c in "${FAILED_CASES[@]}"; do echo "    - $c"; done
  exit 1
fi
exit 0
