#!/usr/bin/env bash
# cleanup_test_artifacts.sh — archive old browser-test screenshots, quarantine
# orphan specs and orphan screenshot dirs.
#
# Problem: per-phase browser-test artifacts accumulate under
#   <workspace>/docs/e2e-testing/screenshots/phase-N/*.png
#   <workspace>/docs/e2e-testing/specs/phase-N.spec.ts
# Across many phases and refactors this directory grows forever. Specs for
# phases that have been renumbered or removed stick around, and screenshot
# dirs for phases that no longer exist orbit forever with no policy.
#
# Behaviour:
#   1. Resolve test root: env BROWSER_TEST_ROOT > .cc/config.json
#      browser_test_root > default <workspace>/docs/e2e-testing.
#   2. Retention: --retention-days N > .cc/config.json artifact_retention_days
#      > default 30.
#   3. Archive: screenshots older than retention are tar+gzipped into
#      <test-root>/screenshots-archive/<YYYY-MM>.tar.gz (grouped by mtime
#      month, appended to if the archive already exists), then deleted.
#   4. Orphan specs: a spec is orphan if no matching phase-N-*.md exists
#      in the test root. Moved to <test-root>/specs/archive/<YYYY-MM>/.
#   5. Orphan screenshot dirs: <test-root>/screenshots/phase-N/ with no
#      matching phase-N-*.md → moved to
#      <test-root>/screenshots-archive/orphaned/phase-N/.
#   6. --dry-run: print what would happen, change nothing.
#
# Safety: never deletes anything except originals already captured in the
# archive; the archives themselves are kept forever (human can curate
# manually).
#
# Usage:
#   cleanup_test_artifacts.sh <workspace> [--retention-days N] [--dry-run]
#
# Exit codes:
#   0 — finished (any work, including zero)
#   1 — test root does not exist
#   2 — bad arguments / refused to run
#
# Bash 3.2 compatible (macOS /bin/bash).
set -euo pipefail

# --------------------------------------------------------------------------
# Argument parsing.
# --------------------------------------------------------------------------
WS=""
RETENTION_CLI=""
DRY_RUN=0

while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help)
      sed -n '2,40p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    --retention-days)
      RETENTION_CLI="${2:-}"
      shift 2
      ;;
    --retention-days=*)
      RETENTION_CLI="${1#--retention-days=}"
      shift
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    --)
      shift
      break
      ;;
    -*)
      echo "cleanup_test_artifacts: unknown argument '$1'" >&2
      exit 2
      ;;
    *)
      if [ -z "$WS" ]; then
        WS="$1"
        shift
      else
        echo "cleanup_test_artifacts: unexpected extra argument '$1'" >&2
        exit 2
      fi
      ;;
  esac
done

if [ -z "$WS" ]; then
  echo "usage: cleanup_test_artifacts.sh <workspace> [--retention-days N] [--dry-run]" >&2
  exit 2
fi

# --------------------------------------------------------------------------
# Hard dependency: python3 (config + mtime + month bucketing). Failing
# loud here is better than misclassifying every file.
# --------------------------------------------------------------------------
command -v python3 >/dev/null 2>&1 || {
  echo "cleanup_test_artifacts: python3 required but not found on PATH" >&2
  exit 2
}

CONFIG="$WS/.cc/config.json"

# --------------------------------------------------------------------------
# Resolve test root: env > config > default.
# --------------------------------------------------------------------------
CONFIG_TEST_ROOT=""
CONFIG_RETENTION=""
if [ -f "$CONFIG" ]; then
  # Print "root|retention" so we shell-parse without jq.
  CFG_OUT="$(python3 - "$CONFIG" <<'PY' 2>/dev/null || true
import json, sys
try:
    with open(sys.argv[1]) as f:
        c = json.load(f)
except Exception:
    c = {}
root = c.get("browser_test_root", "") or ""
ret = c.get("artifact_retention_days", "")
try:
    ret = int(ret)
except Exception:
    ret = ""
print("%s|%s" % (root, ret))
PY
)"
  if [ -n "$CFG_OUT" ]; then
    CONFIG_TEST_ROOT="${CFG_OUT%%|*}"
    CONFIG_RETENTION="${CFG_OUT#*|}"
  fi
fi

if [ -n "${BROWSER_TEST_ROOT:-}" ]; then
  RAW_ROOT="$BROWSER_TEST_ROOT"
elif [ -n "$CONFIG_TEST_ROOT" ]; then
  RAW_ROOT="$CONFIG_TEST_ROOT"
else
  RAW_ROOT="docs/e2e-testing"
fi

