#!/usr/bin/env bash
# test_swarm.sh — smoke test for swarm_join / swarm_publish / swarm_merge_best.
#
# 7 cases:
#   1. Init a swarm dir (manifest + skills + empty best_known_scores) -> join succeeds.
#   2. Join twice with different worker IDs -> both succeed, both heartbeats present.
#   3. Join twice with same ID (live) -> second fails with clear error.
#   4. Publish below local baseline -> scoreboard.jsonl appends, manifest unchanged.
#   5. Publish above local baseline -> scoreboard.jsonl appends, manifest's
#      best_known_scores updated atomically, proposal file written.
#   6. Merge with no global improvement -> "Local is champion".
#   7. Merge with global improvement -> prints diff + manual cp cmd; no auto-apply.
#
# Bash 3.2 compatible. macOS-friendly. python3 used for JSON.
#
# Exit 0 on PASS, non-zero on any failed assertion.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
JOIN="$ROOT_DIR/scripts/swarm_join.sh"
PUB="$ROOT_DIR/scripts/swarm_publish.sh"
MERGE="$ROOT_DIR/scripts/swarm_merge_best.sh"

for s in "$JOIN" "$PUB" "$MERGE"; do
  if [ ! -f "$s" ]; then
    echo "FAIL: missing script $s"
    exit 2
  fi
done

TMP_ROOT="${TMPDIR:-/tmp}"
fails=0
cleanup_dirs=""

pass() { echo "  PASS: $*"; }
fail() { fails=$((fails + 1)); echo "  FAIL: $*"; }

cleanup() {
  for d in $cleanup_dirs; do
    [ -n "$d" ] && [ -d "$d" ] && rm -rf "$d"
  done
}
trap cleanup EXIT INT TERM

mkswarm() {
  local d
  d="$(mktemp -d "$TMP_ROOT/swarm-XXXXXX")"
  cleanup_dirs="$cleanup_dirs $d"
  cat > "$d/manifest.json" <<JSON
{
  "schema_version": 1,
  "swarm_name": "test-swarm",
  "created_at": "2026-05-11T12:00:00Z",
  "skills": ["sd-claude-code-access", "develop-like-sudipta"],
  "max_workers": 8,
  "best_known_scores": {}
}
JSON
  echo "$d"
}

# Fake plugin root with a skill autoresearch dir + baselines.
mkplugin() {
  local d skill="$1" local_best="$2"
  d="$(mktemp -d "$TMP_ROOT/plugin-XXXXXX")"
  cleanup_dirs="$cleanup_dirs $d"
  mkdir -p "$d/skills/$skill/autoresearch"
  echo "target.txt" > "$d/skills/$skill/autoresearch/target.txt"
  echo "initial content for $skill" > "$d/skills/$skill/target.txt"
  if [ -n "$local_best" ]; then
    # one accepted row at local_best, plus a rejected lower row.
    printf '{"ts":"2026-05-11T10:00:00Z","target_hash":"sha256:aaa","score":0.10,"accepted":false,"baseline_before":0,"reason":"worse"}\n' >> "$d/skills/$skill/autoresearch/.baselines.json"
    printf '{"ts":"2026-05-11T10:01:00Z","target_hash":"sha256:bbb","score":%s,"accepted":true,"baseline_before":0,"reason":"improved"}\n' "$local_best" >> "$d/skills/$skill/autoresearch/.baselines.json"
  else
    : > "$d/skills/$skill/autoresearch/.baselines.json"
  fi
  echo "$d"
}

echo "test_swarm: starting"

# ---- Case 1: init + join ----
echo "Case 1: init swarm + join succeeds"
SWARM1="$(mkswarm)"
out1="$(bash "$JOIN" "$SWARM1" "alice-mbp" 2>&1)"
rc1=$?
if [ "$rc1" -ne 0 ]; then
  fail "Case 1: swarm_join exited $rc1"
  echo "$out1"
elif [ ! -f "$SWARM1/workers/alice-mbp.json" ]; then
  fail "Case 1: heartbeat file missing"
elif ! echo "$out1" | grep -q "best_known_scores"; then
  fail "Case 1: stdout missing best_known_scores section"
