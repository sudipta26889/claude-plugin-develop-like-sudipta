#!/usr/bin/env bash
# Score code-hacker by F1 on autoresearch/trigger_corpus.json.
# Usage: bash autoresearch/score.sh
# Run from anywhere — paths resolve from script location.
# Output: single float on stdout (last line) — F1 in [0.0, 1.0].
# Exit:   0 on success, non-zero on missing inputs / parse errors.

set -euo pipefail

# Resolve skill dir as the parent of this script's directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

SKILL_MD="$SKILL_DIR/SKILL.md"
CORPUS_FILE="$SCRIPT_DIR/trigger_corpus.json"

if [ ! -f "$SKILL_MD" ]; then
  echo "ERROR: SKILL.md not found at $SKILL_MD" >&2
  exit 2
fi

if [ ! -f "$CORPUS_FILE" ]; then
  echo "ERROR: trigger_corpus.json not found at $CORPUS_FILE" >&2
  exit 3
fi

command -v python3 >/dev/null 2>&1 || {
  echo "ERROR: python3 is required" >&2
  exit 4
}

python3 - "$SKILL_MD" "$CORPUS_FILE" <<'PY'
import json
import re
import sys
from pathlib import Path

skill_md_path = Path(sys.argv[1])
corpus_path = Path(sys.argv[2])

# --- 1. Extract description from frontmatter ---
text = skill_md_path.read_text()
fm_match = re.search(r"^---\n(.*?)\n---\n", text, re.DOTALL)
if not fm_match:
    print("ERROR: no YAML frontmatter in SKILL.md", file=sys.stderr)
    sys.exit(5)

frontmatter = fm_match.group(1)
desc_match = re.search(
    r"description:\s*(.+?)(?=\n[a-zA-Z_][a-zA-Z0-9_-]*:|\Z)",
    frontmatter,
    re.DOTALL,
)
if not desc_match:
    print("ERROR: no 'description:' field in frontmatter", file=sys.stderr)
    sys.exit(6)

description = desc_match.group(1).strip().lower()

# --- 2. Load corpus ---
try:
    raw = corpus_path.read_text()
    if not raw.strip():
        print("ERROR: trigger_corpus.json is empty", file=sys.stderr)
        sys.exit(7)
    data = json.loads(raw)
except json.JSONDecodeError as e:
    print(f"ERROR: trigger_corpus.json is not valid JSON: {e}", file=sys.stderr)
    sys.exit(8)

# Accept either a top-level list or a dict with "queries" / "evals" / "items"
if isinstance(data, list):
    items = data
elif isinstance(data, dict):
    items = data.get("queries") or data.get("evals") or data.get("items") or []
else:
    items = []

if not items:
    print("ERROR: trigger_corpus.json contains no query items", file=sys.stderr)
    sys.exit(9)

# --- 3. Build description word set ---
STOPWORDS = {
    "the", "and", "for", "with", "from", "into", "that", "this", "these",
    "those", "you", "your", "are", "but", "not", "any", "all", "can",
    "use", "via", "out", "now", "per", "etc", "its", "has", "had",
    "have", "was", "were", "will", "would", "should", "could", "than",
    "then", "when", "what", "which", "who", "how", "why", "where", "while",
    "about", "also", "just", "very", "only", "more", "less", "some", "such",
    "they", "them", "their", "there", "here", "been", "being", "each",
    "over", "under", "before", "after", "between", "again", "still",
    "even", "much", "many", "most", "least", "every", "other",
    "iam", "ive", "didnt", "dont", "doesnt", "wont", "cant",
}

def tokenize(s):
    return [
        w for w in re.findall(r"[a-z][a-z0-9_-]{2,}", s.lower())
        if w not in STOPWORDS
    ]

desc_words = set(tokenize(description))

# --- 4. Match function: query matches if >=60% of its content words appear in desc ---
MATCH_THRESHOLD = 0.60

def query_matches(query):
    q_words = set(tokenize(query))
    if not q_words:
        return False
    overlap = len(q_words & desc_words)
    ratio = overlap / len(q_words)
    return ratio >= MATCH_THRESHOLD

# --- 5. Confusion matrix ---
tp = fp = tn = fn = 0
for it in items:
    query = it.get("query") or it.get("prompt") or ""
    should = bool(it.get("should_trigger", False))
    matched = query_matches(query)
    if should and matched:
        tp += 1
    elif (not should) and matched:
        fp += 1
    elif (not should) and (not matched):
        tn += 1
    else:
        fn += 1

# --- 6. F1 ---
precision = tp / (tp + fp) if (tp + fp) > 0 else 0.0
recall = tp / (tp + fn) if (tp + fn) > 0 else 0.0
f1 = (2 * precision * recall / (precision + recall)) if (precision + recall) > 0 else 0.0

print(f"{f1:.4f}")
PY
