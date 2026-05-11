#!/usr/bin/env bash
# run_autoresearch.sh — Karpathy-style autoresearch driver for a single skill.
#
# Usage: run_autoresearch.sh <skill-dir> [--budget N] [--time SEC] [--once]
#
# Contract enforcement:
#   <skill-dir>/autoresearch/program.md  must exist (locked goal + constraints)
#   <skill-dir>/autoresearch/score.sh    must exist + be executable (one-number scorer)
#   <skill-dir>/autoresearch/target.txt  must exist (names the editable file)
#
# Loop:
#   1. baseline = run score.sh on current state
#   2. for i in 1..budget:
#        a. read current target content
#        b. propose new content via propose_hypothesis.sh (v4.1 stub)
#        c. apply candidate (atomic temp + mv)
#        d. score = score.sh, time-boxed to --time SEC
#        e. compare to baseline; commit (git_experiment.sh accept) or revert (reject)
#        f. append to .baselines.json
#   3. --once exits after one cycle (for testing).
#
# Bash 3.2 compatible. macOS-friendly. No mapfile / wait -n / associative arrays.

set -u
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
GIT_EXP="$SCRIPT_DIR/git_experiment.sh"
SCORE_DISPATCH="$SCRIPT_DIR/score.sh"
PROPOSE="$SCRIPT_DIR/propose_hypothesis.sh"

usage() {
  cat <<'EOF' >&2
Usage: run_autoresearch.sh <skill-dir> [--budget N] [--time SEC] [--once]

  --budget N   Max experiments per run (default 50)
  --time SEC   Time budget per score.sh call in seconds (default 300)
  --once       Run ONE experiment cycle and exit (for testing)
EOF
  exit 2
}

# ---- arg parse ----
SKILL_DIR=""
BUDGET=50
TIME_BUDGET=300
ONCE=0

while [ $# -gt 0 ]; do
  case "$1" in
    --budget) BUDGET="${2:?--budget needs value}"; shift 2 ;;
    --time)   TIME_BUDGET="${2:?--time needs value}"; shift 2 ;;
    --once)   ONCE=1; shift ;;
    -h|--help) usage ;;
    --*) echo "unknown flag: $1" >&2; usage ;;
    *)
      if [ -z "$SKILL_DIR" ]; then SKILL_DIR="$1"; else
        echo "unexpected arg: $1" >&2; usage
      fi
      shift ;;
  esac
done

[ -n "$SKILL_DIR" ] || usage
[ -d "$SKILL_DIR" ] || { echo "skill-dir not a directory: $SKILL_DIR" >&2; exit 1; }
SKILL_DIR="$(cd "$SKILL_DIR" && pwd)"

# ---- contract check ----
AR_DIR="$SKILL_DIR/autoresearch"
PROGRAM_MD="$AR_DIR/program.md"
SKILL_SCORE="$AR_DIR/score.sh"
TARGET_TXT="$AR_DIR/target.txt"

if [ ! -f "$PROGRAM_MD" ]; then
  echo "ERROR: missing $PROGRAM_MD" >&2
  echo "       run_autoresearch refuses to start without program.md (the locked goal)." >&2
  exit 1
fi
if [ ! -f "$SKILL_SCORE" ]; then
  echo "ERROR: missing $SKILL_SCORE" >&2
  echo "       run_autoresearch needs autoresearch/score.sh (the skill-specific scorer)." >&2
  exit 1
fi
if [ ! -f "$TARGET_TXT" ]; then
  echo "ERROR: missing $TARGET_TXT" >&2
  echo "       run_autoresearch needs target.txt naming the ONE editable file." >&2
  exit 1
fi

TARGET_REL="$(head -1 "$TARGET_TXT" | tr -d '[:space:]')"
[ -n "$TARGET_REL" ] || { echo "ERROR: target.txt is empty" >&2; exit 1; }
TARGET_FILE="$SKILL_DIR/$TARGET_REL"
if [ ! -f "$TARGET_FILE" ]; then
  echo "ERROR: target file does not exist: $TARGET_FILE" >&2
  exit 1
fi

