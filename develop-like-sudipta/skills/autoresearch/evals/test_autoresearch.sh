#!/usr/bin/env bash
# test_autoresearch.sh — smoke test for run_autoresearch.sh.
#
# Cases:
#   1. Missing program.md          -> exits 1 with clear error.
#   2. Missing score.sh            -> exits 1.
#   3. Missing target.txt          -> exits 1.
#   4. Happy path with --once      -> fake skill + trivial scorer ("echo 100") -> succeeds.
#   5. Time-box                    -> scorer that sleeps 10s + --time 2 -> timeout, rejected.
#   6. Score parsing               -> scorer that emits multi-line output -> last-line parsed.
#   7. Baseline file appended      -> .baselines.json grows after a run.
#   8. Autonomous proposer accept  -> stub proposer emits BETTER marker -> commit + .baselines accept.
#   9. Autonomous proposer reject  -> stub proposer emits WORSE marker -> revert + .baselines reject.
#   10. Proposer returns empty     -> stub emits nothing -> loop skips iteration without crashing.
#
# Bash 3.2 compatible. macOS-friendly. No mapfile, no wait -n, no assoc arrays.
#
# Usage: ./test_autoresearch.sh
# Exit 0 on PASS, non-zero on any failed assertion.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILL_DIR_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
RUNNER="$SKILL_DIR_ROOT/scripts/run_autoresearch.sh"

if [ ! -x "$RUNNER" ] && [ ! -f "$RUNNER" ]; then
  echo "FAIL: runner not found at $RUNNER"
  exit 2
fi

TMP_ROOT="${TMPDIR:-/tmp}"
fails=0
cleanup_dirs=""

fail() { fails=$((fails + 1)); echo "  FAIL: $*"; }
pass() { echo "  PASS: $*"; }

cleanup() {
  for d in $cleanup_dirs; do
    [ -n "$d" ] && [ -d "$d" ] && rm -rf "$d"
  done
}
trap cleanup EXIT INT TERM

# Make a fake-skill scratch dir inside a fresh git repo so accept/reject work.
mkskill() {
  local root tag="$1"
  root="$(mktemp -d "$TMP_ROOT/autoresearch-test-XXXXXX")"
  cleanup_dirs="$cleanup_dirs $root"
  (
    cd "$root"
    git init -q
    git config user.email "test@test.local"
    git config user.name  "test"
    git config commit.gpgsign false
    mkdir -p "skills/fake/autoresearch"
    echo "initial content $tag" > "skills/fake/target_file.txt"
    git add . >/dev/null
    git -c commit.gpgsign=false commit -q -m "init $tag"
  )
  echo "$root"
}

# ---- Case 1: missing program.md ----
echo "Case 1: missing program.md"
ROOT="$(mkskill c1)"
SKILL="$ROOT/skills/fake"
# only create target.txt + score.sh (no program.md)
echo "target_file.txt" > "$SKILL/autoresearch/target.txt"
cat > "$SKILL/autoresearch/score.sh" <<'EOF'
#!/usr/bin/env bash
echo "1"
EOF
chmod +x "$SKILL/autoresearch/score.sh"

out="$(bash "$RUNNER" "$SKILL" --once 2>&1)"; rc=$?
if [ "$rc" -ne 1 ]; then fail "expected exit 1, got $rc"; else
  if echo "$out" | grep -q "missing.*program.md"; then pass "missing program.md => clear error + exit 1"
  else fail "exit 1 but no clear program.md error message"; fi
fi

# ---- Case 2: missing score.sh ----
echo "Case 2: missing score.sh"
ROOT="$(mkskill c2)"
SKILL="$ROOT/skills/fake"
echo "target_file.txt" > "$SKILL/autoresearch/target.txt"
echo "# program" > "$SKILL/autoresearch/program.md"

out="$(bash "$RUNNER" "$SKILL" --once 2>&1)"; rc=$?
if [ "$rc" -ne 1 ]; then fail "expected exit 1, got $rc"; else
  if echo "$out" | grep -q "missing.*score.sh"; then pass "missing score.sh => clear error + exit 1"
  else fail "exit 1 but no clear score.sh error message"; fi
fi

# ---- Case 3: missing target.txt ----
echo "Case 3: missing target.txt"
ROOT="$(mkskill c3)"
SKILL="$ROOT/skills/fake"
echo "# program" > "$SKILL/autoresearch/program.md"
cat > "$SKILL/autoresearch/score.sh" <<'EOF'
#!/usr/bin/env bash
echo "1"
EOF

