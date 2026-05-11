#!/usr/bin/env bash
# Eval: cc-orchestrator SKILL.md must specify a quota-saver early-exit
# when no active-job.json exists in any workspace.
#
# Why a contract eval and not a runtime test: cc-orchestrator is a markdown
# SKILL.md prompt loaded by Cowork's scheduled-task runtime, not a shell
# script we can exec. The eval enforces the documentation contract — if any
# of these markers go missing in a future edit, the per-minute quota-saver
# behavior loses its anchor and we risk burning subscription quota on idle
# machines.
set -uo pipefail
SKILL_MD="$(dirname "$0")/../../../assets/scheduled-tasks/cc-orchestrator/SKILL.md"

[ -f "$SKILL_MD" ] || { echo "FAIL: SKILL.md missing at $SKILL_MD"; exit 1; }

# Must mention the early-exit (any of these phrasings).
grep -qE "exit IMMEDIATELY if no active jobs|exit immediately if \.cc/active-job\.json absent|quota saver" "$SKILL_MD" || {
  echo "FAIL: SKILL.md does not document the quota-saver early-exit"
  exit 1
}

# Must mention the active-job.json file by name.
grep -q "active-job\.json" "$SKILL_MD" || {
  echo "FAIL: SKILL.md does not reference active-job.json"
  exit 1
}

# Must mention the per-fire wall-clock cap (either phrasing).
grep -qE "wall-clock cap|cycle_timeout" "$SKILL_MD" || {
  echo "FAIL: SKILL.md missing per-fire wall-clock cap"
  exit 1
}

echo "PASS"
