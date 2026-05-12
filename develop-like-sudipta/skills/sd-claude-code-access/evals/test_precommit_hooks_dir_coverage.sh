#!/usr/bin/env bash
# Eval: check_no_hardcoded_paths.sh must catch /Users/<name>/ hardcoded
# paths planted under develop-like-sudipta/hooks/scripts/.
#
# Why: hooks/scripts/ is the hook's own neighbor directory. A blind spot
# there means a future helper script (or test fixture) with a hardcoded
# /Users/<dev>/ path could land on main and break the plugin on every
# other machine — bypassing the very gate that exists to prevent that.
#
# The hook's SHIP_DIRS array includes `develop-like-sudipta/hooks`, and
# is_in_ship_dir matches via `case "$f" in "$d"/*) return 0` — so any
# file under `hooks/scripts/` is in-scope by prefix. This eval pins
# down that coverage as a regression guard: future SHIP_DIRS edits that
# accidentally narrow the path (e.g. switching to literal exact-match
# only) will trip the assertion.
#
# Self-isolated under mktemp + HOME override so the test never reads
# or mutates the user's real repo or git config.
set -uo pipefail

EVAL_DIR="$(cd "$(dirname "$0")" && pwd)"
REAL_HOOK="$(cd "$EVAL_DIR/../../../hooks/scripts" && pwd)/check_no_hardcoded_paths.sh"
[ -x "$REAL_HOOK" ] || { echo "FAIL: hook missing at $REAL_HOOK"; exit 1; }

TD=$(mktemp -d)
trap 'rm -rf "$TD"' EXIT

# Pin HOME inside the tmpdir so git doesn't consult the user's real
# ~/.gitconfig (and any pre-commit auto-installs there).
export HOME="$TD"

cd "$TD"
git init -q
mkdir -p develop-like-sudipta/hooks/scripts
cp "$REAL_HOOK" develop-like-sudipta/hooks/scripts/check_no_hardcoded_paths.sh

# Synthetic offender: one line with a /Users/<name>/ hardcode. The file
# name is chosen to obviously NOT match any EXEMPT_PATHS entry (the two
# exempts under hooks/scripts/ are the hook itself + its installer; a
# fresh test_helper_TEMP.sh is neither).
cat > develop-like-sudipta/hooks/scripts/test_helper_TEMP.sh <<'BAD'
#!/usr/bin/env bash
echo "/Users/sudipta/Workspace/something"
BAD

git add develop-like-sudipta/hooks/scripts/test_helper_TEMP.sh

# Run the hook. It reads `git diff --cached --name-only` for the staged
# file list, so the only setup needed is the git-init + git-add above.
rc=0; out=$(bash develop-like-sudipta/hooks/scripts/check_no_hardcoded_paths.sh 2>&1) || rc=$?

if [ "$rc" -eq 0 ]; then
  echo "FAIL: hook silently accepted a hardcoded path under hooks/scripts/"
  echo "  output was:"
  echo "$out" | sed 's/^/    /'
  exit 1
fi

# The refusal message shape is also part of the contract — confirm the
# hook explained itself rather than exiting non-zero for some unrelated
# reason (e.g. missing git, malformed staging).
case "$out" in
  *'HARDCODED PATH(S) DETECTED'*) ;;
  *) echo "FAIL: hook exited non-zero but without the canonical 'HARDCODED PATH(S) DETECTED' message"
     echo "  output was:"
     echo "$out" | sed 's/^/    /'
     exit 1 ;;
esac

# Negative-control case: same fixture but file path is the hook itself
# (which IS exempt). The hook must NOT refuse — exempts are how the
# script documents the bad pattern without self-flagging. Wipe the
# previous fixture from disk + index before staging the exempt one so
# the hook only sees the negative case.
rm -f develop-like-sudipta/hooks/scripts/test_helper_TEMP.sh
git reset -q HEAD -- . 2>/dev/null || git reset -q 2>/dev/null || true
# Append a hardcoded path inside the exempt file (the hook itself).
echo 'echo "/Users/sudipta/Workspace/exempt-example"' >> develop-like-sudipta/hooks/scripts/check_no_hardcoded_paths.sh
git add develop-like-sudipta/hooks/scripts/check_no_hardcoded_paths.sh
rc=0; bash develop-like-sudipta/hooks/scripts/check_no_hardcoded_paths.sh >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 0 ] || {
  echo "FAIL: hook refused a hardcoded path inside an EXEMPT_PATHS entry"
  echo "  this means is_exempt() got narrower; the hook now self-flags"
  exit 1
}

echo "PASS"
