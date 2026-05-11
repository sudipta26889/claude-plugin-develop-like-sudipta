#!/usr/bin/env bash
# audit.sh — cross-reference a phase directive against commits made
# during/after that phase. Smarter version: parses the directive's commit-pattern
# section, file references, and test references; checks each against git log.
# Heuristic — meant for spot-checks, not formal verification.
#
# Usage: audit.sh <workspace> <phase-number> [--since=N] \
#                 [--retry N] [--retry-interval SEC]
#   --since=N        Range start (default HEAD~20). Also accepted as a bare
#                    positional arg in slot 3 for back-compat.
#   --retry N        On a "missing-file-or-commit" finding, sleep and re-run
#                    up to N times. Default 0 (single-shot — old behaviour).
#                    Useful when CC's checkpoint message lands before the
#                    autocommit / pre-commit hook / GPG signature finishes.
#   --retry-interval Seconds to sleep between retries. Default 2.
#
# Exit codes:
#   0  clean — every expected commit + file landed
#   1  hard error — missing directive file, bad CLI args, etc.
#   2  missing-file-or-commit (retryable drift). Returned when one or more
#      expected commit messages don't appear in git log, OR one or more
#      directive-mentioned files weren't changed in the range. Exit 2 is
#      what the --retry loop watches; with retries enabled, you only see
#      it if drift persists after the full budget is spent.
set -euo pipefail

usage() {
  echo "usage: audit.sh <workspace> <phase-number> [--since=N] [--retry N] [--retry-interval SEC]" >&2
}

# ---------------------------------------------------------------------------
# Argument parsing — keep positional <workspace> <phase> mandatory, accept
# flags in any order afterwards. The legacy 3rd positional (bare since) is
# still honoured so existing automation doesn't break.
# ---------------------------------------------------------------------------
WS="${1:-}"
PHASE="${2:-}"
if [ -z "$WS" ] || [ -z "$PHASE" ]; then
  usage
  exit 1
fi
shift 2

SINCE="HEAD~20"
RETRIES=0
INTERVAL=2

while [ "$#" -gt 0 ]; do
  case "$1" in
    --since=*)
      SINCE="${1#--since=}"
      shift
      ;;
    --since)
      SINCE="${2:?}"
      shift 2
      ;;
    --retry)
      RETRIES="${2:?}"
      shift 2
      ;;
    --retry-interval)
      INTERVAL="${2:?}"
      shift 2
      ;;
    --)
      shift
      break
      ;;
    -*)
      echo "[audit] unknown option: $1" >&2
      usage
      exit 1
      ;;
    *)
      # Bare positional after <ws> <phase> — treat as legacy SINCE.
      SINCE="$1"
      shift
      ;;
  esac
done

# Sanity: numeric retry budget + interval.
case "$RETRIES" in
  ''|*[!0-9]*)
    echo "[audit] --retry must be a non-negative integer (got: $RETRIES)" >&2
    exit 1
    ;;
esac
case "$INTERVAL" in
  ''|*[!0-9]*)
    echo "[audit] --retry-interval must be a non-negative integer (got: $INTERVAL)" >&2
    exit 1
    ;;
esac

DIR_FILE="$WS/.cc/phase-$PHASE.md"
if [ ! -f "$DIR_FILE" ]; then
  echo "[audit] no directive at $DIR_FILE" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# do_audit — single pass. Echoes the human-readable report to stdout. Returns
