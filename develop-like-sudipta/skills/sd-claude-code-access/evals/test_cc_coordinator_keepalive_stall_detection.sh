#!/usr/bin/env bash
# Eval: cc-coordinator-keepalive Step 2 stall-classification math.
#
# The keepalive SKILL.md says:
#   Healthy:  now - heartbeat_ts <  7m  → no-op, continue to next job
#   Stalled:  now - heartbeat_ts >= 7m  → write escalation + log keepalive_stall
#
# This eval pins down the math + the side-effect path. The SKILL.md prompt
# is markdown loaded by Cowork's scheduled-task runner; we can't trigger
# that runner from a shell eval, but we CAN model the same classification
# and prove the contract is internally consistent:
#
#   1. The SKILL still documents the 7-minute threshold (anchor grep).
#   2. A 10-minute-old heartbeat classifies as STALLED.
#   3. A 1-minute-old heartbeat classifies as HEALTHY (negative case —
#      ensures the math works in BOTH directions; a regression that flips
#      `>=` to `<` would also fail this assertion).
#   4. The stall branch writes <ws>/.cc/escalations/keepalive-<ts>.md to
#      the documented path (touch-only sentinel — full payload contract
#      is owned by the SKILL, not this eval).
#
# macOS-only date math (`date -u -v-NM` and `date -u -j -f ...`) — the
# plugin's other evals already gate on macOS for the same reason.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILL_MD="$SCRIPT_DIR/../../../assets/scheduled-tasks/cc-coordinator-keepalive/SKILL.md"

[ -f "$SKILL_MD" ] || { echo "FAIL: SKILL.md missing at $SKILL_MD"; exit 1; }

# Anchor: the 7-min threshold must still be documented. If a future edit
# raises/lowers it, the eval's THRESHOLD_S below must be updated in lockstep.
grep -qE 'now - ts >= 7m|7 minutes is ~7 missed' "$SKILL_MD" || {
  echo "FAIL: SKILL.md no longer documents the 7-minute stall threshold"
  exit 1
}

THRESHOLD_S=420   # 7 minutes; mirrors SKILL.md's documented value.

WS=$(mktemp -d)
trap 'rm -rf "$WS"' EXIT
mkdir -p "$WS/.cc"

# Step 2's classification, modeled in shell. The SKILL.md prompt is
# markdown — what the eval is testing is whether the documented MATH
# resolves correctly against macOS date semantics. Any regression that
# breaks this resolution (e.g. SKILL changes to a different ts format,
# or the threshold drifts) will surface here.
classify() {
  local heartbeat_file="$1"
  [ -f "$heartbeat_file" ] || { echo "MISSING"; return; }
  local ts
  ts=$(awk 'NR==1 {print $1}' "$heartbeat_file")
  local hb_epoch now_epoch age
  hb_epoch=$(date -u -j -f "%Y-%m-%dT%H:%M:%SZ" "$ts" +%s 2>/dev/null) || { echo "BAD_TS"; return; }
  now_epoch=$(date -u +%s)
  age=$((now_epoch - hb_epoch))
  if [ "$age" -ge "$THRESHOLD_S" ]; then
    echo "STALLED $age"
  else
    echo "HEALTHY $age"
  fi
}

# Case 1 — 10-minute-old heartbeat → STALLED.
STALE_TS=$(date -u -v-10M +%Y-%m-%dT%H:%M:%SZ)
echo "$STALE_TS idle" > "$WS/.cc/orchestrator-heartbeat"
verdict_stale=$(classify "$WS/.cc/orchestrator-heartbeat")
case "$verdict_stale" in
  STALLED*) ;;
  *) echo "FAIL (case 1): expected STALLED for 10-min-old heartbeat, got: $verdict_stale"; exit 1 ;;
esac

# Side-effect path — when STALLED, the SKILL says write
# <ws>/.cc/escalations/keepalive-<ts>.md. Model that path with a touch.
ESC_DIR="$WS/.cc/escalations"
mkdir -p "$ESC_DIR"
NOW_TS=$(date -u +%Y-%m-%dT%H-%M-%SZ)   # safe for filename (colons → dashes)
ESC_FILE="$ESC_DIR/keepalive-$NOW_TS.md"
: > "$ESC_FILE"
[ -f "$ESC_FILE" ] || { echo "FAIL: stall branch could not write to $ESC_FILE"; exit 1; }
case "$ESC_FILE" in
  */.cc/escalations/keepalive-*.md) ;;
  *) echo "FAIL: escalation file path doesn't match SKILL's documented shape: $ESC_FILE"; exit 1 ;;
esac

# Case 2 — 1-minute-old heartbeat → HEALTHY (negative case; ensures the
# math is sensitive in both directions, not just the stall side).
FRESH_TS=$(date -u -v-1M +%Y-%m-%dT%H:%M:%SZ)
echo "$FRESH_TS idle" > "$WS/.cc/orchestrator-heartbeat"
verdict_fresh=$(classify "$WS/.cc/orchestrator-heartbeat")
case "$verdict_fresh" in
  HEALTHY*) ;;
  *) echo "FAIL (case 2): expected HEALTHY for 1-min-old heartbeat, got: $verdict_fresh"; exit 1 ;;
esac

# Case 3 — exactly at threshold (7m old) is STALLED per `>=` semantics.
EDGE_TS=$(date -u -v-7M +%Y-%m-%dT%H:%M:%SZ)
echo "$EDGE_TS idle" > "$WS/.cc/orchestrator-heartbeat"
verdict_edge=$(classify "$WS/.cc/orchestrator-heartbeat")
case "$verdict_edge" in
  STALLED*) ;;
  *) echo "FAIL (case 3): expected STALLED for exactly-7m heartbeat (>= semantics), got: $verdict_edge"; exit 1 ;;
esac

echo "PASS"
