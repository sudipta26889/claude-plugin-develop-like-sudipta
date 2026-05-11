#!/usr/bin/env bash
# Smoke test for the autoresearch wiring on develop-like-sudipta.
# 8 cases. Bash 3.2 compatible. Cleans up after itself.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
AR_DIR="$SKILL_DIR/autoresearch"
CORPUS="$AR_DIR/trigger_corpus.json"

PASS=0
FAIL=0
FAILS=""
TMP_BACKUP=""

note_pass() {
  PASS=$((PASS + 1))
  echo "PASS: $1"
}

note_fail() {
  FAIL=$((FAIL + 1))
  FAILS="$FAILS\n  - $1"
  echo "FAIL: $1"
}

cleanup() {
  # Restore any backed-up corpus if a test moved it
  if [ -n "$TMP_BACKUP" ] && [ -f "$TMP_BACKUP" ]; then
    mv -f "$TMP_BACKUP" "$CORPUS" 2>/dev/null || true
  fi
}
trap cleanup EXIT

# ----- Test 1: all required files exist -----
T1_OK=1
for f in program.md score.sh target.txt .baselines.json .gitignore trigger_corpus.json; do
  if [ ! -f "$AR_DIR/$f" ]; then
    note_fail "Test 1: missing $AR_DIR/$f"
    T1_OK=0
  fi
done
if [ "$T1_OK" -eq 1 ]; then
  if ! grep -q "Autoresearch program for develop-like-sudipta" "$AR_DIR/program.md"; then
    note_fail "Test 1: program.md missing expected header"
    T1_OK=0
  fi
fi
[ "$T1_OK" -eq 1 ] && note_pass "Test 1: all required autoresearch files exist"

# ----- Test 2: target.txt names a real file (SKILL.md) -----
TARGET_NAME=$(head -n 1 "$AR_DIR/target.txt" 2>/dev/null | tr -d '[:space:]')
if [ "$TARGET_NAME" = "SKILL.md" ] && [ -f "$SKILL_DIR/SKILL.md" ]; then
  note_pass "Test 2: target.txt names existing SKILL.md"
else
  note_fail "Test 2: target.txt expected 'SKILL.md', got '$TARGET_NAME' or SKILL.md missing"
fi

# ----- Test 3: score.sh is executable and emits ONE float in [0.0, 1.0] (F1) -----
# As of v4.2, score.sh takes no args (paths resolve from script location), matching
# sibling scorers (sd-claude-code-access, code-hacker). It emits F1 on a 0-1 scale.
if [ -x "$AR_DIR/score.sh" ]; then
  SCORE_OUT=$(bash "$AR_DIR/score.sh" 2>/dev/null | tail -n 1)
  if echo "$SCORE_OUT" | grep -Eq '^[0-9]+(\.[0-9]+)?$'; then
    # Range check: 0.0 <= F1 <= 1.0
    IN_RANGE=$(python3 -c "v=float('$SCORE_OUT'); print(1 if 0.0 <= v <= 1.0 else 0)" 2>/dev/null)
    if [ "$IN_RANGE" = "1" ]; then
      note_pass "Test 3: score.sh emits one F1 float in [0.0, 1.0] (got: $SCORE_OUT)"
    else
      note_fail "Test 3: score.sh emitted float outside [0.0, 1.0] (got: '$SCORE_OUT')"
    fi
  else
    note_fail "Test 3: score.sh did not emit a single float (got: '$SCORE_OUT')"
  fi
else
  note_fail "Test 3: score.sh is not executable"
fi

# ----- Test 4: score.sh exits 0 on success -----
if bash "$AR_DIR/score.sh" >/dev/null 2>&1; then
  note_pass "Test 4: score.sh exits 0 on healthy SKILL.md + corpus"
else
  note_fail "Test 4: score.sh exited non-zero on a healthy SKILL.md + corpus"
fi

