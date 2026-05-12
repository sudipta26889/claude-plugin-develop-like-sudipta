#!/usr/bin/env bash
# Eval: cc-orchestrator active-job branches — phase advance, no-next-phase,
# and the monitor.stop kill switch.
#
# Three contracts from the orchestrator SKILL.md (Step 2.2 stop conditions
# and Step 2.4 phase-advance decision):
#
#   A. Phase advance — last state event is `phase_complete phase=N` AND
#      `<ws>/.cc/phase-<N+1>.md` exists → orchestrator sends
#      `Read .cc/phase-<N+1>.md and proceed.` via send.sh.
#
#   B. No-next-phase — last state event is `phase_complete phase=N` but
#      `<ws>/.cc/phase-<N+1>.md` does NOT exist → orchestrator writes a
#      `BLOCKED no-next-phase phase=<N>` learning event and pauses the job.
#
#   C. monitor.stop kill switch — `<ws>/.cc/monitor.stop` exists →
#      HIGHEST priority, evaluated BEFORE any other work. Set
#      job-status.json to {"done": false, "done_reason": "user_stop",
#      "stopped_at": "<UTC>"} and exit the per-job loop.
#
# Why a simulation, not a runtime test: cc-orchestrator's per-fire body is
# Cowork-side reasoning over a markdown SKILL prompt — we can't trigger
# it from a shell eval. What we CAN test is the documented decision logic
# expressed in shell, against the SKILL's anchor text, so a future SKILL
# edit that drifts from any of these three contracts surfaces here.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILL_MD="$SCRIPT_DIR/../../../assets/scheduled-tasks/cc-orchestrator/SKILL.md"

[ -f "$SKILL_MD" ] || { echo "FAIL: SKILL.md missing at $SKILL_MD"; exit 1; }

# Anchor greps — drift catchers. If any anchor disappears, the eval's
# simulation has been written against a contract the SKILL no longer
# documents; an explicit update is required before re-asserting greens.
grep -q 'phase-<N+1>\.md' "$SKILL_MD" || {
  echo "FAIL: SKILL.md no longer documents the phase-<N+1>.md naming convention"
  exit 1
}
grep -q 'BLOCKED no-next-phase' "$SKILL_MD" || {
  echo "FAIL: SKILL.md no longer documents the 'BLOCKED no-next-phase' learning event"
  exit 1
}
grep -q '\.cc/monitor\.stop' "$SKILL_MD" || {
  echo "FAIL: SKILL.md no longer documents the .cc/monitor.stop kill switch"
  exit 1
}
grep -q '"done_reason": "user_stop"' "$SKILL_MD" || {
  echo "FAIL: SKILL.md no longer documents done_reason=user_stop on monitor.stop"
  exit 1
}

WS=$(mktemp -d)
trap 'rm -rf "$WS"' EXIT
mkdir -p "$WS/.cc"

# ──────────────────────────────────────────────────────────────────────────
# Simulators — model the orchestrator's documented decision logic in shell.
# Each returns ONE word on stdout that names the branch the orchestrator
# would take given the fixture's state. The assertions below match those
# branch names against the SKILL's contracts.
# ──────────────────────────────────────────────────────────────────────────

# Highest-priority check: if monitor.stop exists, the orchestrator stops
# IMMEDIATELY before any other work. SKILL.md is explicit about this being
# evaluated before reading state, polling the buffer, or anything else.
decide() {
  local ws="$1"
  if [ -f "$ws/.cc/monitor.stop" ]; then
    echo "USER_STOP"
    return
  fi
  # State-driven branches: look at the last event in state.json (JSONL).
  local last_event last_phase
  if [ -f "$ws/.cc/state.json" ]; then
    last_event=$(tail -1 "$ws/.cc/state.json" | python3 -c 'import json,sys; d=json.loads(sys.stdin.read()); print(d.get("event",""))' 2>/dev/null || echo "")
    last_phase=$(tail -1 "$ws/.cc/state.json" | python3 -c 'import json,sys; d=json.loads(sys.stdin.read()); print(d.get("phase",""))' 2>/dev/null || echo "")
  fi
  if [ "$last_event" = "phase_complete" ] && [ -n "$last_phase" ]; then
    local next=$((last_phase + 1))
    if [ -f "$ws/.cc/phase-$next.md" ]; then
      echo "ADVANCE phase-$next"
    else
      echo "BLOCKED phase=$last_phase"
    fi
    return
  fi
  echo "OTHER"
}

