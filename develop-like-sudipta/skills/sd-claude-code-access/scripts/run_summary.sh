#!/usr/bin/env bash
# run_summary.sh — synthesize a session summary from state.json + git log.
# Output: <workspace>/.cc/runs/<timestamp>.md
# Usage: run_summary.sh <workspace>
set -euo pipefail
WS="${1:?usage: run_summary.sh <workspace>}"
mkdir -p "$WS/.cc/runs"
TS=$(date -u +%Y-%m-%dT%H-%M-%SZ)
OUT="$WS/.cc/runs/$TS.md"

cd "$WS"
{
  echo "# Run summary — $TS"
  echo
  echo "## State events (count by type)"
  if [ -f .cc/state.json ]; then
    awk -F'"event":"' '/event/{split($2,a,"\""); print a[1]}' .cc/state.json | sort | uniq -c | sort -rn
  else
    echo "_(no state.json yet)_"
  fi
  echo
  echo "## Phases observed"
  if [ -f .cc/state.json ]; then
    grep -oE '"phase":"[^"]*"' .cc/state.json | sort -u | sed 's/"phase":"\(.*\)"/  - \1/'
  fi
  echo
  echo "## Commits during this run"
  # Heuristic: commits since first state.json event
  if [ -f .cc/state.json ]; then
    FIRST_TS=$(head -1 .cc/state.json | grep -oE '"ts":"[^"]*"' | sed 's/"ts":"//;s/"$//')
    if [ -n "$FIRST_TS" ]; then
      echo "Since $FIRST_TS:"
      echo
      git log --oneline --since="$FIRST_TS" 2>/dev/null | sed 's/^/  /'
      echo
      echo "**Total: $(git log --oneline --since="$FIRST_TS" 2>/dev/null | wc -l | tr -d ' ') commits**"
    fi
  else
    echo "Last 20 commits:"
    git log --oneline -20 | sed 's/^/  /'
  fi
  echo
  echo "## Danger blocks"
  if [ -f .cc/state.json ]; then
    grep '"event":"danger_blocked"' .cc/state.json | sed 's/^/  - /' || echo "  _(none)_"
  fi
  echo
  echo "## Nudges sent"
  if [ -f .cc/state.json ]; then
    grep '"event":"nudge_sent"' .cc/state.json | sed 's/^/  - /' || echo "  _(none)_"
  fi
  echo
  echo "## Test count"
  if [ -d .venv ]; then
    .venv/bin/pytest --collect-only -q 2>/dev/null | tail -3 | sed 's/^/  /' || echo "  _(pytest not available)_"
  fi
  echo
  echo "## Listed deferred items in STATUS.md"
  if [ -f STATUS.md ]; then
    awk '/Deferred|deferred|V2/,/^##|^$/' STATUS.md | head -30 | sed 's/^/  /' || echo "  _(no V2 list)_"
  fi
} > "$OUT"

echo "[run_summary] wrote $OUT"
echo "  $(wc -l < "$OUT") lines"
