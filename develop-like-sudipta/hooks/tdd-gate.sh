#!/usr/bin/env bash
# TDD Gate — PreToolUse hook for Write/Edit/MultiEdit
# Checks if a test file exists before allowing production code edits.
# Returns additionalContext if no test found, reminding about TDD.

set -euo pipefail

# Early dependency check
if ! command -v python3 &>/dev/null; then
  echo "{\"additionalContext\": \"[TDD GATE] python3 is required but not found. Install Python 3.8+ first.\"}"
  exit 0
fi

# Cache git root to avoid repeated syscalls
GIT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || echo "")

# Read tool input from stdin
INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | python3 -c "
import json, sys
data = json.load(sys.stdin)
# Handle different tool input formats
print(data.get('file_path', data.get('path', '')))
" 2>/dev/null || echo "")

# Skip if we couldn't extract file path
[ -z "$FILE_PATH" ] && exit 0

# Skip non-code files (configs, docs, tests themselves)
case "$FILE_PATH" in
  *test_*|*_test.*|*tests/*|*.test.*|*spec.*|*__tests__/*)
    exit 0 ;;  # This IS a test file — allow
  *.md|*.rst|*.txt|*.json|*.yaml|*.yml|*.toml|*.ini|*.cfg)
    exit 0 ;;  # Config/docs — no test needed
  *.env*|*Dockerfile*|*docker-compose*|*.gitignore)
    exit 0 ;;  # Infra files — no test needed
  *.css|*.scss|*.html|*.svg|*.png|*.jpg)
    exit 0 ;;  # Assets — no test needed
esac

# Extract module name and look for corresponding test file
BASENAME=$(basename "$FILE_PATH")
DIRNAME=$(dirname "$FILE_PATH")
EXTENSION="${BASENAME##*.}"
NAME_NO_EXT="${BASENAME%.*}"

TEST_EXISTS=false

# Python: look for test_<name>.py or <name>_test.py
if [ "$EXTENSION" = "py" ]; then
  for pattern in "test_${NAME_NO_EXT}.py" "${NAME_NO_EXT}_test.py"; do
    # Check same dir, tests/ subdir, and tests/ at project root
    for dir in "$DIRNAME" "$DIRNAME/tests" "$GIT_ROOT/tests"; do
      [ -f "$dir/$pattern" ] 2>/dev/null && TEST_EXISTS=true && break 2
    done
  done
fi

# TypeScript/JavaScript: look for <name>.test.ts or <name>.spec.ts
if [ "$EXTENSION" = "ts" ] || [ "$EXTENSION" = "tsx" ] || [ "$EXTENSION" = "js" ] || [ "$EXTENSION" = "jsx" ]; then
  for suffix in "test" "spec"; do
    for dir in "$DIRNAME" "$DIRNAME/__tests__" "$GIT_ROOT/tests"; do
      [ -f "$dir/${NAME_NO_EXT}.${suffix}.${EXTENSION}" ] 2>/dev/null && TEST_EXISTS=true && break 2
    done
  done
fi

# Go: look for <name>_test.go
if [ "$EXTENSION" = "go" ]; then
  [ -f "$DIRNAME/${NAME_NO_EXT}_test.go" ] 2>/dev/null && TEST_EXISTS=true
fi

if [ "$TEST_EXISTS" = false ]; then
  # Return additionalContext — Claude sees this as guidance
  python3 -c "
import json, sys
msg = '[TDD GATE] ⚠️ No test file found for ' + repr(sys.argv[1]) + '. Pillar 5 requires: write a FAILING test first (RED phase) before editing production code. Create test_' + sys.argv[2] + '.py (or equivalent) with the expected behavior, verify it FAILS, then proceed with this edit.'
print(json.dumps({'additionalContext': msg}))
" "$BASENAME" "$NAME_NO_EXT" 2>/dev/null || cat <<EOF
{
  "additionalContext": "[TDD GATE] No test file found. Write a failing test first."
}
EOF
fi
