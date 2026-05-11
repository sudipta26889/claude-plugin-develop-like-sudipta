#!/usr/bin/env bash
# test_watchdog_escalation.sh — smoke test for the watchdog escalation hook.
#
# Background: when watchdog.sh detects a danger pattern, it refuses to
# auto-approve. Pre-v3.3 that refusal was silent: the run stalled with
# only a line in watchdog.log. This test pins the new behaviour:
#
#   1. scripts/escalate.sh, run in isolation, appends a payload to
#      <workspace>/.cc/escalations.log AND honours an opt-in ESCALATE_CMD
#      env var (e.g. send to ntfy / Slack / email).
#   2. scripts/watchdog.sh, when its danger-deny branch fires, pipes the
#      same payload into escalate.sh additive to (not replacing) the
#      existing refusal.
#
# Bash 3.2 compatible. No `wait -n`, no `mapfile`, no associative arrays,
# no `${var,,}`.
#
# Usage: ./test_watchdog_escalation.sh
# Exit 0 on PASS, non-zero on any failed assertion.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ESCALATE="$SCRIPT_DIR/../scripts/escalate.sh"
WATCHDOG="$SCRIPT_DIR/../scripts/watchdog.sh"

if [ ! -f "$ESCALATE" ]; then
  echo "FAIL: escalate.sh not found at $ESCALATE"
  exit 2
fi
if [ ! -f "$WATCHDOG" ]; then
  echo "FAIL: watchdog.sh not found at $WATCHDOG"
  exit 2
fi

TMP_ROOT="${TMPDIR:-/tmp}"
fails=0
fail() { fails=$((fails + 1)); echo "  FAIL: $*"; }
pass() { echo "  PASS: $*"; }

# ---------------------------------------------------------------------------
# Case 1 — escalate.sh in isolation (no ESCALATE_CMD)
# ---------------------------------------------------------------------------
echo "── Case 1: escalate.sh standalone (writes escalations.log) ──"
WS1="$(mktemp -d "$TMP_ROOT/wd-esc-XXXXXX")"
mkdir -p "$WS1/.cc"

PAYLOAD1="matched=prodctl_nuke
prompt=Running prodctl_nuke for testing. Do you want to proceed?"

printf '%s' "$PAYLOAD1" | bash "$ESCALATE" "$WS1"

LOG1="$WS1/.cc/escalations.log"
if [ -f "$LOG1" ]; then
  pass "escalations.log was created at $LOG1"
else
  fail "escalations.log NOT created"
fi

if grep -q "matched=prodctl_nuke" "$LOG1" 2>/dev/null; then
  pass "log contains matched pattern"
else
  fail "log missing matched pattern"
fi

if grep -q "prodctl_nuke for testing" "$LOG1" 2>/dev/null; then
  pass "log contains prompt snippet"
else
  fail "log missing prompt snippet"
fi

# UTC ISO-ish timestamp line `[YYYY-MM-DDTHH:MM:SSZ]`
if grep -qE '^\[[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z\]' "$LOG1" 2>/dev/null; then
  pass "log has ISO-8601 UTC timestamp line"
else
  fail "log missing ISO-8601 UTC timestamp line"
fi

# ---------------------------------------------------------------------------
# Case 2 — escalate.sh with ESCALATE_CMD set (opt-in fan-out)
# ---------------------------------------------------------------------------
echo
echo "── Case 2: escalate.sh + ESCALATE_CMD env var ──"
WS2="$(mktemp -d "$TMP_ROOT/wd-esc-XXXXXX")"
mkdir -p "$WS2/.cc"
OUT2="$TMP_ROOT/escalate_out_$$.txt"
rm -f "$OUT2"

PAYLOAD2="matched=prodctl_nuke
prompt=Running prodctl_nuke for testing. Do you want to proceed?"

printf '%s' "$PAYLOAD2" | env ESCALATE_CMD="cat > $OUT2" bash "$ESCALATE" "$WS2"

if [ -f "$OUT2" ]; then
  pass "ESCALATE_CMD produced output file $OUT2"
else
  fail "ESCALATE_CMD output file NOT produced"
fi

if grep -q "matched=prodctl_nuke" "$OUT2" 2>/dev/null; then
  pass "ESCALATE_CMD output contains matched pattern"
else
  fail "ESCALATE_CMD output missing matched pattern"
fi

if grep -q "prodctl_nuke for testing" "$OUT2" 2>/dev/null; then
  pass "ESCALATE_CMD output contains prompt snippet"
else
  fail "ESCALATE_CMD output missing prompt snippet"
fi

# And the local log should ALSO have been written (default action runs
# regardless of ESCALATE_CMD).
LOG2="$WS2/.cc/escalations.log"
if [ -f "$LOG2" ] && grep -q "matched=prodctl_nuke" "$LOG2" 2>/dev/null; then
  pass "local escalations.log also written when ESCALATE_CMD set"
