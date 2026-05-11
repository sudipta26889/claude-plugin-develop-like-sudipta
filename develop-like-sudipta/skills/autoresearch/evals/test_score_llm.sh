#!/usr/bin/env bash
# test_score_llm.sh — smoke test for the LLM-scoring variant + dispatcher routing.
#
# Cases:
#   1. Missing API key            -> score-llm.sh exits 2, clear error.
#   2. Cache hit (no API key)     -> cache pre-populated; runs to completion w/o curl.
#   3. Cost guard                 -> 150-entry fixture -> exit 3.
#   4. Stubbed API 200 (YES all)  -> F1 reflects positive-class-only result.
#   5. Stubbed API 401            -> exit 2.
#   6. Dispatcher routing         -> config.json scorer_mode toggles llm vs wordlap.
#
# Bash 3.2 / macOS-friendly. No mapfile, no wait -n, no assoc arrays.
# Usage: ./test_score_llm.sh
# Exit 0 on PASS, non-zero on any failed assertion.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILL_DIR_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DISPATCHER="$SKILL_DIR_ROOT/scripts/score.sh"

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

# Build a minimal fake-skill scaffold compatible with the develop-like-sudipta/code-hacker
# layout (corpus at autoresearch/trigger_corpus.json, scorer at autoresearch/score-llm.sh).
mkfake() {
  local tag="$1" n_items="$2"
  local root
  root="$(mktemp -d "$TMP_ROOT/llm-scorer-test-XXXXXX")"
  cleanup_dirs="$cleanup_dirs $root"

  local sk="$root/skills/fake"
  mkdir -p "$sk/autoresearch"

  cat > "$sk/SKILL.md" <<'EOF'
---
name: fake
description: Fake skill for testing LLM scoring. Triggers on test queries.
---

Body.
EOF

  # Build a fixture with n_items, alternating should_trigger true/false
  python3 - "$sk/autoresearch/trigger_corpus.json" "$n_items" <<'PY'
import json, sys
path = sys.argv[1]
n = int(sys.argv[2])
items = []
for i in range(n):
    items.append({"query": "query number %d" % i, "should_trigger": (i % 2 == 0)})
with open(path, "w") as f:
    json.dump(items, f)
PY

  # Copy the real score-llm.sh from develop-like-sudipta (corpus-based variant).
  cp "$SKILL_DIR_ROOT/../develop-like-sudipta/autoresearch/score-llm.sh" \
     "$sk/autoresearch/score-llm.sh" 2>/dev/null || {
    # Fall back: synthesize from the canonical develop-like-sudipta path computed
    # relative to this test file's parent autoresearch dir.
    local src
    src="$(cd "$SKILL_DIR_ROOT/../develop-like-sudipta/autoresearch" 2>/dev/null && pwd)/score-llm.sh"
    cp "$src" "$sk/autoresearch/score-llm.sh"
  }
  chmod +x "$sk/autoresearch/score-llm.sh"

  # Stub a wordlap score.sh too (echo a fixed value) so dispatcher routing test can
  # distinguish which scorer fired.
  cat > "$sk/autoresearch/score.sh" <<'EOF'
#!/usr/bin/env bash
echo "wordlap-stub: ran"
echo "0.1234"
EOF
  chmod +x "$sk/autoresearch/score.sh"

  echo "$root"
}

# Make a curl stub on PATH that returns a fixed status+body.
# Usage: mkcurlstub <dir> <status> <text>
mkcurlstub() {
  local dir="$1" status="$2" body_text="$3"
  mkdir -p "$dir"
  cat > "$dir/curl" <<EOF
#!/usr/bin/env bash
# Mimic curl -sS -w '\n__HTTP_CODE__:%{http_code}' returning a fixed payload.
cat <<JSON
{"content":[{"type":"text","text":"$body_text"}]}
JSON
printf '\n__HTTP_CODE__:%s' "$status"
EOF
  chmod +x "$dir/curl"
}

