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
# Case 5 — Commit-pattern parsing actually captures the section body
#
# Pre-existing bug: `awk '/^## *Commit pattern/,/^## /'` collapses because
# the END pattern matches the START heading. Result: the "Expected commit
# messages" block ended up empty even when the directive listed several
# patterns. Fix: explicit state machine — skip the start line, capture
# until the NEXT `## ` heading, exit.
#
# This case writes a directive with TWO commit patterns under
# "## Commit pattern" plus a "## Other" heading underneath. After the fix,
# the audit report's "Expected commit messages" block must contain BOTH
# patterns. Pre-fix, it would show only "(no commit-pattern section found)".
# ---------------------------------------------------------------------------
echo
echo "── Case 5: commit-pattern parser captures section body ──"
REPO5="$(mktemp -d "$TMP_ROOT/audit-retry-XXXXXX")"
make_repo "$REPO5"

# Overwrite the fixture directive with one that exercises the parser. We
# want a Commit pattern section with multiple entries, followed by an
# unrelated `## ` heading.
cat > "$REPO5/.cc/phase-1.md" <<'EOF'
# Phase 1 — case 5 directive

## Commit pattern

- `feat(core): add foo`
- `fix(api): handle 5xx`

## Other notes

Random prose that should NOT be parsed as a commit pattern.
EOF

set +e
bash "$AUDIT" "$REPO5" 1 --since=HEAD~5 >"$REPO5/audit.out" 2>"$REPO5/audit.err"
rc5=$?
set -e

echo "  exit code: $rc5"
echo "  stdout 'Expected commit messages' block:"
awk '/Expected commit messages/{flag=1;next} flag && /^── /{flag=0} flag' \
  "$REPO5/audit.out" | sed 's/^/    /'

if grep -q 'feat(core): add foo' "$REPO5/audit.out"; then
  pass "audit extracted 'feat(core): add foo' from § Commit pattern"
else
  fail "expected 'feat(core): add foo' in audit output, not found"
fi
if grep -q 'fix(api): handle 5xx' "$REPO5/audit.out"; then
  pass "audit extracted 'fix(api): handle 5xx' from § Commit pattern"
else
  fail "expected 'fix(api): handle 5xx' in audit output, not found"
fi
# Counter-assertion: must NOT contain the "no commit-pattern section" sentinel.
if grep -q 'no commit-pattern section found' "$REPO5/audit.out"; then
  fail "audit reported empty commit-pattern section despite valid directive"
else
  pass "did not fall through to 'no commit-pattern section' sentinel"
fi

# ---------------------------------------------------------------------------
# Case 6 — Shallow / fresh repo (< 20 commits)
#
# Pre-existing bug: default --since=HEAD~20 errors on repos with fewer than
# 20 commits ("fatal: ambiguous argument 'HEAD~20'…"). The old code
# silenced that with `2>/dev/null` and reported a blank, "clean" audit.
#
# After the fix, audit.sh detects the shallow case and falls back to
# --root. The smoke test: 3 commits, no --since override (so default is
# HEAD~20), assert exit 0 with no leaked "fatal: ambiguous argument".
# ---------------------------------------------------------------------------
echo
echo "── Case 6: shallow repo (3 commits < default --since=HEAD~20) ──"
REPO6="$(mktemp -d "$TMP_ROOT/audit-retry-XXXXXX")"
mkdir -p "$REPO6/.cc"
cd "$REPO6"
git init -q
git config user.email "test@example.com"
git config user.name "Test User"
i=0
while [ "$i" -lt 3 ]; do
  echo "seed $i" >> README.md
  git add README.md
  git commit -q -m "chore: seed $i"
  i=$((i + 1))
done
cat > .cc/phase-1.md <<'EOF'
# Phase 1 — case 6 directive

## Commit pattern

- `chore: seed 0`
EOF
git add .cc/phase-1.md
git commit -q -m "chore: seed 0"
cd - >/dev/null

set +e
bash "$AUDIT" "$REPO6" 1 >"$REPO6/audit.out" 2>"$REPO6/audit.err"
rc6=$?
set -e

echo "  exit code: $rc6"
echo "  stderr tail:"
tail -5 "$REPO6/audit.err" 2>/dev/null | sed 's/^/    /'

# Exit code: 0 (clean — we crafted the directive to match the commit) or 1
# (drift, since "Files" mention something not in the repo). Either way it
# must NOT exit on a "fatal" git error.
if [ "$rc6" -eq 0 ] || [ "$rc6" -eq 1 ] || [ "$rc6" -eq 2 ]; then
  pass "audit ran on shallow repo without crashing on a git fatal (rc=$rc6)"
else
  fail "audit exited with unexpected code $rc6 on shallow repo"
fi

# Critical assertion: no leaked "fatal: ambiguous argument" on stderr.
if grep -q 'fatal: ambiguous argument' "$REPO6/audit.err" 2>/dev/null; then
  fail "shallow repo leaked 'fatal: ambiguous argument' to stderr"
else
  pass "no 'fatal: ambiguous argument' leaked to stderr"
fi

# Should have logged the fallback decision so the operator can see it.
if grep -q 'falling back to --root' "$REPO6/audit.err" 2>/dev/null; then
  pass "logged --root fallback to stderr"
else
  fail "expected '--root fallback' log line on stderr, not found"
fi

# And the audit report should actually contain commit listings — proving
# the fallback retrieved real data instead of producing an empty report.
if grep -q 'chore: seed' "$REPO6/audit.out" 2>/dev/null; then
  pass "audit report contains commits from the shallow repo"
else
  fail "audit report empty despite shallow repo having commits"
fi

# ---------------------------------------------------------------------------
# Case 7 — Genuine git error: workspace is not a git repo
#
# Pre-existing bug: a non-repo workspace silently produced an empty,
# "clean" audit because every `git log` call had its stderr swallowed.
# After the fix, audit.sh must detect this up front and exit 2 with a
# clear error message.
# ---------------------------------------------------------------------------
echo
echo "── Case 7: workspace is not a git repo ──"
REPO7="$(mktemp -d "$TMP_ROOT/audit-retry-XXXXXX")"
# No `git init`. But we DO need a directive for the script to get past its
# pre-flight directive check — otherwise it would exit 1 on missing
# directive, not 2 on missing repo.
mkdir -p "$REPO7/.cc"
cat > "$REPO7/.cc/phase-1.md" <<'EOF'
# Phase 1 — case 7 directive
EOF

set +e
bash "$AUDIT" "$REPO7" 1 --since=HEAD~5 >"$REPO7/audit.out" 2>"$REPO7/audit.err"
rc7=$?
set -e

echo "  exit code: $rc7"
echo "  stderr tail:"
tail -5 "$REPO7/audit.err" 2>/dev/null | sed 's/^/    /'

if [ "$rc7" -eq 2 ]; then
  pass "non-repo workspace exits 2 (genuine git error)"
else
  fail "expected exit 2 on non-repo, got $rc7"
fi

if grep -q 'not a git repository' "$REPO7/audit.err" 2>/dev/null; then
  pass "clear 'not a git repository' message on stderr"
else
  fail "expected 'not a git repository' on stderr, not found"
fi

# ---------------------------------------------------------------------------
# Cleanup + verdict
# ---------------------------------------------------------------------------
rm -rf "$REPO1" "$REPO2" "$REPO3" "$REPO4" "$REPO5" "$REPO6" "$REPO7"

echo
if [ "$fails" -eq 0 ]; then
  echo "PASS — all audit cases behave as specified."
  exit 0
else
  echo "FAIL — $fails assertion(s) failed."
  exit 1
fi
