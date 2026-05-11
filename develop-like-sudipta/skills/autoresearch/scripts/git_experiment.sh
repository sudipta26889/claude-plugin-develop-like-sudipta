#!/usr/bin/env bash
# git_experiment.sh — accept (commit) or reject (revert) an autoresearch candidate.
#
# Usage:
#   git_experiment.sh accept <skill-dir> <target-rel-path> <score>
#   git_experiment.sh reject <skill-dir> <target-rel-path> <score>
#
# accept: stages the target file and commits with a structured message.
# reject: `git checkout -- <target>` to discard the candidate.
#
# Bash 3.2 compatible.

set -u

ACTION="${1:-}"
SKILL_DIR="${2:-}"
TARGET_REL="${3:-}"
SCORE="${4:-0}"

usage() {
  echo "Usage: git_experiment.sh <accept|reject> <skill-dir> <target-rel-path> <score>" >&2
  exit 2
}

[ -n "$ACTION" ] || usage
[ -n "$SKILL_DIR" ] || usage
[ -n "$TARGET_REL" ] || usage
[ -d "$SKILL_DIR" ] || { echo "skill-dir not a directory: $SKILL_DIR" >&2; exit 1; }

SKILL_DIR="$(cd "$SKILL_DIR" && pwd)"
TARGET="$SKILL_DIR/$TARGET_REL"
SKILL_NAME="$(basename "$SKILL_DIR")"

# Find the git root (the script can be invoked from anywhere; the skill might
# live deep inside a repo).
GIT_ROOT="$(cd "$SKILL_DIR" && git rev-parse --show-toplevel 2>/dev/null || true)"
if [ -z "$GIT_ROOT" ]; then
  echo "ERROR: $SKILL_DIR is not inside a git repository" >&2
  exit 1
fi

case "$ACTION" in
  accept)
    # Stage and commit. Use the target's path relative to git root for `git add`.
    REL_TO_ROOT="${TARGET#$GIT_ROOT/}"
    ( cd "$GIT_ROOT" && \
      git add -- "$REL_TO_ROOT" && \
      git -c commit.gpgsign=false commit -m "experiment: score=$SCORE on $SKILL_NAME target=$TARGET_REL" \
    ) || {
      echo "ERROR: accept commit failed" >&2
      exit 1
    }
    ;;
  reject)
    REL_TO_ROOT="${TARGET#$GIT_ROOT/}"
    ( cd "$GIT_ROOT" && git checkout -- "$REL_TO_ROOT" ) || {
      echo "ERROR: reject revert failed" >&2
      exit 1
    }
    ;;
  *)
    usage
    ;;
esac