else
  pass "Case 1: join works on fresh swarm"
fi

# ---- Case 2: two different worker ids ----
echo "Case 2: two different worker ids both register"
SWARM2="$(mkswarm)"
bash "$JOIN" "$SWARM2" "alice-mbp" >/dev/null 2>&1
rc_a=$?
bash "$JOIN" "$SWARM2" "bob-mbp" >/dev/null 2>&1
rc_b=$?
if [ "$rc_a" -eq 0 ] && [ "$rc_b" -eq 0 ] && \
   [ -f "$SWARM2/workers/alice-mbp.json" ] && \
   [ -f "$SWARM2/workers/bob-mbp.json" ]; then
  pass "Case 2: both workers registered"
else
  fail "Case 2: rc_a=$rc_a rc_b=$rc_b alice=$([ -f "$SWARM2/workers/alice-mbp.json" ] && echo y || echo n) bob=$([ -f "$SWARM2/workers/bob-mbp.json" ] && echo y || echo n)"
fi

# ---- Case 3: dup join (live) fails ----
echo "Case 3: dup join with same id (live) fails"
SWARM3="$(mkswarm)"
bash "$JOIN" "$SWARM3" "alice-mbp" >/dev/null 2>&1
out3="$(bash "$JOIN" "$SWARM3" "alice-mbp" 2>&1)"
rc3=$?
if [ "$rc3" -ne 0 ] && echo "$out3" | grep -qi "already live"; then
  pass "Case 3: duplicate live worker_id correctly rejected"
else
  fail "Case 3: expected failure with 'already live', got rc=$rc3 out=$out3"
fi

# ---- Case 4: publish below local baseline ----
echo "Case 4: publish below local baseline (manifest unchanged)"
SWARM4="$(mkswarm)"
PLUG4="$(mkplugin "sd-claude-code-access" "0.80")"
TARGET4="$PLUG4/skills/sd-claude-code-access/target.txt"
echo "weak candidate" > "$TARGET4"

# Pre-set manifest's existing global best for this skill = 0.70 (so 0.50 is below local 0.80 AND below global 0.70).
python3 - "$SWARM4/manifest.json" <<'PY'
import json, sys
p = sys.argv[1]
with open(p) as f: m = json.load(f)
m["best_known_scores"] = {"sd-claude-code-access": 0.70}
with open(p, "w") as f: json.dump(m, f, indent=2); f.write("\n")
PY

SWARM_PLUGIN_ROOT="$PLUG4" SWARM_WORKER_ID="alice" bash "$PUB" "$SWARM4" "sd-claude-code-access" "$TARGET4" "0.50" "wordlap" >/dev/null 2>&1
rc4=$?
sb_lines=0
[ -f "$SWARM4/scoreboard.jsonl" ] && sb_lines="$(wc -l < "$SWARM4/scoreboard.jsonl" | tr -d ' ')"
mfst_best=$(python3 -c "import json; print(json.load(open('$SWARM4/manifest.json'))['best_known_scores'].get('sd-claude-code-access'))")
if [ "$rc4" -eq 0 ] && [ "$sb_lines" = "1" ] && [ "$mfst_best" = "0.7" ]; then
  pass "Case 4: appended scoreboard, manifest unchanged (best=0.7)"
else
  fail "Case 4: rc=$rc4 sb_lines=$sb_lines mfst_best=$mfst_best"
fi

# ---- Case 5: publish above local baseline ----
echo "Case 5: publish above local baseline updates manifest atomically"
SWARM5="$(mkswarm)"
PLUG5="$(mkplugin "sd-claude-code-access" "0.80")"
TARGET5="$PLUG5/skills/sd-claude-code-access/target.txt"
echo "strong candidate v5" > "$TARGET5"