else
  fail "local escalations.log not written (or missing payload) when ESCALATE_CMD set"
fi

# ---------------------------------------------------------------------------
# Case 3 — watchdog.sh → escalate.sh integration
#
# Strategy: build a fake "bridge dir" with stub read.sh, keys.sh, and
# a copy of escalate.sh. Run the real watchdog.sh with CCBRIDGE_DIR
# pointing at that fake dir and WORKSPACE pointing at a temp workspace.
# The stub read.sh emits a buffer that contains both a CC permission
# prompt AND a token that matches a per-project danger_patterns_extra.txt
# entry. Wait briefly, then assert the workspace's escalations.log was
# written. Kill the watchdog.
# ---------------------------------------------------------------------------
echo
echo "── Case 3: watchdog → escalate.sh integration ──"
WS3="$(mktemp -d "$TMP_ROOT/wd-esc-XXXXXX")"
mkdir -p "$WS3/.cc"
BRIDGE3="$(mktemp -d "$TMP_ROOT/wd-esc-bridge-XXXXXX")"

# Per-project extras: a token that wouldn't be in the base list and is
# guaranteed unique to the test.
echo 'prodctl_nuke' > "$WS3/.cc/danger_patterns_extra.txt"

# Empty base danger_patterns so we only match via the extras file. This
# also exercises the "extras alone is enough" path.
: > "$BRIDGE3/danger_patterns.txt"

# Stub read.sh: emit a buffer that the watchdog's PROMPT_PATTERN matches
# AND that contains "prodctl_nuke" so the extras pattern fires.
cat > "$BRIDGE3/read.sh" <<'EOF'
#!/usr/bin/env bash
cat <<'BUF'
$ prodctl_nuke --target=prod-tenant-42
This will destroy the prod tenant.
Do you want to proceed?
1. Yes
2. No
BUF
EOF
chmod +x "$BRIDGE3/read.sh"

# Stub keys.sh: just log invocations so the test can confirm the watchdog
# did NOT press Enter (it should refuse on this buffer).
cat > "$BRIDGE3/keys.sh" <<EOF
#!/usr/bin/env bash
echo "keys.sh called with: \$*" >> "$BRIDGE3/keys.log"
EOF
chmod +x "$BRIDGE3/keys.sh"

# Stub state.sh: also log invocations, no-op otherwise.
cat > "$BRIDGE3/state.sh" <<EOF
#!/usr/bin/env bash
echo "state.sh called with: \$*" >> "$BRIDGE3/state.log"
EOF
chmod +x "$BRIDGE3/state.sh"

# Copy escalate.sh into the bridge dir (mirrors what install.sh would do).
cp "$ESCALATE" "$BRIDGE3/escalate.sh"
chmod +x "$BRIDGE3/escalate.sh"

# Run the real watchdog in background. Use a short loop budget: we expect
# it to detect the prompt and escalate within ~10 s (one poll cycle).
env CCBRIDGE_DIR="$BRIDGE3" WORKSPACE="$WS3" bash "$WATCHDOG" >"$BRIDGE3/watchdog.out" 2>"$BRIDGE3/watchdog.err" &
WD_PID=$!

# Poll for up to 12 s for escalations.log to appear.
LOG3="$WS3/.cc/escalations.log"
waited=0
while [ "$waited" -lt 12 ]; do
  if [ -s "$LOG3" ]; then
    break
  fi
  sleep 1
  waited=$((waited + 1))
done

# Kill the watchdog regardless of outcome. Use SIGKILL because watchdog.sh
# installs a `trap cleanup EXIT INT TERM` handler — after running the
# handler, bash continues the loop instead of exiting (the documented
# behaviour for a custom TERM trap that doesn't re-exit). SIGKILL can't be
# trapped, so the process dies immediately and `wait` returns promptly.
# We also kill any direct children (the sleep / read.sh sub-processes)
# defensively so they don't keep the wait blocked.
# Redirect stderr in this block so bash's "Killed" job-control notice
# doesn't pollute the otherwise clean test output.
{
  kill -KILL "$WD_PID" 2>/dev/null || true
  pkill -KILL -P "$WD_PID" 2>/dev/null || true
  wait "$WD_PID" 2>/dev/null || true
} 2>/dev/null

echo "  watchdog waited ${waited}s before escalations.log appeared"

if [ -s "$LOG3" ]; then
  pass "watchdog wrote escalations.log via escalate.sh"
else
  fail "escalations.log not written within 12 s"
fi

if grep -q "prodctl_nuke" "$LOG3" 2>/dev/null; then
  pass "log contains the matched pattern token"
else
  fail "log missing matched pattern token"
fi

# Critical: the watchdog must have refused (NOT called keys.sh return).
if [ -f "$BRIDGE3/keys.log" ] && grep -q "return" "$BRIDGE3/keys.log" 2>/dev/null; then
  fail "watchdog pressed Enter despite danger match (refusal broken)"
else
  pass "watchdog refused (keys.sh not called for Enter)"
