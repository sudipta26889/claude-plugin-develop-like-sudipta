#!/usr/bin/env bash
# v5.0.6 BUG-2 regression — project-scoped allow-list must exempt a narrow
# known-safe shape WITHOUT weakening the base deny-list.
#
# Field report: Django's `DROP DATABASE IF EXISTS test_app_master` tripped
# base pattern 46 five times in one session. Repeated manual approval of
# DROP DATABASE trains an unsafe reflex — the opposite of a deny-list's job.
# Pre-v5.0.6 there was no allow mechanism at all (only _extra.txt, which
# ADDS patterns).
#
# Four contracts:
#   A. Allow-list match  → watchdog does NOT refuse; emits danger_exempted.
#   B. Same base pattern, NON-matching shape (real DB, no test_ prefix)
#      → still refused (allow entry is narrower than the pattern it exempts).
#   C. No allow file present → behavior identical to pre-v5.0.6 (refuse).
#   D. Allow file present but comment-only → refuse (comments not patterns).
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

# Shared: a prompt whose buffer contains the Django test-DB drop.
_mock_buffer() {
  cat > "$DEST/read.sh" <<MOCK
#!/usr/bin/env bash
cat <<'EOF'
⏺ Bash(docker compose exec -T postgres psql -U app -d app_master -c "$1")
 Do you want to proceed?
 ❯ 1. Yes
   2. No
EOF
MOCK
  chmod +x "$DEST/read.sh"
}

_run_watchdog() {
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

# ── A: allow-list match → exempted, approved ────────────────────────────────
cat > "$WS/.cc/danger_patterns_allow.txt" <<'EOF'
# Django recreates its own ephemeral test database between runs.
\bDROP[[:space:]]+DATABASE[[:space:]]+(IF[[:space:]]+EXISTS[[:space:]]+)?test_[a-z0-9_]+
EOF
_mock_buffer 'DROP DATABASE IF EXISTS test_app_master;'
_run_watchdog
if grep -q '"event":"danger_exempted"' "$WS/.cc/state.json" 2>/dev/null; then
  echo "PASS A: allow-list match → danger_exempted event emitted"
else
  echo "FAIL A: no danger_exempted event (allow-list not consulted)"
  [ -f "$WS/.cc/state.json" ] && sed 's/^/    /' "$WS/.cc/state.json"
  FAIL=1
fi
if grep -q '"event":"danger_blocked"' "$WS/.cc/state.json" 2>/dev/null; then
  echo "FAIL A: still emitted danger_blocked despite allow-list match"
  FAIL=1
fi

# ── B: same pattern, real DB (no test_ prefix) → STILL refused ──────────────
_mock_buffer 'DROP DATABASE app_master;'
_run_watchdog
if grep -q '"event":"danger_blocked"' "$WS/.cc/state.json" 2>/dev/null; then
  echo "PASS B: non-matching shape (real DB) still refused"
else
  echo "FAIL B: real-DB DROP was NOT refused — allow entry is too broad or deny scan skipped"
  [ -f "$WS/.cc/state.json" ] && sed 's/^/    /' "$WS/.cc/state.json"
  FAIL=1
fi

# ── C: no allow file → pre-v5.0.6 behavior (refuse) ─────────────────────────
rm -f "$WS/.cc/danger_patterns_allow.txt"
_mock_buffer 'DROP DATABASE IF EXISTS test_app_master;'
_run_watchdog
if grep -q '"event":"danger_blocked"' "$WS/.cc/state.json" 2>/dev/null; then
  echo "PASS C: no allow file → refuses (back-compat preserved)"
else
  echo "FAIL C: without an allow file the test-DB drop was not refused"
  FAIL=1
fi

# ── D: comment-only allow file → refuse (comments are not patterns) ─────────
cat > "$WS/.cc/danger_patterns_allow.txt" <<'EOF'
# \bDROP[[:space:]]+DATABASE[[:space:]]+.*test_
# (all commented out — should have zero effect)
EOF
_mock_buffer 'DROP DATABASE IF EXISTS test_app_master;'
_run_watchdog
if grep -q '"event":"danger_blocked"' "$WS/.cc/state.json" 2>/dev/null; then
  echo "PASS D: comment-only allow file → refuses"
else
  echo "FAIL D: commented allow entry was treated as active"
  FAIL=1
fi

[ "$FAIL" -eq 0 ] && { echo "ALL PASS — allow-list exempts narrowly, deny-list intact"; exit 0; }
echo "FAIL — BUG-2 allow-list contract violated"
exit 1
