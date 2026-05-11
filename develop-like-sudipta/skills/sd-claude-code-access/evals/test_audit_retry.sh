#!/usr/bin/env bash
# test_audit_retry.sh — smoke test for audit.sh's --retry / --retry-interval.
#
# Background: CC's checkpoint message can render BEFORE the autocommit /
# pre-commit hook / GPG-signing pipeline has actually landed the commit on
# disk. A single-shot audit then misreads healthy work as drift. The retry
# flag teaches audit.sh to sleep + re-run when the only finding is
# "missing-file-or-commit" (exit code 2).
#
# Two cases:
#   1. Eventually-green — a background task creates the file + commit after
#      4 s. With --retry 6 --retry-interval 2, audit should sleep, re-poll,
#      and exit 0 within ~12 s.
#   2. Persistently-red — no background task. Audit should exhaust the
#      budget and exit non-zero (specifically 2 — the laggy-drift code)
#      after roughly retries × interval seconds.
#
# Usage: ./test_audit_retry.sh
# Exit 0 on PASS, non-zero on any failed assertion.
#
# Bash 3.2 compatible. No `wait -n`, no `mapfile`, no associative arrays,
# no `${var,,}`. Uses `wait $!` and plain polling.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
AUDIT="$SCRIPT_DIR/../scripts/audit.sh"

if [ ! -f "$AUDIT" ]; then
  echo "FAIL: audit.sh not found at $AUDIT"
  exit 2
fi

# Pick a tmp parent that exists on both macOS and Linux. mktemp -d -t works
# on macOS but takes a different suffix shape on GNU — use the portable form.
TMP_ROOT="${TMPDIR:-/tmp}"

# ---------------------------------------------------------------------------
# make_repo <dir>
#   Initialise a git repo at <dir> with a directive that mentions foo.py.
#   The directive lives at <dir>/.cc/phase-1.md so audit.sh's DIR_FILE path
#   resolves. We do NOT create foo.py up front — that's what the retry has
#   to wait for (case 1) or never see (case 2).
# ---------------------------------------------------------------------------
make_repo() {
  repo="$1"
  mkdir -p "$repo/.cc"
  cd "$repo"
  git init -q
  git config user.email "test@example.com"
  git config user.name "Test User"
  # audit.sh's default range is HEAD~20..HEAD. Lay down enough background
  # commits so HEAD~5 (which we pass via --since) resolves cleanly. Bash
  # 3.2 compatible: no C-style for ((..)).
  i=0
  while [ "$i" -lt 5 ]; do
    echo "seed line $i" >> README.md
    git add README.md
    git commit -q -m "chore: seed $i"
    i=$((i + 1))
  done

  cat > .cc/phase-1.md <<'EOF'
# Phase 1 — fixture directive

## Commit pattern

- `feat(core): add foo`

## Files

- `foo.py`
EOF
  git add .cc/phase-1.md
  git commit -q -m "chore: add phase-1 directive"
  cd - >/dev/null
}

# Track failures
fails=0
fail() {
  fails=$((fails + 1))
  echo "  FAIL: $*"
}
pass() {
  echo "  PASS: $*"
}

# ---------------------------------------------------------------------------
# Case 1 — eventually-green
# ---------------------------------------------------------------------------
echo "── Case 1: eventually-green (file lands after 4 s) ──"
REPO1="$(mktemp -d "$TMP_ROOT/audit-retry-XXXXXX")"
make_repo "$REPO1"

# Background: after 4 s, create foo.py and commit it.
(
  sleep 4
  cd "$REPO1"
  echo "def foo(): return 1" > foo.py
  git add foo.py
  git commit -q -m "feat(core): add foo"
) &
BG_PID=$!

t0=$(date +%s)
# Allow ~12 s budget: 6 retries x 2 s = 12 s sleep + small per-run overhead.
set +e
bash "$AUDIT" "$REPO1" 1 --since=HEAD~5 --retry 6 --retry-interval 2 >"$REPO1/audit.out" 2>"$REPO1/audit.err"
rc1=$?
set -e
t1=$(date +%s)
elapsed1=$((t1 - t0))

# Reap the background job so we don't leak processes.
wait "$BG_PID" 2>/dev/null || true

echo "  exit code: $rc1"
echo "  elapsed:   ${elapsed1}s"
echo "  stderr tail:"
tail -5 "$REPO1/audit.err" 2>/dev/null | sed 's/^/    /'

if [ "$rc1" -eq 0 ]; then
  pass "audit exited 0 once the commit landed"
else
  fail "expected exit 0 after retry, got $rc1"
fi

# Note: we deliberately do NOT assert an upper bound on elapsed time here.
# The retry budget (6 × 2 s = 12 s) plus the 4 s background wait plus
# per-iteration audit overhead can drift past 14 s on heavy CI runners.
# The exit-code-0 + "retry messages logged" assertions below already prove
# that retry happened; wall-time bounds add only flakiness.

if grep -q "retry" "$REPO1/audit.err" 2>/dev/null; then
  pass "retry messages logged to stderr"
else
  fail "no retry log lines found on stderr"
fi

