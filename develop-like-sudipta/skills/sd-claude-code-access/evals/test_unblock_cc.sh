#!/usr/bin/env bash
# BUG-4 regression — unblock_cc.sh detects + navigates multi-option CC prompts.
#
# Four contracts covered (one subtest each):
#  1. Cursor on option 3 ("No") → up x2 + return  (the BUG-4 case from cycle 18)
#  2. Cursor on option 1 ("Yes") → return only    (no nav needed)
#  3. No prompt visible           → exit 3, no keys (CC isn't blocked)
#  4. Danger pattern in buffer    → exit 2, no keys (refuse, never navigate)
#
# Mechanics: build a fake CCBRIDGE_DIR with the script under test, mock
# read.sh per-subtest with the desired buffer, mock keys.sh to log keystrokes
# to a file. Assert the keystroke log matches expectation. Cleanup via trap.
set -uo pipefail
DEST=$(mktemp -d)
KEY_LOG=$(mktemp)
WS=$(mktemp -d)
trap 'rm -rf "$DEST" "$KEY_LOG" "$WS"' EXIT

cp "$(dirname "$0")/../scripts/unblock_cc.sh" "$DEST/"
cp "$(dirname "$0")/../scripts/danger_patterns.txt" "$DEST/"
chmod +x "$DEST/unblock_cc.sh"
# Intentionally NOT copying state.sh/learning.sh — the unblock_cc.sh has
# `[ -x ]` guards for those; with no script present, the optional logging
# branches no-op (correct behavior for the unit-eval scope). Their absence
# also prevents real register_project.sh side effects on ~/.cache/ccbridge/
# during the test run.

# Mock keys.sh — record any keystrokes to KEY_LOG
cat > "$DEST/keys.sh" <<MOCK
#!/usr/bin/env bash
echo "\$1" >> "$KEY_LOG"
MOCK
chmod +x "$DEST/keys.sh"

mkdir -p "$WS/.cc"

# ───────────── case 1: cursor on option 3 → expect up,up,return ─────────────
cat > "$DEST/read.sh" <<'MOCK'
#!/usr/bin/env bash
cat <<EOF
 Do you want to proceed?
   1. Yes
  2.Yes, and don't ask again for similar commands
 ❯ 3. No
EOF
MOCK
chmod +x "$DEST/read.sh"
: > "$KEY_LOG"
CCBRIDGE_DIR="$DEST" CCBRIDGE_HOME="$DEST" WORKSPACE="$WS" bash "$DEST/unblock_cc.sh" >/dev/null
EXPECT=$'up\nup\nreturn'
GOT=$(cat "$KEY_LOG")
if [ "$GOT" != "$EXPECT" ]; then
  echo "FAIL case1 (cursor=3): expected 'up,up,return'; got: $(echo "$GOT" | tr '\n' ',')"
  exit 1
fi
echo "PASS case1: cursor on option 3 → up,up,return"

# ───────────── case 2: cursor on option 1 → expect return only ─────────────
cat > "$DEST/read.sh" <<'MOCK'
#!/usr/bin/env bash
cat <<EOF
 Do you want to proceed?
 ❯ 1. Yes
   2. No
EOF
MOCK
chmod +x "$DEST/read.sh"
: > "$KEY_LOG"
CCBRIDGE_DIR="$DEST" CCBRIDGE_HOME="$DEST" WORKSPACE="$WS" bash "$DEST/unblock_cc.sh" >/dev/null
GOT=$(cat "$KEY_LOG")
if [ "$GOT" != "return" ]; then
  echo "FAIL case2 (cursor=1): expected 'return'; got: $(echo "$GOT" | tr '\n' ',')"
  exit 1
fi
echo "PASS case2: cursor on option 1 → return only"

# ───────────── case 3: no prompt → exit 3, no keys ─────────────
cat > "$DEST/read.sh" <<'MOCK'
#!/usr/bin/env bash
cat <<EOF

❯
  ⏵⏵ accept edits on (shift+tab to cycle) · esc to interrupt
EOF
MOCK
chmod +x "$DEST/read.sh"
: > "$KEY_LOG"
CCBRIDGE_DIR="$DEST" CCBRIDGE_HOME="$DEST" WORKSPACE="$WS" bash "$DEST/unblock_cc.sh" >/dev/null
rc=$?
if [ "$rc" != "3" ]; then
  echo "FAIL case3 (no prompt): expected exit 3; got: $rc"
  exit 1
fi
if [ -s "$KEY_LOG" ]; then
  echo "FAIL case3: should not press keys; got: $(cat "$KEY_LOG" | tr '\n' ',')"
  exit 1
fi
echo "PASS case3: no prompt → exit 3, no keys"

# ───────────── case 4: danger pattern → exit 2, no keys ─────────────
cat > "$DEST/read.sh" <<'MOCK'
#!/usr/bin/env bash
cat <<EOF
 Do you want to proceed with rm -rf /?
 ❯ 1. Yes
   2. No
EOF
MOCK
chmod +x "$DEST/read.sh"
: > "$KEY_LOG"
CCBRIDGE_DIR="$DEST" CCBRIDGE_HOME="$DEST" WORKSPACE="$WS" bash "$DEST/unblock_cc.sh" >/dev/null
rc=$?
if [ "$rc" != "2" ]; then
  echo "FAIL case4 (danger): expected exit 2; got: $rc"
  exit 1
fi
if [ -s "$KEY_LOG" ]; then
  echo "FAIL case4: should not press keys after danger refuse; got: $(cat "$KEY_LOG" | tr '\n' ',')"
  exit 1
fi
echo "PASS case4: danger pattern → exit 2, no keys"

echo "ALL PASS — BUG-4 contract verified"
