#!/usr/bin/env bash
# register_project.sh — idempotently register a workspace in the global ccbridge registry.
#
# Why: autoresearch runs as a scheduled task; it needs to know every workspace that
# uses this plugin so it can sweep their learnings.jsonl files and learn across projects.
# Each command (watchdog, audit, /cc-drive, /browser-test, /reproduce-bug, verify-gate)
# calls this as its first step — registration is then a no-op for already-known projects.
#
# Usage: register_project.sh <workspace_absolute_path>
# Effects:
#   - Hashes the workspace path → 16-char id
#   - Upserts into ~/.cache/ccbridge/projects.json
#   - Touches ~/.cache/ccbridge/learnings/<id>.jsonl (so aggregator picks it up)
#   - Echoes the id on stdout (callers can use it for direct writes)
#
# bash 3.2 compatible — no associative arrays, no mapfile.

set -euo pipefail

WS="${1:?usage: register_project.sh <workspace_absolute_path>}"
# Resolve to absolute path (macOS lacks readlink -f; use python fallback)
WS_ABS=$(cd "$WS" 2>/dev/null && pwd -P) || WS_ABS="$WS"

CCBRIDGE="${CCBRIDGE_HOME:-$HOME/.cache/ccbridge}"
mkdir -p "$CCBRIDGE/learnings" "$CCBRIDGE/aggregated" "$CCBRIDGE/distillation"

PROJECTS="$CCBRIDGE/projects.json"
[ -f "$PROJECTS" ] || echo '{"version":1,"projects":[]}' > "$PROJECTS"

# Hash workspace path → stable 16-hex-char id
ID=$(printf '%s' "$WS_ABS" | shasum -a 256 | awk '{print substr($1,1,16)}')
TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# Upsert: use python for json safety (jq not guaranteed on user machines)
python3 - "$PROJECTS" "$ID" "$WS_ABS" "$TS" <<'PY'
import json, sys, os
p, pid, path, ts = sys.argv[1:]
with open(p) as f: d = json.load(f)
projs = d.setdefault("projects", [])
for entry in projs:
    if entry.get("id") == pid:
        entry["last_seen"] = ts
        entry["path"] = path  # update if moved
        break
else:
    projs.append({"id": pid, "path": path, "first_seen": ts, "last_seen": ts})
tmp = p + ".tmp"
with open(tmp, "w") as f: json.dump(d, f, indent=2)
os.replace(tmp, p)
PY

# Ensure the per-project tail log exists
TAIL="$CCBRIDGE/learnings/$ID.jsonl"
[ -f "$TAIL" ] || : > "$TAIL"

echo "$ID"