# write_user_stop_status — the side effect the SKILL says monitor.stop
# triggers. Test that the documented JSON shape is producible from shell.
write_user_stop_status() {
  local ws="$1"
  local ts; ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  python3 -c 'import json,sys
json.dump({"done": False, "done_reason": "user_stop", "stopped_at": sys.argv[1]}, open(sys.argv[2], "w"))
' "$ts" "$ws/.cc/job-status.json"
}

# ──────────────────────────────────────────────────────────────────────────
# Case A — phase advance (last event = phase_complete; next directive present)
# ──────────────────────────────────────────────────────────────────────────
cat > "$WS/.cc/active-job.json" <<'JSON'
{"job_id":"sentinel","plan_path":"docs/plans/x.md","max_duration_hours":24,"max_cycles":1440,
 "done_criteria":{"phase_complete_min":7,"browser_test_required":false,"evidence_dir":"docs/e2e-testing"}}
JSON
cat > "$WS/.cc/state.json" <<'JSONL'
{"ts":"2026-05-12T01:00:00Z","event":"phase_start","phase":"1"}
{"ts":"2026-05-12T01:30:00Z","event":"phase_complete","phase":"1"}
JSONL
echo "# phase 2 directive" > "$WS/.cc/phase-2.md"

verdict_a=$(decide "$WS")
case "$verdict_a" in
  "ADVANCE phase-2") ;;
  *) echo "FAIL (case A): expected 'ADVANCE phase-2', got: $verdict_a"; exit 1 ;;
esac
# Side effect — what send.sh would receive. Don't actually invoke send.sh
# (osascript is destructive on a real Mac); model the trigger string.
TRIGGER="Read .cc/phase-2.md and proceed."
case "$TRIGGER" in
  "Read .cc/phase-"*".md and proceed.") ;;
  *) echo "FAIL (case A): trigger string shape changed: $TRIGGER"; exit 1 ;;
esac

# ──────────────────────────────────────────────────────────────────────────
# Case B — phase_complete but the next directive doesn't exist → BLOCKED.
# ──────────────────────────────────────────────────────────────────────────
rm -f "$WS/.cc/phase-2.md"   # remove the next directive
verdict_b=$(decide "$WS")
case "$verdict_b" in
  "BLOCKED phase=1") ;;
  *) echo "FAIL (case B): expected 'BLOCKED phase=1', got: $verdict_b"; exit 1 ;;
esac

# ──────────────────────────────────────────────────────────────────────────
# Case C — monitor.stop kill switch (highest priority, short-circuits all
# state-driven branches). Recreate phase-2.md so case A WOULD trigger again
# if the priority order regressed — that's the negative case.
# ──────────────────────────────────────────────────────────────────────────
echo "# phase 2 directive" > "$WS/.cc/phase-2.md"
touch "$WS/.cc/monitor.stop"

verdict_c=$(decide "$WS")
case "$verdict_c" in
  "USER_STOP") ;;
  *) echo "FAIL (case C): expected 'USER_STOP', got: $verdict_c"
     echo "  (monitor.stop must short-circuit BEFORE the state-driven phase-advance branch)"
     exit 1 ;;
esac

# Documented side effect — job-status.json gets {"done": false,
# "done_reason": "user_stop", "stopped_at": "<UTC>"}.
write_user_stop_status "$WS"
[ -f "$WS/.cc/job-status.json" ] || { echo "FAIL (case C): job-status.json not written"; exit 1; }
python3 -c '
import json, sys
d = json.load(open(sys.argv[1]))
assert d["done"] is False, f"done must be False, got {d['"'"'done'"'"']}"
assert d["done_reason"] == "user_stop", f"done_reason must be user_stop, got {d['"'"'done_reason'"'"']}"
assert "stopped_at" in d, "stopped_at missing"
' "$WS/.cc/job-status.json" || { echo "FAIL (case C): job-status.json shape wrong"; exit 1; }

echo "PASS"
