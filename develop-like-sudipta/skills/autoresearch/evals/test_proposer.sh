#!/usr/bin/env bash
# test_proposer.sh — smoke test for propose_hypothesis.sh and its sub-scripts.
#
# Cases:
#   1. No API key, no config -> file mode triggered (writes .proposed_prompt.txt
#                                and starts polling).
#   2. File mode happy path  -> background writer drops .proposed_target.txt
#                                after 1s; proposer reads it, emits to stdout.
#   3. File mode timeout     -> nothing writes the target file; PROPOSER_FILE_TIMEOUT=2
#                                proposer exits non-zero after ~2s.
#   4. Cleanup               -> after success, .proposed_prompt.txt and
#                                .proposed_target.txt are both removed.
#   5. API mode happy path   -> stub curl on PATH emits a fake messages JSON;
#                                propose_via_api.sh parses content[0].text and
#                                emits it on stdout.
#   6. API mode auth fail    -> stub curl emits HTTP 401 -> proposer exits 2.
#   7. API mode rate limit   -> stub curl emits HTTP 429 -> proposer exits 3.
#
# Bash 3.2 compatible. macOS-friendly. No mapfile, no wait -n, no assoc arrays.
#
# Usage: ./test_proposer.sh
# Exit 0 on PASS, non-zero on any failed assertion.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILL_DIR_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DISPATCH="$SKILL_DIR_ROOT/scripts/propose_hypothesis.sh"
VIA_FILE="$SKILL_DIR_ROOT/scripts/propose_via_file.sh"
VIA_API="$SKILL_DIR_ROOT/scripts/propose_via_api.sh"

for f in "$DISPATCH" "$VIA_FILE" "$VIA_API"; do
  if [ ! -f "$f" ]; then
    echo "FAIL: missing script $f"
    exit 2
  fi
done

TMP_ROOT="${TMPDIR:-/tmp}"
fails=0
cleanup_dirs=""

fail() { fails=$((fails + 1)); echo "  FAIL: $*"; }
pass() { echo "  PASS: $*"; }

# Kill any stray background writers / proposers on exit.
PIDS_TO_KILL=""

cleanup() {
  for p in $PIDS_TO_KILL; do
    kill -TERM "$p" 2>/dev/null || true
  done
  sleep 0.2 2>/dev/null || sleep 1
  for p in $PIDS_TO_KILL; do
    kill -KILL "$p" 2>/dev/null || true
  done
  for d in $cleanup_dirs; do
    [ -n "$d" ] && [ -d "$d" ] && rm -rf "$d"
  done
}
trap cleanup EXIT INT TERM

# Build a minimal skill scaffold (no git needed — proposers don't use git).
mkskill() {
  local tag="$1"
  local root
  root="$(mktemp -d "$TMP_ROOT/proposer-test-XXXXXX")"
  cleanup_dirs="$cleanup_dirs $root"
  mkdir -p "$root/autoresearch"
  echo "# program for $tag" > "$root/autoresearch/program.md"
  echo "target_file.txt" > "$root/autoresearch/target.txt"
  cat > "$root/autoresearch/score.sh" <<'EOF'
#!/usr/bin/env bash
echo "1"
EOF
  chmod +x "$root/autoresearch/score.sh"
  echo "initial content $tag" > "$root/target_file.txt"
  echo "$root"
}

# ============================================================================
# Case 1: No API key, no config -> file mode triggered (prompt + polling)
# ============================================================================
echo "Case 1: no API key + no config -> file mode + polling"
SKILL="$(mkskill c1)"
PROMPT="$SKILL/autoresearch/.proposed_prompt.txt"

# Run dispatcher in background with a short timeout so it polls then dies.
(
  unset ANTHROPIC_API_KEY
  PROPOSER_FILE_TIMEOUT=4 PROPOSER_FILE_POLL_SEC=1 \
    bash "$DISPATCH" "$SKILL" > "$SKILL/out.txt" 2> "$SKILL/err.txt"
  echo $? > "$SKILL/rc.txt"
) &
BG_PID=$!
PIDS_TO_KILL="$PIDS_TO_KILL $BG_PID"

# Give the proposer a moment to write the prompt and start polling.
sleep 2

PROMPT_OK=0
if [ -f "$PROMPT" ]; then PROMPT_OK=1; fi

POLLING_OK=0
# Proposer should still be alive (polling).
if kill -0 "$BG_PID" 2>/dev/null; then POLLING_OK=1; fi

# Wait for it to finish (timeout will fire ~4s).
wait "$BG_PID" 2>/dev/null || true
PIDS_TO_KILL="$(echo "$PIDS_TO_KILL" | sed "s/ $BG_PID//")"

if [ "$PROMPT_OK" = "1" ] && [ "$POLLING_OK" = "1" ]; then
  pass "wrote .proposed_prompt.txt and was polling"
