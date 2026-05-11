#!/usr/bin/env bash
# check_no_hardcoded_paths.sh — pre-commit hook that fails the commit if any
# staged file under the plugin tree contains a /Users/<name>/ hardcoded path.
#
# Why: v4.3.3 shipped scheduled-task SKILLs with `/Users/sudipta/Workspace/...`
# baked in — the cron-triggered tasks would have silently failed on every
# other machine. This catches the regression at commit time.
#
# Trigger pattern: `/Users/<anything>/`
# Exempt: this hook itself (it needs the literal pattern as documentation).
#
# Install: bash develop-like-sudipta/hooks/scripts/install_precommit_path_check.sh

set -uo pipefail

PATTERN='/Users/[A-Za-z0-9._-]+/'

# Only check files under the plugin tree that are likely to ship to users.
SHIP_DIRS=(
  "develop-like-sudipta/.claude-plugin"
  "develop-like-sudipta/agents"
  "develop-like-sudipta/commands"
  "develop-like-sudipta/skills"
  "develop-like-sudipta/assets"
  "develop-like-sudipta/hooks"
)

# Files to skip even within ship dirs:
# - this script itself + its README (documents the bad pattern)
# - test fixtures
EXEMPT_PATHS=(
  "develop-like-sudipta/hooks/scripts/check_no_hardcoded_paths.sh"
  "develop-like-sudipta/hooks/scripts/install_precommit_path_check.sh"
  "develop-like-sudipta/skills/sd-claude-code-access/evals"
  "develop-like-sudipta/skills/develop-like-sudipta/evals"
  "develop-like-sudipta/skills/code-hacker/evals"
)

is_exempt() {
  local f="$1"
  for ex in "${EXEMPT_PATHS[@]}"; do
    case "$f" in "$ex"*) return 0 ;; esac
  done
  return 1
}

is_in_ship_dir() {
  local f="$1"
  for d in "${SHIP_DIRS[@]}"; do
    case "$f" in "$d"/*) return 0 ;; esac
  done
  return 1
}

# Get staged files (added or modified). Pre-commit hook context.
STAGED=$(git diff --cached --name-only --diff-filter=ACM)

PROBLEMS=0
while IFS= read -r f; do
  [ -z "$f" ] && continue
  is_in_ship_dir "$f" || continue
  is_exempt "$f" && continue
  if grep -nHE "$PATTERN" "$f" 2>/dev/null; then
    PROBLEMS=$((PROBLEMS+1))
  fi
done <<< "$STAGED"

if [ "$PROBLEMS" -gt 0 ]; then
  cat >&2 <<EOF

============================================================
[pre-commit] HARDCODED PATH(S) DETECTED — refusing commit
============================================================
$PROBLEMS file(s) contain '/Users/<name>/' hardcodes. These will
break the plugin on any other machine.

Fix:
  - Use \$HOME or ~/  (e.g. ~/Workspace/... instead of /Users/sudipta/Workspace/...)
  - Use \${CLAUDE_PLUGIN_ROOT} for plugin-relative refs
  - Use \${CCBRIDGE_HOME:-\$HOME/.cache/ccbridge} for bridge refs

If a hardcoded path is legitimately intentional (e.g. illustrative
example, never executed), add the file to EXEMPT_PATHS in:
  develop-like-sudipta/hooks/scripts/check_no_hardcoded_paths.sh

Bypass once with --no-verify (NOT recommended).
EOF
  exit 1
fi

exit 0