# Curl stub that exits 99 if invoked (asserts no network call happened).
mkcurlstub_forbidden() {
  local dir="$1"
  mkdir -p "$dir"
  cat > "$dir/curl" <<'EOF'
#!/usr/bin/env bash
echo "FAIL: curl was called when it should not have been" >&2
exit 99
EOF
  chmod +x "$dir/curl"
}

# ---- Case 1: missing API key ----
echo "Case 1: missing API key"
ROOT="$(mkfake c1 4)"
SK="$ROOT/skills/fake"
out="$(unset ANTHROPIC_API_KEY; bash "$SK/autoresearch/score-llm.sh" 2>&1)"; rc=$?
if [ "$rc" -eq 2 ] && echo "$out" | grep -qi "ANTHROPIC_API_KEY"; then
  pass "missing API key => exit 2 with clear error"
else
  fail "expected exit 2 + clear error; rc=$rc out=$out"
fi

# ---- Case 2: cache hit (no API key needed if all queries are cached) ----
# Implementation note: score-llm.sh currently exits early on missing API key BEFORE
# checking cache, which is the safer design (the cache could miss for new queries).
# Verify cache behavior by setting a DUMMY key and stubbing curl to exit 99 — the
# script should never reach curl.
echo "Case 2: cache hit (curl stubbed to fail, must not be called)"
ROOT="$(mkfake c2 4)"
SK="$ROOT/skills/fake"
STUBDIR="$ROOT/stubs"
mkcurlstub_forbidden "$STUBDIR"
# Pre-populate cache with all 4 queries under the correct description hash.
python3 - "$SK/SKILL.md" "$SK/autoresearch/.llm_cache.json" <<'PY'
import json, re, hashlib, sys
md = open(sys.argv[1]).read()
fm = re.search(r"^---\n(.*?)\n---\n", md, re.DOTALL).group(1)
desc = re.search(r"description:\s*(.+?)(?=\n[a-zA-Z_][a-zA-Z0-9_-]*:|\Z)", fm, re.DOTALL).group(1).strip()
dh = hashlib.sha256(desc.encode()).hexdigest()[:16]
cache = {}
for i in range(4):
    q = "query number %d" % i
    # Predict YES for should_trigger==True (i even), NO otherwise → perfect F1
    cache["%s::%s" % (dh, q)] = "YES" if i % 2 == 0 else "NO"
open(sys.argv[2], "w").write(json.dumps(cache))
PY

out="$(PATH="$STUBDIR:$PATH" ANTHROPIC_API_KEY=dummy bash "$SK/autoresearch/score-llm.sh" 2>&1)"; rc=$?
last="$(printf '%s\n' "$out" | tail -n 1)"
if [ "$rc" -eq 0 ] && [ "$last" = "1.0000" ]; then
  pass "cache hit: F1=1.0000, no curl calls"
else
  fail "expected rc=0 + F1=1.0000 from cache; rc=$rc last=$last out=$out"
fi

# ---- Case 3: cost guard (>100 entries) ----
echo "Case 3: cost guard (150 entries)"
ROOT="$(mkfake c3 150)"
SK="$ROOT/skills/fake"
out="$(ANTHROPIC_API_KEY=dummy bash "$SK/autoresearch/score-llm.sh" 2>&1)"; rc=$?
if [ "$rc" -eq 3 ] && echo "$out" | grep -qi "fixture too large"; then
  pass "150-entry fixture => exit 3 with cost-guard message"
else
  fail "expected exit 3 + 'fixture too large'; rc=$rc out=$out"
fi

# ---- Case 4: stubbed API 200, returns YES for every query ----
echo "Case 4: stubbed API 200 returning YES for all"
ROOT="$(mkfake c4 4)"
SK="$ROOT/skills/fake"
STUBDIR="$ROOT/stubs"
mkcurlstub "$STUBDIR" 200 "YES"
# Items 0,2 → should_trigger=true (matched, YES → tp). Items 1,3 → should=false (matched, YES → fp).
# TP=2, FP=2, FN=0 → P=0.5, R=1.0, F1=0.6667
out="$(PATH="$STUBDIR:$PATH" ANTHROPIC_API_KEY=dummy bash "$SK/autoresearch/score-llm.sh" 2>&1)"; rc=$?
last="$(printf '%s\n' "$out" | tail -n 1)"
if [ "$rc" -eq 0 ] && [ "$last" = "0.6667" ]; then
  pass "all-YES stub: F1=0.6667 (P=0.5 R=1.0)"
