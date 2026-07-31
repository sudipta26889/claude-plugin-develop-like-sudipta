#!/usr/bin/env bash
# Smoke eval: ccbridge_status.sh — health-check reporting under a fully
# synthetic CCBRIDGE_HOME.
#
# ccbridge_status.sh is the user-facing diagnostic invoked via
# /ccbridge-status. It walks the bridge install + watchdog + learnings +
# distillation + autoresearch and prints a one-screen verdict. The
# smoke pins down both directions of the verdict:
#
#   GREEN — fake CCBRIDGE populated with all 22 expected scripts +
#           subdirs + projects.json → exit 0, "green" in HEALTH section,
#           every section header rendered.
#
#   RED   — fake CCBRIDGE points at an empty directory (missing scripts
#           + subdirs + projects.json) → exit 1, "red" in HEALTH with a
#           non-zero problem count.
set -uo pipefail

SCRIPT="$(dirname "$0")/../scripts/ccbridge_status.sh"
[ -x "$SCRIPT" ] || { echo "FAIL: $SCRIPT not executable"; exit 1; }

# Mirrors the EXPECTED_SCRIPTS array baked into ccbridge_status.sh. If
# ccbridge_status.sh extends the list, this eval needs the same additions
# or the green path will trip a "MISSING" error. Keep them in sync.
EXPECTED_SCRIPTS=(
  send.sh read.sh read_history.sh keys.sh
  watchdog.sh start_watchdog.sh stop_watchdog.sh
  nudge_if_stuck.sh audit.sh unblock_cc.sh
  state.sh state_salvage.sh lock.sh diagnose.sh run_summary.sh
  install_precommit.sh escalate.sh
  register_project.sh learning.sh launch_cc.sh
  aggregate_learnings.sh distill_learnings.sh ccbridge_status.sh
  dispatch_signature.sh propose_fix_pr.sh sync_learnings.sh
)
# v5.0.7 L4 — data files the status check now verifies.
EXPECTED_DATA=(
  danger_patterns.txt skip_nudge_patterns.txt
)

# Synthesize a HOME so the script's PLUGIN_HINT-fallback search doesn't
# wander into the real $HOME/Workspace/... and report on the dev's actual
# plugin install (which would couple this eval's output to dev state).
FAKE_HOME=$(mktemp -d)
trap 'rm -rf "$FAKE_HOME"' EXIT

CC_GREEN="$FAKE_HOME/.cache/ccbridge"
CC_RED="$FAKE_HOME/empty-ccbridge"
mkdir -p "$CC_GREEN/learnings" "$CC_GREEN/aggregated" "$CC_GREEN/distillation" "$CC_RED"

# Populate the green CCBRIDGE: touch every expected script + a valid
# projects.json. Content doesn't matter — ccbridge_status.sh's
# presence-check is `[ -f ]`, not exec/parse.
for s in "${EXPECTED_SCRIPTS[@]}"; do
  : > "$CC_GREEN/$s"
done
for d in "${EXPECTED_DATA[@]}"; do
  : > "$CC_GREEN/$d"
done
echo '{"version":1,"projects":[]}' > "$CC_GREEN/projects.json"

# Build a plugin-root pointer so PLUGIN section finds the real plugin.json.
# This is the first arg the script accepts as $PLUGIN_HINT.
PLUGIN_ROOT=$(cd "$(dirname "$0")/.." && pwd)
PLUGIN_HINT="$(cd "$PLUGIN_ROOT/../../.." && pwd)/develop-like-sudipta"

# ──────────────────────────────────────────────────────────────────────────
# Case A — fully-populated CCBRIDGE → green verdict + exit 0
# ──────────────────────────────────────────────────────────────────────────
rc=0
out=$(HOME="$FAKE_HOME" CCBRIDGE_HOME="$CC_GREEN" bash "$SCRIPT" "$PLUGIN_HINT" 2>&1) || rc=$?

if [ "$rc" -ne 0 ]; then
  echo "FAIL (green): expected exit 0, got $rc"
  echo "--- output ---"; echo "$out" | sed 's/^/  /'
  exit 1
fi

# Every section header should render.
for h in 'PLUGIN' 'BRIDGE' 'WATCHDOG' 'LEARNINGS' 'DISTILLATION' 'AUTORESEARCH' 'HEALTH'; do
  echo "$out" | grep -q "^$h" || {
    echo "FAIL (green): section header '$h' not rendered"
    echo "$out" | sed 's/^/  /'
    exit 1
  }
done

# HEALTH should say green.
echo "$out" | grep -q 'green — bridge is intact' || {
  echo "FAIL (green): HEALTH did not report green"
  echo "$out" | grep -A2 '^HEALTH' | sed 's/^/  /'
  exit 1
}

# ──────────────────────────────────────────────────────────────────────────
# Case B — empty CCBRIDGE (no scripts, no subdirs, no projects.json) →
#           red verdict + exit 1 + non-zero problem count
# ──────────────────────────────────────────────────────────────────────────
rc=0
out=$(HOME="$FAKE_HOME" CCBRIDGE_HOME="$CC_RED" bash "$SCRIPT" "$PLUGIN_HINT" 2>&1) || rc=$?

if [ "$rc" -ne 1 ]; then
  echo "FAIL (red): expected exit 1, got $rc"
  echo "--- output ---"; echo "$out" | sed 's/^/  /'
  exit 1
fi

echo "$out" | grep -qE 'red — [0-9]+ problem' || {
  echo "FAIL (red): HEALTH did not report 'red — N problem(s)' shape"
  echo "$out" | grep -A2 '^HEALTH' | sed 's/^/  /'
  exit 1
}

echo "PASS"