SWARM_PLUGIN_ROOT="$PLUG5" SWARM_WORKER_ID="alice" bash "$PUB" "$SWARM5" "sd-claude-code-access" "$TARGET5" "0.92" "wordlap" >/dev/null 2>&1
rc5=$?
sb_lines5=0
[ -f "$SWARM5/scoreboard.jsonl" ] && sb_lines5="$(wc -l < "$SWARM5/scoreboard.jsonl" | tr -d ' ')"
mfst_best5=$(python3 -c "import json; print(json.load(open('$SWARM5/manifest.json'))['best_known_scores'].get('sd-claude-code-access'))")
prop_count=$(ls "$SWARM5/proposals/" 2>/dev/null | wc -l | tr -d ' ')
if [ "$rc5" -eq 0 ] && [ "$sb_lines5" = "1" ] && \
   python3 -c "import sys; sys.exit(0 if abs(float('$mfst_best5') - 0.92) < 1e-6 else 1)" && \
   [ "$prop_count" -ge 1 ]; then
  pass "Case 5: scoreboard appended, manifest=$mfst_best5, proposal file written"
else
  fail "Case 5: rc=$rc5 sb_lines=$sb_lines5 mfst=$mfst_best5 prop_count=$prop_count"
fi

# ---- Case 6: merge — local is champion ----
echo "Case 6: merge with no global improvement (local is champion)"
SWARM6="$(mkswarm)"
PLUG6="$(mkplugin "sd-claude-code-access" "0.95")"
# manifest says global best is 0.70 - lower than local 0.95
python3 - "$SWARM6/manifest.json" <<'PY'
import json, sys
p = sys.argv[1]
with open(p) as f: m = json.load(f)
m["best_known_scores"] = {"sd-claude-code-access": 0.70}
with open(p, "w") as f: json.dump(m, f, indent=2); f.write("\n")
PY
out6="$(bash "$MERGE" "$SWARM6" "sd-claude-code-access" "$PLUG6/skills/sd-claude-code-access" 2>&1)"
rc6=$?
if [ "$rc6" -eq 0 ] && echo "$out6" | grep -qi "current global champion"; then
  pass "Case 6: 'Local is champion' branch hit"
else
  fail "Case 6: rc=$rc6 out=$out6"
fi

# ---- Case 7: merge — global improvement, prints diff + manual cmd ----
echo "Case 7: merge with global improvement (no auto-apply)"
SWARM7="$(mkswarm)"
PLUG7="$(mkplugin "sd-claude-code-access" "0.60")"
# Set up scenario: publish a high score from a "remote" worker.
TARGET_REMOTE="$(mktemp "$TMP_ROOT/remote-tgt-XXXXXX.txt")"
# track the file itself for cleanup (not the dir — that's $TMPDIR)
echo "remote awesome candidate" > "$TARGET_REMOTE"
remote_tgt_cleanup="$TARGET_REMOTE"

# Publish with a *different* plugin root so we don't disturb local baselines.
PLUG_REMOTE="$(mkplugin "sd-claude-code-access" "")"
cp "$TARGET_REMOTE" "$PLUG_REMOTE/skills/sd-claude-code-access/target.txt"
SWARM_PLUGIN_ROOT="$PLUG_REMOTE" SWARM_WORKER_ID="bob" \
  bash "$PUB" "$SWARM7" "sd-claude-code-access" \
  "$PLUG_REMOTE/skills/sd-claude-code-access/target.txt" "0.90" "wordlap" >/dev/null 2>&1
rc_pub=$?
if [ "$rc_pub" -ne 0 ]; then
  fail "Case 7 setup: remote publish failed rc=$rc_pub"
else
  out7="$(bash "$MERGE" "$SWARM7" "sd-claude-code-access" "$PLUG7/skills/sd-claude-code-access" 2>&1)"
  rc7=$?
  # Local target should still equal its original content (no auto-apply).
  if [ "$rc7" -eq 0 ] && \
     echo "$out7" | grep -q "DIFF" && \
     echo "$out7" | grep -qi "manual confirmation" && \
     echo "$out7" | grep -q "cp " && \
     [ "$(cat "$PLUG7/skills/sd-claude-code-access/target.txt")" = "initial content for sd-claude-code-access" ]; then
    pass "Case 7: diff + manual cmd printed; local target untouched"
  else
    fail "Case 7: rc=$rc7 out=$out7"
  fi
fi

echo ""
if [ "$fails" -eq 0 ]; then
  echo "test_swarm: ALL PASS"
  exit 0
else
  echo "test_swarm: $fails FAILED"
  exit 1
fi
