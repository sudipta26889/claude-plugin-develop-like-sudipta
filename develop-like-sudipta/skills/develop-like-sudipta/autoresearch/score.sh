#!/usr/bin/env bash
# Score develop-like-sudipta SKILL.md description by trigger-accuracy proxy.
# Reads labeled fixtures from autoresearch/trigger_corpus.json.
# Usage: score.sh <skill-dir>
# Output: single float on stdout (last line) — weighted trigger accuracy % (0.0-100.0).
#         Higher is better.
set -euo pipefail

SKILL_DIR="${1:?skill-dir arg required}"

command -v python3 >/dev/null || { echo "python3 required" >&2; exit 2; }

SKILL_MD="$SKILL_DIR/SKILL.md"
[ -f "$SKILL_MD" ] || { echo "SKILL.md missing at $SKILL_MD" >&2; exit 2; }

CORPUS="$SKILL_DIR/autoresearch/trigger_corpus.json"
if [ ! -f "$CORPUS" ]; then
  echo "trigger_corpus.json missing at $CORPUS — cannot score without labeled fixtures" >&2
  exit 2
fi

python3 - "$SKILL_MD" "$CORPUS" <<'PY'
import json, re, sys
from pathlib import Path

skill_md = Path(sys.argv[1])
corpus_path = Path(sys.argv[2])

text = skill_md.read_text()
m = re.search(r'^---\n(.*?)\n---\n', text, re.DOTALL)
if not m:
    print("no YAML frontmatter in SKILL.md", file=sys.stderr)
    sys.exit(2)

frontmatter = m.group(1)
desc_match = re.search(r'description:\s*(.+?)(?=\n[a-zA-Z_]+:|\Z)', frontmatter, re.DOTALL)
description = (desc_match.group(1) if desc_match else "").strip().lower()

# Load corpus
try:
    corpus = json.loads(corpus_path.read_text())
except json.JSONDecodeError as e:
    print(f"trigger_corpus.json invalid JSON: {e}", file=sys.stderr)
    sys.exit(2)

queries = corpus.get("queries", [])
if not queries:
    print("trigger_corpus.json has no queries", file=sys.stderr)
    sys.exit(2)

STOPWORDS = {
    "the","and","for","with","this","that","from","into","when","what",
    "your","you","are","but","not","add","use","get","set","let","can",
    "out","new","one","two","its","has","had","was","were","will","would",
    "should","could","just","also","very","over","under","then","than","more",
    "most","less","least","make","made","like","such","some","any","all",
    "each","every","other","another","much","many","few","own","same",
}

def content_words(s):
    return {w for w in re.findall(r"[a-z][a-z0-9_-]{2,}", s.lower()) if w not in STOPWORDS}

desc_words = content_words(description)

MATCH_THRESHOLD = 0.60  # >= 60% of query content words must appear in description to count as match

tp = fp = tn = fn = 0
total_score = 0.0
total = 0

for q in queries:
    text = q.get("query", "")
    should = bool(q.get("should_trigger", False))
    qw = content_words(text)
    if not qw:
        continue
    overlap = len(qw & desc_words) / len(qw)
    predicted = overlap >= MATCH_THRESHOLD

    if predicted and should:
        tp += 1
    elif predicted and not should:
        fp += 1
    elif not predicted and not should:
        tn += 1
    else:
        fn += 1

    # Weighted accuracy score (matches sd-claude-code-access 0-100 scale):
    # reward overlap for positives, reward (1-overlap) for negatives.
    if should:
        total_score += overlap
    else:
        total_score += (1.0 - overlap)
    total += 1

# Report F1 in stderr for diagnostics; weighted-accuracy pct on stdout for scoring.
precision = tp / (tp + fp) if (tp + fp) else 0.0
recall = tp / (tp + fn) if (tp + fn) else 0.0
f1 = 2 * precision * recall / (precision + recall) if (precision + recall) else 0.0

print(f"tp={tp} fp={fp} tn={tn} fn={fn} precision={precision:.3f} recall={recall:.3f} f1={f1:.3f}",
      file=sys.stderr)

pct = (total_score / total * 100.0) if total else 0.0
print(f"{pct:.2f}")
PY
