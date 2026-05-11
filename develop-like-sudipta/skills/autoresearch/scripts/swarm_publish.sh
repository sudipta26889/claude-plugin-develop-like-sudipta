#!/usr/bin/env bash
# swarm_publish.sh — publish a local experiment result to the swarm scoreboard.
#
# Usage: swarm_publish.sh <swarm-dir> <skill> <target-file> <score> <scorer-mode>
#
# Optional env:
#   SWARM_WORKER_ID         worker_id to record (default: $(hostname))
#   SWARM_PLUGIN_ROOT       path to the develop-like-sudipta plugin root
#                           (used to read <plugin>/skills/<skill>/autoresearch/
#                           .baselines.json). Default: walks up from this
#                           script's directory.
#   SWARM_NOTES             freeform notes string appended to the entry
#   SWARM_PROPOSAL_ID       custom proposal id (default: <sha8>-<rand>)
#
# Logic:
#   1. Verify swarm-dir + target-file exist; score is a float in [0, 1].
#   2. Compute sha256 of target-file content -> target_hash.
#   3. Read local baseline (best accepted score) from
#      <plugin>/skills/<skill>/autoresearch/.baselines.json to compute
#      delta_from_local_baseline.
#   4. Append a scoreboard.jsonl entry. Use flock if available; fall back to
#      mkdir-lock (atomic on POSIX local + most network FSes).
#   5. Copy target-file content to
#      <swarm-dir>/proposals/<skill>-<sha8>-<score-pct>.<ext>
#   6. If score > current manifest.best_known_scores[skill], rewrite the
#      manifest atomically (temp + mv on same FS).
#   7. Print confirmation: target_hash, current global best, local delta.
#
# Bash 3.2 compatible. macOS-friendly. python3 used for JSON.

set -u
set -o pipefail

usage() {
  echo "Usage: $0 <swarm-dir> <skill> <target-file> <score> <scorer-mode>" >&2
}

if [ "$#" -ne 5 ]; then
  usage
  exit 2
fi

SWARM_DIR="$1"
SKILL="$2"
TARGET_FILE="$3"
SCORE_RAW="$4"
SCORER_MODE="$5"

WORKER_ID="${SWARM_WORKER_ID:-$(hostname 2>/dev/null || echo unknown)}"
NOTES="${SWARM_NOTES:-}"

# --- validate inputs ---
if [ ! -d "$SWARM_DIR" ]; then
  echo "ERROR: swarm-dir not found: $SWARM_DIR" >&2
  exit 1
fi
if [ ! -f "$SWARM_DIR/manifest.json" ]; then
  echo "ERROR: manifest.json missing in $SWARM_DIR" >&2
  exit 1
fi
if [ ! -f "$TARGET_FILE" ]; then
  echo "ERROR: target-file not found: $TARGET_FILE" >&2
  exit 1
fi

case "$SKILL" in
  ""|*[!a-z0-9-]*)
    echo "ERROR: skill name '$SKILL' must be lowercase [a-z0-9-]" >&2
    exit 2
    ;;
esac

# Score must be a float in [0, 1]
SCORE_OK="$(python3 - "$SCORE_RAW" <<'PY'
import sys
try:
    s = float(sys.argv[1])
except Exception:
    print("BAD"); sys.exit(0)
if s < 0 or s > 1:
    print("BAD"); sys.exit(0)
print(f"{s:.6f}")
PY
)"
if [ "$SCORE_OK" = "BAD" ]; then
  echo "ERROR: score '$SCORE_RAW' must be a float in [0, 1]" >&2
  exit 2
fi
SCORE="$SCORE_OK"

# --- find plugin root for local baseline (best-effort) ---
PLUGIN_ROOT="${SWARM_PLUGIN_ROOT:-}"
if [ -z "$PLUGIN_ROOT" ]; then
  SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
  # scripts/ -> autoresearch/ -> skills/ -> develop-like-sudipta/
  candidate="$(cd "$SCRIPT_DIR/../../.." 2>/dev/null && pwd)" || candidate=""
  PLUGIN_ROOT="$candidate"
fi

LOCAL_BASELINES=""
LOCAL_BEST=""
if [ -n "$PLUGIN_ROOT" ] && [ -f "$PLUGIN_ROOT/skills/$SKILL/autoresearch/.baselines.json" ]; then
  LOCAL_BASELINES="$PLUGIN_ROOT/skills/$SKILL/autoresearch/.baselines.json"
  LOCAL_BEST="$(python3 - "$LOCAL_BASELINES" <<'PY'
import json, sys
p = sys.argv[1]
best = None
try:
    with open(p) as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                row = json.loads(line)
            except Exception:
                continue
            if row.get("accepted") is True:
                s = row.get("score")
                if isinstance(s, (int, float)):
                    if best is None or s > best:
                        best = s
except Exception:
    pass
if best is None:
    # treat empty as 0.0 baseline
    print("")
else:
    print(f"{best:.6f}")
PY
)"
fi

# delta = score - local_best (if known); else null
DELTA="$(python3 - "$SCORE" "$LOCAL_BEST" <<'PY'
import sys
s = float(sys.argv[1])
lb = sys.argv[2]
if lb == "":
    print("null")
else:
    print(f"{(s - float(lb)):+.6f}")
PY
)"

# --- compute sha256 of target ---
sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print $1}'
  else
    python3 -c "import hashlib,sys; print(hashlib.sha256(open(sys.argv[1],'rb').read()).hexdigest())" "$1"
  fi
}
TARGET_SHA="$(sha256_of "$TARGET_FILE")"
TARGET_HASH="sha256:$TARGET_SHA"
SHA8="$(printf '%s' "$TARGET_SHA" | cut -c1-8)"

