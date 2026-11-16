#!/usr/bin/env bash
# Completion Gate — Stop hook
# Runs after every assistant reply. Checks:
# 1. No orphaned TODOs in changed files (always, cheap)
# 2. Test suite + coverage — ONLY when COMPLETION_GATE_RUN_TESTS=1.
#    Full suites can take minutes, so they are the verify step of the workflow
#    (/implement), not a per-reply hook. When opted in, failure is judged by
#    exit code, and hooks.json caps the whole hook at 120 s.
# Only runs if we're in a git repo.

set -euo pipefail

# Only run if in a git repo
GIT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || echo "")
[ -z "$GIT_ROOT" ] && exit 0

WARNINGS=""

if [ "${COMPLETION_GATE_RUN_TESTS:-0}" = "1" ]; then
  # --- 1. TEST SUITE CHECK ---
  # Python: pytest, stop at first failure
  if [ -d "$GIT_ROOT/tests" ] || [ -d "$GIT_ROOT/test" ]; then
    if command -v pytest &>/dev/null; then
      if ! (cd "$GIT_ROOT" && pytest -x --tb=no --no-header -q >/dev/null 2>&1); then
        WARNINGS="${WARNINGS}[COMPLETION GATE] ⚠️ Tests FAILING. Cannot claim done with broken tests. "
      fi
    fi
  fi

  # Node: package.json with a test script. Jest/vitest get a 3-worker cap.
  if [ -f "$GIT_ROOT/package.json" ]; then
    TEST_CMD=$(python3 -c "
import json, sys
with open(sys.argv[1]) as f:
    t = json.load(f).get('scripts', {}).get('test', '')
if not t:
    print('none')
elif 'jest' in t or 'vitest' in t:
    print('capped')
else:
    print('plain')
" "$GIT_ROOT/package.json" 2>/dev/null || echo "none")
    if [ "$TEST_CMD" = "capped" ]; then
      (cd "$GIT_ROOT" && npm test --silent -- --maxWorkers=3 >/dev/null 2>&1) || \
        WARNINGS="${WARNINGS}[COMPLETION GATE] ⚠️ npm tests FAILING. Fix before claiming done. "
    elif [ "$TEST_CMD" = "plain" ]; then
      (cd "$GIT_ROOT" && npm test --silent >/dev/null 2>&1) || \
        WARNINGS="${WARNINGS}[COMPLETION GATE] ⚠️ npm tests FAILING. Fix before claiming done. "
    fi
  fi

  # --- 2. COVERAGE CHECK ---
  if command -v pytest &>/dev/null && command -v coverage &>/dev/null; then
    if ! COV_RESULT=$(cd "$GIT_ROOT" && coverage report --fail-under=80 2>&1); then
      COV_PCT=$(echo "$COV_RESULT" | grep -oE '[0-9]+%' | tail -1 || echo "unknown")
      WARNINGS="${WARNINGS}[COMPLETION GATE] Coverage at ${COV_PCT} (below 80% threshold). Add more tests. "
    fi
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
