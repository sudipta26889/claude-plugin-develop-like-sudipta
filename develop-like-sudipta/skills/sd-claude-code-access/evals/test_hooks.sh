#!/usr/bin/env bash
# test_hooks.sh — smoke test for hooks/scripts/check_bug_id.sh and
# hooks/scripts/check_test_paired_with_src.sh.
#
# Each case sets up a minimal git workspace under a tmp dir, stages
# whatever files the case needs, and invokes the hook script directly
# (the hook is filesystem-independent — it queries `git diff --cached`
# inside the tmp workspace).
#
# Exit 0 on PASS (all 9 cases behave as documented), non-zero on FAIL.
#
# Usage: ./test_hooks.sh

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# evals/ → skills/sd-claude-code-access/ → skills/ → develop-like-sudipta/
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
BUG_HOOK="$PLUGIN_ROOT/hooks/scripts/check_bug_id.sh"
TDD_HOOK="$PLUGIN_ROOT/hooks/scripts/check_test_paired_with_src.sh"

if [ ! -f "$BUG_HOOK" ]; then
  echo "FAIL: bug-id hook not found at $BUG_HOOK"
  exit 2
fi
if [ ! -f "$TDD_HOOK" ]; then
  echo "FAIL: tdd-pairing hook not found at $TDD_HOOK"
  exit 2
fi

# Make sure they're executable (a fresh checkout might not preserve the bit).
chmod +x "$BUG_HOOK" "$TDD_HOOK" 2>/dev/null || true

TMP_ROOT="$(mktemp -d -t test_hooks.XXXXXX)"
trap 'rm -rf "$TMP_ROOT"' EXIT

failures=0
case_num=0

# Helper: announce a case and increment counter.
case_begin() {
  case_num=$((case_num + 1))
  echo "── case $case_num: $1"
}

# Helper: fail a case with a reason.
fail() {
  echo "    FAIL — $1"
  failures=$((failures + 1))
}

pass() {
  echo "    PASS"
}

# Helper: set up a fresh tmp git workspace.
mkws() {
  local ws
  ws="$TMP_ROOT/ws_${case_num}_$RANDOM"
  mkdir -p "$ws"
  (
    cd "$ws"
    git init -q
    git config user.email "test@example.com"
    git config user.name "Test"
    # An initial empty commit so HEAD exists (some git versions need it).
    git commit -q --allow-empty -m "init"
  )
  printf '%s' "$ws"
}

# Helper: write a commit message to a file inside a workspace.
mkmsg() {
  local ws="$1"
  local msg="$2"
  local f="$ws/.git/COMMIT_EDITMSG"
  printf '%s\n' "$msg" > "$f"
  printf '%s' "$f"
}

# ─────────────────────────────────────────────────────────────────
# check_bug_id.sh cases
# ─────────────────────────────────────────────────────────────────

# Case 1: commit message with no bug ref → exit 0 (allow).
case_begin "check_bug_id: no bug ref → allow"
ws=$(mkws)
msg=$(mkmsg "$ws" "feat: add login flow")
(cd "$ws" && "$BUG_HOOK" "$msg") >/dev/null 2>&1
rc=$?
if [ "$rc" -eq 0 ]; then pass; else fail "expected 0, got $rc"; fi

# Case 2: bug ref present but no .cc/bugs/<id>.md → exit 1.
case_begin "check_bug_id: bug ref + missing .cc/bugs/<id>.md → refuse"
ws=$(mkws)
msg=$(mkmsg "$ws" "fix(cart): off-by-tax (bug-phase-3-bug-cart)")
(cd "$ws" && "$BUG_HOOK" "$msg") >/dev/null 2>&1
rc=$?
if [ "$rc" -eq 1 ]; then pass; else fail "expected 1, got $rc"; fi

