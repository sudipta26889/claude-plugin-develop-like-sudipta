#!/usr/bin/env bash
# test_ssh_probe.sh — smoke test for scripts/ssh_probe.sh.
#
# Background: ssh_probe.sh is the gate for "Path D" — driving CC on a
# REMOTE Mac via SSH from Cowork's LOCAL Mac. We can't assume CI has a
# real SSH target available, so this test PATH-shims `ssh` with a stub
# that simulates the remote state based on env flags. The probe should
# not be able to tell the difference between a real ssh and our stub.
#
# Cases covered:
#   1. No SSH_TARGET (env unset, no arg)        -> exit 1, "no-ssh-target"
#   2. SSH connection fails (stub rc=255)        -> exit 2, "ssh-failed"
#   3. Remote has no osascript                   -> exit 3, "no-osascript-on-remote"
#   4. Remote has no claude CLI                  -> exit 4, "no-claude-cli-on-remote"
#   5. All present                                -> exit 0, "READY 14.5 claude 2.5.0"
#
# Stub strategy:
#   We write a stub `ssh` into a temp dir and prepend that dir to PATH.
#   The stub inspects its argv and env-flags to decide what to emit:
#     STUB_SSH_CONN=ok|fail
#     STUB_OSASCRIPT=yes|no
#     STUB_CLAUDE=yes|no
#
# Bash 3.2 compatible. No `mapfile`, `wait -n`, associative arrays.
#
# Usage: ./test_ssh_probe.sh
# Exit 0 on PASS, non-zero on any failed assertion.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROBE="$SCRIPT_DIR/../scripts/ssh_probe.sh"

if [ ! -f "$PROBE" ]; then
  echo "FAIL: ssh_probe.sh not found at $PROBE"
  exit 2
fi

fails=0
fail() { fails=$((fails + 1)); echo "  FAIL: $*"; }
pass() { echo "  PASS: $*"; }

# ---------------------------------------------------------------------------
# Build the ssh stub
# ---------------------------------------------------------------------------
# The stub matches on argv to decide which probe call this is. Order
# matters: 'echo READY' is checked first because the probe's connectivity
# check runs first.
TMP_BIN="$(mktemp -d -t ssh-stub-bin.XXXXXX)"
trap 'rm -rf "$TMP_BIN"' EXIT INT TERM

cat > "$TMP_BIN/ssh" <<'EOF'
#!/usr/bin/env bash
# Stub `ssh` — strips ssh options (-o XYZ=ABC) so we can match on the
# actual remote-command argument. The remote command is always the LAST
# positional argument when ssh is invoked the way ssh_probe.sh does it.
set -u

# Walk argv and capture the last argument (the remote command).
REMOTE_CMD=""
prev_was_o=0
for a in "$@"; do
  if [ $prev_was_o -eq 1 ]; then
    prev_was_o=0
    continue
  fi
  case "$a" in
    -o) prev_was_o=1 ;;
    -*) ;;     # other flags (none in our use, but safe to skip)
    *)  REMOTE_CMD="$a" ;;  # final non-flag wins (host comes first, cmd last)
  esac
done

# Connectivity branch — first probe call uses 'echo READY'
case "$REMOTE_CMD" in
  *"echo READY"*)
    if [ "${STUB_SSH_CONN:-ok}" = "ok" ]; then
      echo READY
      exit 0
    else
      # 255 mirrors real ssh's exit code on connection failure.
      echo "Connection refused (stub)" 1>&2
      exit 255
    fi
    ;;
  *"command -v osascript"*)
    if [ "${STUB_OSASCRIPT:-yes}" = "yes" ]; then
      echo /usr/bin/osascript
      exit 0
    else
      # Empty stdout, non-zero — matches `command -v` semantics for missing.
      exit 1
    fi
    ;;
  *"command -v claude"*)
    if [ "${STUB_CLAUDE:-yes}" = "yes" ]; then
      echo /usr/local/bin/claude
      exit 0
    else
      exit 1
    fi
    ;;
  *"sw_vers -productVersion"*)
    echo "${STUB_MACOS_VERSION:-14.5}"
    exit 0
    ;;
  *"claude --version"*)
    echo "${STUB_CLAUDE_VERSION:-claude 2.5.0}"
    exit 0
    ;;
  *)
    # Default: succeed silently (probe doesn't issue other commands).
    exit 0
    ;;
esac
EOF
chmod +x "$TMP_BIN/ssh"

# Helper: run the probe with a clean env (no real SSH_TARGET inherited)
# and the stub PATH prepended. We accept extra env-vars for the stub.
run_probe() {
  # First arg: optional explicit positional for ssh_probe.sh.
  local arg="${1:-}"
  shift || true
  # The remaining args are env assignments (FOO=bar) passed to env(1).
  env -i HOME="$HOME" PATH="$TMP_BIN:/usr/bin:/bin" "$@" bash "$PROBE" $arg
}

