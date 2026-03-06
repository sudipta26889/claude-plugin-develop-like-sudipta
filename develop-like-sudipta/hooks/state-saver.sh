#!/usr/bin/env bash
# State Saver — PreCompact hook
# Saves current session state to .claude/plans/ before context compaction.
# Ensures progress can be rebuilt after context loss.

set -euo pipefail

GIT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || echo "$HOME")
PLANS_DIR="$GIT_ROOT/.claude/plans"
if ! mkdir -p "$PLANS_DIR" 2>/dev/null; then
  echo "{\"additionalContext\": \"[STATE SAVER] Cannot create plans directory at $PLANS_DIR. Check permissions.\"}"
  exit 0
fi

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
STATE_FILE="$PLANS_DIR/auto-save-${TIMESTAMP}.md"

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

  # Existing plan files
  if ls "$PLANS_DIR"/*.md &>/dev/null; then
    echo "## Active Plans"
    for plan in "$PLANS_DIR"/*.md; do
      [ "$plan" = "$STATE_FILE" ] && continue
      echo "- $(basename "$plan")"
    done
    echo ""
  fi

  echo "## Recovery Instructions"
  echo "After compaction, read this file to restore context."
  echo "Then read the active plan file(s) listed above."
} > "$STATE_FILE"

echo "{\"additionalContext\": \"Session state saved to ${STATE_FILE} before compaction.\"}"