out="$(bash "$RUNNER" "$SKILL" --once 2>&1)"; rc=$?
if [ "$rc" -ne 1 ]; then fail "expected exit 1, got $rc"; else
  if echo "$out" | grep -q "missing.*target.txt"; then pass "missing target.txt => clear error + exit 1"
  else fail "exit 1 but no clear target.txt error message"; fi
fi

# ---- Case 4: happy path with --once (trivial scorer "echo 100") ----
echo "Case 4: happy path --once"
ROOT="$(mkskill c4)"
SKILL="$ROOT/skills/fake"
echo "target_file.txt" > "$SKILL/autoresearch/target.txt"
echo "# program" > "$SKILL/autoresearch/program.md"
cat > "$SKILL/autoresearch/score.sh" <<'EOF'
#!/usr/bin/env bash
echo "100"
EOF
chmod +x "$SKILL/autoresearch/score.sh"

# stub proposer => no candidate; --once should establish baseline and exit cleanly
out="$(bash "$RUNNER" "$SKILL" --once --time 5 2>&1)"; rc=$?
if [ "$rc" -eq 0 ]; then
  if echo "$out" | grep -q "baseline = 100"; then pass "happy path: baseline = 100, exit 0"
  else fail "exit 0 but baseline=100 not in output"; fi
else
  fail "expected exit 0, got $rc; out=$out"
fi

# ---- Case 5: time-box (scorer sleeps 10s, --time 2 -> rejected timeout) ----
echo "Case 5: time-box (--time 2 vs 10s scorer)"
ROOT="$(mkskill c5)"
SKILL="$ROOT/skills/fake"
echo "target_file.txt" > "$SKILL/autoresearch/target.txt"
echo "# program" > "$SKILL/autoresearch/program.md"
cat > "$SKILL/autoresearch/score.sh" <<'EOF'
#!/usr/bin/env bash
sleep 10
echo "100"
EOF
chmod +x "$SKILL/autoresearch/score.sh"

# Baseline itself will hit the timeout; --once exits 3 because no baseline.
out="$(bash "$RUNNER" "$SKILL" --once --time 2 2>&1)"; rc=$?
# Either rc=3 ("could not establish baseline") OR rc=0 with timeout-rejected
# both are acceptable proofs that the timeout fired.
if [ "$rc" -eq 3 ] || echo "$out" | grep -qi "could not establish baseline"; then
  pass "time-box fires on slow scorer (baseline could not establish)"
elif echo "$out" | grep -qi "timeout"; then
  pass "time-box fires (rejected as timeout)"
else
  fail "expected timeout-related failure; rc=$rc, out=$out"
fi

# ---- Case 6: score parsing (multi-line, last line = score) ----
echo "Case 6: multi-line scorer output, last line parsed"
ROOT="$(mkskill c6)"
SKILL="$ROOT/skills/fake"
echo "target_file.txt" > "$SKILL/autoresearch/target.txt"
echo "# program" > "$SKILL/autoresearch/program.md"
cat > "$SKILL/autoresearch/score.sh" <<'EOF'
#!/usr/bin/env bash
echo "debug: loading evals..."
echo "debug: 42 items"
echo "debug: computing overlap"
echo "73.50"
EOF
chmod +x "$SKILL/autoresearch/score.sh"

out="$(bash "$RUNNER" "$SKILL" --once --time 5 2>&1)"; rc=$?
if [ "$rc" -eq 0 ] && echo "$out" | grep -q "baseline = 73.50"; then
  pass "multi-line output, last line parsed as 73.50"
else
  fail "expected baseline=73.50 from last line; rc=$rc, out=$out"
fi

# ---- Case 7: baseline file appended ----
echo "Case 7: .baselines.json created/grows"
# Needs an iteration with an actual scored candidate; use the stub-proposer
# pattern from Cases 8-10 so the loop runs deterministically (no real proposer
# timeout).
ROOT="$(mkskill c7)"
SKILL="$ROOT/skills/fake"
echo "target_file.txt" > "$SKILL/autoresearch/target.txt"
echo "# program" > "$SKILL/autoresearch/program.md"
cat > "$SKILL/autoresearch/score.sh" <<'EOF'
#!/usr/bin/env bash
# Score depends on a marker in the target file: "GOOD" => 80, else 50.
if grep -q GOOD "$1/target_file.txt"; then echo "80"; else echo "50"; fi
EOF
chmod +x "$SKILL/autoresearch/score.sh"

