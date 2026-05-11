#!/usr/bin/env bash
# swarm_join.sh — register this machine as a worker for an autoresearch swarm.
#
# Usage: swarm_join.sh <swarm-dir> <worker-id>
#
# v4.2 scaffolding: workers coordinate via a shared filesystem
# (Dropbox / iCloud / S3-via-mount / NFS). No network protocol yet.
#
# Logic:
#   1. Verify <swarm-dir>/manifest.json exists and is valid JSON.
#   2. Reject if a *live* worker with the same id is already heartbeating
#      (last_seen within STALE_AFTER_SEC). Stale heartbeats are reclaimable.
#   3. Write/refresh <swarm-dir>/workers/<worker-id>.json with current heartbeat.
#   4. Print manifest.best_known_scores to stdout so the local agent knows
#      what to beat.
#   5. Exit 0 on success; non-zero with a clear error otherwise.
#
# Bash 3.2 compatible. macOS-friendly. python3 used for JSON parsing only.

set -u
set -o pipefail

STALE_AFTER_SEC="${SWARM_STALE_AFTER_SEC:-300}"  # 5 min

usage() {
  echo "Usage: $0 <swarm-dir> <worker-id>" >&2
}

if [ "$#" -ne 2 ]; then
  usage
  exit 2
fi

SWARM_DIR="$1"
WORKER_ID="$2"

if [ -z "$SWARM_DIR" ] || [ -z "$WORKER_ID" ]; then
  usage
  exit 2
fi

# Validate worker_id chars (alnum, -, _, .)
case "$WORKER_ID" in
  *[!A-Za-z0-9._-]*)
    echo "ERROR: worker_id must contain only [A-Za-z0-9._-]" >&2
    exit 2
    ;;
esac

MANIFEST="$SWARM_DIR/manifest.json"
WORKERS_DIR="$SWARM_DIR/workers"
HEARTBEAT="$WORKERS_DIR/$WORKER_ID.json"

if [ ! -d "$SWARM_DIR" ]; then
  echo "ERROR: swarm-dir not found: $SWARM_DIR" >&2
  exit 1
fi

if [ ! -f "$MANIFEST" ]; then
  echo "ERROR: manifest.json not found at $MANIFEST" >&2
  echo "       (Initialize the swarm by writing a manifest. See assets/scoreboard_schema.json.)" >&2
  exit 1
fi

# Validate manifest JSON shape.
python3 - "$MANIFEST" <<'PY' || exit 1
import json, sys
p = sys.argv[1]
try:
    with open(p, "r") as f:
        m = json.load(f)
except Exception as e:
    print(f"ERROR: manifest is not valid JSON: {e}", file=sys.stderr)
    sys.exit(1)
required = ["schema_version", "swarm_name", "skills", "best_known_scores"]
missing = [k for k in required if k not in m]
if missing:
    print(f"ERROR: manifest missing required keys: {missing}", file=sys.stderr)
    sys.exit(1)
if m.get("schema_version") != 1:
    print(f"ERROR: unsupported manifest schema_version={m.get('schema_version')}", file=sys.stderr)
    sys.exit(1)
PY

mkdir -p "$WORKERS_DIR" || {
  echo "ERROR: could not create $WORKERS_DIR" >&2
  exit 1
}

NOW_ISO="$(date -u +'%Y-%m-%dT%H:%M:%SZ')"
NOW_EPOCH="$(date -u +'%s')"
HOSTNAME_VAL="$(hostname 2>/dev/null || echo unknown)"
PID_VAL="$$"

# Check for live duplicate.
if [ -f "$HEARTBEAT" ]; then
  LAST_EPOCH="$(python3 - "$HEARTBEAT" "$NOW_EPOCH" <<'PY'
import json, sys, time, calendar
p, now_s = sys.argv[1], int(sys.argv[2])
try:
    with open(p) as f:
        h = json.load(f)
    ts = h.get("last_seen")
    if not ts:
        print(0)
        sys.exit(0)
    # parse 2026-05-11T14:23:00Z
    t = time.strptime(ts, "%Y-%m-%dT%H:%M:%SZ")
    epoch = calendar.timegm(t)
    print(epoch)
except Exception:
    print(0)
PY
)"
  AGE=$((NOW_EPOCH - LAST_EPOCH))
  if [ "$LAST_EPOCH" -gt 0 ] && [ "$AGE" -lt "$STALE_AFTER_SEC" ]; then
    echo "ERROR: worker_id '$WORKER_ID' is already live (last_seen ${AGE}s ago, stale_after=${STALE_AFTER_SEC}s)." >&2
    echo "       Pick a different worker_id, or wait for the stale window to elapse." >&2
    exit 1
  fi
fi

# Atomic-ish write: temp + mv (same FS).
TMP_HB="$HEARTBEAT.tmp.$$"
cat >"$TMP_HB" <<JSON
{
  "worker_id": "$WORKER_ID",
  "last_seen": "$NOW_ISO",
  "current_skill": null,
  "pid": $PID_VAL,
  "hostname": "$HOSTNAME_VAL"
}
JSON
mv "$TMP_HB" "$HEARTBEAT" || {
  rm -f "$TMP_HB"
  echo "ERROR: failed to write heartbeat at $HEARTBEAT" >&2
  exit 1
}

echo "[swarm_join] worker=$WORKER_ID registered at $NOW_ISO"
echo "[swarm_join] heartbeat: $HEARTBEAT"
echo ""
echo "[swarm_join] best_known_scores (beat these):"
python3 - "$MANIFEST" <<'PY'
import json, sys
with open(sys.argv[1]) as f:
    m = json.load(f)
bks = m.get("best_known_scores", {}) or {}
if not bks:
    print("  (none yet — swarm is brand new)")
else:
    for k in sorted(bks):
        print(f"  {k}: {bks[k]}")
PY

exit 0