# Score percentage (e.g. 0.842 -> 84)
SCORE_PCT="$(python3 -c "import sys; s=float(sys.argv[1]); print(int(round(s*100)))" "$SCORE")"

# Filename extension from target.
ext="${TARGET_FILE##*/}"
case "$ext" in
  *.*) ext=".${ext##*.}" ;;
  *)   ext="" ;;
esac

PROPOSALS_DIR="$SWARM_DIR/proposals"
mkdir -p "$PROPOSALS_DIR" || { echo "ERROR: cannot create $PROPOSALS_DIR" >&2; exit 1; }
PROPOSAL_FNAME="${SKILL}-${SHA8}-${SCORE_PCT}${ext}"
PROPOSAL_PATH="$PROPOSALS_DIR/$PROPOSAL_FNAME"
PROPOSAL_ID="${SWARM_PROPOSAL_ID:-${SHA8}-$(printf '%04x' $RANDOM 2>/dev/null || echo "0000")}"

# --- atomic-ish lock on the scoreboard + manifest ---
LOCK_DIR="$SWARM_DIR/.swarm.lock"
acquire_lock() {
  local tries=0
  while ! mkdir "$LOCK_DIR" 2>/dev/null; do
    tries=$((tries + 1))
    if [ "$tries" -gt 100 ]; then
      echo "ERROR: could not acquire $LOCK_DIR after 100 tries; remove it if stale" >&2
      return 1
    fi
    sleep 0.1 2>/dev/null || sleep 1
  done
  return 0
}
release_lock() {
  rmdir "$LOCK_DIR" 2>/dev/null || true
}
trap release_lock EXIT INT TERM

acquire_lock || exit 1

# --- append scoreboard.jsonl ---
SCOREBOARD="$SWARM_DIR/scoreboard.jsonl"
NOW_ISO="$(date -u +'%Y-%m-%dT%H:%M:%SZ')"
ACCEPTED_LOCALLY="true"  # publish implies local-accept
ENTRY_JSON="$(python3 - <<PY
import json
entry = {
  "ts": "$NOW_ISO",
  "worker_id": "$WORKER_ID",
  "skill": "$SKILL",
  "target_hash": "$TARGET_HASH",
  "score": float("$SCORE"),
  "scorer_mode": "$SCORER_MODE",
  "accepted_locally": True,
  "proposal_id": "$PROPOSAL_ID",
}
delta = """$DELTA"""
if delta != "null":
    entry["delta_from_local_baseline"] = float(delta)
notes = """$NOTES"""
if notes:
    entry["notes"] = notes
print(json.dumps(entry, separators=(",", ":")))
PY
)"
printf '%s\n' "$ENTRY_JSON" >> "$SCOREBOARD"

# --- copy target content into proposals/ ---
cp "$TARGET_FILE" "$PROPOSAL_PATH.tmp" && mv "$PROPOSAL_PATH.tmp" "$PROPOSAL_PATH"

# --- update manifest if new global best ---
MANIFEST="$SWARM_DIR/manifest.json"
GLOBAL_BEST_OLD="$(python3 - "$MANIFEST" "$SKILL" <<'PY'
import json, sys
with open(sys.argv[1]) as f:
    m = json.load(f)
bks = m.get("best_known_scores", {}) or {}
v = bks.get(sys.argv[2])
print("" if v is None else f"{float(v):.6f}")
PY
)"

UPDATED="false"
if [ -z "$GLOBAL_BEST_OLD" ] || python3 -c "import sys; sys.exit(0 if float('$SCORE') > float('$GLOBAL_BEST_OLD') else 1)"; then
  TMP_MANIFEST="$MANIFEST.tmp.$$"
  python3 - "$MANIFEST" "$SKILL" "$SCORE" "$TMP_MANIFEST" <<'PY'
import json, sys
mp, skill, score, tmp = sys.argv[1], sys.argv[2], float(sys.argv[3]), sys.argv[4]
with open(mp) as f:
    m = json.load(f)
m.setdefault("best_known_scores", {})
m["best_known_scores"][skill] = score
with open(tmp, "w") as f:
    json.dump(m, f, indent=2, sort_keys=True)
    f.write("\n")
PY
  mv "$TMP_MANIFEST" "$MANIFEST"
  UPDATED="true"
fi

release_lock
trap - EXIT INT TERM

# --- confirmation ---
GLOBAL_BEST_NEW="$(python3 - "$MANIFEST" "$SKILL" <<'PY'
import json, sys
with open(sys.argv[1]) as f:
    m = json.load(f)
v = (m.get("best_known_scores") or {}).get(sys.argv[2])
print("none" if v is None else f"{float(v):.6f}")
PY
)"

echo "[swarm_publish] skill=$SKILL worker=$WORKER_ID"
echo "[swarm_publish] target_hash=$TARGET_HASH"
echo "[swarm_publish] score=$SCORE scorer_mode=$SCORER_MODE"
if [ "$DELTA" = "null" ]; then
  echo "[swarm_publish] delta_from_local_baseline=n/a (no local baseline yet)"
else
  echo "[swarm_publish] delta_from_local_baseline=$DELTA"
fi
echo "[swarm_publish] proposal=$PROPOSAL_PATH"
echo "[swarm_publish] global_best_before=${GLOBAL_BEST_OLD:-none} -> after=$GLOBAL_BEST_NEW (updated=$UPDATED)"

exit 0