else
  fail "expected rc=0 + F1=0.6667; rc=$rc last=$last out=$out"
fi

# ---- Case 5: stubbed API 401 ----
echo "Case 5: stubbed API 401"
ROOT="$(mkfake c5 4)"
SK="$ROOT/skills/fake"
STUBDIR="$ROOT/stubs"
mkcurlstub "$STUBDIR" 401 "unauthorized"
out="$(PATH="$STUBDIR:$PATH" ANTHROPIC_API_KEY=dummy bash "$SK/autoresearch/score-llm.sh" 2>&1)"; rc=$?
if [ "$rc" -eq 2 ] && echo "$out" | grep -qi "401"; then
  pass "401 stub => exit 2 with 401 in stderr"
else
  fail "expected exit 2 + 401 message; rc=$rc out=$out"
fi

# ---- Case 6: dispatcher routing via config.json scorer_mode ----
echo "Case 6: dispatcher routes wordlap vs llm based on config.json"
ROOT="$(mkfake c6 4)"
SK="$ROOT/skills/fake"

# 6a. No config.json → defaults to wordlap (stub returns 0.1234)
out="$(bash "$DISPATCHER" "$SK" 2>&1)"; rc=$?
last="$(printf '%s\n' "$out" | tail -n 1)"
if [ "$rc" -eq 0 ] && [ "$last" = "0.1234" ]; then
  pass "6a: missing config.json => wordlap (0.1234)"
else
  fail "6a: expected wordlap (0.1234); rc=$rc last=$last"
fi

# 6b. config with scorer_mode: wordlap → wordlap
echo '{"scorer_mode":"wordlap"}' > "$SK/autoresearch/config.json"
out="$(bash "$DISPATCHER" "$SK" 2>&1)"; rc=$?
last="$(printf '%s\n' "$out" | tail -n 1)"
if [ "$rc" -eq 0 ] && [ "$last" = "0.1234" ]; then
  pass "6b: scorer_mode=wordlap => wordlap (0.1234)"
else
  fail "6b: expected wordlap (0.1234); rc=$rc last=$last"
fi

# 6c. config with scorer_mode: llm → llm (use cache so we don't need API)
echo '{"scorer_mode":"llm"}' > "$SK/autoresearch/config.json"
# Pre-populate cache so the LLM scorer hits cache for every item.
python3 - "$SK/SKILL.md" "$SK/autoresearch/.llm_cache.json" <<'PY'
import json, re, hashlib, sys
md = open(sys.argv[1]).read()
fm = re.search(r"^---\n(.*?)\n---\n", md, re.DOTALL).group(1)
desc = re.search(r"description:\s*(.+?)(?=\n[a-zA-Z_][a-zA-Z0-9_-]*:|\Z)", fm, re.DOTALL).group(1).strip()
dh = hashlib.sha256(desc.encode()).hexdigest()[:16]
cache = {}
for i in range(4):
    q = "query number %d" % i
    cache["%s::%s" % (dh, q)] = "YES" if i % 2 == 0 else "NO"
open(sys.argv[2], "w").write(json.dumps(cache))
PY

# Use a forbidden curl stub to assert no API call.
STUBDIR="$ROOT/stubs2"
mkcurlstub_forbidden "$STUBDIR"
out="$(PATH="$STUBDIR:$PATH" ANTHROPIC_API_KEY=dummy bash "$DISPATCHER" "$SK" 2>&1)"; rc=$?
last="$(printf '%s\n' "$out" | tail -n 1)"
if [ "$rc" -eq 0 ] && [ "$last" = "1.0000" ]; then
  pass "6c: scorer_mode=llm => llm via cache (1.0000)"
else
  fail "6c: expected llm (1.0000); rc=$rc last=$last out=$out"
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
