#!/usr/bin/env bash
# test_cleanup_test_artifacts.sh — smoke test for cleanup_test_artifacts.sh.
#
# Background: per-phase browser-test artifacts accumulate forever:
#   <test-root>/screenshots/phase-N/*.png
#   <test-root>/specs/phase-N.spec.ts
# When phases are renumbered or refactored away, the on-disk artifacts
# orbit forever with no retention or archival policy. cleanup_test_artifacts.sh
# archives old screenshots to monthly tarballs, quarantines orphan specs,
# and moves orphan screenshot dirs to a separate bin — never deletes them.
#
# Cases:
#   1. Missing test root           -> exit 1 with "no test root found"
#   2. Empty test root             -> exit 0, "Archived 0 screenshots"
#   3. Fresh screenshots only      -> nothing archived, originals remain
#   4. Mixed fresh + old           -> old screenshots tarred, originals
#                                     deleted, fresh ones remain
#   5. Orphan spec (no md)         -> moved to specs/archive/YYYY-MM/
#   6. Orphan screenshot dir       -> moved to screenshots-archive/orphaned/
#   7. --dry-run                   -> nothing changes; summary still prints
#                                     "would archive"
#
# Bash 3.2 compatible. macOS-friendly `touch -t` for deterministic mtimes.
#
# Usage: ./test_cleanup_test_artifacts.sh
# Exit 0 on PASS, non-zero on any failed assertion.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CLEANUP="$SCRIPT_DIR/../scripts/cleanup_test_artifacts.sh"

if [ ! -f "$CLEANUP" ]; then
  echo "FAIL: cleanup_test_artifacts.sh not found at $CLEANUP"
  exit 2
fi

TMP_ROOT="${TMPDIR:-/tmp}"
fails=0
cleanup_dirs=""

fail() { fails=$((fails + 1)); echo "  FAIL: $*"; }
pass() { echo "  PASS: $*"; }

cleanup() {
  for d in $cleanup_dirs; do
    [ -n "$d" ] && [ -d "$d" ] && rm -rf "$d"
  done
}
trap cleanup EXIT INT TERM

mkws() {
  ws="$(mktemp -d "$TMP_ROOT/cleanup-artifacts-XXXXXX")"
  cleanup_dirs="$cleanup_dirs $ws"
  printf '%s\n' "$ws"
}

# Build a test root with the standard browser-testing layout.
mktestroot() {
  ws="$1"
  root="$ws/docs/e2e-testing"
  mkdir -p "$root/screenshots" "$root/specs"
  printf '%s\n' "$root"
}

# Generate a YYYYMMDDHHMM stamp for `touch -t` that is N days in the past.
# Bash 3.2 + macOS `date` only (no GNU date -d).
ts_days_ago() {
  n="$1"
  # `date -v-${n}d` is BSD/macOS syntax. Linux fallback uses -d.
  if date -v-1d +%Y >/dev/null 2>&1; then
    date -v-${n}d +%Y%m%d%H%M
  else
    date -d "$n days ago" +%Y%m%d%H%M
  fi
}

# ---------------------------------------------------------------------------
# Case 1 — missing test root
# ---------------------------------------------------------------------------
echo "-- Case 1: missing test root --"
WS1="$(mkws)"
# No docs/e2e-testing created.
OUT1="$(bash "$CLEANUP" "$WS1" 2>&1)"
RC1=$?
if [ "$RC1" -eq 1 ]; then
  pass "exit code 1 when no test root (got $RC1)"
else
  fail "expected exit 1, got $RC1"
fi
if printf '%s' "$OUT1" | grep -qi "no test root found"; then
  pass "stderr mentions 'no test root found'"
else
  fail "expected 'no test root found' in output: $OUT1"
fi

# ---------------------------------------------------------------------------
# Case 2 — empty test root
# ---------------------------------------------------------------------------
echo "-- Case 2: empty test root --"
WS2="$(mkws)"
ROOT2="$(mktestroot "$WS2")"
OUT2="$(bash "$CLEANUP" "$WS2" 2>&1)"
RC2=$?
if [ "$RC2" -eq 0 ]; then
  pass "exit 0 on empty test root"
else
  fail "expected exit 0, got $RC2 (output: $OUT2)"
fi
if printf '%s' "$OUT2" | grep -qE "Archived 0 screenshots"; then
  pass "output reports 0 screenshots archived"
else
  fail "expected 'Archived 0 screenshots': $OUT2"
fi