else
  fail "expected prompt file + polling. prompt_ok=$PROMPT_OK polling_ok=$POLLING_OK"
  echo "    stderr: $(head -20 "$SKILL/err.txt" 2>/dev/null)"
fi

# Also assert the err log mentions file mode.
if grep -q "mode=file" "$SKILL/err.txt" 2>/dev/null; then
  pass "stderr announces mode=file"
else
  fail "stderr did not announce mode=file"
fi

# ============================================================================
# Case 2: File mode happy path (writer drops target file after 1s)
# ============================================================================
echo "Case 2: file mode happy path"
SKILL="$(mkskill c2)"
PROMPT="$SKILL/autoresearch/.proposed_prompt.txt"
PROPOSAL="$SKILL/autoresearch/.proposed_target.txt"

# Background writer: wait 1s, then write the proposal.
(
  sleep 1
  printf 'NEW PROPOSED CONTENT for c2\n' > "$PROPOSAL"
) &
WRITER_PID=$!
PIDS_TO_KILL="$PIDS_TO_KILL $WRITER_PID"

(
  unset ANTHROPIC_API_KEY
  PROPOSER_FILE_TIMEOUT=15 PROPOSER_FILE_POLL_SEC=1 \
    bash "$DISPATCH" "$SKILL" > "$SKILL/out.txt" 2> "$SKILL/err.txt"
  echo $? > "$SKILL/rc.txt"
) &
DISP_PID=$!
PIDS_TO_KILL="$PIDS_TO_KILL $DISP_PID"

wait "$DISP_PID" 2>/dev/null || true
wait "$WRITER_PID" 2>/dev/null || true
PIDS_TO_KILL="$(echo "$PIDS_TO_KILL" | sed "s/ $DISP_PID//; s/ $WRITER_PID//")"

RC="$(cat "$SKILL/rc.txt" 2>/dev/null || echo 99)"
if [ "$RC" = "0" ]; then
  if grep -q "NEW PROPOSED CONTENT for c2" "$SKILL/out.txt"; then
    pass "exit 0 + stdout has proposed content"
  else
    fail "exit 0 but stdout missing content. out: $(cat "$SKILL/out.txt" 2>/dev/null)"
  fi
else
  fail "expected exit 0, got $RC. err: $(head -20 "$SKILL/err.txt" 2>/dev/null)"
fi

# Hold this skill for Case 4 cleanup checks.
SKILL_C2="$SKILL"

# ============================================================================
# Case 3: File mode timeout
# ============================================================================
echo "Case 3: file mode timeout (PROPOSER_FILE_TIMEOUT=2)"
SKILL="$(mkskill c3)"
(
  unset ANTHROPIC_API_KEY
  PROPOSER_FILE_TIMEOUT=2 PROPOSER_FILE_POLL_SEC=1 \
    bash "$DISPATCH" "$SKILL" > "$SKILL/out.txt" 2> "$SKILL/err.txt"
  echo $? > "$SKILL/rc.txt"
) &
DISP_PID=$!
PIDS_TO_KILL="$PIDS_TO_KILL $DISP_PID"

# It should die in ~2-3s. Give it 6s max.
elapsed=0
while [ "$elapsed" -lt 6 ]; do
  if ! kill -0 "$DISP_PID" 2>/dev/null; then break; fi
  sleep 1
  elapsed=$((elapsed + 1))
done
wait "$DISP_PID" 2>/dev/null || true
PIDS_TO_KILL="$(echo "$PIDS_TO_KILL" | sed "s/ $DISP_PID//")"

RC="$(cat "$SKILL/rc.txt" 2>/dev/null || echo 99)"
if [ "$RC" != "0" ] && [ "$RC" != "99" ]; then
  if grep -qi "TIMEOUT" "$SKILL/err.txt"; then
    pass "exited non-zero ($RC) with TIMEOUT msg after ~2s"
  else
    pass "exited non-zero ($RC) after ~2s"
  fi
else
  fail "expected non-zero exit on timeout, got rc=$RC"
fi

# ============================================================================
# Case 4: Cleanup (.proposed_prompt.txt and .proposed_target.txt both removed)
# ============================================================================
echo "Case 4: cleanup after success (from Case 2)"
PROMPT_C2="$SKILL_C2/autoresearch/.proposed_prompt.txt"
PROPOSAL_C2="$SKILL_C2/autoresearch/.proposed_target.txt"
if [ ! -f "$PROMPT_C2" ] && [ ! -f "$PROPOSAL_C2" ]; then
  pass "both .proposed_prompt.txt and .proposed_target.txt removed"
else
  msg=""
  [ -f "$PROMPT_C2" ] && msg="$msg prompt-still-exists"
  [ -f "$PROPOSAL_C2" ] && msg="$msg target-still-exists"
  fail "cleanup incomplete:$msg"
fi

