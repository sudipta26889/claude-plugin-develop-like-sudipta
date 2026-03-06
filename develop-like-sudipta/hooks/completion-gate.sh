#!/usr/bin/env bash
# Completion Gate — Stop hook
# Runs before agent finishes responding. Checks:
# 1. Test suite passes
# 2. Coverage meets threshold
# 3. No orphaned TODOs
# Only runs if we're in a git repo with a test suite.

set -euo pipefail

# Only run if in a git repo
GIT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || echo "")
[ -z "$GIT_ROOT" ] && exit 0

WARNINGS=""

# --- 1. TEST SUITE CHECK ---
# Python: check if pytest is available and tests directory exists
if [ -d "$GIT_ROOT/tests" ] || [ -d "$GIT_ROOT/test" ]; then
  if command -v pytest &>/dev/null; then
    TEST_RESULT=$(cd "$GIT_ROOT" && pytest --tb=no --no-header -q 2>&1 || true)
    if echo "$TEST_RESULT" | grep -q "FAILED\|ERROR"; then
      FAIL_COUNT=$(echo "$TEST_RESULT" | grep -oE '[0-9]+ failed' || echo "some")
      WARNINGS="${WARNINGS}[COMPLETION GATE] ⚠️ Tests FAILING (${FAIL_COUNT}). Cannot claim done with broken tests. "
    fi
  fi
fi

# Node: check if package.json has test script
if [ -f "$GIT_ROOT/package.json" ]; then
  HAS_TEST=$(python3 -c "
import json, sys
with open(sys.argv[1]) as f:
    d = json.load(f)
    print('yes' if 'test' in d.get('scripts', {}) else 'no')
" "$GIT_ROOT/package.json" 2>/dev/null || echo "no")
  if [ "$HAS_TEST" = "yes" ]; then
    TEST_RESULT=$(cd "$GIT_ROOT" && npm test --silent 2>&1 || true)
    if echo "$TEST_RESULT" | grep -qi "fail\|error"; then
      WARNINGS="${WARNINGS}[COMPLETION GATE] ⚠️ npm tests FAILING. Fix before claiming done. "
    fi
  fi
fi

# --- 2. COVERAGE CHECK ---
if command -v pytest &>/dev/null && command -v coverage &>/dev/null; then
  COV_RESULT=$(cd "$GIT_ROOT" && coverage report --fail-under=80 2>&1 || true)
  if echo "$COV_RESULT" | grep -q "FAIL"; then
    COV_PCT=$(echo "$COV_RESULT" | grep -oE '[0-9]+%' | tail -1 || echo "unknown")
    WARNINGS="${WARNINGS}[COMPLETION GATE] Coverage at ${COV_PCT} (below 80% threshold). Add more tests. "
  fi
fi

# --- 3. TODO CHECK ---
# Only check files modified in this session (staged + unstaged)
CHANGED_FILES=$(cd "$GIT_ROOT" && git diff --name-only HEAD 2>/dev/null || true)
if [ -n "$CHANGED_FILES" ]; then
  TODO_COUNT=0
  while IFS= read -r f; do
    [ -f "$GIT_ROOT/$f" ] && TODO_COUNT=$((TODO_COUNT + $(grep -c "TODO" "$GIT_ROOT/$f" 2>/dev/null || echo 0)))
  done <<< "$CHANGED_FILES"
  if [ "$TODO_COUNT" -gt 0 ]; then
    WARNINGS="${WARNINGS}[COMPLETION GATE] ${TODO_COUNT} TODO(s) found in changed files. Ensure each has a ticket/plan reference. "
  fi
fi

# Output
if [ -n "$WARNINGS" ]; then
  ESCAPED=$(echo "$WARNINGS" | python3 -c "import json,sys; print(json.dumps(sys.stdin.read().strip()))")
  if [ $? -ne 0 ]; then
    echo "{\"additionalContext\": \"[COMPLETION GATE] Warnings detected but could not be JSON-encoded. Ensure python3 is available.\"}"
    exit 0
  fi
  echo "{\"additionalContext\": ${ESCAPED}}"
fi