# Case 3: bug ref present AND .cc/bugs/<id>.md exists → exit 0.
case_begin "check_bug_id: bug ref + matching evidence file → allow"
ws=$(mkws)
mkdir -p "$ws/.cc/bugs"
printf '# bug-phase-3-bug-cart\n' > "$ws/.cc/bugs/phase-3-bug-cart.md"
msg=$(mkmsg "$ws" "fix(cart): off-by-tax (bug-phase-3-bug-cart)")
(cd "$ws" && "$BUG_HOOK" "$msg") >/dev/null 2>&1
rc=$?
if [ "$rc" -eq 0 ]; then pass; else fail "expected 0, got $rc"; fi

# Case 4: bypass envvar → exit 0 even if file missing.
case_begin "check_bug_id: BUG_HOOK_BYPASS=1 → allow despite missing file"
ws=$(mkws)
msg=$(mkmsg "$ws" "fix(cart): hot patch (bug-phase-9-bug-emergency)")
(cd "$ws" && BUG_HOOK_BYPASS=1 "$BUG_HOOK" "$msg") >/dev/null 2>&1
rc=$?
if [ "$rc" -eq 0 ]; then pass; else fail "expected 0, got $rc"; fi

# ─────────────────────────────────────────────────────────────────
# check_test_paired_with_src.sh cases
# ─────────────────────────────────────────────────────────────────

# Case 5: only src/foo.py staged → exit 1.
case_begin "check_test_paired_with_src: only src/ → refuse"
ws=$(mkws)
mkdir -p "$ws/src"
printf 'print("x")\n' > "$ws/src/foo.py"
(cd "$ws" && git add src/foo.py)
(cd "$ws" && "$TDD_HOOK") >/dev/null 2>&1
rc=$?
if [ "$rc" -eq 1 ]; then pass; else fail "expected 1, got $rc"; fi

# Case 6: src/foo.py + tests/test_foo.py both staged → exit 0.
case_begin "check_test_paired_with_src: src + tests paired → allow"
ws=$(mkws)
mkdir -p "$ws/src" "$ws/tests"
printf 'print("x")\n' > "$ws/src/foo.py"
printf 'def test_foo(): assert True\n' > "$ws/tests/test_foo.py"
(cd "$ws" && git add src/foo.py tests/test_foo.py)
(cd "$ws" && "$TDD_HOOK") >/dev/null 2>&1
rc=$?
if [ "$rc" -eq 0 ]; then pass; else fail "expected 0, got $rc"; fi

# Case 7: only tests/test_foo.py staged → exit 0.
case_begin "check_test_paired_with_src: only tests → allow"
ws=$(mkws)
mkdir -p "$ws/tests"
printf 'def test_foo(): assert True\n' > "$ws/tests/test_foo.py"
(cd "$ws" && git add tests/test_foo.py)
(cd "$ws" && "$TDD_HOOK") >/dev/null 2>&1
rc=$?
if [ "$rc" -eq 0 ]; then pass; else fail "expected 0, got $rc"; fi

# Case 8: only README.md staged → exit 0.
case_begin "check_test_paired_with_src: only docs → allow"
ws=$(mkws)
printf '# Project\n' > "$ws/README.md"
(cd "$ws" && git add README.md)
(cd "$ws" && "$TDD_HOOK") >/dev/null 2>&1
rc=$?
if [ "$rc" -eq 0 ]; then pass; else fail "expected 0, got $rc"; fi

# Case 9: TDD_HOOK_BYPASS=1 with only src staged → exit 0.
case_begin "check_test_paired_with_src: TDD_HOOK_BYPASS=1 → allow despite src-only"
ws=$(mkws)
mkdir -p "$ws/src"
printf 'print("x")\n' > "$ws/src/foo.py"
(cd "$ws" && git add src/foo.py)
(cd "$ws" && TDD_HOOK_BYPASS=1 "$TDD_HOOK") >/dev/null 2>&1
rc=$?
if [ "$rc" -eq 0 ]; then pass; else fail "expected 0, got $rc"; fi

# ─────────────────────────────────────────────────────────────────
# Summary
# ─────────────────────────────────────────────────────────────────

echo
if [ "$failures" -eq 0 ]; then
  echo "PASS — $case_num/$case_num cases."
  exit 0
else
  echo "FAIL — $failures/$case_num case(s) wrong."
  exit 1
fi
