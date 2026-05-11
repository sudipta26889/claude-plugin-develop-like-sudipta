#!/usr/bin/env bash
# learning.sh — capture a runtime learning event (dual-write).
#
# Why: the plugin is used across many projects on the user's machine. Each project
# observes different failure modes (permission patterns, flake clusters, substrate
# quirks, watchdog recoveries). For autoresearch to learn from ALL of them, every
# capture has to land in TWO places:
#   1) <workspace>/.cc/learnings.jsonl    — local, debuggable, lives with the project
#   2) ~/.cache/ccbridge/learnings/<id>.jsonl — central tail, swept by scheduled tasks
#
# Side-effect: calls register_project.sh first, so first-touch projects get registered
# automatically with no manual setup.
#
# Usage: learning.sh <workspace> <category> [k=v ...]
# Categories (free-form, but these are the canonical ones aggregated/scored):
#   watchdog_recovery        nudge or escalation that unblocked CC
#   permission_pattern       a permission/refusal phrase observed
#   audit_finding            audit.sh flagged a discrepancy
#   bug_triage               bug-triage-agent classification
#   verify_red               static or test command failed
#   substrate_choice         which Path (A/B/C/D) was selected and why
#   browser_test_failure     /browser-test red
#   bug_reproduction         /reproduce-bug failing test seeded
#   spec_drift               stale or regenerated playwright spec
#   resume_after_crash       /cc-resume invoked
#
# All values are escaped for JSON. Keys may not contain '='. Multi-line values: use \n.

set -euo pipefail

WS="${1:?usage: learning.sh <workspace> <category> [k=v ...]}"
CAT="${2:?usage: learning.sh <workspace> <category> [k=v ...]}"
shift 2

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ID=$("$SCRIPT_DIR/register_project.sh" "$WS")

CCBRIDGE="${CCBRIDGE_HOME:-$HOME/.cache/ccbridge}"
LOCAL_F="$WS/.cc/learnings.jsonl"
CENTRAL_F="$CCBRIDGE/learnings/$ID.jsonl"
mkdir -p "$WS/.cc"

TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
JSON='{"ts":"'"$TS"'","ws_id":"'"$ID"'","category":"'"$CAT"'"'
for arg in "$@"; do
  k="${arg%%=*}"
  v="${arg#*=}"
  v_esc=$(printf '%s' "$v" | python3 -c 'import sys,json; sys.stdout.write(json.dumps(sys.stdin.read())[1:-1])')
  JSON="$JSON,\"$k\":\"$v_esc\""
done
JSON="$JSON}"

# Append-only, both sides. Order: local first (closer to caller, debuggable), then central.
echo "$JSON" >> "$LOCAL_F"
echo "$JSON" >> "$CENTRAL_F" 2>/dev/null || true  # central write best-effort
