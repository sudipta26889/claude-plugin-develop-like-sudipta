#!/usr/bin/env bash
# aggregate_learnings.sh — sweep all registered projects' learning tails and
# produce a single dated aggregate file. Idempotent; safe to run multiple times.
#
# Why: each workspace appends to ~/.cache/ccbridge/learnings/<id>.jsonl. The
# autoresearch loop needs a single chronologically-merged view of "what happened
# across the whole user fleet today" — that's the input to distill_learnings.sh.
#
# Usage:
#   aggregate_learnings.sh                       # aggregate everything new since last run
#   aggregate_learnings.sh --since 2026-05-01    # explicit since date (inclusive)
#   aggregate_learnings.sh --date 2026-05-10     # emit only entries from that day
#
# Output: ~/.cache/ccbridge/aggregated/<YYYY-MM-DD>.jsonl  (one file per UTC day spanned)

set -euo pipefail

CCBRIDGE="${CCBRIDGE_HOME:-$HOME/.cache/ccbridge}"
PROJECTS="$CCBRIDGE/projects.json"
AGG_DIR="$CCBRIDGE/aggregated"
CURSOR="$CCBRIDGE/.aggregate_cursor"

mkdir -p "$AGG_DIR"
[ -f "$PROJECTS" ] || { echo "no projects registered yet" >&2; exit 0; }

SINCE=""
DATE_FILTER=""
while [ $# -gt 0 ]; do
  case "$1" in
    --since) SINCE="$2"; shift 2 ;;
    --date)  DATE_FILTER="$2"; shift 2 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

# Default --since: read cursor (last ts processed). If absent, sweep everything.
if [ -z "$SINCE" ] && [ -z "$DATE_FILTER" ]; then
  [ -f "$CURSOR" ] && SINCE=$(cat "$CURSOR")
fi

# Stream all tail files through python; filter by ts; group by date; append to per-day jsonl.
# Python because jq is not guaranteed, and shell sort-by-ts is fragile.
python3 - "$CCBRIDGE" "$AGG_DIR" "$SINCE" "$DATE_FILTER" "$CURSOR" <<'PY'
import json, os, re, sys, glob
ccbridge, agg_dir, since, date_filter, cursor_path = sys.argv[1:]
# v5.0 — walk BOTH the local tails (learnings/*.jsonl) AND the remote-pulled
# tails (learnings/remote-<host>/*.jsonl). sync_learnings.sh deposits per-peer
# learning files under remote-<host>/ subdirs; without picking those up the
# autoresearch loop sees only the local Mac's data and misses cross-MACHINE
# signal (vs cross-PROJECT, which the central tail already handles).
local_glob  = os.path.join(ccbridge, "learnings", "*.jsonl")
remote_glob = os.path.join(ccbridge, "learnings", "remote-*", "*.jsonl")
tails = sorted(glob.glob(local_glob) + glob.glob(remote_glob))

def source_host_for(path):
    # learnings/remote-<host>/<id>.jsonl  →  <host>
    # learnings/<id>.jsonl                →  "local"
    parent = os.path.basename(os.path.dirname(path))
    m = re.match(r"^remote-(.+)$", parent)
    return m.group(1) if m else "local"

buckets = {}   # date -> [lines]
max_ts = since or ""

for tail in tails:
    src_host = source_host_for(tail)
    try:
        with open(tail) as f:
            for line in f:
                line = line.rstrip("\n")
                if not line:
                    continue
                try:
                    rec = json.loads(line)
                except Exception:
                    continue
                ts = rec.get("ts", "")
                if since and ts <= since:
                    continue
                day = ts[:10]  # YYYY-MM-DD
                if date_filter and day != date_filter:
                    continue
                # Inject source_host so distillation can compute cross-machine
                # signatures alongside cross-project ones. Don't overwrite if
                # the line already carried a source_host (e.g. came in via a
                # peer whose autoresearch already tagged it).
                rec.setdefault("source_host", src_host)
                buckets.setdefault(day, []).append(json.dumps(rec))
                if ts > max_ts:
                    max_ts = ts
    except FileNotFoundError:
        continue

total = 0
for day, lines in sorted(buckets.items()):
    out = os.path.join(agg_dir, f"{day}.jsonl")
    with open(out, "a") as f:
        for ln in lines:
            f.write(ln + "\n")
    total += len(lines)
    print(f"[aggregate] {day}: +{len(lines)} -> {out}")

if max_ts and not date_filter:
    with open(cursor_path, "w") as f:
        f.write(max_ts)

print(f"[aggregate] total appended: {total}")
PY
