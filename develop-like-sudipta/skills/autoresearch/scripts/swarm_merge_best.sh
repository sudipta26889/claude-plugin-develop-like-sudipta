#!/usr/bin/env bash
# swarm_merge_best.sh — pick the highest-scoring experiment across all
# workers for one skill, and propose it as the new local baseline.
#
# Usage: swarm_merge_best.sh <swarm-dir> <skill> <local-plugin-skill-dir>
#
# <local-plugin-skill-dir> is the path to the skill inside the local plugin,
# e.g. <plugin>/skills/sd-claude-code-access. The script reads
# <local-plugin-skill-dir>/autoresearch/.baselines.json to compute the local
# best, and <local-plugin-skill-dir>/autoresearch/target.txt to identify the
# editable target file.
#
# Logic:
#   1. Read manifest.json -> best_known_scores[skill].
#   2. Find the proposal in <swarm-dir>/proposals/ whose name matches
#      <skill>-<sha8>-<score-pct>.<ext> at the global-best score-pct.
#      (If multiple, pick the most recently published — sort by scoreboard.jsonl.)
#   3. Read local best (highest accepted score) from .baselines.json.
#   4. If global > local:
#        - Print a diff: local target vs proposed target.
#        - Print the *manual* cp command to apply, then re-baseline note.
#        - DO NOT auto-apply.
#   5. If local >= global: print "Local is current global champion".
#
# v4.2 is intentionally manual. Reasoning: a buggy worker could publish a
# regression-as-improvement (e.g. wrong scorer_mode). Auto-overwriting the
# baseline would poison the swarm. A human (or future v5.0 anti-cheat layer)
# vouches for the merge.
#
# Bash 3.2 compatible. macOS-friendly. python3 used for JSON.

set -u
set -o pipefail

usage() {
  echo "Usage: $0 <swarm-dir> <skill> <local-plugin-skill-dir>" >&2
}

if [ "$#" -ne 3 ]; then
  usage
  exit 2
fi

SWARM_DIR="$1"
SKILL="$2"
SKILL_DIR="$3"

MANIFEST="$SWARM_DIR/manifest.json"
PROPOSALS_DIR="$SWARM_DIR/proposals"
SCOREBOARD="$SWARM_DIR/scoreboard.jsonl"
AR_DIR="$SKILL_DIR/autoresearch"
BASELINES="$AR_DIR/.baselines.json"
TARGET_NAMEFILE="$AR_DIR/target.txt"

if [ ! -f "$MANIFEST" ]; then
  echo "ERROR: manifest.json missing in $SWARM_DIR" >&2
  exit 1
fi
if [ ! -d "$SKILL_DIR" ]; then
  echo "ERROR: local skill dir not found: $SKILL_DIR" >&2
  exit 1
fi
if [ ! -f "$TARGET_NAMEFILE" ]; then
  echo "ERROR: $TARGET_NAMEFILE missing (cannot identify editable target)" >&2
  exit 1
fi

TARGET_REL="$(head -n1 "$TARGET_NAMEFILE" | tr -d ' \t\r\n')"
LOCAL_TARGET="$SKILL_DIR/$TARGET_REL"
if [ ! -f "$LOCAL_TARGET" ]; then
  echo "ERROR: local target file not found: $LOCAL_TARGET" >&2
  exit 1
fi

# --- read global best ---
GLOBAL_BEST="$(python3 - "$MANIFEST" "$SKILL" <<'PY'
import json, sys
with open(sys.argv[1]) as f:
    m = json.load(f)
v = (m.get("best_known_scores") or {}).get(sys.argv[2])
print("" if v is None else f"{float(v):.6f}")
PY
)"

if [ -z "$GLOBAL_BEST" ]; then
  echo "[swarm_merge_best] No global best recorded for skill='$SKILL' yet."
  echo "[swarm_merge_best] Nothing to merge."
  exit 0
fi

# --- read local best (best accepted score in .baselines.json) ---
LOCAL_BEST="0.000000"
if [ -f "$BASELINES" ]; then
  LOCAL_BEST="$(python3 - "$BASELINES" <<'PY'
import json, sys
best = 0.0
try:
    with open(sys.argv[1]) as f:
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
                if isinstance(s, (int, float)) and s > best:
                    best = s
except Exception:
    pass
print(f"{best:.6f}")
PY
)"
fi

echo "[swarm_merge_best] skill=$SKILL"
echo "[swarm_merge_best] local_best=$LOCAL_BEST"
echo "[swarm_merge_best] global_best=$GLOBAL_BEST"

