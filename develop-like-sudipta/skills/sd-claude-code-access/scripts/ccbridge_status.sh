#!/usr/bin/env bash
# ccbridge_status.sh — one-screen health check of the v4.3+ closed loop.
#
# What it reports (in order, top to bottom):
#   PLUGIN     version + install dir
#   BRIDGE     scripts present in ~/.cache/ccbridge/, cache subdirs, projects count
#   WATCHDOG   running PID(s) + their WORKSPACE env (via ps -E)
#   LEARNINGS  per-category event counts in last 7 days (across all projects)
#   DISTILL    last distillation report's CROSS_N + decisions log tail
#   AUTORES    latest baseline score per autoresearch-wired skill
#   HEALTH     one-word verdict + reasons
#
# This script is bash-only (no MCP), so it runs everywhere — Cowork sandbox,
# Desktop_Commander, an SSH session, anywhere. For Cowork scheduled-task
# next-run-times you need the /ccbridge-status slash command (which merges
# this output with mcp__scheduled-tasks__list_scheduled_tasks).
#
# Exit codes:
#   0  bridge healthy enough (no missing required pieces)
#   1  bridge has problems (missing scripts, dead bridge, etc.)

set -uo pipefail   # NOT -e: report problems, don't abort on the first one

CCBRIDGE="${CCBRIDGE_HOME:-$HOME/.cache/ccbridge}"
PLUGIN_HINT="${1:-}"   # optional: path hint to the plugin root

EXPECTED_SCRIPTS=(
  send.sh read.sh read_history.sh keys.sh
  watchdog.sh start_watchdog.sh stop_watchdog.sh
  nudge_if_stuck.sh audit.sh unblock_cc.sh
  state.sh state_salvage.sh lock.sh diagnose.sh run_summary.sh
  install_precommit.sh escalate.sh
  register_project.sh learning.sh launch_cc.sh
  aggregate_learnings.sh distill_learnings.sh ccbridge_status.sh
)

PROBLEMS=0

print_header() {
  local now; now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  local host; host=$(hostname -s 2>/dev/null || hostname)
  echo "================================================================"
  echo " ccbridge-status @ $host @ $now"
  echo "================================================================"
}

print_plugin() {
  echo
  echo "PLUGIN"
  local plugin_json=""
  if [ -n "$PLUGIN_HINT" ] && [ -f "$PLUGIN_HINT/.claude-plugin/plugin.json" ]; then
    plugin_json="$PLUGIN_HINT/.claude-plugin/plugin.json"
  else
    # Find any develop-like-sudipta plugin.json under common locations.
    for d in \
      "$HOME/Workspace/personal/claude-plugin-develop-like-sudipta/develop-like-sudipta" \
      "$HOME/.claude/plugins"/*/develop-like-sudipta \
      "$HOME/Library/Application Support/Claude/local-agent-mode-sessions"/*/cowork_plugins/cache/*/develop-like-sudipta; do
      if [ -f "$d/.claude-plugin/plugin.json" ]; then
        plugin_json="$d/.claude-plugin/plugin.json"
        break
      fi
    done
  fi
  if [ -n "$plugin_json" ]; then
    local v; v=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("version","?"))' "$plugin_json" 2>/dev/null)
    echo "  version: ${v:-?}"
    echo "  install: $(dirname "$(dirname "$plugin_json")")"
  else
    echo "  WARN: plugin.json not found at any known location"
    PROBLEMS=$((PROBLEMS+1))
  fi
}

print_bridge() {
  echo
  echo "BRIDGE ($CCBRIDGE/)"
  if [ ! -d "$CCBRIDGE" ]; then
    echo "  MISSING: $CCBRIDGE does not exist — run /ccbridge-init"
    PROBLEMS=$((PROBLEMS+1))
    return
  fi
  local present=0 missing=()
  for f in "${EXPECTED_SCRIPTS[@]}"; do
    if [ -f "$CCBRIDGE/$f" ]; then
      present=$((present+1))
    else
      missing+=("$f")
    fi
  done
  echo "  scripts: $present / ${#EXPECTED_SCRIPTS[@]} present"
  if [ ${#missing[@]} -gt 0 ]; then
    echo "  MISSING: ${missing[*]}"
    PROBLEMS=$((PROBLEMS+1))
  fi
  local subdir_status=""
  for sd in learnings aggregated distillation; do
    if [ -d "$CCBRIDGE/$sd" ]; then
      subdir_status+="$sd/ "
    else
      subdir_status+="!$sd "
      PROBLEMS=$((PROBLEMS+1))
    fi
  done
  echo "  subdirs: $subdir_status"
  if [ -f "$CCBRIDGE/projects.json" ]; then
    local n; n=$(python3 -c 'import json,sys; print(len(json.load(open(sys.argv[1])).get("projects",[])))' "$CCBRIDGE/projects.json" 2>/dev/null || echo "?")
    echo "  registered projects: $n"
  else
    echo "  projects.json: MISSING"
    PROBLEMS=$((PROBLEMS+1))
  fi
}

print_watchdog() {
  echo
  echo "WATCHDOG"
  local pids; pids=$(pgrep -f "$CCBRIDGE/watchdog.sh" 2>/dev/null | tr '\n' ' ')
  if [ -z "$pids" ]; then
    echo "  status: not running"
    return
  fi
  echo "  status: running"
  for pid in $pids; do
    # ps -E shows env on Linux; on macOS ps doesn't have -E. Use procstat-style
    # parse via `ps eww` if available; otherwise just show PID.
    local ws
    ws=$(ps eww -p "$pid" 2>/dev/null | tr ' ' '\n' | awk -F= '/^WORKSPACE=/{print $2; exit}')
    echo "  pid=$pid WORKSPACE=${ws:-?}"
  done
}

print_learnings() {
  echo
  echo "LEARNINGS (last 7 days, all projects)"
  local since
  if date -u -v-7d +%Y-%m-%d >/dev/null 2>&1; then
    since=$(date -u -v-7d +%Y-%m-%d)              # macOS BSD date
  else
    since=$(date -u -d '7 days ago' +%Y-%m-%d)    # GNU date
  fi
  if ! ls "$CCBRIDGE/learnings"/*.jsonl >/dev/null 2>&1; then
    echo "  (no learning tails)"
    return
  fi
  python3 - "$CCBRIDGE" "$since" <<'PY'
import json, os, sys, glob
from collections import Counter
cc, since = sys.argv[1:]
cat = Counter()
ws_ids = set()
total = 0
for f in glob.glob(os.path.join(cc, "learnings", "*.jsonl")):
    with open(f) as fh:
        for ln in fh:
            ln = ln.strip()
            if not ln: continue
            try: rec = json.loads(ln)
            except: continue
            if rec.get("ts","")[:10] < since: continue
            cat[rec.get("category","?")] += 1
            ws_ids.add(rec.get("ws_id","?"))
            total += 1
if total == 0:
    print("  (no events in last 7 days)")
else:
    print(f"  total: {total} events across {len(ws_ids)} workspace(s)")
    for c, n in cat.most_common():
        print(f"    {c:<28s} {n}")
PY
}

print_distill() {
  echo
  echo "DISTILLATION"
  local latest
  latest=$(ls -t "$CCBRIDGE/distillation"/*.md 2>/dev/null | head -1)
  if [ -z "$latest" ]; then
    echo "  (no distillation reports yet)"
    return
  fi
  echo "  latest: $latest"
  # awk-count avoids the grep -c double-output bug (grep -c exits 1 on no
  # matches and the `|| echo 0` fallback would print "0" twice).
  local cross
  cross=$(awk '/\*\*YES\*\*/{n++} END{print n+0}' "$latest" 2>/dev/null)
  echo "  cross-project signatures: ${cross:-0}"
  if [ -f "$CCBRIDGE/distillation/.decisions.log" ]; then
    echo "  recent decisions:"
    tail -3 "$CCBRIDGE/distillation/.decisions.log" 2>/dev/null | sed 's/^/    /'
  fi
}