# ---- lock ----
LOCK="$AR_DIR/.lock"
acquire_lock() {
  if [ -f "$LOCK" ]; then
    holder_pid="$(awk -F= '/^pid=/{print $2}' "$LOCK" 2>/dev/null)"
    if [ -n "$holder_pid" ] && kill -0 "$holder_pid" 2>/dev/null; then
      echo "ERROR: lock held by pid=$holder_pid (see $LOCK)" >&2
      exit 2
    fi
    rm -f "$LOCK"
  fi
  {
    echo "pid=$$"
    echo "host=$(hostname 2>/dev/null || echo unknown)"
    echo "start=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "budget=$BUDGET"
    echo "time=$TIME_BUDGET"
  } > "$LOCK"
}
release_lock() { rm -f "$LOCK"; }

cleanup() {
  # revert any in-flight candidate
  if [ -n "${IN_FLIGHT:-}" ] && [ "$IN_FLIGHT" = "1" ]; then
    ( cd "$SKILL_DIR" && git checkout -- "$TARGET_REL" 2>/dev/null ) || true
  fi
  release_lock
}
trap cleanup EXIT
trap 'echo "[autoresearch] interrupted"; exit 130' INT TERM

acquire_lock

# ---- helpers ----
BASELINES="$AR_DIR/.baselines.json"

iso_now() { date -u +%Y-%m-%dT%H:%M:%SZ; }

# Run a command with a wall-clock timeout (portable, Bash 3.2).
# usage: run_with_timeout SEC CMD ARGS...
run_with_timeout() {
  local secs="$1"; shift
  ( "$@" ) &
  local pid=$!
  ( sleep "$secs" && kill -TERM "$pid" 2>/dev/null && \
    sleep 2 && kill -KILL "$pid" 2>/dev/null ) >/dev/null 2>&1 &
  local watcher=$!
  wait "$pid" 2>/dev/null
  local rc=$?
  kill -TERM "$watcher" 2>/dev/null
  wait "$watcher" 2>/dev/null
  return $rc
}

# Score the current target. Echoes the parsed float on stdout, or empty on failure.
# Returns rc: 0=ok, 1=timeout, 2=parse failure, 3=scorer crash.
score_current() {
  local out
  out="$(mktemp)" || return 3
  run_with_timeout "$TIME_BUDGET" bash "$SCORE_DISPATCH" "$SKILL_DIR" \
    > "$out" 2>>"$AR_DIR/.score.stderr.log"
  local rc=$?
  if [ "$rc" -ne 0 ]; then
    rm -f "$out"
    if [ "$rc" -eq 143 ] || [ "$rc" -eq 137 ]; then return 1; fi
    return 3
  fi
  local last
  last="$(grep -v '^[[:space:]]*$' "$out" | tail -1)"
  rm -f "$out"
  if echo "$last" | grep -Eq '^-?[0-9]+(\.[0-9]+)?$'; then
    echo "$last"
    return 0
  fi
  return 2
}

# Append a JSONL row to .baselines.json
append_baseline() {
  local ts="$1" hash="$2" score="$3" accepted="$4" baseline_before="$5" reason="$6"
  printf '{"ts":"%s","target_hash":"%s","score":%s,"accepted":%s,"baseline_before":%s,"reason":"%s"}\n' \
    "$ts" "$hash" "$score" "$accepted" "$baseline_before" "$reason" >> "$BASELINES"
}

# Compare two floats; echo 1 if $1 > $2, else 0. Uses awk (portable).
fgt() {
  awk -v a="$1" -v b="$2" 'BEGIN { print (a+0 > b+0) ? 1 : 0 }'
}

# ---- baseline ----
echo "[autoresearch] skill=$SKILL_DIR target=$TARGET_REL budget=$BUDGET time=${TIME_BUDGET}s"
echo "[autoresearch] establishing baseline..."

baseline=""
baseline_score="$(score_current)" || true
rc=$?
if [ -n "$baseline_score" ]; then
  baseline="$baseline_score"
  echo "[autoresearch] baseline = $baseline"
else
  echo "ERROR: could not establish baseline (rc=$rc). See $AR_DIR/.score.stderr.log" >&2
  exit 3
