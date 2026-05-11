#!/usr/bin/env bash
# BUG-1 regression: launch_cc.sh detect_cc_for_workspace must match BOTH
# bare-name `claude` argv[0] AND full-path /…/claude argv[0].
#
# Test mechanics — must work in non-interactive runners (CI, Claude Code's
# Bash tool, etc.) as well as in interactive terminals:
#
#   1. /usr/bin/script -q /dev/null gives the fake a controlling pty so
#      launch_cc.sh's is_terminal_cc() tty check (added in v4.5.1) passes.
#      Without this the awk match no longer matters — the tty filter drops
#      every candidate before the regex test is reached.
#
#   2. The INNER `bash -c '...'` runs a compound body (echo + sleep), not
#      a single command. Bash optimizes single-command `-c` strings by
#      exec'ing directly into the command — which would replace bash with
#      sleep and lose the argv[0]="claude" we set via `exec -a claude`. A
#      compound body forces bash to stay alive as the interpreter, so
#      argv[0] survives in `ps -axo command=`.
#
#   3. The fake's PID is NOT $! (that's the script wrapper). The inner bash
#      writes its own $$ to a pidfile so we can assert on the correct PID.
set -uo pipefail
WS=$(mktemp -d)
PIDFILE="$WS/.fakepid"
SCRIPT_PID=""
FAKE_PID=""
trap 'rm -rf "$WS"; kill ${SCRIPT_PID:-0} ${FAKE_PID:-0} 2>/dev/null' EXIT

( cd "$WS" && /usr/bin/script -q /dev/null bash -c "exec -a claude bash -c 'echo \$\$ > \"$PIDFILE\" ; sleep 30'" ) >/dev/null 2>&1 &
SCRIPT_PID=$!

# Wait up to 2s for the inner bash to write its PID.
for _ in 1 2 3 4 5 6 7 8 9 10; do
  [ -s "$PIDFILE" ] && break
  sleep 0.2
done
FAKE_PID=$(cat "$PIDFILE" 2>/dev/null || true)

if [ -z "$FAKE_PID" ]; then
  echo "FAIL: fake-claude PID never written (script wrapper failed to spawn?)"
  exit 1
fi

PID=$(bash "$(dirname "$0")/../scripts/launch_cc.sh" "$WS" --detect-only 2>/dev/null | tail -1)
EXIT=$?

if [ "$EXIT" -eq 0 ] && [ "$PID" = "$FAKE_PID" ]; then
  echo "PASS"
  exit 0
else
  echo "FAIL: exit=$EXIT pid=$PID expected=$FAKE_PID"
  exit 1
fi
