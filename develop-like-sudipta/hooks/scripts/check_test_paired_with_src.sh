#!/usr/bin/env bash
# check_test_paired_with_src.sh — pre-commit git hook.
#
# Purpose: refuse a commit that touches production code under
# src/, lib/, app/, pkg/, or internal/ without staging at least one
# test file in the same commit. Bug-driven TDD requires the failing
# test to land alongside (or before) the fix — never after.
#
# Installation (per workspace):
#   cp develop-like-sudipta/hooks/scripts/check_test_paired_with_src.sh \
#      <workspace>/.git/hooks/pre-commit
#   chmod +x <workspace>/.git/hooks/pre-commit
#
# Bypass (use sparingly):
#   TDD_HOOK_BYPASS=1 git commit ...
#
# Exit codes:
#   0  — pure test commit, pure docs/config commit, src+test paired, or bypass
#   1  — src changes staged with NO test changes
#   2  — environment / git error

set -u

# Bypass for emergencies (refactor sweeps, dependency bumps, etc.).
if [ "${TDD_HOOK_BYPASS:-}" = "1" ]; then
  echo "[check_test_paired_with_src] TDD_HOOK_BYPASS=1 set — skipping test-pairing check." >&2
  exit 0
fi

# List staged files (added / copied / modified / renamed).
STAGED=$(git diff --cached --name-only --diff-filter=ACMR 2>/dev/null || true)
if [ -z "$STAGED" ]; then
  # Nothing staged — let git handle the "no changes" case itself.
  exit 0
fi

# Production-code path patterns. We anchor with ^ so we match top-level dirs.
# Adjust this list if your project keeps code elsewhere.
CODE_REGEX='^(src|lib|app|pkg|internal)/'

# Test path patterns. Anchored where reasonable; the basename patterns
# (_test., .test., .spec.) match anywhere in the path.
#   - top-level test dirs: tests/, test/
#   - nested __tests__/ (Jest convention)
#   - Go's _test.go suffix
#   - JS/TS .test. and .spec. infixes
TEST_REGEX='(^tests/|^test/|/__tests__/|_test\.|\.test\.|\.spec\.)'

CODE_CHANGES=$(printf '%s\n' "$STAGED" | grep -E "$CODE_REGEX" | grep -vE "$TEST_REGEX" || true)
TEST_CHANGES=$(printf '%s\n' "$STAGED" | grep -E "$TEST_REGEX" || true)

# Case 1: no code changes at all → allow (pure docs / config / tests).
if [ -z "$CODE_CHANGES" ]; then
  exit 0
fi

# Case 2: code changes AND test changes both present → allow.
if [ -n "$TEST_CHANGES" ]; then
  exit 0
fi

# Case 3: code changes, NO test changes → refuse.
echo "[check_test_paired_with_src] staged changes touch production code but no test files:" >&2
printf '%s\n' "$CODE_CHANGES" | sed 's/^/    /' >&2
echo >&2
echo "  Bug-driven-TDD requires failing-test-first (see references/bug_driven_tdd.md)." >&2
echo "  Stage a test file (tests/, test/, __tests__/, _test., .test., .spec.)" >&2
echo "  or set TDD_HOOK_BYPASS=1 if this commit is genuinely test-less" >&2
echo "  (rare — refactor sweeps and dependency bumps are the usual exceptions)." >&2
exit 1