fi

# ---- experiment loop ----
i=0
IN_FLIGHT=0
LIMIT="$BUDGET"
[ "$ONCE" = "1" ] && LIMIT=1

while [ "$i" -lt "$LIMIT" ]; do
  i=$((i + 1))
  echo ""
  echo "[autoresearch] === experiment $i / $LIMIT ==="

  # 1. propose (v4.1 stub: emits guidance; no mutation made)
  PROPOSAL_OUT="$(mktemp)"
  bash "$PROPOSE" "$SKILL_DIR" > "$PROPOSAL_OUT" 2>&1 || true

  # In v4.1 the proposer is a stub. Cowork/CC supplies the actual mutation
  # out-of-band; here, we detect whether the target file is dirty (proposer
  # OR human modified it) and only score if so.
  ( cd "$SKILL_DIR" && git diff --quiet -- "$TARGET_REL" ) && DIRTY=0 || DIRTY=1
  rm -f "$PROPOSAL_OUT"

  if [ "$DIRTY" = "0" ]; then
    echo "[autoresearch] no candidate proposed (target unchanged). v4.1: proposer is a stub."
    echo "[autoresearch] write a candidate to $TARGET_FILE then re-run with --once to score it."
    if [ "$ONCE" = "1" ]; then exit 0; fi
    # in a multi-cycle run with the stub proposer, we'd spin forever. Break out.
    echo "[autoresearch] stub proposer + multi-cycle = nothing to do. Stopping."
    break
  fi

  IN_FLIGHT=1

  # 2. score
  candidate_hash="$(cd "$SKILL_DIR" && git hash-object "$TARGET_REL" 2>/dev/null || echo unknown)"
  score="$(score_current)" || true
  rc=$?

  ts="$(iso_now)"
  if [ "$rc" -eq 1 ]; then
    echo "[autoresearch] REJECT: timeout after ${TIME_BUDGET}s"
    bash "$GIT_EXP" reject "$SKILL_DIR" "$TARGET_REL" "0" || true
    append_baseline "$ts" "$candidate_hash" "0" "false" "$baseline" "timeout"
    IN_FLIGHT=0
    [ "$ONCE" = "1" ] && exit 0
    continue
  fi
  if [ "$rc" -eq 2 ]; then
    echo "[autoresearch] REJECT: score parse failure (last line of score.sh was not a float)"
    bash "$GIT_EXP" reject "$SKILL_DIR" "$TARGET_REL" "0" || true
    append_baseline "$ts" "$candidate_hash" "0" "false" "$baseline" "parse_failure"
    IN_FLIGHT=0
    [ "$ONCE" = "1" ] && exit 0
    continue
  fi
  if [ "$rc" -eq 3 ] || [ -z "$score" ]; then
    echo "[autoresearch] REJECT: scorer crashed (see $AR_DIR/.score.stderr.log)"
    bash "$GIT_EXP" reject "$SKILL_DIR" "$TARGET_REL" "0" || true
    append_baseline "$ts" "$candidate_hash" "0" "false" "$baseline" "crash"
    IN_FLIGHT=0
    [ "$ONCE" = "1" ] && exit 0
    continue
  fi

  # 3. compare
  better="$(fgt "$score" "$baseline")"
  if [ "$better" = "1" ]; then
    echo "[autoresearch] ACCEPT: score=$score > baseline=$baseline"
    bash "$GIT_EXP" accept "$SKILL_DIR" "$TARGET_REL" "$score" || true
    append_baseline "$ts" "$candidate_hash" "$score" "true" "$baseline" "improved"
    baseline="$score"
  else
    echo "[autoresearch] REJECT: score=$score <= baseline=$baseline"
    bash "$GIT_EXP" reject "$SKILL_DIR" "$TARGET_REL" "$score" || true
    reason="worse"
    if [ "$score" = "$baseline" ]; then reason="equal"; fi
    append_baseline "$ts" "$candidate_hash" "$score" "false" "$baseline" "$reason"
  fi
  IN_FLIGHT=0
done

echo ""
echo "[autoresearch] done. final baseline = $baseline. experiments = $i."
exit 0
