#!/usr/bin/env bash
# v5.0.7 C2 regression — danger scan must target the COMMAND BLOCK, not
# displayed file content.
#
# Observed twice while this plugin developed itself: CC editing
# danger_patterns.txt (or showing an eval diff containing `rm -rf`) put the
# dangerous STRING on screen as content; the watchdog refused a perfectly
# safe edit. Fail-closed contract preserved: when no command marker exists,
# the whole buffer is scanned.
#
# Contracts:
#   A. `rm -rf` inside displayed diff content, command block clean → APPROVE
#      (no danger_blocked event).
#   B. `rm -rf` inside the actual `⏺ Bash(...)` command block → REFUSE.
#   C. No command marker at all + `rm -rf` anywhere → REFUSE (fail-closed).
set -uo pipefail
DEST=$(mktemp -d)
KEY_LOG=$(mktemp)
WS=$(mktemp -d)
WD_PID=""
trap 'kill -KILL ${WD_PID:-0} 2>/dev/null; pkill -KILL -P "${WD_PID:-0}" 2>/dev/null; rm -rf "$DEST" "$KEY_LOG" "$WS"' EXIT

SRC="$(cd "$(dirname "$0")/../scripts" && pwd)"
cp "$SRC/"{watchdog,read,keys,state,learning,register_project,escalate}.sh "$DEST/"
cp "$SRC/danger_patterns.txt" "$DEST/"
chmod +x "$DEST"/*.sh

cat > "$DEST/keys.sh" <<MOCK
#!/usr/bin/env bash
echo "\$1" >> "$KEY_LOG"
MOCK
chmod +x "$DEST/keys.sh"
mkdir -p "$WS/.cc"

_run() {
  : > "$KEY_LOG"; : > "$WS/.cc/state.json"
  set +m
  CCBRIDGE_DIR="$DEST" CCBRIDGE_HOME="$DEST" WORKSPACE="$WS" WATCHDOG_AUTO_APPROVE=1 \
    bash "$DEST/watchdog.sh" >/dev/null 2>&1 &
  WD_PID=$!
  sleep 5
  { kill -TERM "$WD_PID" 2>/dev/null; wait "$WD_PID" 2>/dev/null; } 2>/dev/null
  WD_PID=""
}

FAIL=0

# ── A: dangerous string in DISPLAYED CONTENT, clean command ────────────────
cat > "$DEST/read.sh" <<'MOCK'
#!/usr/bin/env bash
cat <<'EOF'
⏺ Update(develop-like-sudipta/skills/sd-claude-code-access/danger_patterns.txt)
  ⎿  Updated with 1 addition
       46  \brm[[:space:]]+-rf\b   # the deny pattern itself, displayed as content
⏺ Bash(git add danger_patterns.txt && git commit -m "docs: pattern comment")
 Do you want to proceed?
 ❯ 1. Yes
   2. No
EOF
MOCK
chmod +x "$DEST/read.sh"
_run
if grep -q '"event":"danger_blocked"' "$WS/.cc/state.json" 2>/dev/null; then
  echo "FAIL A: refused on displayed content — command block was clean (git add/commit)"
  FAIL=1
else
  echo "PASS A: displayed rm -rf content did not trip the deny scan"
fi

# ── B: dangerous string in the ACTUAL command block → refuse ───────────────
cat > "$DEST/read.sh" <<'MOCK'
#!/usr/bin/env bash
cat <<'EOF'
⏺ Bash(rm -rf /tmp/build && make all)
 Do you want to proceed?
 ❯ 1. Yes
   2. No
EOF
MOCK
chmod +x "$DEST/read.sh"
_run
if grep -q '"event":"danger_blocked"' "$WS/.cc/state.json" 2>/dev/null; then
  echo "PASS B: rm -rf in command block refused"
else
  echo "FAIL B: rm -rf in command block was NOT refused"
  FAIL=1
fi

# ── C: no command marker, dangerous string anywhere → refuse (fail-closed) ─
cat > "$DEST/read.sh" <<'MOCK'
#!/usr/bin/env bash
cat <<'EOF'
some unstructured screen containing rm -rf / in prose
 Do you want to proceed?
 ❯ 1. Yes
   2. No
EOF
MOCK
chmod +x "$DEST/read.sh"
_run
if grep -q '"event":"danger_blocked"' "$WS/.cc/state.json" 2>/dev/null; then
  echo "PASS C: no command marker → fail-closed whole-buffer refusal"
else
  echo "FAIL C: fail-closed contract broken (no marker should mean whole-buffer scan)"
  FAIL=1
fi

[ "$FAIL" -eq 0 ] && { echo "ALL PASS — danger scan scoped to command block, fail-closed"; exit 0; }
exit 1