# ============================================================================
# Case 5: API mode happy path (PATH-shimmed curl)
# ============================================================================
echo "Case 5: API mode happy path (stubbed curl)"
SKILL="$(mkskill c5)"
SHIM_DIR="$(mktemp -d "$TMP_ROOT/proposer-shim-XXXXXX")"
cleanup_dirs="$cleanup_dirs $SHIM_DIR"

# Write a fake curl. It must emulate `curl -sS -o <file> -w '%{http_code}' ...`.
# We parse out the -o argument and write a canned response there, then print
# the HTTP code on stdout.
cat > "$SHIM_DIR/curl" <<'EOF'
#!/usr/bin/env bash
# Stubbed curl. Args contain -o <file>. Status comes from env CURL_STUB_STATUS
# (default 200). Body is in env CURL_STUB_BODY (default valid messages JSON).
out_file=""
prev=""
for a in "$@"; do
  if [ "$prev" = "-o" ]; then out_file="$a"; fi
  prev="$a"
done
status="${CURL_STUB_STATUS:-200}"
body="${CURL_STUB_BODY:-'{"content":[{"type":"text","text":"STUB-API-RESPONSE\n"}]}'}"
if [ -n "$out_file" ]; then
  printf '%s' "$body" > "$out_file"
fi
printf '%s' "$status"
EOF
chmod +x "$SHIM_DIR/curl"

OLD_PATH="$PATH"
PATH="$SHIM_DIR:$PATH"
export PATH

(
  export ANTHROPIC_API_KEY="test-key"
  export CURL_STUB_STATUS="200"
  export CURL_STUB_BODY='{"content":[{"type":"text","text":"API-PROPOSAL-OK"}]}'
  bash "$DISPATCH" "$SKILL" > "$SKILL/out.txt" 2> "$SKILL/err.txt"
  echo $? > "$SKILL/rc.txt"
)
RC="$(cat "$SKILL/rc.txt" 2>/dev/null || echo 99)"

PATH="$OLD_PATH"
export PATH

if [ "$RC" = "0" ]; then
  if grep -q "API-PROPOSAL-OK" "$SKILL/out.txt"; then
    if grep -q "mode=api" "$SKILL/err.txt"; then
      pass "API mode invoked, parsed content[0].text"
    else
      pass "API mode produced expected content (no mode banner)"
    fi
  else
    fail "exit 0 but stdout missing parsed content. out: $(cat "$SKILL/out.txt" 2>/dev/null)"
  fi
else
  fail "expected exit 0, got $RC. err: $(head -20 "$SKILL/err.txt" 2>/dev/null)"
fi

# ============================================================================
# Case 6: API mode auth fail (401 -> exit 2)
# ============================================================================
echo "Case 6: API mode 401 -> exit 2"
SKILL="$(mkskill c6)"
PATH="$SHIM_DIR:$OLD_PATH"
export PATH
(
  export ANTHROPIC_API_KEY="bogus"
  export CURL_STUB_STATUS="401"
  export CURL_STUB_BODY='{"type":"error","error":{"type":"authentication_error","message":"invalid key"}}'
  bash "$DISPATCH" "$SKILL" > "$SKILL/out.txt" 2> "$SKILL/err.txt"
  echo $? > "$SKILL/rc.txt"
)
RC="$(cat "$SKILL/rc.txt" 2>/dev/null || echo 99)"
PATH="$OLD_PATH"
export PATH

if [ "$RC" = "2" ]; then
  pass "401 -> exit 2"
else
  fail "expected exit 2 on 401, got $RC. err: $(head -20 "$SKILL/err.txt" 2>/dev/null)"
fi

# ============================================================================
# Case 7: API mode rate limit (429 -> exit 3)
# ============================================================================
echo "Case 7: API mode 429 -> exit 3"
SKILL="$(mkskill c7)"
PATH="$SHIM_DIR:$OLD_PATH"
export PATH
(
  export ANTHROPIC_API_KEY="test-key"
  export CURL_STUB_STATUS="429"
  export CURL_STUB_BODY='{"type":"error","error":{"type":"rate_limit_error","message":"slow down"}}'
  bash "$DISPATCH" "$SKILL" > "$SKILL/out.txt" 2> "$SKILL/err.txt"
  echo $? > "$SKILL/rc.txt"
)
RC="$(cat "$SKILL/rc.txt" 2>/dev/null || echo 99)"
PATH="$OLD_PATH"
export PATH

if [ "$RC" = "3" ]; then
  pass "429 -> exit 3"
else
  fail "expected exit 3 on 429, got $RC. err: $(head -20 "$SKILL/err.txt" 2>/dev/null)"
fi

# ============================================================================
# Summary
# ============================================================================
echo ""
if [ "$fails" -eq 0 ]; then
  echo "All cases PASSED."
  exit 0
else
  echo "$fails case(s) FAILED."
  exit 1
fi
