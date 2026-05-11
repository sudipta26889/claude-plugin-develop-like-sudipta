#!/usr/bin/env bash
# score.sh — generic dispatcher that invokes the skill-specific scorer.
#
# Usage: score.sh <skill-dir>
#
# Resolves <skill-dir>/autoresearch/score.sh (the per-skill scorer wired by
# the skill's own autoresearch wiring task) and invokes it, passing through
# stdout (the single-number score on the last line) and exit code.
#
# This dispatcher exists so run_autoresearch.sh has ONE entry point regardless
# of which skill it's optimizing. The per-skill scorer is the thing that
# actually loads evals and computes the metric.
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

SKILL_SCORE="$SKILL_DIR/autoresearch/score.sh"
if [ ! -f "$SKILL_SCORE" ]; then
  echo "ERROR: missing skill-specific scorer at $SKILL_SCORE" >&2
  echo "       Each skill that opts into autoresearch must provide its own score.sh." >&2
  echo "       See skills/autoresearch/assets/score_template.sh for a starting point." >&2
  exit 1
fi

# Invoke the skill scorer. It receives the skill-dir as $1 and must emit a
# single parseable float on the LAST non-empty line of stdout.
bash "$SKILL_SCORE" "$SKILL_DIR"