# 0 if the audit is clean, 2 if any expected commit or directive-mentioned
# file is missing from the range (the retryable laggy-drift signal).
# ---------------------------------------------------------------------------
do_audit() {
  cd "$WS"

  echo "============================================================"
  echo "  AUDIT: Phase $PHASE"
  echo "  Directive: $DIR_FILE"
  echo "  Range:     $SINCE..HEAD"
  echo "============================================================"
  echo

  # 1. Commits in range
  echo "── Commits in range ──"
  git log --oneline "$SINCE..HEAD" 2>/dev/null | sed 's/^/  /'
  N_COMMITS=$(git log --oneline "$SINCE..HEAD" 2>/dev/null | wc -l | tr -d ' ')
  echo
  echo "  Total: $N_COMMITS commits"
  echo

  # 2. Expected commit messages from directive
  echo "── Expected commit messages (from directive § Commit pattern) ──"
  EXPECTED=$(awk '/^## *Commit pattern/,/^## /' "$DIR_FILE" | grep -oE '`[a-zA-Z][a-zA-Z0-9_./()+-]*: [^`]+`' | tr -d '`' | sed 's/^/  - /' || true)
  if [ -z "$EXPECTED" ]; then
    echo "  _(no commit-pattern section found)_"
  else
    echo "$EXPECTED"
  fi
  echo

  # 3. Of those, how many exist in git log? Track misses for the exit code.
  echo "── Commits matched ──"
  COMMIT_MISSES=0
  if [ -n "$EXPECTED" ]; then
    # while-read inside a process substitution would let us mutate
    # COMMIT_MISSES, but the original script piped through `while` which
    # spawned a subshell and dropped the counter. Use a here-doc so the
    # loop body runs in the current shell.
    while IFS= read -r line; do
      [ -z "$line" ] && continue
      PATTERN=$(echo "$line" | sed 's/^  - //; s/(/\\(/g; s/)/\\)/g')
      HIT=$(git log --oneline "$SINCE..HEAD" --grep="$PATTERN" 2>/dev/null | head -1)
      if [ -n "$HIT" ]; then
        echo "  ✓ $line"
        echo "      → $HIT"
      else
        echo "  ✗ $line  (NOT FOUND in $SINCE..HEAD)"
        COMMIT_MISSES=$((COMMIT_MISSES + 1))
      fi
    done <<EOF
$EXPECTED
EOF
  fi
  echo

  # 4. Files mentioned in directive vs files changed
  echo "── Files in directive ──"
  DIR_FILES=$(grep -oE '`[a-zA-Z0-9_./-]+\.(py|ts|tsx|md|sql|yaml|yml|json|toml|sh)`' "$DIR_FILE" | sort -u | tr -d '`' | sed 's/^/  /' || true)
  echo "$DIR_FILES"
  echo

  echo "── Files changed in range ──"
  CHANGED=$(git log --name-only --pretty=format: "$SINCE..HEAD" 2>/dev/null | sort -u | grep -v '^$' | sed 's/^/  /')
  echo "$CHANGED"
  echo

  # 5. Files in directive but not changed — track misses for the exit code.
  echo "── ⚠ Mentioned but NOT changed ──"
  FILE_MISSES=0
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    trimmed=$(echo "$f" | tr -d ' ')
    [ -z "$trimmed" ] && continue
    if ! echo "$CHANGED" | grep -qF "$trimmed"; then
      echo "  ⚠ $trimmed"
      FILE_MISSES=$((FILE_MISSES + 1))
    fi
  done <<EOF
$DIR_FILES
EOF
  echo

  # 6. Test count delta
  echo "── Test files mentioned ──"
  DIR_TESTS=$(grep -oE '`tests?/[a-zA-Z0-9_./-]+\.py`' "$DIR_FILE" | sort -u | tr -d '`' | sed 's/^/  /' || true)
  if [ -n "$DIR_TESTS" ]; then
    echo "$DIR_TESTS"
  else
    echo "  _(no specific test files mentioned)_"
  fi
  echo

  echo "── Audit complete ──"

  if [ "$COMMIT_MISSES" -gt 0 ] || [ "$FILE_MISSES" -gt 0 ]; then
    return 2
  fi
  return 0
}

# ---------------------------------------------------------------------------
# Retry loop. With RETRIES=0 (default) this runs once and exits — preserving
# the original single-shot behaviour for callers that don't pass --retry.
# Each retry sleeps INTERVAL seconds and re-runs do_audit. Only exit code 2
# (missing-file-or-commit) is treated as retryable; anything else terminates
# the loop immediately.
# ---------------------------------------------------------------------------
attempt=0
max_attempts=$((RETRIES + 1))
while :; do
  attempt=$((attempt + 1))
  set +e
  do_audit
  rc=$?
  set -e
  if [ "$rc" -eq 0 ]; then
    exit 0
  fi
  if [ "$rc" -ne 2 ]; then
    # Hard error from do_audit — pass it through unchanged.
    exit "$rc"
  fi
  # rc == 2: laggy drift. Retry if budget allows.
  remaining=$((max_attempts - attempt))
  if [ "$remaining" -le 0 ]; then
    if [ "$RETRIES" -gt 0 ]; then
      echo "[audit] retry budget exhausted ($RETRIES retries × ${INTERVAL}s) — surfacing drift" >&2
      exit 2
    fi
    # No-flag invocation: maintain legacy exit 1 for back-compat. No
    # extraneous stderr — the report on stdout is the signal.
    exit 1
  fi
  echo "[audit] retry $attempt/$RETRIES — sleeping ${INTERVAL}s (waiting for commit lag)" >&2
  sleep "$INTERVAL"
done
