#!/usr/bin/env bash
# v5.0.5 FAILURE 10 regression — nudge_if_stuck.sh must suppress Esc when the
# buffer contains a known long-I/O pattern (docker pull, npm install, etc).
#
# Field report: a `docker pull` from India hung the buffer for 5+ min. Without
# this check, nudge_if_stuck.sh would press Esc → kill the pull → corrupt CC.
#
# Three contracts:
#   A. Stalled buffer + skip-pattern match → no keystroke, nudge_skipped event.
#   B. Stalled buffer + no skip-pattern    → keystroke (Esc) pressed, nudge_sent.
#   C. Per-workspace extras file picked up dynamically (no restart needed).
set -uo pipefail
SCRIPTS_DIR="$(cd "$(dirname "$0")/../scripts" && pwd)"
SCRIPT="$SCRIPTS_DIR/nudge_if_stuck.sh"
[ -x "$SCRIPT" ] || { echo "FAIL: $SCRIPT not executable"; exit 1; }
test -f "$SCRIPTS_DIR/skip_nudge_patterns.txt" || {
  echo "FAIL: skip_nudge_patterns.txt missing from scripts/"; exit 1;
}

DEST=$(mktemp -d)
WS=$(mktemp -d)
KEY_LOG=$(mktemp)
NUDGE_PID=""
trap 'kill -KILL ${NUDGE_PID:-0} 2>/dev/null; rm -rf "$DEST" "$KEY_LOG" "$WS"' EXIT

cp "$SCRIPT" "$DEST/"
cp "$SCRIPTS_DIR/skip_nudge_patterns.txt" "$DEST/"
chmod +x "$DEST/nudge_if_stuck.sh"

# Mock keys.sh — record any presses
cat > "$DEST/keys.sh" <<MOCK
#!/usr/bin/env bash
echo "\$1" >> "$KEY_LOG"
MOCK
chmod +x "$DEST/keys.sh"
# Mock state.sh — append events (so we can grep nudge_skipped / nudge_sent)
mkdir -p "$WS/.cc"
cat > "$DEST/state.sh" <<MOCK
#!/usr/bin/env bash
shift  # drop \$WS arg
echo "{\"event\":\"\$1\",\"args\":\"\$@\"}" >> "$WS/.cc/state.json"
MOCK
chmod +x "$DEST/state.sh"

# ───────────── case A: buffer contains "docker pull" → skip ─────────────
cat > "$DEST/read.sh" <<'MOCK'
#!/usr/bin/env bash
cat <<EOF
⏺ Bash(docker pull python:3.11-slim)
  ⎿  Pulling from library/python
     0e9aa64c1b9b: Downloading [============>                                      ]  29.6MB/118.7MB

(buffer constant — no output progress visible)
EOF
MOCK
chmod +x "$DEST/read.sh"
: > "$KEY_LOG"; : > "$WS/.cc/state.json"
set +m
CCBRIDGE_DIR="$DEST" CCBRIDGE_HOME="$DEST" WORKSPACE="$WS" \
  bash "$DEST/nudge_if_stuck.sh" 1 1 >/dev/null 2>&1 &
NUDGE_PID=$!
sleep 6  # 3 confirms × 1s poll + a settle
{ kill -KILL "$NUDGE_PID" 2>/dev/null; wait "$NUDGE_PID" 2>/dev/null; } 2>/dev/null
NUDGE_PID=""

if [ -s "$KEY_LOG" ]; then
  echo "FAIL case A: nudge pressed keys despite docker-pull skip-pattern: $(tr '\n' ' ' < "$KEY_LOG")"
  exit 1
fi
if ! grep -q '"event":"nudge_skipped"' "$WS/.cc/state.json"; then
  echo "FAIL case A: no nudge_skipped event in state.json"
  cat "$WS/.cc/state.json"
  exit 1
fi
echo "PASS case A: docker-pull buffer → nudge suppressed, nudge_skipped event"

# ───────────── case B: buffer constant, no skip-pattern → nudge fires ─────────────
cat > "$DEST/read.sh" <<'MOCK'
#!/usr/bin/env bash
cat <<EOF
⏺ Thinking about the next step...
(genuinely hung — no operation in progress, no skip pattern visible)
EOF
MOCK
chmod +x "$DEST/read.sh"
: > "$KEY_LOG"; : > "$WS/.cc/state.json"
CCBRIDGE_DIR="$DEST" CCBRIDGE_HOME="$DEST" WORKSPACE="$WS" \
  bash "$DEST/nudge_if_stuck.sh" 1 1 >/dev/null 2>&1 &
NUDGE_PID=$!
sleep 6
{ kill -KILL "$NUDGE_PID" 2>/dev/null; wait "$NUDGE_PID" 2>/dev/null; } 2>/dev/null
NUDGE_PID=""

if [ "$(cat "$KEY_LOG")" != "esc" ]; then
  echo "FAIL case B: expected single 'esc' keystroke; got: $(tr '\n' ',' < "$KEY_LOG")"
  exit 1
fi
if ! grep -q '"event":"nudge_sent"' "$WS/.cc/state.json"; then
  echo "FAIL case B: no nudge_sent event in state.json"
  exit 1
fi
echo "PASS case B: genuine hang → esc pressed, nudge_sent event"

# ───────────── case C: per-workspace extras file picked up ─────────────
cat > "$WS/.cc/skip_nudge_patterns_extra.txt" <<'EOF'
# project-specific long-I/O ops
custom-build-tool running
EOF
cat > "$DEST/read.sh" <<'MOCK'
#!/usr/bin/env bash
cat <<EOF
custom-build-tool running for 3 minutes...
(no progress output)
EOF
MOCK
chmod +x "$DEST/read.sh"
: > "$KEY_LOG"; : > "$WS/.cc/state.json"
CCBRIDGE_DIR="$DEST" CCBRIDGE_HOME="$DEST" WORKSPACE="$WS" \
  bash "$DEST/nudge_if_stuck.sh" 1 1 >/dev/null 2>&1 &
NUDGE_PID=$!
sleep 6
{ kill -KILL "$NUDGE_PID" 2>/dev/null; wait "$NUDGE_PID" 2>/dev/null; } 2>/dev/null
NUDGE_PID=""

if [ -s "$KEY_LOG" ]; then
  echo "FAIL case C: nudge fired despite per-workspace skip pattern match"
  exit 1
fi
if ! grep -q '"event":"nudge_skipped"' "$WS/.cc/state.json"; then
  echo "FAIL case C: no nudge_skipped event (extras file ignored?)"
  cat "$WS/.cc/state.json"
  exit 1
fi
echo "PASS case C: per-workspace extras file picked up dynamically"

echo "ALL PASS — skip-nudge patterns enforce long-I/O safety"
