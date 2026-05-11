#!/usr/bin/env bash
# install_precommit_path_check.sh — install check_no_hardcoded_paths.sh as
# a git pre-commit hook in the plugin's own repo.
#
# Idempotent: re-running overwrites the hook script (cp -f) but never
# duplicates installs.

set -euo pipefail

REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || {
  echo "[install-precommit] ERROR: not inside a git repo" >&2
  exit 1
}

HOOK_SRC="$REPO_ROOT/develop-like-sudipta/hooks/scripts/check_no_hardcoded_paths.sh"
HOOK_DEST="$REPO_ROOT/.git/hooks/pre-commit"

if [ ! -f "$HOOK_SRC" ]; then
  echo "[install-precommit] ERROR: source missing at $HOOK_SRC" >&2
  exit 1
fi

# Wrap the hook so we can chain with any existing pre-commit logic later.
# For now, just point pre-commit at our script directly.
cp -f "$HOOK_SRC" "$HOOK_DEST"
chmod +x "$HOOK_DEST"

echo "[install-precommit] installed: $HOOK_DEST"
echo "  → scans staged files under develop-like-sudipta/{commands,skills,assets,agents,hooks,.claude-plugin}"
echo "  → fails commit on /Users/<name>/ hardcodes"
echo "  → bypass with: git commit --no-verify (NOT recommended)"
