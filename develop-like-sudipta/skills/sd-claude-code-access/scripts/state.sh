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

# v4.6 — `tail`/`recent` subcommand: dump last N JSONL events pretty-printed.
# Discoverable alternative to `tail -10 .cc/state.json | jq` for users who
# don't use jq daily.
if [ "${1:-}" = "tail" ] || [ "${1:-}" = "recent" ]; then
  WS="${2:?usage: state.sh tail <workspace> [N=10]}"
  N="${3:-10}"
  F="$WS/.cc/state.json"
  if [ ! -f "$F" ]; then
    echo "[state] no state.json at $F" >&2
    exit 1
  fi
  tail -n "$N" "$F" | python3 -c '
import json, sys
for ln in sys.stdin:
    ln = ln.strip()
    if not ln: continue
    try: print(json.dumps(json.loads(ln), indent=2))
    except: print(ln)
'
  exit 0
fi

WS="${1:?usage: state.sh <workspace> <event_type> [k=v ...]   OR   state.sh tail <workspace> [N=10]}"
EVT="${2:?usage: state.sh <workspace> <event_type> [k=v ...]   OR   state.sh tail <workspace> [N=10]}"
shift 2
mkdir -p "$WS/.cc"
F="$WS/.cc/state.json"

# Build JSON object from key=value args
TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
JSON='{"ts":"'"$TS"'","event":"'"$EVT"'"'
for arg in "$@"; do
  k="${arg%%=*}"
  v="${arg#*=}"
  # v5.0.7 H2 — proper JSON string escaping. The old sed escaped `"` ONLY;
  # any value containing a backslash (regex text, danger patterns, Windows
  # paths — exactly what buffer snippets carry) produced invalid JSON like
  # `"\b"` mid-string and corrupted the JSONL line. state_salvage.sh existed
  # largely to clean up after this. Order matters: backslash FIRST, then
  # quote; control chars stripped (they can't appear in argv normally, but
  # captured buffer text can smuggle \r / \t through).
  v_escaped=$(printf '%s' "$v" | tr -d '\000-\010\013\014\016-\037' | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e 's/\t/\\t/g' -e $'s/\r/\\\\r/g')
  JSON="$JSON,\"$k\":\"$v_escaped\""
done
JSON="$JSON}"

echo "$JSON" >> "$F"
