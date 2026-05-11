#!/usr/bin/env bash
# Smoke test for code-hacker autoresearch wiring.
# Runs 8 cases and reports PASS/FAIL each. Exit 0 iff all pass.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
AR_DIR="$SKILL_DIR/autoresearch"

PASS=0
FAIL=0

check() {
  local name="$1"; shift
  if "$@"; then
    echo "PASS  $name"
    PASS=$((PASS + 1))
  else
    echo "FAIL  $name"
    FAIL=$((FAIL + 1))
  fi
}

# 1. All 5 required files exist
required_files_exist() {
  for f in program.md score.sh target.txt .baselines.json trigger_corpus.json; do
    if [ ! -f "$AR_DIR/$f" ]; then
      echo "  missing: autoresearch/$f" >&2
      return 1
    fi
  done
  return 0
}
check "1. required files present" required_files_exist

# 2. target.txt names a real file (resolved against SKILL_DIR)
target_resolves() {
  local tgt
  tgt="$(tr -d '[:space:]' < "$AR_DIR/target.txt")"
  [ -n "$tgt" ] || { echo "  target.txt empty" >&2; return 1; }
  [ -f "$SKILL_DIR/$tgt" ] || { echo "  target file missing: $SKILL_DIR/$tgt" >&2; return 1; }
  return 0
}
check "2. target.txt resolves to a real file" target_resolves

# 3. score.sh is executable
score_executable() {
  [ -x "$AR_DIR/score.sh" ]
}
check "3. score.sh is executable" score_executable

# 4. score.sh runs, exits 0, and emits a float on its last stdout line
score_runs_emits_float() {
  local out last
  out="$(bash "$AR_DIR/score.sh" 2>/dev/null)" || { echo "  score.sh exit non-zero" >&2; return 1; }
  last="$(printf '%s\n' "$out" | tail -n 1)"
  echo "$last" | python3 -c "import sys; f=float(sys.stdin.read().strip()); assert 0.0 <= f <= 1.0, f" 2>/dev/null \
    || { echo "  last stdout line is not a float in [0,1]: '$last'" >&2; return 1; }
  return 0
}
check "4. score.sh emits a float in [0,1]" score_runs_emits_float

# 5. score.sh exits 0 on the happy path
score_exit_zero() {
  bash "$AR_DIR/score.sh" >/dev/null 2>&1
}
check "5. score.sh exits 0" score_exit_zero

# 6. score.sh handles missing trigger_corpus.json with a clear error and non-zero exit
score_missing_corpus() {
  local tmp_backup="$AR_DIR/trigger_corpus.json.bak"
  cp "$AR_DIR/trigger_corpus.json" "$tmp_backup" || return 1
  rm -f "$AR_DIR/trigger_corpus.json"
  local err rc
  err="$(bash "$AR_DIR/score.sh" 2>&1 >/dev/null)"; rc=$?
  mv "$tmp_backup" "$AR_DIR/trigger_corpus.json" || true
  if [ $rc -eq 0 ]; then
    echo "  expected non-zero exit when corpus is missing, got 0" >&2
    return 1
  fi
  echo "$err" | grep -qiE "trigger_corpus|not found|missing" \
    || { echo "  error message did not mention the missing corpus: '$err'" >&2; return 1; }
  return 0
}
check "6. score.sh fails clearly when trigger_corpus.json missing" score_missing_corpus

# 7. program.md has all required sections
program_sections() {
  local p="$AR_DIR/program.md"
  for sec in "## Goal" "## Metric" "## Constraints" "## Hypothesis seeds" "## Out of scope"; do
    grep -qF "$sec" "$p" || { echo "  missing section: $sec" >&2; return 1; }
  done
  return 0
}
check "7. program.md has Goal / Metric / Constraints / Hypothesis seeds / Out of scope" program_sections

# 8. .baselines.json is valid JSON array; trigger_corpus.json has >=20 positives + >=10 negatives
fixtures_valid() {
  python3 - "$AR_DIR/.baselines.json" "$AR_DIR/trigger_corpus.json" <<'PY' || return 1
import json, sys
baselines_path, corpus_path = sys.argv[1], sys.argv[2]
b = json.load(open(baselines_path))
assert isinstance(b, list), f".baselines.json must be a JSON array, got {type(b).__name__}"
c = json.load(open(corpus_path))
queries = c["queries"] if isinstance(c, dict) else c
pos = sum(1 for q in queries if q.get("should_trigger") is True)
neg = sum(1 for q in queries if q.get("should_trigger") is False)
assert pos >= 20, f"need >=20 positives, got {pos}"
assert neg >= 10, f"need >=10 negatives, got {neg}"
PY
  return 0
}
check "8. .baselines.json valid + corpus has >=20 pos / >=10 neg" fixtures_valid

echo "---"
echo "Passed: $PASS"
echo "Failed: $FAIL"
if [ $FAIL -ne 0 ]; then
  exit 1
fi
exit 0
