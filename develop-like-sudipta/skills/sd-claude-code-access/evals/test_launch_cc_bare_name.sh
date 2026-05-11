#!/usr/bin/env bash
# BUG-1 regression: launch_cc.sh detect_cc_for_workspace must match BOTH
# bare-name `claude` argv[0] AND full-path /…/claude argv[0].
set -uo pipefail
WS=$(mktemp -d)
trap 'rm -rf "$WS"; kill ${FAKE_PID:-0} 2>/dev/null' EXIT

# Spawn a fake "claude" via exec -a so argv[0] is literally "claude" with cwd=$WS
( cd "$WS" && exec -a claude bash -c "sleep 30" ) &
FAKE_PID=$!
sleep 1

PID=$(bash "$(dirname "$0")/../scripts/launch_cc.sh" "$WS" --detect-only 2>/dev/null | tail -1)
EXIT=$?

if [ "$EXIT" -eq 0 ] && [ "$PID" = "$FAKE_PID" ]; then
  echo "PASS"
  exit 0
else
  echo "FAIL: exit=$EXIT pid=$PID expected=$FAKE_PID"
  exit 1
fi
