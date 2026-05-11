#!/usr/bin/env bash
# state.sh — append a structured event to <workspace>/.cc/state.json.
# Usage: state.sh <workspace> <event_type> [key=value ...]
# Examples:
#   state.sh /path/to/proj phase_start phase=7
#   state.sh /path/to/proj phase_complete phase=7 commits=5 tests=280
#   state.sh /path/to/proj prompt_approved fp=abc123
#   state.sh /path/to/proj danger_blocked pattern='git reset --hard'
#   state.sh /path/to/proj nudge_sent reason='hung 600s'
#
# state.json is a JSONL file (one event per line) so it's append-safe even
# under concurrent writers. The "current" snapshot is the rolling tail.
# Resume-after-crash reads the tail to know where the run left off.
set -euo pipefail
WS="${1:?usage: state.sh <workspace> <event_type> [k=v ...]}"
EVT="${2:?usage: state.sh <workspace> <event_type> [k=v ...]}"
shift 2
mkdir -p "$WS/.cc"
F="$WS/.cc/state.json"

# Build JSON object from key=value args
TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
JSON='{"ts":"'"$TS"'","event":"'"$EVT"'"'
for arg in "$@"; do
  k="${arg%%=*}"
  v="${arg#*=}"
  # Escape double quotes in value
  v_escaped=$(printf '%s' "$v" | sed 's/"/\\"/g')
  JSON="$JSON,\"$k\":\"$v_escaped\""
done
JSON="$JSON}"

echo "$JSON" >> "$F"
