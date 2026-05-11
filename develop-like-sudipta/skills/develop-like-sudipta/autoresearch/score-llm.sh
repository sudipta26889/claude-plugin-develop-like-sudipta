#!/usr/bin/env bash
# Score develop-like-sudipta by F1 on autoresearch/trigger_corpus.json — LLM judgment variant.
# Asks Claude Haiku-4.5 to decide YES/NO per query given the SKILL.md description.
# Usage: bash autoresearch/score-llm.sh
# Output: single float on stdout (last line) — F1 in [0.0, 1.0].
#
# Exit codes:
#   0 success
#   2 missing ANTHROPIC_API_KEY OR missing SKILL.md OR 401 from API
#   3 fixture too large (>100) OR 429 exhausted
#   4 5xx exhausted
#   5+ assorted parse/file errors
#
# Bash 3.2 compatible.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

SKILL_MD="$SKILL_DIR/SKILL.md"
CORPUS_FILE="$SCRIPT_DIR/trigger_corpus.json"
CACHE_FILE="$SCRIPT_DIR/.llm_cache.json"

if [ -z "${ANTHROPIC_API_KEY:-}" ]; then
  echo "ERROR: ANTHROPIC_API_KEY env var is required for LLM scoring" >&2
  echo "       set it or use score.sh (deterministic word-overlap) instead" >&2
  exit 2
fi

if [ ! -f "$SKILL_MD" ]; then
  echo "ERROR: SKILL.md not found at $SKILL_MD" >&2
  exit 2
fi

if [ ! -f "$CORPUS_FILE" ]; then
  echo "ERROR: trigger_corpus.json not found at $CORPUS_FILE" >&2
  exit 3
fi

command -v python3 >/dev/null 2>&1 || { echo "ERROR: python3 required" >&2; exit 4; }
command -v curl    >/dev/null 2>&1 || { echo "ERROR: curl required"    >&2; exit 4; }

CURL_BIN="$(command -v curl)"
export CURL_BIN

python3 - "$SKILL_MD" "$CORPUS_FILE" "$CACHE_FILE" <<'PY'
import json
import os
import re
import sys
import hashlib
import subprocess
import time
from pathlib import Path

skill_md_path = Path(sys.argv[1])
corpus_path   = Path(sys.argv[2])
cache_path    = Path(sys.argv[3])

api_key = os.environ.get("ANTHROPIC_API_KEY", "")
curl_bin = os.environ.get("CURL_BIN", "curl")
model   = "claude-haiku-4-5-20251001"
api_url = "https://api.anthropic.com/v1/messages"

text = skill_md_path.read_text()
fm_match = re.search(r"^---\n(.*?)\n---\n", text, re.DOTALL)
if not fm_match:
    print("ERROR: no YAML frontmatter in SKILL.md", file=sys.stderr); sys.exit(5)
desc_match = re.search(
    r"description:\s*(.+?)(?=\n[a-zA-Z_][a-zA-Z0-9_-]*:|\Z)",
    fm_match.group(1), re.DOTALL,
)
if not desc_match:
    print("ERROR: no 'description:'", file=sys.stderr); sys.exit(6)
description = desc_match.group(1).strip()
desc_hash = hashlib.sha256(description.encode()).hexdigest()[:16]

try:
    raw = corpus_path.read_text()
    data = json.loads(raw) if raw.strip() else []
except json.JSONDecodeError as e:
    print(f"ERROR: trigger_corpus.json invalid: {e}", file=sys.stderr); sys.exit(8)

if isinstance(data, list):
    items = data
elif isinstance(data, dict):
    items = data.get("queries") or data.get("evals") or data.get("items") or []
else:
    items = []

if not items:
    print("ERROR: no query items", file=sys.stderr); sys.exit(9)

if len(items) > 100:
    print(
        "ERROR: fixture has %d entries (>100); fixture too large for LLM scoring; "
        "use score.sh (word-overlap)" % len(items),
        file=sys.stderr,
    )
    sys.exit(3)

