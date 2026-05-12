#!/usr/bin/env bash
# Eval: cc-coordinator-keepalive Step 1 idle path.
#
# The keepalive's documented Step 1 (mandatory quota-saver):
#   find ~/Workspace -maxdepth 4 -name "active-job.json" -path "*/.cc/*"
#   → if empty, "[keepalive] idle: no active jobs" + exit
#
# This eval runs the SAME find command Step 1 specifies against a fully
# synthetic HOME so it can never trip on the user's real workspaces. Two
# cases:
#   A. Fake HOME with NO Workspace/ at all → find must produce zero lines.
#   B. Fake HOME with a workspace that has .cc/ but NO active-job.json →
#      find must STILL produce zero lines (only active-job.json triggers
#      the per-minute keepalive cycle).
#
# A future SKILL.md edit that loosens the filename pattern, drops the
# -path filter, or changes maxdepth in a way that picks up stray files
# would flip this eval RED.
#
# Pattern follows test_cc_orchestrator_idle_exit.sh (same skill family).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILL_MD="$SCRIPT_DIR/../../../assets/scheduled-tasks/cc-coordinator-keepalive/SKILL.md"

[ -f "$SKILL_MD" ] || { echo "FAIL: SKILL.md missing at $SKILL_MD"; exit 1; }

# Sanity-check that the SKILL still documents the find command the eval
# is testing. If a future edit moves to a different discovery mechanism
# (e.g. projects.json registry sweep), this anchor catches it so the eval
# can be updated deliberately rather than silently drift.
grep -q 'find ~/Workspace -maxdepth 4 -name "active-job\.json" -path "\*/.cc/\*"' "$SKILL_MD" || {
  echo "FAIL: SKILL.md no longer documents the canonical find command Step 1 uses"
  exit 1
}

FAKE_HOME=$(mktemp -d)
trap 'rm -rf "$FAKE_HOME"' EXIT

run_find() {
  # Pass HOME via env-prefix so the child bash re-expands `~` against the
  # fake HOME at parse time. Inheriting HOME via export-then-bash works too
  # but is less defensible — the env-prefix form is the documented bash
  # behavior for HOME-scoped tilde expansion.
  HOME="$FAKE_HOME" bash -c \
    'find ~/Workspace -maxdepth 4 -name "active-job.json" -path "*/.cc/*" 2>/dev/null | head -20'
}

# Case A — HOME has no Workspace/ at all.
out_a=$(run_find)
if [ -n "$out_a" ]; then
  echo "FAIL (case A): find produced output against empty fake HOME"
  echo "  got: $out_a"
  exit 1
fi

# Case B — HOME has a workspace with .cc/ but NO active-job.json.
# Only state.json, learnings.jsonl, etc — the routine bridge files that
# accumulate on every actively-used workspace but DON'T indicate an
# active orchestrator job.
mkdir -p "$FAKE_HOME/Workspace/test-ws/.cc"
echo '{}' > "$FAKE_HOME/Workspace/test-ws/.cc/state.json"
echo '{}' > "$FAKE_HOME/Workspace/test-ws/.cc/learnings.jsonl"
touch    "$FAKE_HOME/Workspace/test-ws/.cc/.driver.lock"

out_b=$(run_find)
if [ -n "$out_b" ]; then
  echo "FAIL (case B): find matched something that isn't active-job.json"
  echo "  got: $out_b"
  exit 1
fi

# Positive control — drop a real active-job.json and confirm find WOULD
# catch it (defends against false-greens where the find command is broken
# in a way that always returns empty).
mkdir -p "$FAKE_HOME/Workspace/test-ws/.cc"
echo '{"job_id":"sentinel"}' > "$FAKE_HOME/Workspace/test-ws/.cc/active-job.json"
out_c=$(run_find)
if [ -z "$out_c" ]; then
  echo "FAIL (positive control): find did NOT find the sentinel active-job.json"
  echo "  this means the find pattern itself is broken — Step 1 would never wake"
  exit 1
fi

echo "PASS"
