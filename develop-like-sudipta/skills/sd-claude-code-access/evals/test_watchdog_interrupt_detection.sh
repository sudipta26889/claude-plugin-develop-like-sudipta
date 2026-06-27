#!/usr/bin/env bash
# v5.0.5 FAILURE 4 regression — watchdog must detect CC's "Interrupted ·" UI
# state and emit a `prompt_interrupted` state event (NOT a `prompt_pending`).
#
# Field report (GuardianAI 20-phase deploy):
#   - CC entered "Interrupted · What should Claude do instead?" after a parallel
#     SSH+CC Docker conflict killed its build command.
#   - Watchdog only matched permission-prompt patterns → silent miss.
#   - Manager had no `prompt_interrupted` event in state.json to detect + recover.
#
# Contract this test enforces (post-fix):
#   - When the visible buffer contains "Interrupted ·" → watchdog emits
#     `state.sh "$WS" prompt_interrupted snippet=...` event.
#   - This is DISTINCT from `prompt_pending` — the manager needs to send a
#     typed re-trigger message, not press return.
#   - Watchdog MUST NOT press any keys on interrupt detection.
#
# Mechanics: mock read.sh to emit the literal interrupt UI, run watchdog for
# 5s, kill SIGTERM, assert state.json has prompt_interrupted event AND no
# keystroke was pressed.
set -uo pipefail
DEST=$(mktemp -d)
KEY_LOG=$(mktemp)
WS=$(mktemp -d)
WD_PID=""
trap 'kill -KILL ${WD_PID:-0} 2>/dev/null; pkill -KILL -P "${WD_PID:-0}" 2>/dev/null; rm -rf "$DEST" "$KEY_LOG" "$WS"' EXIT

cp "$(dirname "$0")/../scripts/"{watchdog,read,keys,state,learning,register_project,escalate}.sh "$DEST/"
cp "$(dirname "$0")/../scripts/danger_patterns.txt" "$DEST/"
chmod +x "$DEST"/*.sh

cat > "$DEST/read.sh" <<'MOCK'
#!/usr/bin/env bash
cat <<EOF
⏺ Bash(docker compose build)
  ⎿  ...build output truncated...

Interrupted · What should Claude do instead?

❯ (write your response here)
EOF
MOCK
chmod +x "$DEST/read.sh"

cat > "$DEST/keys.sh" <<MOCK
#!/usr/bin/env bash
echo "\$1" >> "$KEY_LOG"
MOCK
chmod +x "$DEST/keys.sh"

mkdir -p "$WS/.cc"
set +m
CCBRIDGE_DIR="$DEST" CCBRIDGE_HOME="$DEST" WORKSPACE="$WS" \
  bash "$DEST/watchdog.sh" >/dev/null 2>&1 &
WD_PID=$!
sleep 5
{ kill -TERM "$WD_PID" 2>/dev/null; wait "$WD_PID" 2>/dev/null; } 2>/dev/null
true

if ! grep -q '"event":"prompt_interrupted"' "$WS/.cc/state.json" 2>/dev/null; then
  echo "FAIL: no prompt_interrupted event in state.json (watchdog did not detect Interrupted UI)"
  [ -f "$WS/.cc/state.json" ] && { echo "  state.json contents:"; sed 's/^/    /' "$WS/.cc/state.json"; }
  exit 1
fi

if [ -s "$KEY_LOG" ]; then
  echo "FAIL: watchdog pressed key(s) on interrupt — must not press anything"
  echo "  key log: $(tr '\n' ' ' < "$KEY_LOG")"
  exit 1
fi

if grep -q '"event":"prompt_pending"' "$WS/.cc/state.json" 2>/dev/null; then
  echo "FAIL: watchdog mis-classified Interrupted UI as prompt_pending (must be prompt_interrupted)"
  exit 1
fi

echo "PASS — interrupt UI detected, prompt_interrupted event emitted, no keystroke"