print_autoresearch() {
  echo
  echo "AUTORESEARCH baselines"
  if [ -z "$PLUGIN_HINT" ] || [ ! -d "$PLUGIN_HINT/skills" ]; then
    echo "  (plugin path unknown — pass plugin root as first arg to see baselines)"
    return
  fi
  local any=0
  for skill in "$PLUGIN_HINT/skills"/*/autoresearch/.baselines.json; do
    [ -f "$skill" ] || continue
    any=1
    local name; name=$(basename "$(dirname "$(dirname "$skill")")")
    # Baselines file is a JSON array (NOT JSONL). Try array first; if that
    # fails (e.g. older JSONL-format file), fall back to line-by-line parse.
    local best
    best=$(python3 -c '
import json, sys
def scores_from(data):
    if isinstance(data, list):
        return [d.get("score", 0) for d in data if isinstance(d, dict)]
    return []
try:
    raw = open(sys.argv[1]).read().strip()
    if not raw:
        print("?"); sys.exit()
    if raw.startswith("["):
        data = json.loads(raw)
        scores = scores_from(data)
    else:
        scores = [json.loads(x).get("score", 0) for x in raw.splitlines() if x.strip()]
    if scores:
        print(f"{max(scores):.4f}")
    else:
        print("?")
except Exception:
    print("?")
' "$skill" 2>/dev/null)
    echo "  $name: $best (best across history)"
  done
  if [ "$any" -eq 0 ]; then
    echo "  (no autoresearch-wired skills found)"
  fi
}

print_health() {
  echo
  echo "HEALTH"
  if [ "$PROBLEMS" -eq 0 ]; then
    echo "  green — bridge is intact. To activate the closed loop:"
    echo "    1. /cc-drive <workspace>  (registers + emits first events)"
    echo "    2. wait for nightly aggregate at 02:15 local"
    echo "    3. wait for weekly distill at Sunday 03:30 local"
  else
    echo "  red — $PROBLEMS problem(s) detected. Run /ccbridge-init to fix."
  fi
}

print_header
print_plugin
print_bridge
print_watchdog
print_learnings
print_distill
print_autoresearch
print_health

[ "$PROBLEMS" -eq 0 ] && exit 0 || exit 1