case "$RAW_ROOT" in
  /*) TEST_ROOT="$RAW_ROOT" ;;
   *) TEST_ROOT="$WS/$RAW_ROOT" ;;
esac

if [ ! -d "$TEST_ROOT" ]; then
  echo "cleanup_test_artifacts: no test root found at $TEST_ROOT" >&2
  exit 1
fi

# --------------------------------------------------------------------------
# Resolve retention days: CLI > config > 30.
# --------------------------------------------------------------------------
RETENTION_DAYS=30
if [ -n "$RETENTION_CLI" ]; then
  case "$RETENTION_CLI" in
    ''|*[!0-9]*)
      echo "cleanup_test_artifacts: --retention-days must be a non-negative integer (got '$RETENTION_CLI')" >&2
      exit 2
      ;;
    *) RETENTION_DAYS="$RETENTION_CLI" ;;
  esac
elif [ -n "$CONFIG_RETENTION" ]; then
  RETENTION_DAYS="$CONFIG_RETENTION"
fi

# --------------------------------------------------------------------------
# Helpers.
# --------------------------------------------------------------------------

# Print file mtime as epoch seconds and YYYY-MM (single line, space-sep).
mtime_info() {
  python3 - "$1" <<'PY'
import os, sys, time
try:
    m = os.path.getmtime(sys.argv[1])
except Exception:
    m = 0
ts = int(m)
ym = time.strftime("%Y-%m", time.localtime(ts)) if ts > 0 else "1970-01"
print("%d %s" % (ts, ym))
PY
}

# Bytes -> human MB (one decimal).
human_mb() {
  python3 - "$1" <<'PY'
import sys
try:
    n = int(sys.argv[1])
except Exception:
    n = 0
print("%.1f" % (n / (1024.0 * 1024.0)))
PY
}

# True if a phase-N-*.md exists in $TEST_ROOT for the given N.
# NOTE: uses local-ish var names (_hpm_*) to avoid clobbering outer loop
# variables — bash 3.2 functions don't auto-localize, and `local` is
# unavailable in strict POSIX.
has_phase_md() {
  _hpm_n="$1"
  # `compgen -G` isn't in bash 3.2's POSIX subset; use plain glob.
  for _hpm_f in "$TEST_ROOT"/phase-"$_hpm_n"-*.md; do
    if [ -e "$_hpm_f" ]; then
      return 0
    fi
  done
  return 1
}

# Extract the phase number from a path like '.../phase-12-foo.md' or
# '.../phase-3.spec.ts' or '.../phase-7'. Prints the digits or empty.
phase_num_from() {
  _pnf_base="$(basename "$1")"
  # Strip leading 'phase-' then take everything up to first non-digit.
  _pnf_rest="${_pnf_base#phase-}"
  _pnf_digits=""
  _pnf_i=0
  while [ "$_pnf_i" -lt ${#_pnf_rest} ]; do
    _pnf_ch="${_pnf_rest:$_pnf_i:1}"
    case "$_pnf_ch" in
      [0-9]) _pnf_digits="$_pnf_digits$_pnf_ch" ;;
      *) break ;;
    esac
    _pnf_i=$((_pnf_i + 1))
  done
  printf '%s' "$_pnf_digits"
}

# --------------------------------------------------------------------------
# Pass 1: orphan screenshot dirs. Done BEFORE archiving so the archive
# pass doesn't trip over moved directories.
# --------------------------------------------------------------------------
ORPHAN_DIRS=0
SCREEN_DIR="$TEST_ROOT/screenshots"
ORPHANED_DEST="$TEST_ROOT/screenshots-archive/orphaned"

if [ -d "$SCREEN_DIR" ]; then
  for d in "$SCREEN_DIR"/phase-*; do
    [ -d "$d" ] || continue
    pn="$(phase_num_from "$d")"
    [ -z "$pn" ] && continue
    if has_phase_md "$pn"; then
      continue
    fi
    ORPHAN_DIRS=$((ORPHAN_DIRS + 1))
    if [ "$DRY_RUN" -eq 1 ]; then
      continue
    fi
    mkdir -p "$ORPHANED_DEST"
    # If a same-named dir already exists in the orphaned bin (re-runs),
    # suffix with timestamp.
    target="$ORPHANED_DEST/$(basename "$d")"
    if [ -e "$target" ]; then
      target="${target}.$(date -u +%Y%m%dT%H%M%SZ).$$"
    fi
    mv "$d" "$target"
  done
fi

# --------------------------------------------------------------------------
# Pass 2: archive screenshots older than retention, grouped by month.
# --------------------------------------------------------------------------
ARCHIVED_COUNT=0
ARCHIVED_BYTES=0
WOULD_BYTES=0
ARCHIVE_DIR="$TEST_ROOT/screenshots-archive"

# Cutoff epoch.
CUTOFF="$(python3 - "$RETENTION_DAYS" <<'PY'
import sys, time
days = int(sys.argv[1])
print(int(time.time()) - days * 86400)
PY
)"

# Collect old screenshots into a temp file, one per line:
#   <YYYY-MM>\t<absolute path>
TMP_LIST="$(mktemp "${TMPDIR:-/tmp}/cleanup-old-XXXXXX")"
trap 'rm -f "$TMP_LIST"' EXIT INT TERM

if [ -d "$SCREEN_DIR" ]; then
  # Re-glob: phase-* dirs that still exist (after orphan move).
  for d in "$SCREEN_DIR"/phase-*; do
    [ -d "$d" ] || continue
    for f in "$d"/*.png; do
      [ -f "$f" ] || continue
      info="$(mtime_info "$f")"
      m_epoch="${info%% *}"
      ym="${info##* }"
      if [ "$m_epoch" -lt "$CUTOFF" ]; then
        printf '%s\t%s\n' "$ym" "$f" >> "$TMP_LIST"
      fi
    done
  done
fi

# Distinct months, in encountered order.
MONTHS="$(awk -F'\t' '!seen[$1]++ {print $1}' "$TMP_LIST")"

for ym in $MONTHS; do
  # Files for this month into a per-month list file.
  MONTH_LIST="$(mktemp "${TMPDIR:-/tmp}/cleanup-month-XXXXXX")"
  awk -F'\t' -v m="$ym" '$1==m {print $2}' "$TMP_LIST" > "$MONTH_LIST"
  # Count + sum size.
  while IFS= read -r f; do
    [ -f "$f" ] || continue
    ARCHIVED_COUNT=$((ARCHIVED_COUNT + 1))
    sz="$(wc -c < "$f" | tr -d ' ')"
    if [ "$DRY_RUN" -eq 1 ]; then
      WOULD_BYTES=$((WOULD_BYTES + sz))
    else
      ARCHIVED_BYTES=$((ARCHIVED_BYTES + sz))
    fi
  done < "$MONTH_LIST"

  if [ "$DRY_RUN" -eq 1 ]; then
    rm -f "$MONTH_LIST"
    continue
  fi

  mkdir -p "$ARCHIVE_DIR"
  TARBALL="$ARCHIVE_DIR/${ym}.tar.gz"
  # Paths in the tarball are relative to $TEST_ROOT for portability.
  # Convert absolute paths to relative.
  REL_LIST="$(mktemp "${TMPDIR:-/tmp}/cleanup-rel-XXXXXX")"
  while IFS= read -r f; do
    rel="${f#$TEST_ROOT/}"
    printf '%s\n' "$rel" >> "$REL_LIST"
  done < "$MONTH_LIST"

  if [ -f "$TARBALL" ]; then
    # Append: gunzip → append → gzip. Bash 3.2 / BSD tar safe.
    TMP_TAR="$(mktemp "${TMPDIR:-/tmp}/cleanup-tar-XXXXXX")"
    gunzip -c "$TARBALL" > "$TMP_TAR"
    ( cd "$TEST_ROOT" && tar -rf "$TMP_TAR" -T "$REL_LIST" )
    gzip -c "$TMP_TAR" > "$TARBALL"
    rm -f "$TMP_TAR"
  else
    ( cd "$TEST_ROOT" && tar -czf "$TARBALL" -T "$REL_LIST" )
  fi

  # Delete originals only after tarball write succeeds.
  while IFS= read -r f; do
    [ -f "$f" ] && rm -f "$f"
  done < "$MONTH_LIST"

  rm -f "$MONTH_LIST" "$REL_LIST"
done

rm -f "$TMP_LIST"
trap - EXIT INT TERM

# --------------------------------------------------------------------------
# Pass 3: orphan specs (no corresponding phase-N-*.md).
# --------------------------------------------------------------------------
QUARANTINED=0
SPECS_DIR="$TEST_ROOT/specs"
SPECS_ARCHIVE="$SPECS_DIR/archive"
THIS_MONTH="$(date +%Y-%m)"

if [ -d "$SPECS_DIR" ]; then
  for f in "$SPECS_DIR"/phase-*.spec.ts; do
    [ -f "$f" ] || continue
    pn="$(phase_num_from "$f")"
    [ -z "$pn" ] && continue
    if has_phase_md "$pn"; then
      continue
    fi
    QUARANTINED=$((QUARANTINED + 1))
    if [ "$DRY_RUN" -eq 1 ]; then
      continue
    fi
    DEST_DIR="$SPECS_ARCHIVE/$THIS_MONTH"
    mkdir -p "$DEST_DIR"
    DEST="$DEST_DIR/$(basename "$f")"
    if [ -e "$DEST" ]; then
      DEST="${DEST}.$(date -u +%Y%m%dT%H%M%SZ).$$"
    fi
    mv "$f" "$DEST"
  done
fi

# --------------------------------------------------------------------------
# Summary.
# --------------------------------------------------------------------------
if [ "$DRY_RUN" -eq 1 ]; then
  MB="$(human_mb "$WOULD_BYTES")"
  echo "DRY-RUN: would archive $ARCHIVED_COUNT screenshots (${MB} MB), would quarantine $QUARANTINED orphan specs, $ORPHAN_DIRS orphan screenshot dirs."
else
  MB="$(human_mb "$ARCHIVED_BYTES")"
  echo "Archived $ARCHIVED_COUNT screenshots (${MB} MB), quarantined $QUARANTINED orphan specs, $ORPHAN_DIRS orphan screenshot dirs."
fi

exit 0
