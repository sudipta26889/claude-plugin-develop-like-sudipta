#!/usr/bin/env bash
# test_flake_retry.sh — smoke test for the verify-gate's flake-retry +
# whitelist decision tree (documented in references/verify_gate.md).
#
# The verify-gate runner is methodology, not a script — Cowork itself
# implements the decision tree by reading the doc. This eval encodes the
# documented logic as an inline bash harness and asserts each case produces
# the documented verdict.
#
# Verdicts:
#   green                  — passes on first try
#   flake-recovered        — fails first, eventually passes within retry budget
#   yellow-flake           — fails through retry budget, but test is in whitelist
#   red-bug-required       — fails through retry budget AND not in whitelist
#                            (this is what triggers bug-driven TDD)
#
# Bash 3.2 compatible. No `mapfile`, no associative arrays, no `${var,,}`,
# no `wait -n`.
#
# Usage: ./test_flake_retry.sh
# Exit 0 on PASS, non-zero on any failed assertion.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TMP_ROOT="${TMPDIR:-/tmp}"
WORK="$(mktemp -d "$TMP_ROOT/flake-retry-XXXXXX")"

fails=0
fail() {
  fails=$((fails + 1))
  echo "  FAIL: $*"
}
pass() {
  echo "  PASS: $*"
}

# ---------------------------------------------------------------------------
# slug — replace anything not [A-Za-z0-9._-] with '_' so the test name can
# appear in a file path. Bash 3.2 friendly (no ${var//pat/rep} on Mac's bash
# would actually work but we use sed for clarity).
# ---------------------------------------------------------------------------
slug() {
  printf '%s' "$1" | sed 's/[^A-Za-z0-9._-]/_/g'
}

# ---------------------------------------------------------------------------
# Test simulator
#
# simulate_test <test_name> <pass_on_attempt>
#   Writes a stub script to $WORK/runner-<slug>.sh that exits 1 the first
#   (pass_on_attempt - 1) times and exits 0 on attempt pass_on_attempt and
#   after. State is kept in $WORK/attempt-<slug>. Use pass_on_attempt=9999
#   to mean "never passes". Slugification preserves the original test_name
#   for whitelist matching while keeping file paths safe.
# ---------------------------------------------------------------------------
simulate_test() {
  test_name="$1"
  pass_on="$2"
  s=$(slug "$test_name")
  runner="$WORK/runner-${s}.sh"
  counter="$WORK/attempt-${s}"
  echo 0 > "$counter"
  cat > "$runner" <<EOF
#!/usr/bin/env bash
# stub runner for $test_name; passes starting at attempt $pass_on
n=\$(cat "$counter")
n=\$((n + 1))
echo \$n > "$counter"
if [ "\$n" -ge "$pass_on" ]; then
  echo "PASS $test_name (attempt \$n)"
  exit 0
else
  echo "FAIL $test_name (attempt \$n)"
  exit 1
fi
EOF
  chmod +x "$runner"
}

# ---------------------------------------------------------------------------
# Whitelist lookup — literal match against newline-separated list.
#   is_whitelisted <test_name> <whitelist_file>
# Returns 0 if found, 1 otherwise. Bash 3.2 friendly (no readarray).
# ---------------------------------------------------------------------------
is_whitelisted() {
  needle="$1"
  list="$2"
  [ -f "$list" ] || return 1
  while IFS= read -r line; do
    # ignore blank lines
    [ -z "$line" ] && continue
    if [ "$line" = "$needle" ]; then
      return 0
    fi
  done < "$list"
  return 1
}

# ---------------------------------------------------------------------------
# verify_gate_decision <test_name> <flake_retries> <whitelist_file>
#
# Implements the decision tree from references/verify_gate.md:
#   1. Run the test once.
#   2. If pass → "green".
#   3. Else, retry up to flake_retries times. If any retry passes →
#      "flake-recovered".
#   4. Else, check whitelist. If whitelisted → "yellow-flake". Else →
#      "red-bug-required".
#
# Prints the verdict to stdout. Writes diagnostic lines to stderr.
# Returns 0 always (so callers can capture the verdict regardless).
# ---------------------------------------------------------------------------
verify_gate_decision() {
  test_name="$1"
  retries="$2"
  whitelist="$3"
  s=$(slug "$test_name")
  runner="$WORK/runner-${s}.sh"

  if "$runner" >/dev/null 2>&1; then
    echo "green"
    return 0
  fi

  # First run failed. Retry up to $retries more times.
  i=0
  while [ "$i" -lt "$retries" ]; do
    i=$((i + 1))
    echo "  retry $i for $test_name" >&2
    if "$runner" >/dev/null 2>&1; then
      echo "flake-recovered"
      return 0
    fi
  done

  # Persistent failure. Check whitelist.
  if is_whitelisted "$test_name" "$whitelist"; then
    echo "  $test_name persistently red but whitelisted — yellow-flake" >&2
    echo "yellow-flake"
  else
    echo "  $test_name persistently red, not whitelisted — bug-protocol" >&2
    echo "red-bug-required"
  fi
  return 0
}

# ---------------------------------------------------------------------------
# Fixture whitelist file used by cases 3 and 4.
# ---------------------------------------------------------------------------
WHITELIST="$WORK/whitelist.txt"
cat > "$WHITELIST" <<'EOF'
tests/integration/test_websocket_race.py::test_reconnect_storm
tests/e2e/checkout.spec.ts::handles intermittent CDN 503
EOF