cache = {}
if cache_path.exists():
    try:
        cache = json.loads(cache_path.read_text() or "{}")
    except Exception:
        cache = {}

def cache_key(query, dh):
    return "%s::%s" % (dh, query)

def call_api(query):
    prompt = (
        "Given this skill description: " + description + "\n\n"
        "Would the query '" + query + "' invoke this skill? Answer YES or NO."
    )
    body = json.dumps({
        "model": model,
        "max_tokens": 8,
        "messages": [{"role": "user", "content": prompt}],
    })
    attempts_429 = 0
    attempts_5xx = 0
    while True:
        proc = subprocess.run(
            [
                curl_bin, "-sS", "-w", "\n__HTTP_CODE__:%{http_code}",
                "-X", "POST", api_url,
                "-H", "x-api-key: " + api_key,
                "-H", "anthropic-version: 2023-06-01",
                "-H", "content-type: application/json",
                "-d", body,
            ],
            capture_output=True, text=True,
        )
        out = proc.stdout or ""
        m = re.search(r"__HTTP_CODE__:(\d+)\s*$", out)
        status = int(m.group(1)) if m else 0
        body_text = re.sub(r"\n?__HTTP_CODE__:\d+\s*$", "", out)
        if status == 401:
            print("ERROR: 401 from Anthropic API (bad key)", file=sys.stderr); sys.exit(2)
        if status == 429:
            attempts_429 += 1
            if attempts_429 > 3:
                print("ERROR: 429 rate-limited; exhausted 3 retries", file=sys.stderr); sys.exit(3)
            time.sleep(5); continue
        if 500 <= status < 600:
            attempts_5xx += 1
            if attempts_5xx > 3:
                print("ERROR: 5xx from Anthropic API; exhausted 3 retries", file=sys.stderr); sys.exit(4)
            time.sleep(2); continue
        if status != 200:
            print("WARN: unexpected status %d; treating as NO" % status, file=sys.stderr)
            return "NO"
        try:
            payload = json.loads(body_text)
            content = payload.get("content", [])
            first = content[0] if content else {}
            text_out = (first.get("text") or "").strip()
        except Exception as e:
            print("WARN: malformed response (%s); treating as NO" % e, file=sys.stderr); return "NO"
        m2 = re.match(r"\s*([A-Za-z]+)", text_out)
        if not m2:
            print("WARN: no YES/NO in '%s'; treating as NO" % text_out, file=sys.stderr); return "NO"
        word = m2.group(1).upper()
        if word.startswith("YES"): return "YES"
        if word.startswith("NO"):  return "NO"
        print("WARN: ambiguous '%s'; treating as NO" % word, file=sys.stderr)
        return "NO"

tp = fp = tn = fn = 0
new_cache_entries = 0
for it in items:
    query = it.get("query") or it.get("prompt") or ""
    should = bool(it.get("should_trigger", False))
    key = cache_key(query, desc_hash)
    if key in cache:
        verdict = cache[key]
    else:
        verdict = call_api(query)
        cache[key] = verdict
        new_cache_entries += 1
        subprocess.run(["python3", "-c", "import time; time.sleep(0.1)"])
    matched = (verdict == "YES")
    if should and matched:       tp += 1
    elif (not should) and matched: fp += 1
    elif (not should) and (not matched): tn += 1
    else: fn += 1

if new_cache_entries > 0:
    try:
        cache_path.write_text(json.dumps(cache, indent=2))
    except Exception as e:
        print("WARN: could not write cache: %s" % e, file=sys.stderr)

precision = tp / (tp + fp) if (tp + fp) > 0 else 0.0
recall    = tp / (tp + fn) if (tp + fn) > 0 else 0.0
f1 = (2 * precision * recall / (precision + recall)) if (precision + recall) > 0 else 0.0

print(
    "llm-scorer: tp=%d fp=%d tn=%d fn=%d precision=%.3f recall=%.3f f1=%.4f (new_cache=%d)" % (
        tp, fp, tn, fn, precision, recall, f1, new_cache_entries,
    ),
    file=sys.stderr,
)
print("%.4f" % f1)
PY