# ----- Test 5: score.sh exits non-zero when trigger_corpus.json is missing,
#               AND emitted score (when present) stays in F1 range [0.0, 1.0] -----
TMP_BACKUP="$AR_DIR/.trigger_corpus.json.bak.$$"
if [ -f "$CORPUS" ]; then
  mv "$CORPUS" "$TMP_BACKUP"
  set +e
  bash "$AR_DIR/score.sh" >/dev/null 2>&1
  RC=$?
  set -e
  mv "$TMP_BACKUP" "$CORPUS"
  TMP_BACKUP=""
  if [ "$RC" -ne 0 ]; then
    # Also re-verify the upper bound on a healthy run (sticky regression guard)
    S=$(bash "$AR_DIR/score.sh" 2>/dev/null | tail -n 1)
    UPPER_OK=$(python3 -c "v=float('$S'); print(1 if v <= 1.0 else 0)" 2>/dev/null)
    if [ "$UPPER_OK" = "1" ]; then
      note_pass "Test 5: score.sh exits non-zero when trigger_corpus.json is missing (rc=$RC); healthy F1 within [0,1] upper bound (=$S)"
    else
      note_fail "Test 5: missing-fixture exit code OK (rc=$RC) but healthy F1 exceeded 1.0 (got '$S')"
    fi
  else
    note_fail "Test 5: score.sh exited 0 with missing trigger_corpus.json"
  fi
else
  note_fail "Test 5: trigger_corpus.json not present — cannot run missing-fixture test"
fi

# ----- Test 6: program.md contains all required sections -----
P6_OK=1
for section in "## Goal" "## Metric" "## Constraints" "## Hypothesis seeds" "## Out of scope"; do
  if ! grep -qF "$section" "$AR_DIR/program.md"; then
    note_fail "Test 6: program.md missing section: $section"
    P6_OK=0
  fi
done
[ "$P6_OK" -eq 1 ] && note_pass "Test 6: program.md has all 5 required sections"

# ----- Test 7: .baselines.json is a valid JSON array -----
if python3 -c "import json,sys; d=json.load(open('$AR_DIR/.baselines.json')); sys.exit(0 if isinstance(d,list) else 1)" 2>/dev/null; then
  note_pass "Test 7: .baselines.json is a valid JSON array"
else
  note_fail "Test 7: .baselines.json is not valid JSON or not an array"
fi

# ----- Test 8: trigger_corpus.json shape — >=20 positives, >=10 negatives, required keys -----
python3 - "$CORPUS" <<'PY' >/tmp/dls_corpus_check.$$ 2>&1
import json, sys
p = sys.argv[1]
try:
    d = json.load(open(p))
except Exception as e:
    print(f"INVALID_JSON: {e}")
    sys.exit(1)
qs = d.get("queries", [])
pos = [q for q in qs if q.get("should_trigger") is True]
neg = [q for q in qs if q.get("should_trigger") is False]
required_keys = {"query", "should_trigger", "category"}
bad = [i for i, q in enumerate(qs) if not required_keys.issubset(q.keys())]
if bad:
    print(f"MISSING_KEYS rows={bad[:5]}")
    sys.exit(1)
if len(pos) < 20:
    print(f"TOO_FEW_POSITIVES count={len(pos)}")
    sys.exit(1)
if len(neg) < 10:
    print(f"TOO_FEW_NEGATIVES count={len(neg)}")
    sys.exit(1)
print(f"OK positives={len(pos)} negatives={len(neg)}")
PY
T8_RC=$?
T8_MSG=$(cat /tmp/dls_corpus_check.$$ 2>/dev/null)
rm -f /tmp/dls_corpus_check.$$
if [ "$T8_RC" -eq 0 ]; then
  note_pass "Test 8: trigger_corpus.json shape OK ($T8_MSG)"
else
  note_fail "Test 8: trigger_corpus.json shape check failed: $T8_MSG"
fi

# ----- Report -----
TOTAL=$((PASS + FAIL))
echo ""
echo "==== autoresearch wiring smoke (develop-like-sudipta) ===="
echo "Passed: $PASS / $TOTAL"
if [ "$FAIL" -gt 0 ]; then
  echo "Failures:"
  printf "%b\n" "$FAILS"
  exit 1
fi
echo "All wiring smoke tests passed."
exit 0
