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

WS="${1:?usage: learning.sh <workspace> <category> [k=v ...]   (stdin = optional long-form body)}"
CAT="${2:?usage: learning.sh <workspace> <category> [k=v ...]   (stdin = optional long-form body)}"
shift 2

# v4.6 — argv validation. Reject empty workspace or category and any kv pair
# that doesn't contain '=' (common mistake: positional arg where kv expected).
[ -d "$WS" ] || { echo "[learning] ERROR: workspace not a dir: $WS" >&2; exit 1; }
[ -n "$CAT" ] || { echo "[learning] ERROR: empty category" >&2; exit 1; }
for arg in "$@"; do
  case "$arg" in
    *=*) ;;  # ok
    *) echo "[learning] ERROR: argument '$arg' is not key=value" >&2; exit 1 ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ID=$("$SCRIPT_DIR/register_project.sh" "$WS")

CCBRIDGE="${CCBRIDGE_HOME:-$HOME/.cache/ccbridge}"
LOCAL_F="$WS/.cc/learnings.jsonl"
CENTRAL_F="$CCBRIDGE/learnings/$ID.jsonl"
mkdir -p "$WS/.cc"

# v4.6 — optional stdin body (F5). If anything is piped on stdin, capture it
# under a "body" field. Useful for multi-line notes / markdown / log excerpts
# that don't fit in key=value kv pairs.
BODY=""
if [ ! -t 0 ]; then
  BODY="$(cat)"
fi

TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
JSON='{"ts":"'"$TS"'","ws_id":"'"$ID"'","category":"'"$CAT"'"'
for arg in "$@"; do
  k="${arg%%=*}"
  v="${arg#*=}"
  v_esc=$(printf '%s' "$v" | python3 -c 'import sys,json; sys.stdout.write(json.dumps(sys.stdin.read())[1:-1])')
  JSON="$JSON,\"$k\":\"$v_esc\""
done
if [ -n "$BODY" ]; then
  BODY_ESC=$(printf '%s' "$BODY" | python3 -c 'import sys,json; sys.stdout.write(json.dumps(sys.stdin.read())[1:-1])')
  JSON="$JSON,\"body\":\"$BODY_ESC\""
fi
JSON="$JSON}"

# Append-only, both sides. Order: local first (closer to caller, debuggable), then central.
echo "$JSON" >> "$LOCAL_F"
echo "$JSON" >> "$CENTRAL_F" 2>/dev/null || true  # central write best-effort

# v4.6 — H2: print one-line success so the caller knows the write landed.
# Routes to stderr so structured-output callers can still pipe stdout cleanly.
echo "[learning] event=$CAT ws=$ID -> $LOCAL_F" >&2