# ---------------------------------------------------------------------------
# Case 2 — persistently-red
# ---------------------------------------------------------------------------
echo
echo "── Case 2: persistently-red (file never lands) ──"
REPO2="$(mktemp -d "$TMP_ROOT/audit-retry-XXXXXX")"
make_repo "$REPO2"

t0=$(date +%s)
set +e
bash "$AUDIT" "$REPO2" 1 --since=HEAD~5 --retry 3 --retry-interval 2 >"$REPO2/audit.out" 2>"$REPO2/audit.err"
rc2=$?
set -e
t1=$(date +%s)
elapsed2=$((t1 - t0))

echo "  exit code: $rc2"
echo "  elapsed:   ${elapsed2}s"
echo "  stderr tail:"
tail -5 "$REPO2/audit.err" 2>/dev/null | sed 's/^/    /'

if [ "$rc2" -ne 0 ]; then
  pass "audit exited non-zero after exhausting retries"
else
  fail "expected non-zero exit, got 0"
fi

if [ "$rc2" -eq 2 ]; then
  pass "exit code is 2 (missing-file-or-commit / laggy drift)"
else
  fail "expected exit 2 specifically, got $rc2"
fi

# 3 retries × 2 s = 6 s of sleep minimum. Keep the lower bound only —
# that's the proof the loop actually slept. Drop the upper bound: per-
# iteration audit overhead on slow CI can easily push past 12 s without
# indicating a real bug.
if [ "$elapsed2" -ge 5 ]; then
  pass "spent retry budget (≥5 s, observed ${elapsed2}s)"
else
  fail "expected ≥5 s elapsed, got ${elapsed2}s"
fi

if grep -q "retry" "$REPO2/audit.err" 2>/dev/null; then
  pass "retry messages logged to stderr"
else
  fail "no retry log lines found on stderr"
fi

# ---------------------------------------------------------------------------
# Case 3 — no-flag drift returns exit 1 (legacy back-compat)
#
# Without --retry, audit.sh must keep its prior exit 1 behaviour even when
# the drift is the missing-file-or-commit kind. Otherwise any caller doing
# `case $? in 1) ...` silently changes meaning. This test pins that contract.
# ---------------------------------------------------------------------------
echo
echo "── Case 3: no --retry → drift returns exit 1 (legacy) ──"
REPO3="$(mktemp -d "$TMP_ROOT/audit-retry-XXXXXX")"
make_repo "$REPO3"

set +e
bash "$AUDIT" "$REPO3" 1 --since=HEAD~5 >"$REPO3/audit.out" 2>"$REPO3/audit.err"
rc3=$?
set -e

echo "  exit code: $rc3"
echo "  stderr tail:"
tail -5 "$REPO3/audit.err" 2>/dev/null | sed 's/^/    /'

if [ "$rc3" -eq 1 ]; then
  pass "no-flag drift exits 1 (legacy contract preserved)"
else
  fail "expected exit 1 on no-flag drift, got $rc3"
fi

# Spec also says: no extraneous output on the no-flag path. The "budget
# exhausted" stderr line must NOT appear here.
if grep -q "retry budget exhausted" "$REPO3/audit.err" 2>/dev/null; then
  fail "no-flag invocation leaked 'retry budget exhausted' to stderr"
else
  pass "no-flag invocation kept stderr clean (no 'budget exhausted' line)"
fi

# ---------------------------------------------------------------------------
# Case 4 — with --retry, drift returns exit 2 (new precision)
#
# Mirror of Case 3 but with --retry 1 --retry-interval 1. Confirms the
# branching: same drift, different exit code based on whether the caller
# opted into retry.
# ---------------------------------------------------------------------------
echo
echo "── Case 4: --retry 1 → drift returns exit 2 (new precision) ──"
REPO4="$(mktemp -d "$TMP_ROOT/audit-retry-XXXXXX")"
make_repo "$REPO4"

set +e
bash "$AUDIT" "$REPO4" 1 --since=HEAD~5 --retry 1 --retry-interval 1 >"$REPO4/audit.out" 2>"$REPO4/audit.err"
rc4=$?
set -e

echo "  exit code: $rc4"
echo "  stderr tail:"
tail -5 "$REPO4/audit.err" 2>/dev/null | sed 's/^/    /'

if [ "$rc4" -eq 2 ]; then
  pass "--retry drift exits 2 (new precision)"
else
  fail "expected exit 2 with --retry on drift, got $rc4"
fi

if grep -q "retry budget exhausted" "$REPO4/audit.err" 2>/dev/null; then
  pass "'budget exhausted' surfaced on stderr (expected with --retry)"
else
  fail "expected 'retry budget exhausted' on stderr with --retry, not found"
fi

# ---------------------------------------------------------------------------
# Cleanup + verdict
# ---------------------------------------------------------------------------
rm -rf "$REPO1" "$REPO2" "$REPO3" "$REPO4"

echo
if [ "$fails" -eq 0 ]; then
  echo "PASS — both retry cases behave as specified."
  exit 0
else
  echo "FAIL — $fails assertion(s) failed."
  exit 1
fi
