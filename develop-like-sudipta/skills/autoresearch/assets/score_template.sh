#!/usr/bin/env bash
# score.sh — per-skill scorer template.
#
# Wired by each skill that opts into autoresearch. Lives at
# <skill-dir>/autoresearch/score.sh.
#
# Usage: score.sh <skill-dir>
#
# CONTRACT (enforced by the shared driver):
#   - Receives the skill-dir as $1.
#   - Computes ONE float metric.
#   - Prints the metric on the LAST non-empty line of stdout, parseable as a float.
#   - Direction (higher OR lower is better) is fixed; must match program.md.
#   - Exits 0 on success; non-zero on internal error (treated as rejected).
#   - Verbose / debug output goes to stderr OR earlier lines of stdout — the
#     driver reads only the last non-empty line of stdout as the score.
#
# Bash 3.2 compatible.

set -u
set -o pipefail

SKILL_DIR="${1:?Usage: score.sh <skill-dir>}"
[ -d "$SKILL_DIR" ] || { echo "ERROR: skill-dir not found: $SKILL_DIR" >&2; exit 1; }
SKILL_DIR="$(cd "$SKILL_DIR" && pwd)"

# -----------------------------------------------------------------------------
# 1. Validate the target file exists and is well-formed.
#    Reject (exit non-zero OR emit very-low score) if structural invariants fail.
# -----------------------------------------------------------------------------
TARGET_REL="$(head -1 "$SKILL_DIR/autoresearch/target.txt" 2>/dev/null || echo SKILL.md)"
TARGET="$SKILL_DIR/$TARGET_REL"
if [ ! -f "$TARGET" ]; then
  echo "0"
  exit 0
fi

# Example structural check (adapt to your target):
#   - SKILL.md must have valid YAML frontmatter
#   - description length must be 200-2000 chars
#   - etc.
#
# python3 - "$TARGET" <<'PY' >/dev/null 2>&1 || { echo "0"; exit 0; }
# import sys, re
# t = open(sys.argv[1]).read()
# m = re.match(r'^---\n(.*?)\n---', t, re.DOTALL)
# assert m, "no frontmatter"
# desc = re.search(r'description:\s*(.+?)(?=\n[a-zA-Z_]+:|\Z)', m.group(1), re.DOTALL)
# assert desc, "no description"
# d = desc.group(1).strip()
# assert 200 <= len(d) <= 4000, "description out of range"
# PY

# -----------------------------------------------------------------------------
# 2. Compute the metric.
#    Replace this block with the skill-specific scoring logic.
# -----------------------------------------------------------------------------
#
# Common patterns:
#
# A) Trigger-accuracy: load evals/*.json, compute lexical-overlap or LLM-agreement
# B) Regex F1: run target regex against labeled fixture, compute precision/recall
# C) Audit completeness: run audit script against fixture repo, compare to answer key
# D) Smoke pass-rate: run evals/test_*.sh, % passed
#
# Replace the stub below with your real scorer.
# -----------------------------------------------------------------------------

python3 - "$SKILL_DIR" <<'PY'
import sys, os
skill_dir = sys.argv[1]
# TODO: replace with real metric.
# Stub: emit 0.0 so the loop has SOMETHING to compare against.
SCORE = 0.0
print(f"{SCORE:.2f}")
PY
