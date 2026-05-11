#!/usr/bin/env bash
# audit.sh — cross-reference a phase directive against commits made
# during/after that phase. Smarter version: parses the directive's commit-pattern
# section, file references, and test references; checks each against git log.
# Heuristic — meant for spot-checks, not formal verification.
#
# Usage: audit.sh <workspace> <phase-number> [--since=N]
#   N defaults to "20 commits ago" (HEAD~20). Use a higher number if the
#   phase has more commits, or override with e.g. --since=HEAD~50.
set -euo pipefail
WS="${1:?usage: audit.sh <workspace> <phase-number>}"
PHASE="${2:?usage: audit.sh <workspace> <phase-number>}"
SINCE="${3:-HEAD~20}"
SINCE="${SINCE#--since=}"

DIR_FILE="$WS/.cc/phase-$PHASE.md"
if [ ! -f "$DIR_FILE" ]; then
  echo "[audit] no directive at $DIR_FILE"
  exit 1
fi
cd "$WS"

echo "============================================================"
echo "  AUDIT: Phase $PHASE"
echo "  Directive: $DIR_FILE"
echo "  Range:     $SINCE..HEAD"
echo "============================================================"
echo

# 1. Commits in range
echo "── Commits in range ──"
git log --oneline "$SINCE..HEAD" 2>/dev/null | sed 's/^/  /'
N_COMMITS=$(git log --oneline "$SINCE..HEAD" 2>/dev/null | wc -l | tr -d ' ')
echo
echo "  Total: $N_COMMITS commits"
echo

# 2. Expected commit messages from directive
echo "── Expected commit messages (from directive § Commit pattern) ──"
EXPECTED=$(awk '/^## *Commit pattern/,/^## /' "$DIR_FILE" | grep -oE '`[a-zA-Z][a-zA-Z0-9_./()+-]*: [^`]+`' | tr -d '`' | sed 's/^/  - /' || true)
if [ -z "$EXPECTED" ]; then
  echo "  _(no commit-pattern section found)_"
else
  echo "$EXPECTED"
fi
echo

# 3. Of those, how many exist in git log?
echo "── Commits matched ──"
MATCHED=0
TOTAL=0
echo "$EXPECTED" | while read -r line; do
  [ -z "$line" ] && continue
  PATTERN=$(echo "$line" | sed 's/^  - //; s/(/\\(/g; s/)/\\)/g')
  TOTAL=$((TOTAL + 1))
  HIT=$(git log --oneline "$SINCE..HEAD" --grep="$PATTERN" 2>/dev/null | head -1)
  if [ -n "$HIT" ]; then
    echo "  ✓ $line"
    echo "      → $HIT"
  else
    echo "  ✗ $line  (NOT FOUND in $SINCE..HEAD)"
  fi
done
echo

# 4. Files mentioned in directive vs files changed
echo "── Files in directive ──"
DIR_FILES=$(grep -oE '`[a-zA-Z0-9_./-]+\.(py|ts|tsx|md|sql|yaml|yml|json|toml|sh)`' "$DIR_FILE" | sort -u | tr -d '`' | sed 's/^/  /' || true)
echo "$DIR_FILES"
echo

echo "── Files changed in range ──"
CHANGED=$(git log --name-only --pretty=format: "$SINCE..HEAD" 2>/dev/null | sort -u | grep -v '^$' | sed 's/^/  /')
echo "$CHANGED"
echo

# 5. Files in directive but not changed
echo "── ⚠ Mentioned but NOT changed ──"
echo "$DIR_FILES" | tr -d ' ' | while read -r f; do
  [ -z "$f" ] && continue
  if ! echo "$CHANGED" | grep -qF "$f"; then
    echo "  ⚠ $f"
  fi
done
echo

# 6. Test count delta
echo "── Test files mentioned ──"
DIR_TESTS=$(grep -oE '`tests?/[a-zA-Z0-9_./-]+\.py`' "$DIR_FILE" | sort -u | tr -d '`' | sed 's/^/  /' || true)
if [ -n "$DIR_TESTS" ]; then
  echo "$DIR_TESTS"
else
  echo "  _(no specific test files mentioned)_"
fi
echo

echo "── Audit complete ──"
