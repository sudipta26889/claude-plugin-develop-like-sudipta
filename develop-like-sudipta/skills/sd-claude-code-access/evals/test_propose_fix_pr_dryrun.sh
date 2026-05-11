#!/usr/bin/env bash
# test_propose_fix_pr_dryrun.sh — DRY_RUN=1 must produce no side effects.
#
# Stubs a priors file with 2 cross-project signatures, runs
# scripts/propose_fix_pr.sh with DRY_RUN=1, then asserts:
#   - no `claude` child spawned (we test indirectly: PR log not written,
#     gh-mock not invoked, and the script only narrates)
#   - no entries appended to the (isolated) .pr_log.jsonl
#   - stdout names BOTH signatures + their dispatch targets + "WOULD spawn"
#
# Side-effect isolation: PR_LOG_FILE and PRIORS_FILE both point inside a
# mktemp dir so the real ~/.cache/ccbridge/ is never touched.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PROPOSE="$SKILL_DIR/scripts/propose_fix_pr.sh"
DISPATCH="$SKILL_DIR/scripts/dispatch_signature.sh"

if [ ! -f "$PROPOSE" ]; then
  echo "FAIL: propose_fix_pr.sh missing at $PROPOSE"
  exit 2
fi
if [ ! -f "$DISPATCH" ]; then
  echo "FAIL: dispatch_signature.sh missing at $DISPATCH"
  exit 2
fi

TMP="$(mktemp -d -t propose_fix_pr_dryrun.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

PRIORS="$TMP/priors.md"
PR_LOG="$TMP/.pr_log.jsonl"

cat > "$PRIORS" <<'EOF'
# Cross-project priors (test fixture)
- watchdog_recovery: watchdog_started_pid (CROSS_N=3)
- diagnose_timeout: diagnose_inner_osascript_died (CROSS_N=2)
EOF

# Run with DRY_RUN=1 and GH_OVERRIDE=mock (belt-and-braces).
out="$(
  PRIORS_FILE="$PRIORS" \
  PR_LOG_FILE="$PR_LOG" \
  DRY_RUN=1 \
  GH_OVERRIDE=mock \
  DISPATCH_SCRIPT="$DISPATCH" \
  bash "$PROPOSE" 2>&1
)"
rc=$?

failures=0

if [ "$rc" -ne 0 ]; then
  echo "FAIL: propose_fix_pr.sh exited rc=$rc under DRY_RUN=1"
  echo "----- stdout/stderr -----"
  echo "$out"
  echo "-------------------------"
  failures=$((failures + 1))
fi

# --- side effects: PR log MUST NOT exist (no appends under DRY_RUN) ---
if [ -e "$PR_LOG" ]; then
  echo "FAIL: PR log was written under DRY_RUN=1: $PR_LOG"
  echo "  contents:"
  cat "$PR_LOG"
  failures=$((failures + 1))
fi

# --- stdout assertions ---
expect_substrings=(
  "watchdog_recovery"
  "diagnose_timeout"
  "watchdog.sh"
  "diagnose.sh"
  "WOULD spawn"
)
for needle in "${expect_substrings[@]}"; do
  case "$out" in
    *"$needle"*) : ;;
    *)
      echo "FAIL: stdout missing substring: '$needle'"
      failures=$((failures + 1))
      ;;
  esac
done

# WOULD spawn should appear at least twice (one per signature)
woulds="$(printf '%s' "$out" | grep -c 'WOULD spawn' || true)"
if [ "$woulds" -lt 2 ]; then
  echo "FAIL: 'WOULD spawn' appeared $woulds times, expected >=2"
  failures=$((failures + 1))
fi

echo
if [ "$failures" -eq 0 ]; then
  echo "PASS — DRY_RUN narrates both signatures with no side effects."
  exit 0
else
  echo "FAIL — $failures assertion(s) failed."
  echo "----- run output -----"
  echo "$out"
  echo "----------------------"
  exit 1
fi
