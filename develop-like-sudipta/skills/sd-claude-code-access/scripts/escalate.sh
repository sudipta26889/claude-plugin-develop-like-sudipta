#!/usr/bin/env bash
# escalate.sh — pluggable shim for watchdog refusals.
#
# Reads a free-form text payload from stdin and:
#   1. Appends a timestamped record to <workspace>/.cc/escalations.log
#      (the default action — works with zero config).
#   2. If $ESCALATE_CMD is set, pipes the same record into a subshell
#      running that command (opt-in fan-out for ntfy / Slack / email /
#      whatever the user wires up).
#
# The watchdog calls this script every time it refuses to auto-approve
# a CC permission prompt because a danger pattern matched. The refusal
# itself is handled by watchdog.sh; this hook is purely additive — it
# turns a silent stall into something a human can find.
#
# Usage:
#   echo "matched=foo\nprompt=..." | escalate.sh <workspace>
#
# Exit codes:
#   0 — payload logged (and ESCALATE_CMD fanned out, if set)
#   non-zero — workspace arg missing, log write failed, or escalate.sh
#              was invoked with a bad path. ESCALATE_CMD failures are
#              swallowed: they must never break the watchdog loop.
#
# Bash 3.2 compatible. No external deps beyond coreutils + date.

set -euo pipefail

WORKSPACE="${1:?escalate.sh: workspace path required as first argument}"
LOG="$WORKSPACE/.cc/escalations.log"

mkdir -p "$(dirname "$LOG")"

# Read the entire stdin payload into a single variable so we can fan it
# out to both destinations (log + optional ESCALATE_CMD) without re-reading.
PAYLOAD="$(cat)"
TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# Default action: append to the local log. Format is intentionally plain
# text and grep-able — no JSON, no log rotation. Users who want
# structured logging can add their own ESCALATE_CMD that re-serialises.
{
  printf '[%s]\n' "$TS"
  printf '%s\n' "$PAYLOAD"
  printf -- '---\n'
} >> "$LOG"

# Opt-in fan-out. Failures here must NOT crash the watchdog or this
# shim — the local log is the source of truth; ESCALATE_CMD is a nice
# to-have. Hence `|| true` and a stderr warning.
if [ -n "${ESCALATE_CMD:-}" ]; then
  {
    printf '[%s]\n' "$TS"
    printf '%s\n' "$PAYLOAD"
  } | bash -c "$ESCALATE_CMD" || {
    echo "escalate.sh: ESCALATE_CMD failed (exit $?): $ESCALATE_CMD" >&2
    true
  }
fi
