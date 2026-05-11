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
# Pre-flight: confirm git is on PATH and that $WS actually is a git
# workspace. Without this, the later `git log` calls were swallowing fatals
# via `2>/dev/null` and silently producing an empty audit. Exit 2 here so
# the caller can distinguish "no commits to look at" from "I have nothing to
# tell you".
# ---------------------------------------------------------------------------
if ! command -v git >/dev/null 2>&1; then
  echo "[audit] git not found on PATH — cannot run audit" >&2
  exit 2
fi
if ! (cd "$WS" && git rev-parse --is-inside-work-tree >/dev/null 2>&1); then
  echo "[audit] $WS is not a git repository" >&2
  exit 2
fi

# ---------------------------------------------------------------------------
# Shallow / fresh-repo guard. The default --since=HEAD~20 errors on repos
# with fewer than 20 commits ("fatal: ambiguous argument 'HEAD~20'…"). We
# used to silence that with `2>/dev/null` and produce a blank audit; now we
# detect the shallow case up front and fall back to --root so the first
# commit becomes the implicit floor. Only kicks in for the relative
# HEAD~N[..HEAD] form — explicit SHAs / refs / --root pass through.
# ---------------------------------------------------------------------------
since_depth=""
case "$SINCE" in
  HEAD~*..HEAD)
    since_depth="${SINCE#HEAD~}"
    since_depth="${since_depth%..HEAD}"
    ;;
  HEAD~*)
    since_depth="${SINCE#HEAD~}"
    ;;
esac
case "$since_depth" in
  ''|*[!0-9]*) since_depth="" ;;
esac
if [ -n "$since_depth" ]; then
  commit_count=$(cd "$WS" && git rev-list --count HEAD 2>/dev/null || echo 0)
  case "$commit_count" in
    ''|*[!0-9]*) commit_count=0 ;;
  esac
  if [ "$commit_count" -le "$since_depth" ]; then
    echo "[audit] only $commit_count commit(s) in $WS — falling back to --root (requested depth: $since_depth)" >&2
    SINCE="--root"
  fi
fi

# ---------------------------------------------------------------------------
# do_audit — single pass. Echoes the human-readable report to stdout. Returns
# 0 if the audit is clean, 2 if any expected commit or directive-mentioned
# file is missing from the range (the retryable laggy-drift signal).
# ---------------------------------------------------------------------------
do_audit() {
  cd "$WS"

  # Translate $SINCE into a git-log range. `--root` means "from the very
  # first commit"; everything else is `<since>..HEAD`. Without this split,
  # passing `--root..HEAD` would mean something different (and wrong).
  if [ "$SINCE" = "--root" ]; then
    RANGE_LABEL="--root..HEAD"
    set -- --root HEAD
  else
    RANGE_LABEL="$SINCE..HEAD"
    set -- "$SINCE..HEAD"
  fi

  echo "============================================================"
  echo "  AUDIT: Phase $PHASE"
  echo "  Directive: $DIR_FILE"
  echo "  Range:     $RANGE_LABEL"
  echo "============================================================"
  echo

  # 1. Commits in range
  # Capture stderr so a genuine git error (bad ref, corrupted repo) surfaces
  # to the user instead of being silently swallowed by `2>/dev/null`.
  echo "── Commits in range ──"
  git_err=$(mktemp 2>/dev/null || echo "/tmp/audit_git_err.$$")
  if ! git log --oneline "$@" 2>"$git_err" | sed 's/^/  /'; then
    cat "$git_err" >&2
    rm -f "$git_err"
    echo "[audit] git log failed for range $RANGE_LABEL" >&2
    return 1
  fi
  if [ -s "$git_err" ]; then
    cat "$git_err" >&2
    rm -f "$git_err"
    echo "[audit] git emitted errors for range $RANGE_LABEL — refusing to report empty audit" >&2
    return 1
  fi
  rm -f "$git_err"
  N_COMMITS=$(git log --oneline "$@" 2>/dev/null | wc -l | tr -d ' ')
  echo
  echo "  Total: $N_COMMITS commits"
  echo

  # 2. Expected commit messages from directive
  echo "── Expected commit messages (from directive § Commit pattern) ──"
  # NOTE: The old form `awk '/^## *Commit pattern/,/^## /'` collapses to a
  # single line — the END pattern matches the START heading and the range
  # closes immediately. Use explicit state so we skip the start heading and
  # exit on the NEXT `## ` heading.
  EXPECTED=$(awk '
    /^## *Commit pattern/ { in_section = 1; next }
    /^## / && in_section { exit }
    in_section { print }
  ' "$DIR_FILE" | grep -oE '`[a-zA-Z][a-zA-Z0-9_./()+-]*: [^`]+`' | tr -d '`' | sed 's/^/  - /' || true)
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
      # Strip the "  - " bullet. Use --fixed-strings so parens, slashes and
      # other regex meta in commit-message prefixes (`feat(core)`, `fix/api`)
      # match literally — the previous `sed 's/(/\\(/g; s/)/\\)/g'` produced
      # a BRE group expression that never matched the literal text.
      PATTERN=$(echo "$line" | sed 's/^  - //')
      HIT=$(git log --oneline "$@" --fixed-strings --grep="$PATTERN" 2>/dev/null | head -1)
      if [ -n "$HIT" ]; then
        echo "  ✓ $line"
        echo "      → $HIT"
      else
        echo "  ✗ $line  (NOT FOUND in $RANGE_LABEL)"
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
  # Same stderr discipline as the first git log: surface real errors,
  # don't silently produce an empty list.
  git_err=$(mktemp 2>/dev/null || echo "/tmp/audit_git_err.$$")
  CHANGED=$(git log --name-only --pretty=format: "$@" 2>"$git_err" | sort -u | grep -v '^$' | sed 's/^/  /')
  if [ -s "$git_err" ]; then
    cat "$git_err" >&2
    rm -f "$git_err"
    echo "[audit] git log --name-only failed for range $RANGE_LABEL" >&2
    return 1
  fi
  rm -f "$git_err"
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
    # v4.3: capture clean-audit signal so autoresearch can compare frequency
    # of clean vs drift outcomes across projects.
    DEST="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    if [ -n "${WORKSPACE:-}" ] && [ -x "$DEST/learning.sh" ]; then
      "$DEST/learning.sh" "$WORKSPACE" audit_finding \
        "outcome=clean" "attempts=$attempt" >/dev/null 2>&1 || true
    fi
    exit 0
  fi
  if [ "$rc" -ne 2 ]; then
    # Hard error from do_audit — pass it through unchanged.
    DEST="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    if [ -n "${WORKSPACE:-}" ] && [ -x "$DEST/learning.sh" ]; then
      "$DEST/learning.sh" "$WORKSPACE" audit_finding \
        "outcome=hard_error" "rc=$rc" "attempts=$attempt" >/dev/null 2>&1 || true
    fi
    exit "$rc"
  fi
  # rc == 2: laggy drift. Retry if budget allows.
  remaining=$((max_attempts - attempt))
  if [ "$remaining" -le 0 ]; then
    DEST="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    if [ -n "${WORKSPACE:-}" ] && [ -x "$DEST/learning.sh" ]; then
      "$DEST/learning.sh" "$WORKSPACE" audit_finding \
        "outcome=drift" "attempts=$attempt" "retries=$RETRIES" >/dev/null 2>&1 || true
    fi
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