# ---------------------------------------------------------------------------
# Case 1 — no SSH_TARGET, no arg
# ---------------------------------------------------------------------------
echo "-- Case 1: no SSH_TARGET, no arg --"
OUT1="$(run_probe '' 2>&1)"
RC1=$?
if [ $RC1 -eq 1 ]; then
  pass "exit code 1 for no-ssh-target (got $RC1)"
else
  fail "expected exit 1, got $RC1 (output: $OUT1)"
fi
if printf '%s' "$OUT1" | grep -q "no-ssh-target"; then
  pass "stdout reports 'no-ssh-target'"
else
  fail "expected 'no-ssh-target' in stdout: $OUT1"
fi

# ---------------------------------------------------------------------------
# Case 2 — SSH connection fails (stub rc=255)
# ---------------------------------------------------------------------------
echo "-- Case 2: ssh connection fails (rc=255) --"
OUT2="$(run_probe 'user@host.invalid' STUB_SSH_CONN=fail 2>&1)"
RC2=$?
if [ $RC2 -eq 2 ]; then
  pass "exit code 2 for ssh-failed (got $RC2)"
else
  fail "expected exit 2, got $RC2 (output: $OUT2)"
fi
if printf '%s' "$OUT2" | grep -q "ssh-failed"; then
  pass "stdout reports 'ssh-failed'"
else
  fail "expected 'ssh-failed' in stdout: $OUT2"
fi

# ---------------------------------------------------------------------------
# Case 3 — no osascript on remote
# ---------------------------------------------------------------------------
echo "-- Case 3: no osascript on remote --"
OUT3="$(run_probe 'user@linux.example.com' STUB_OSASCRIPT=no 2>&1)"
RC3=$?
if [ $RC3 -eq 3 ]; then
  pass "exit code 3 for no-osascript-on-remote (got $RC3)"
else
  fail "expected exit 3, got $RC3 (output: $OUT3)"
fi
if printf '%s' "$OUT3" | grep -q "no-osascript-on-remote"; then
  pass "stdout reports 'no-osascript-on-remote'"
else
  fail "expected 'no-osascript-on-remote' in stdout: $OUT3"
fi

# ---------------------------------------------------------------------------
# Case 4 — no claude CLI on remote
# ---------------------------------------------------------------------------
echo "-- Case 4: no claude CLI on remote --"
OUT4="$(run_probe 'user@mac.local' STUB_CLAUDE=no 2>&1)"
RC4=$?
if [ $RC4 -eq 4 ]; then
  pass "exit code 4 for no-claude-cli-on-remote (got $RC4)"
else
  fail "expected exit 4, got $RC4 (output: $OUT4)"
fi
if printf '%s' "$OUT4" | grep -q "no-claude-cli-on-remote"; then
  pass "stdout reports 'no-claude-cli-on-remote'"
else
  fail "expected 'no-claude-cli-on-remote' in stdout: $OUT4"
fi

# ---------------------------------------------------------------------------
# Case 5 — all present
# ---------------------------------------------------------------------------
echo "-- Case 5: all present, READY with versions --"
OUT5="$(run_probe 'user@mac.local' 2>&1)"
RC5=$?
if [ $RC5 -eq 0 ]; then
  pass "exit code 0 for READY (got $RC5)"
else
  fail "expected exit 0, got $RC5 (output: $OUT5)"
fi
if printf '%s' "$OUT5" | grep -q "^READY"; then
  pass "stdout starts with READY"
else
  fail "expected 'READY' at start of stdout: $OUT5"
fi
if printf '%s' "$OUT5" | grep -q "14.5"; then
  pass "stdout includes macOS version 14.5"
else
  fail "expected '14.5' in stdout: $OUT5"
fi
if printf '%s' "$OUT5" | grep -q "claude 2.5.0"; then
  pass "stdout includes claude version 2.5.0"
else
  fail "expected 'claude 2.5.0' in stdout: $OUT5"
fi

# ---------------------------------------------------------------------------
# Case 5b — SSH_TARGET via env (not positional)
# ---------------------------------------------------------------------------
echo "-- Case 5b: SSH_TARGET via env --"
OUT5B="$(run_probe '' SSH_TARGET=user@mac.local 2>&1)"
RC5B=$?
if [ $RC5B -eq 0 ]; then
  pass "exit code 0 with env SSH_TARGET (got $RC5B)"
else
  fail "expected exit 0 with env SSH_TARGET, got $RC5B (output: $OUT5B)"
fi
if printf '%s' "$OUT5B" | grep -q "^READY"; then
  pass "stdout starts with READY (env-only invocation)"
else
  fail "expected 'READY' in env-only invocation: $OUT5B"
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo
if [ $fails -eq 0 ]; then
  echo "ALL PASS"
  exit 0
else
  echo "$fails assertion(s) FAILED"
  exit 1
fi
