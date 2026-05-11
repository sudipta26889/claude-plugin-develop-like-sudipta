#!/usr/bin/env bash
# score.sh — generic dispatcher that invokes the skill-specific scorer.
#
# Usage: score.sh <skill-dir>
#
# Resolves which scorer to invoke from <skill-dir>/autoresearch/config.json:
#   { "scorer_mode": "wordlap" }   -> autoresearch/score.sh        (default)
#   { "scorer_mode": "llm"     }   -> autoresearch/score-llm.sh    (opt-in)
#
# Falls back to wordlap if config.json is missing or scorer_mode is unset.
#
# Passes through stdout (the single-number score on the last line) and exit
# code from the chosen scorer.
#
# This dispatcher exists so run_autoresearch.sh has ONE entry point regardless
# of which skill it's optimizing AND which scoring mode is active.
#
# Bash 3.2 compatible.

set -u

SKILL_DIR="${1:-}"
if [ -z "$SKILL_DIR" ]; then
  echo "Usage: score.sh <skill-dir>" >&2
  exit 2
fi
if [ ! -d "$SKILL_DIR" ]; then
  echo "ERROR: skill-dir not a directory: $SKILL_DIR" >&2
  exit 1
fi
SKILL_DIR="$(cd "$SKILL_DIR" && pwd)"

CONFIG_FILE="$SKILL_DIR/autoresearch/config.json"
WORDLAP_SCORER="$SKILL_DIR/autoresearch/score.sh"
LLM_SCORER="$SKILL_DIR/autoresearch/score-llm.sh"

# Determine mode: default wordlap; only switch to llm if config.json explicitly says so.
MODE="wordlap"
if [ -f "$CONFIG_FILE" ]; then
  if command -v python3 >/dev/null 2>&1; then
    PARSED="$(
      python3 - "$CONFIG_FILE" <<'PY' 2>/dev/null || true
import json, sys
try:
    cfg = json.loads(open(sys.argv[1]).read() or "{}")
    print((cfg.get("scorer_mode") or "wordlap").strip())
except Exception:
    print("wordlap")
PY
    )"
    if [ -n "$PARSED" ]; then
      MODE="$PARSED"
    fi
  fi
fi

case "$MODE" in
  llm)
    SCORER="$LLM_SCORER"
    ;;
  wordlap|"")
    SCORER="$WORDLAP_SCORER"
    ;;
  *)
    echo "ERROR: unknown scorer_mode '$MODE' in $CONFIG_FILE (expected wordlap|llm)" >&2
    exit 1
    ;;
esac

if [ ! -f "$SCORER" ]; then
  echo "ERROR: missing skill-specific scorer at $SCORER" >&2
  echo "       Each skill that opts into autoresearch must provide its own score.sh." >&2
  echo "       See skills/autoresearch/assets/score_template.sh for a starting point." >&2
  exit 1
fi

# Invoke. The scorer receives the skill-dir as $1 and must emit a single
# parseable float on the LAST non-empty line of stdout.
bash "$SCORER" "$SKILL_DIR"