# Compare
IS_IMPROVEMENT="$(python3 -c "import sys; print('yes' if float('$GLOBAL_BEST') > float('$LOCAL_BEST') else 'no')")"
if [ "$IS_IMPROVEMENT" = "no" ]; then
  echo "[swarm_merge_best] Local is current global champion; nothing to merge."
  exit 0
fi

# --- find the matching proposal file ---
# Expected score_pct = round(global_best * 100)
GLOBAL_PCT="$(python3 -c "print(int(round(float('$GLOBAL_BEST')*100)))")"

if [ ! -d "$PROPOSALS_DIR" ]; then
  echo "ERROR: proposals/ directory missing at $PROPOSALS_DIR" >&2
  exit 1
fi

# Look for files: <skill>-*-<global_pct>.<anything>
# We prefer the most recent proposal_id matching from scoreboard.jsonl, but
# fall back to filename glob.
PROPOSAL_PATH=""
if [ -f "$SCOREBOARD" ]; then
  PROPOSAL_PATH="$(python3 - "$SCOREBOARD" "$PROPOSALS_DIR" "$SKILL" "$GLOBAL_BEST" <<'PY'
import json, os, sys, math
sb, pdir, skill, gbest = sys.argv[1], sys.argv[2], sys.argv[3], float(sys.argv[4])
candidates = []
with open(sb) as f:
    for line in f:
        line = line.strip()
        if not line:
            continue
        try:
            row = json.loads(line)
        except Exception:
            continue
        if row.get("skill") != skill:
            continue
        s = row.get("score")
        if not isinstance(s, (int, float)):
            continue
        if abs(s - gbest) > 1e-9:
            continue
        candidates.append(row)
if not candidates:
    print("")
    sys.exit(0)
# Most recent wins.
candidates.sort(key=lambda r: r.get("ts", ""), reverse=True)
for row in candidates:
    th = row.get("target_hash", "")
    if th.startswith("sha256:"):
        sha8 = th[len("sha256:"):][:8]
        pct = int(round(s := row["score"] * 100))
        # try common extensions
        for entry in sorted(os.listdir(pdir)):
            prefix = f"{skill}-{sha8}-{pct}"
            if entry == prefix or entry.startswith(prefix + "."):
                print(os.path.join(pdir, entry))
                sys.exit(0)
print("")
PY
)"
fi

if [ -z "$PROPOSAL_PATH" ] || [ ! -f "$PROPOSAL_PATH" ]; then
  # Fallback: glob.
  PROPOSAL_PATH="$(ls "$PROPOSALS_DIR" 2>/dev/null | awk -v skill="$SKILL" -v pct="$GLOBAL_PCT" '
    {
      # filename = <skill>-<sha8>-<pct>[.ext]
      n = split($0, a, "-")
      if (n < 3) next
      if (a[1] != skill) next
      last = a[n]
      # strip extension off last
      sub(/\..*$/, "", last)
      if (last == pct) print $0
    }' | tail -n1)"
  if [ -n "$PROPOSAL_PATH" ]; then
    PROPOSAL_PATH="$PROPOSALS_DIR/$PROPOSAL_PATH"
  fi
fi

if [ -z "$PROPOSAL_PATH" ] || [ ! -f "$PROPOSAL_PATH" ]; then
  echo "ERROR: could not locate a proposal file in $PROPOSALS_DIR" >&2
  echo "       Expected pattern: ${SKILL}-<sha8>-${GLOBAL_PCT}.<ext>" >&2
  echo "       (Manifest claims global_best=$GLOBAL_BEST but no matching proposal was published.)" >&2
  exit 1
fi

echo "[swarm_merge_best] candidate proposal: $PROPOSAL_PATH"
echo ""
echo "----- DIFF (local vs proposed) -----"
diff -u "$LOCAL_TARGET" "$PROPOSAL_PATH" || true
echo "----- END DIFF -----"
echo ""
echo "[swarm_merge_best] global > local — merge requires manual confirmation."
echo ""
echo "To apply, review the diff above and run:"
echo ""
echo "  cp \"$PROPOSAL_PATH\" \"$LOCAL_TARGET\""
echo "  # then re-baseline:"
echo "  bash \"$SKILL_DIR/../autoresearch/scripts/run_autoresearch.sh\" \"$SKILL_DIR\" --once"
echo ""
echo "(v4.2 deliberately does NOT auto-apply — a buggy worker could poison the swarm.)"

exit 0
