#!/usr/bin/env bash
# State Saver — PreCompact hook
# Saves current session state to .claude/state/autosaves/ before context compaction.
# Ensures progress can be rebuilt after context loss.
#
# WHY .claude/state/autosaves/ and not .claude/plans/: these are machine-written
# session snapshots, not plans. Sitting in a directory called "plans" they get
# mistaken for hand-written implementation plans — and in a repo that keeps real
# plans under .claude/docs/plans/, two directories end up named "plans" with
# completely different contents. "state" says what this is.

set -euo pipefail

# How many autosaves to keep per repo. Older ones are pruned after each write.
# Their value decays to ~zero once the session that produced them has ended;
# without a cap this directory grows by one file per compaction, forever.
RETAIN=${STATE_SAVER_RETAIN:-10}

GIT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || echo "$HOME")
STATE_DIR="$GIT_ROOT/.claude/state/autosaves"
if ! mkdir -p "$STATE_DIR" 2>/dev/null; then
  echo "{\"additionalContext\": \"[STATE SAVER] Cannot create state directory at $STATE_DIR. Check permissions.\"}"
  exit 0
fi

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
STATE_FILE="$STATE_DIR/auto-save-${TIMESTAMP}.md"

{
  echo "# Auto-Saved State (Pre-Compaction)"
  echo "**Saved at:** $(date -Iseconds)"
  echo ""

  # Git status
  if git rev-parse --is-inside-work-tree &>/dev/null; then
    echo "## Git Status"
    echo '```'
    git status --short 2>/dev/null || true
    echo '```'
    echo ""

    echo "## Changed Files"
    echo '```'
    git diff --name-only HEAD 2>/dev/null || true
    echo '```'
    echo ""

    echo "## Current Branch"
    echo "$(git branch --show-current 2>/dev/null || echo 'unknown')"
    echo ""
  fi

  # Hand-written plans, so recovery points at real plans rather than at other
  # autosaves. Prefers an INDEX if the repo keeps one.
  PLANS_DIR="$GIT_ROOT/.claude/docs/plans"
  if [ -d "$PLANS_DIR" ] && ls "$PLANS_DIR"/*.md &>/dev/null; then
    echo "## Active Plans"
    for plan in "$PLANS_DIR"/*.md; do
      echo "- .claude/docs/plans/$(basename "$plan")"
    done
    echo ""
  fi

  echo "## Recovery Instructions"
  echo "After compaction, read this file to restore context."
  echo "Then read the active plan file(s) listed above."
} > "$STATE_FILE"

# Prune oldest autosaves beyond RETAIN. Never allowed to fail the hook — a
# pruning problem must not block compaction.
if [ "$RETAIN" -gt 0 ] 2>/dev/null; then
  ls -1t "$STATE_DIR"/auto-save-*.md 2>/dev/null | tail -n "+$((RETAIN + 1))" | while IFS= read -r old; do
    rm -f -- "$old" 2>/dev/null || true
  done || true
fi

echo "{\"additionalContext\": \"Session state saved to ${STATE_FILE} before compaction.\"}"
