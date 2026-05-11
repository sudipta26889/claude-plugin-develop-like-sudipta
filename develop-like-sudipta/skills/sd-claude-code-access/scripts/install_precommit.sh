#!/usr/bin/env bash
# install_precommit.sh — install a pre-commit hook in <workspace> that
# refuses to commit anything under .cc/ (Cowork's scratch directives).
# Idempotent — refuses to overwrite an existing custom hook unless --force.
#
# Usage:
#   install_precommit.sh <workspace>          # safe install
#   install_precommit.sh <workspace> --force  # overwrite existing hook
set -euo pipefail
WS="${1:?usage: install_precommit.sh <workspace> [--force]}"
FORCE="${2:-}"

if [ ! -d "$WS/.git" ]; then
  echo "[precommit] $WS is not a git repo (.git missing)" >&2
  exit 1
fi

HOOK="$WS/.git/hooks/pre-commit"
if [ -f "$HOOK" ] && [ "$FORCE" != "--force" ]; then
  if ! grep -q 'sd-claude-code-access' "$HOOK"; then
    echo "[precommit] $HOOK already exists with custom content."
    echo "  Re-run with --force to overwrite, or merge manually:"
    echo "    grep '.cc/' $HOOK || echo 'add a refuse-to-commit-.cc/ check'"
    exit 2
  fi
fi

cat > "$HOOK" <<'HOOK'
#!/usr/bin/env bash
# pre-commit hook installed by sd-claude-code-access
# Refuses to commit anything under .cc/ (Cowork scratch directives).
set -e
STAGED=$(git diff --cached --name-only --diff-filter=ACM | grep -E '^\.cc/' || true)
if [ -n "$STAGED" ]; then
  echo "[pre-commit] refusing to commit .cc/ scratch directives:"
  echo "$STAGED" | sed 's/^/    /'
  echo
  echo "  These are Cowork's scratch files, not part of the codebase."
  echo "  Remove with:    git restore --staged \$(echo \"$STAGED\" | tr '\n' ' ')"
  echo "  Or amend gitignore: echo '.cc/' >> .gitignore"
  exit 1
fi
HOOK

chmod +x "$HOOK"
echo "[precommit] installed pre-commit hook at $HOOK"
echo "  Refuses to commit .cc/ paths. Bypass with: git commit --no-verify (not recommended)."