# ---------------------------------------------------------------------------
# Case 3 — fresh screenshots only (<retention days)
# ---------------------------------------------------------------------------
echo "-- Case 3: fresh screenshots only (none archived) --"
WS3="$(mkws)"
ROOT3="$(mktestroot "$WS3")"
# A real phase-1 spec markdown so the screenshot dir is NOT orphan.
touch "$ROOT3/phase-1-login.md"
mkdir -p "$ROOT3/screenshots/phase-1"
echo "fakepng" > "$ROOT3/screenshots/phase-1/01-home.png"
# Touch to 5 days ago (well within default 30).
FRESH_TS="$(ts_days_ago 5)"
touch -t "$FRESH_TS" "$ROOT3/screenshots/phase-1/01-home.png"
OUT3="$(bash "$CLEANUP" "$WS3" 2>&1)"
RC3=$?
if [ "$RC3" -eq 0 ]; then
  pass "exit 0 with fresh-only screenshots"
else
  fail "expected exit 0, got $RC3 (output: $OUT3)"
fi
if printf '%s' "$OUT3" | grep -qE "Archived 0 screenshots"; then
  pass "0 archived"
else
  fail "expected 'Archived 0 screenshots': $OUT3"
fi
if [ -f "$ROOT3/screenshots/phase-1/01-home.png" ]; then
  pass "fresh screenshot still exists"
else
  fail "fresh screenshot was wrongly removed"
fi

# ---------------------------------------------------------------------------
# Case 4 — mixed fresh + old: old archived, fresh kept
# ---------------------------------------------------------------------------
echo "-- Case 4: mixed fresh + old screenshots --"
WS4="$(mkws)"
ROOT4="$(mktestroot "$WS4")"
touch "$ROOT4/phase-2-checkout.md"
mkdir -p "$ROOT4/screenshots/phase-2"
echo "old1" > "$ROOT4/screenshots/phase-2/01-cart.png"
echo "old2" > "$ROOT4/screenshots/phase-2/02-pay.png"
echo "fresh" > "$ROOT4/screenshots/phase-2/03-success.png"
OLD_TS="$(ts_days_ago 60)"
FRESH_TS4="$(ts_days_ago 3)"
touch -t "$OLD_TS" "$ROOT4/screenshots/phase-2/01-cart.png"
touch -t "$OLD_TS" "$ROOT4/screenshots/phase-2/02-pay.png"
touch -t "$FRESH_TS4" "$ROOT4/screenshots/phase-2/03-success.png"
OUT4="$(bash "$CLEANUP" "$WS4" 2>&1)"
RC4=$?
if [ "$RC4" -eq 0 ]; then
  pass "exit 0 on mixed"
else
  fail "expected exit 0, got $RC4 (output: $OUT4)"
fi
if printf '%s' "$OUT4" | grep -qE "Archived 2 screenshots"; then
  pass "2 archived"
else
  fail "expected 'Archived 2 screenshots': $OUT4"
fi
# Archive tar.gz exists (don't care exactly which month, just that one exists).
ARCH4="$(ls "$ROOT4/screenshots-archive/"*.tar.gz 2>/dev/null | head -1)"
if [ -n "$ARCH4" ] && [ -f "$ARCH4" ]; then
  pass "tar.gz archive created at $ARCH4"
else
  fail "no tar.gz archive in screenshots-archive/"
fi
if [ -f "$ROOT4/screenshots/phase-2/01-cart.png" ] || \
   [ -f "$ROOT4/screenshots/phase-2/02-pay.png" ]; then
  fail "old screenshot original was not deleted"
else
  pass "old originals deleted"
fi
if [ -f "$ROOT4/screenshots/phase-2/03-success.png" ]; then
  pass "fresh screenshot kept"
else
  fail "fresh screenshot was wrongly removed"
fi

# ---------------------------------------------------------------------------
# Case 5 — orphan spec (no matching phase-N-*.md)
# ---------------------------------------------------------------------------
echo "-- Case 5: orphan spec quarantined --"
WS5="$(mkws)"
ROOT5="$(mktestroot "$WS5")"
# phase-3 has no .md — orphan.
echo "// stale spec" > "$ROOT5/specs/phase-3.spec.ts"
# phase-4 has a matching md — should NOT be quarantined.
touch "$ROOT5/phase-4-payments.md"
echo "// live spec" > "$ROOT5/specs/phase-4.spec.ts"
OUT5="$(bash "$CLEANUP" "$WS5" 2>&1)"
RC5=$?
if [ "$RC5" -eq 0 ]; then
  pass "exit 0 on orphan-spec scenario"
else
  fail "expected exit 0, got $RC5 (output: $OUT5)"
fi
if printf '%s' "$OUT5" | grep -qE "quarantined 1 orphan spec"; then
  pass "output reports 1 quarantined orphan spec"
