#!/usr/bin/env bash
# v5.0.7 C1 regression — WATCHDOG_AUTO_APPROVE=1 must be cursor-aware.
#
# BUG-4 (cursor defaults to "3. No" on multi-option prompts) was fixed for
# the orchestrator via unblock_cc.sh in v5.0.2 — but the watchdog's own
# auto-approve branch kept pressing bare return, REJECTING the action it
# meant to approve. The field reporter runs WATCHDOG_AUTO_APPROVE=1.
#
# Contracts:
#   A. Cursor on option 3 → keys: up, up, return.
#   B. Cursor on option 1 → keys: return only.
#   C. No numbered cursor (plain question) → return only (legacy behavior).
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

# ── A: cursor on option 3 → up, up, return ─────────────────────────────────
cat > "$DEST/read.sh" <<'MOCK'
#!/usr/bin/env bash
cat <<'EOF'
⏺ Bash(git commit -m "safe docs change")
 Do you want to proceed?
   1. Yes
   2. Yes, and don't ask again
 ❯ 3. No
EOF
MOCK
chmod +x "$DEST/read.sh"
_run
GOT=$(cat "$KEY_LOG")
if [ "$GOT" = "$(printf 'up\nup\nreturn')" ]; then
  echo "PASS A: cursor=3 → up,up,return"
else
  echo "FAIL A: cursor=3 → expected up,up,return; got: $(echo "$GOT" | tr '\n' ',')"
  FAIL=1
fi

# ── B: cursor on option 1 → return only ────────────────────────────────────
cat > "$DEST/read.sh" <<'MOCK'
#!/usr/bin/env bash
cat <<'EOF'
⏺ Bash(git status)
 Do you want to proceed?
 ❯ 1. Yes
   2. No
EOF
MOCK
chmod +x "$DEST/read.sh"
_run
if [ "$(cat "$KEY_LOG")" = "return" ]; then
  echo "PASS B: cursor=1 → return only"
else
  echo "FAIL B: cursor=1 → expected return; got: $(tr '\n' ',' < "$KEY_LOG")"
  FAIL=1
fi

# ── C: no numbered cursor line → return only (legacy) ──────────────────────
cat > "$DEST/read.sh" <<'MOCK'
#!/usr/bin/env bash
cat <<'EOF'
⏺ Bash(ls)
 Do you want to proceed with listing?
EOF
MOCK
chmod +x "$DEST/read.sh"
_run
if [ "$(cat "$KEY_LOG")" = "return" ]; then
  echo "PASS C: no cursor line → return only"
else
  echo "FAIL C: no cursor line → expected return; got: $(tr '\n' ',' < "$KEY_LOG")"
  FAIL=1
fi

[ "$FAIL" -eq 0 ] && { echo "ALL PASS — auto-approve is cursor-aware"; exit 0; }
exit 1