fi

# The watchdog.log itself should still have the existing DANGER line.
if grep -q "DANGER" "$BRIDGE3/watchdog.log" 2>/dev/null; then
  pass "watchdog.log still has DANGER refusal line (back-compat)"
else
  fail "watchdog.log missing DANGER refusal line"
fi

# ---------------------------------------------------------------------------
# Case 4 — UTF-8 boundary safety in watchdog snippet truncation
#
# Background: the watchdog builds a ~200-char snippet of the visible
# buffer before piping it into escalate.sh. The previous implementation
# used `cut -c1-200`, which on macOS/Linux operates on BYTES — cutting
# at byte 200 can land mid-multibyte sequence and emit invalid UTF-8
# into escalations.log (breaking jq, Slack webhooks, etc).
#
# This case exercises the integration path with a buffer that places a
# multibyte UTF-8 character (€ = \xe2\x82\xac, 3 bytes) straddling the
# 200-byte boundary, then verifies the resulting escalations.log is
# valid UTF-8 via `iconv -f UTF-8 -t UTF-8 < <log>`.
# ---------------------------------------------------------------------------
echo
echo "── Case 4: watchdog snippet truncation is UTF-8-safe ──"
WS4="$(mktemp -d "$TMP_ROOT/wd-esc-XXXXXX")"
mkdir -p "$WS4/.cc"
BRIDGE4="$(mktemp -d "$TMP_ROOT/wd-esc-bridge-XXXXXX")"

echo 'prodctl_nuke' > "$WS4/.cc/danger_patterns_extra.txt"
: > "$BRIDGE4/danger_patterns.txt"

# Craft a buffer so the snippet path lands mid-multibyte. After the
# `tr '\n' ' '` collapse the buffer is roughly one line; we want the
# 200-byte mark to land on byte 2 of a 3-byte € (\xe2\x82\xac). Pad
# with 198 'a's, then €, then trailing junk + the prompt the watchdog
# requires. The danger token 'prodctl_nuke' lives later in the buffer.
# We write the buffer to a fixture file so the stub read.sh can `cat`
# it verbatim (no shell-quoting hazards with multibyte bytes).
{
  printf 'a%.0s' $(seq 1 198)
  printf '\xe2\x82\xac'
  printf 'trailing-junk prodctl_nuke --target=prod\n'
  printf 'Do you want to proceed?\n1. Yes\n2. No\n'
} > "$BRIDGE4/buffer.txt"

cat > "$BRIDGE4/read.sh" <<EOF
#!/usr/bin/env bash
cat "$BRIDGE4/buffer.txt"
EOF
chmod +x "$BRIDGE4/read.sh"

cat > "$BRIDGE4/keys.sh" <<EOF
#!/usr/bin/env bash
echo "keys.sh called with: \$*" >> "$BRIDGE4/keys.log"
EOF
chmod +x "$BRIDGE4/keys.sh"

cp "$ESCALATE" "$BRIDGE4/escalate.sh"
chmod +x "$BRIDGE4/escalate.sh"

env CCBRIDGE_DIR="$BRIDGE4" WORKSPACE="$WS4" bash "$WATCHDOG" >"$BRIDGE4/watchdog.out" 2>"$BRIDGE4/watchdog.err" &
WD_PID4=$!

LOG4="$WS4/.cc/escalations.log"
waited=0
while [ "$waited" -lt 12 ]; do
  if [ -s "$LOG4" ]; then
    break
  fi
  sleep 1
  waited=$((waited + 1))
done

{
  kill -KILL "$WD_PID4" 2>/dev/null || true
  pkill -KILL -P "$WD_PID4" 2>/dev/null || true
  wait "$WD_PID4" 2>/dev/null || true
} 2>/dev/null

echo "  watchdog waited ${waited}s before escalations.log appeared"

if [ -s "$LOG4" ]; then
  pass "watchdog wrote escalations.log on UTF-8-boundary buffer"
else
  fail "escalations.log not written within 12 s"
fi

# Core assertion: the resulting log must be valid UTF-8. `iconv -f UTF-8
# -t UTF-8` exits non-zero on any invalid byte sequence.
if iconv -f UTF-8 -t UTF-8 <"$LOG4" >/dev/null 2>&1; then
  pass "escalations.log is valid UTF-8 (no mid-multibyte cut)"
else
  fail "escalations.log contains invalid UTF-8 — snippet cut mid-multibyte"
fi

# ---------------------------------------------------------------------------
# Cleanup
# ---------------------------------------------------------------------------
rm -rf "$WS1" "$WS2" "$WS3" "$WS4" "$BRIDGE3" "$BRIDGE4"
rm -f "$OUT2"

echo
if [ "$fails" -eq 0 ]; then
  echo "PASS — escalate.sh isolation + watchdog integration both behave as specified."
  exit 0
else
  echo "FAIL — $fails assertion(s) failed."
  exit 1
fi