# Initial target has no marker -> baseline = 50. Stub proposer emits GOOD -> 80.
echo "neutral starter" > "$SKILL/target_file.txt"
( cd "$ROOT" && git add -A && git -c commit.gpgsign=false commit -q -m "c7 setup" )

# NOTE: mk_stubbed_runner is defined further down (Cases 8-10 block). Inline
# the equivalent here so Case 7 stays self-contained and ordered.
STUBDIR_C7="$(mktemp -d "$TMP_ROOT/autoresearch-stub-c7-XXXXXX")"
cleanup_dirs="$cleanup_dirs $STUBDIR_C7"
cp "$SKILL_DIR_ROOT/scripts/run_autoresearch.sh" "$STUBDIR_C7/run_autoresearch.sh"
cp "$SKILL_DIR_ROOT/scripts/git_experiment.sh"   "$STUBDIR_C7/git_experiment.sh"
cp "$SKILL_DIR_ROOT/scripts/score.sh"            "$STUBDIR_C7/score.sh"
cat > "$STUBDIR_C7/propose_hypothesis.sh" <<'EOF'
#!/usr/bin/env bash
printf "%s\n" "GOOD candidate content"
exit 0
EOF
chmod +x "$STUBDIR_C7"/*.sh

out="$(bash "$STUBDIR_C7/run_autoresearch.sh" "$SKILL" --once --time 5 2>&1)"; rc=$?

BL="$SKILL/autoresearch/.baselines.json"
if [ -f "$BL" ] && [ "$(wc -l < "$BL" | tr -d ' ')" -ge 1 ]; then
  if grep -q '"accepted":true' "$BL" && grep -q '"score":80' "$BL"; then
    pass ".baselines.json appended with accepted improvement (50->80)"
  else
    pass ".baselines.json appended (entry recorded, accept/reject = whatever scorer said)"
  fi
else
  fail ".baselines.json not created or empty; rc=$rc, out=$out"
fi

# ---- Cases 8/9/10 helpers: stubbed scripts/ dir for autonomous-proposer tests ----
# We want to swap propose_hypothesis.sh for a stub WITHOUT touching the real
# scripts/. run_autoresearch.sh resolves its siblings via $SCRIPT_DIR (the
# directory of $0), so we build a parallel scripts dir that contains the real
# run_autoresearch.sh + git_experiment.sh + score.sh dispatcher AND a stub
# propose_hypothesis.sh. Then we invoke the copied runner.
SCRIPTS_REAL="$SKILL_DIR_ROOT/scripts"

mk_stubbed_runner() {
  # $1 = tag for tmp dir
  # $2 = stub_proposer body (the FULL script body, after the shebang)
  local tag="$1" stub_body="$2"
  local dir
  dir="$(mktemp -d "$TMP_ROOT/autoresearch-stub-XXXXXX")"
  cleanup_dirs="$cleanup_dirs $dir"
  cp "$SCRIPTS_REAL/run_autoresearch.sh" "$dir/run_autoresearch.sh"
  cp "$SCRIPTS_REAL/git_experiment.sh"   "$dir/git_experiment.sh"
  cp "$SCRIPTS_REAL/score.sh"            "$dir/score.sh"
  {
    echo '#!/usr/bin/env bash'
    echo "$stub_body"
  } > "$dir/propose_hypothesis.sh"
  chmod +x "$dir/propose_hypothesis.sh" "$dir/run_autoresearch.sh" \
           "$dir/git_experiment.sh" "$dir/score.sh"
  echo "$dir"
}

# Marker-aware skill scorer used by Cases 8/9/10:
#   target contains "BETTER" -> 2.0
#   target contains "WORSE"  -> 0.5
#   else                     -> 1.0
write_marker_scorer() {
  local skill="$1"
  cat > "$skill/autoresearch/score.sh" <<'EOF'
#!/usr/bin/env bash
TF="$1/target_file.txt"
if grep -q BETTER "$TF"; then echo "2.0"
elif grep -q WORSE "$TF"; then echo "0.5"
else echo "1.0"
fi
EOF
  chmod +x "$skill/autoresearch/score.sh"
}

# ---- Case 8: autonomous proposer accept ----
echo "Case 8: autonomous proposer accept (stub emits BETTER => score 2.0 > 1.0)"
ROOT="$(mkskill c8)"
SKILL="$ROOT/skills/fake"
echo "target_file.txt" > "$SKILL/autoresearch/target.txt"
echo "# program" > "$SKILL/autoresearch/program.md"
write_marker_scorer "$SKILL"
echo "initial neutral content" > "$SKILL/target_file.txt"
( cd "$ROOT" && git add -A && git -c commit.gpgsign=false commit -q -m "c8 setup" )

STUBBED="$(mk_stubbed_runner c8 '
printf "%s\n" "BETTER candidate from stub proposer"
exit 0
')"

out="$(bash "$STUBBED/run_autoresearch.sh" "$SKILL" --once --time 5 2>&1)"; rc=$?
BL="$SKILL/autoresearch/.baselines.json"
if [ "$rc" -eq 0 ] && [ -f "$BL" ] \
   && echo "$out" | grep -q "ACCEPT" \
   && grep -q '"accepted":true' "$BL" \
   && grep -q '"score":2.0' "$BL"; then
  ncommits="$(cd "$ROOT" && git rev-list --count HEAD)"
  if [ "$ncommits" -ge 2 ]; then
    pass "autonomous proposer ACCEPT path: score 1.0 -> 2.0, commit landed"
  else
    fail "ACCEPT logged but no extra commit (n=$ncommits); out=$out"
  fi
else
  fail "expected ACCEPT with score=2.0 + accepted:true; rc=$rc, out=$out"
fi

# ---- Case 9: autonomous proposer reject ----
echo "Case 9: autonomous proposer reject (stub emits WORSE => score 0.5 < 1.0)"
ROOT="$(mkskill c9)"
SKILL="$ROOT/skills/fake"
echo "target_file.txt" > "$SKILL/autoresearch/target.txt"
echo "# program" > "$SKILL/autoresearch/program.md"
write_marker_scorer "$SKILL"
echo "initial neutral content" > "$SKILL/target_file.txt"
( cd "$ROOT" && git add -A && git -c commit.gpgsign=false commit -q -m "c9 setup" )
commits_before="$(cd "$ROOT" && git rev-list --count HEAD)"

STUBBED="$(mk_stubbed_runner c9 '
printf "%s\n" "WORSE candidate from stub proposer"
exit 0
')"

out="$(bash "$STUBBED/run_autoresearch.sh" "$SKILL" --once --time 5 2>&1)"; rc=$?
BL="$SKILL/autoresearch/.baselines.json"
commits_after="$(cd "$ROOT" && git rev-list --count HEAD)"
target_now="$(cat "$SKILL/target_file.txt")"
if [ "$rc" -eq 0 ] && [ -f "$BL" ] \
   && echo "$out" | grep -q "REJECT" \
   && grep -q '"accepted":false' "$BL" \
   && grep -q '"score":0.5' "$BL" \
   && [ "$commits_after" = "$commits_before" ] \
   && [ "$target_now" = "initial neutral content" ]; then
  pass "autonomous proposer REJECT path: score 0.5 < 1.0, revert, no new commit"
else
  fail "expected REJECT with score=0.5 + accepted:false + revert; rc=$rc, commits=$commits_before->$commits_after, target='$target_now', out=$out"
fi

# ---- Case 10: proposer returns empty -> skip iteration gracefully ----
echo "Case 10: proposer returns empty -> skip iteration (no crash, no git ops)"
ROOT="$(mkskill c10)"
SKILL="$ROOT/skills/fake"
echo "target_file.txt" > "$SKILL/autoresearch/target.txt"
echo "# program" > "$SKILL/autoresearch/program.md"
write_marker_scorer "$SKILL"
echo "initial neutral content" > "$SKILL/target_file.txt"
( cd "$ROOT" && git add -A && git -c commit.gpgsign=false commit -q -m "c10 setup" )
commits_before="$(cd "$ROOT" && git rev-list --count HEAD)"
target_before="$(cat "$SKILL/target_file.txt")"

STUBBED="$(mk_stubbed_runner c10 '
exit 0
')"

out="$(bash "$STUBBED/run_autoresearch.sh" "$SKILL" --once --time 5 2>&1)"; rc=$?
commits_after="$(cd "$ROOT" && git rev-list --count HEAD)"
target_after="$(cat "$SKILL/target_file.txt")"
if [ "$rc" -eq 0 ] \
   && [ "$commits_after" = "$commits_before" ] \
   && [ "$target_after" = "$target_before" ] \
   && echo "$out" | grep -qiE "empty|skip"; then
  pass "empty proposer: rc=0, no commit, target unchanged, skip noted"
else
  fail "expected graceful skip on empty proposer; rc=$rc, commits=$commits_before->$commits_after, out=$out"
fi

# ---- summary ----
echo ""
if [ "$fails" -eq 0 ]; then
  echo "All cases PASSED."
  exit 0
else
  echo "$fails case(s) FAILED."
  exit 1
fi