EMPTY_WHITELIST="$WORK/empty_whitelist.txt"
: > "$EMPTY_WHITELIST"

# ---------------------------------------------------------------------------
# Case 1 — Flake recovers on retry 1
# ---------------------------------------------------------------------------
echo "── Case 1: flake recovers on retry 1 ──"
simulate_test "case1" 2  # fails attempt 1, passes attempt 2
v=$(verify_gate_decision "case1" 2 "$WHITELIST" 2>/dev/null)
echo "  verdict: $v"
if [ "$v" = "flake-recovered" ]; then
  pass "single-retry flake produced flake-recovered"
else
  fail "expected flake-recovered, got '$v'"
fi

# ---------------------------------------------------------------------------
# Case 2 — Flake recovers on retry 2
# ---------------------------------------------------------------------------
echo
echo "── Case 2: flake recovers on retry 2 (third call) ──"
simulate_test "case2" 3  # fails 1+2, passes 3
v=$(verify_gate_decision "case2" 2 "$WHITELIST" 2>/dev/null)
echo "  verdict: $v"
if [ "$v" = "flake-recovered" ]; then
  pass "double-retry flake produced flake-recovered"
else
  fail "expected flake-recovered, got '$v'"
fi

# ---------------------------------------------------------------------------
# Case 3 — Persistent failure, whitelisted → yellow-flake
# ---------------------------------------------------------------------------
echo
echo "── Case 3: persistent failure, whitelisted ──"
WL_NAME="tests/integration/test_websocket_race.py::test_reconnect_storm"
simulate_test "$WL_NAME" 9999   # never passes
v=$(verify_gate_decision "$WL_NAME" 2 "$WHITELIST" 2>/dev/null)
echo "  verdict: $v"
if [ "$v" = "yellow-flake" ]; then
  pass "whitelisted persistent failure produced yellow-flake"
else
  fail "expected yellow-flake, got '$v'"
fi

# Confirm the runner was indeed called 1 + 2 = 3 times.
WL_SLUG=$(slug "$WL_NAME")
attempts=$(cat "$WORK/attempt-${WL_SLUG}")
if [ "$attempts" = "3" ]; then
  pass "runner invoked 3 times (1 initial + 2 retries)"
else
  fail "expected 3 invocations, got $attempts"
fi

# ---------------------------------------------------------------------------
# Case 4 — Persistent failure, NOT whitelisted → red-bug-required
# ---------------------------------------------------------------------------
echo
echo "── Case 4: persistent failure, NOT whitelisted ──"
simulate_test "case4" 9999  # never passes; "case4" not in whitelist
v=$(verify_gate_decision "case4" 2 "$WHITELIST" 2>/dev/null)
echo "  verdict: $v"
if [ "$v" = "red-bug-required" ]; then
  pass "non-whitelisted persistent failure triggers bug-protocol"
else
  fail "expected red-bug-required, got '$v'"
fi

# ---------------------------------------------------------------------------
# Case 5 — flake_retries=0 → immediate red-bug-required, no retry
# ---------------------------------------------------------------------------
echo
echo "── Case 5: flake_retries=0 → immediate decision ──"
simulate_test "case5" 9999
v=$(verify_gate_decision "case5" 0 "$WHITELIST" 2>/dev/null)
echo "  verdict: $v"
if [ "$v" = "red-bug-required" ]; then
  pass "zero retries → immediate red-bug-required"
else
  fail "expected red-bug-required with retries=0, got '$v'"
fi

attempts5=$(cat "$WORK/attempt-case5")
if [ "$attempts5" = "1" ]; then
  pass "runner invoked exactly once (no retries)"
else
  fail "expected exactly 1 invocation, got $attempts5"
fi

# ---------------------------------------------------------------------------
# Case 6 — Config missing (empty whitelist file, default retries=2)
# ---------------------------------------------------------------------------
echo
echo "── Case 6: empty/missing whitelist + defaults ──"
simulate_test "case6_recovers" 2     # recovers on retry 1
v=$(verify_gate_decision "case6_recovers" 2 "$EMPTY_WHITELIST" 2>/dev/null)
if [ "$v" = "flake-recovered" ]; then
  pass "defaults: flake recovers on retry"
else
  fail "expected flake-recovered, got '$v'"
fi

simulate_test "case6_persistent" 9999  # never passes
v=$(verify_gate_decision "case6_persistent" 2 "$EMPTY_WHITELIST" 2>/dev/null)
if [ "$v" = "red-bug-required" ]; then
  pass "defaults: persistent failure + empty whitelist → bug-protocol"
else
  fail "expected red-bug-required, got '$v'"
fi

# Also sanity-check: passes-on-first-try → green.
echo
echo "── Bonus sanity: first-try pass → green ──"
simulate_test "happy" 1
v=$(verify_gate_decision "happy" 2 "$WHITELIST" 2>/dev/null)
if [ "$v" = "green" ]; then
  pass "first-attempt pass → green"
else
  fail "expected green, got '$v'"
fi

# ---------------------------------------------------------------------------
# Cleanup + verdict
# ---------------------------------------------------------------------------
rm -rf "$WORK"

echo
if [ "$fails" -eq 0 ]; then
  echo "PASS — all 6 cases (and bonus) match documented decision tree."
  exit 0
else
  echo "FAIL — $fails assertion(s) failed."
  exit 1
fi