else
  fail "expected 'quarantined 1 orphan spec' in output: $OUT5"
fi
# phase-3 should be under specs/archive/YYYY-MM/
MOVED5="$(find "$ROOT5/specs/archive" -name "phase-3.spec.ts" 2>/dev/null | head -1)"
if [ -n "$MOVED5" ] && [ -f "$MOVED5" ]; then
  pass "orphan phase-3.spec.ts moved to $MOVED5"
else
  fail "orphan spec not moved into specs/archive/"
fi
# phase-4 should still be in place.
if [ -f "$ROOT5/specs/phase-4.spec.ts" ]; then
  pass "live phase-4 spec kept"
else
  fail "live phase-4 spec was wrongly moved"
fi

# ---------------------------------------------------------------------------
# Case 6 — orphan screenshot dir (no matching phase-N-*.md)
# ---------------------------------------------------------------------------
echo "-- Case 6: orphan screenshot dir moved to screenshots-archive/orphaned/ --"
WS6="$(mkws)"
ROOT6="$(mktestroot "$WS6")"
mkdir -p "$ROOT6/screenshots/phase-99"
# A fresh screenshot — orphan check is based on dir, not mtime.
echo "data" > "$ROOT6/screenshots/phase-99/01.png"
FRESH_TS6="$(ts_days_ago 1)"
touch -t "$FRESH_TS6" "$ROOT6/screenshots/phase-99/01.png"
OUT6="$(bash "$CLEANUP" "$WS6" 2>&1)"
RC6=$?
if [ "$RC6" -eq 0 ]; then
  pass "exit 0 on orphan-dir scenario"
else
  fail "expected exit 0, got $RC6 (output: $OUT6)"
fi
if printf '%s' "$OUT6" | grep -qE "1 orphan screenshot dir"; then
  pass "output reports 1 orphan screenshot dir"
else
  fail "expected '1 orphan screenshot dir' in output: $OUT6"
fi
if [ -d "$ROOT6/screenshots-archive/orphaned/phase-99" ]; then
  pass "phase-99 moved under screenshots-archive/orphaned/"
else
  fail "orphan dir not moved to orphaned/"
fi
if [ -d "$ROOT6/screenshots/phase-99" ]; then
  fail "original phase-99 dir still in place"
else
  pass "original phase-99 dir removed from screenshots/"
fi

# ---------------------------------------------------------------------------
# Case 7 — --dry-run: nothing changes; summary still reports work
# ---------------------------------------------------------------------------
echo "-- Case 7: --dry-run leaves files untouched --"
WS7="$(mkws)"
ROOT7="$(mktestroot "$WS7")"
touch "$ROOT7/phase-5-search.md"
mkdir -p "$ROOT7/screenshots/phase-5"
echo "old" > "$ROOT7/screenshots/phase-5/01.png"
OLD_TS7="$(ts_days_ago 90)"
touch -t "$OLD_TS7" "$ROOT7/screenshots/phase-5/01.png"
EXPECTED_SHA7="$(shasum "$ROOT7/screenshots/phase-5/01.png" 2>/dev/null | awk '{print $1}')"
OUT7="$(bash "$CLEANUP" "$WS7" --dry-run 2>&1)"
RC7=$?
if [ "$RC7" -eq 0 ]; then
  pass "exit 0 on --dry-run"
else
  fail "expected exit 0, got $RC7 (output: $OUT7)"
fi
if printf '%s' "$OUT7" | grep -qiE "would archive 1 screenshot"; then
  pass "output reports 'would archive 1 screenshot'"
else
  fail "expected 'would archive 1 screenshot' in output: $OUT7"
fi
# File must still exist + be unchanged.
if [ -f "$ROOT7/screenshots/phase-5/01.png" ]; then
  pass "original still present after --dry-run"
else
  fail "original missing after --dry-run"
fi
ACTUAL_SHA7="$(shasum "$ROOT7/screenshots/phase-5/01.png" 2>/dev/null | awk '{print $1}')"
if [ "$EXPECTED_SHA7" = "$ACTUAL_SHA7" ]; then
  pass "screenshot bytes unchanged"
else
  fail "screenshot bytes changed during --dry-run"
fi
if [ -d "$ROOT7/screenshots-archive" ]; then
  fail "screenshots-archive created during --dry-run"
else
  pass "no screenshots-archive dir during --dry-run"
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo
if [ "$fails" -eq 0 ]; then
  echo "ALL PASS"
  exit 0
else
  echo "$fails assertion(s) FAILED"
  exit 1
fi
