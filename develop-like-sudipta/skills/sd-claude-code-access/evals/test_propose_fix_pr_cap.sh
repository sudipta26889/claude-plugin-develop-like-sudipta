#!/usr/bin/env bash
# test_propose_fix_pr_cap.sh — 3-PR cap enforcement.
#
# Stubs 5 cross-project signatures; runs DRY_RUN=1; asserts first 3
# emit "WOULD spawn", remaining 2 emit "batched_to_issue", and the
# summary reports the cap explicitly.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PROPOSE="$SKILL_DIR/scripts/propose_fix_pr.sh"
DISPATCH="$SKILL_DIR/scripts/dispatch_signature.sh"

if [ ! -f "$PROPOSE" ]; then
  echo "FAIL: propose_fix_pr.sh missing at $PROPOSE"
  exit 2
fi

TMP="$(mktemp -d -t propose_fix_pr_cap.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

PRIORS="$TMP/priors.md"
PR_LOG="$TMP/.pr_log.jsonl"

cat > "$PRIORS" <<'EOF'
- watchdog_recovery: watchdog_started (CROSS_N=2)
- diagnose_timeout: diagnose_inner_died (CROSS_N=2)
- send_paste_drift: send_pbcopy_unicode (CROSS_N=3)
- launch_cc_detect_only: launch_cc_skipped (CROSS_N=2)
- learning_emit_failed: learning_no_workspace (CROSS_N=2)
EOF

out="$(
  PRIORS_FILE="$PRIORS" \
  PR_LOG_FILE="$PR_LOG" \
  DRY_RUN=1 \
  PR_CAP=3 \
  GH_OVERRIDE=mock \
  DISPATCH_SCRIPT="$DISPATCH" \
  bash "$PROPOSE" 2>&1
)"
rc=$?

failures=0

if [ "$rc" -ne 0 ]; then
  echo "FAIL: propose_fix_pr.sh exited rc=$rc"
  echo "----- output -----"
  echo "$out"
  echo "------------------"
  failures=$((failures + 1))
fi

would_count="$(printf '%s\n' "$out" | grep -c 'WOULD spawn' || true)"
batched_count="$(printf '%s\n' "$out" | grep -c 'batched_to_issue' || true)"

if [ "$would_count" -ne 3 ]; then
  echo "FAIL: WOULD spawn count = $would_count (expected 3)"
  failures=$((failures + 1))
fi
if [ "$batched_count" -ne 2 ]; then
  echo "FAIL: batched_to_issue count = $batched_count (expected 2)"
  failures=$((failures + 1))
fi

# Cap must be reported explicitly somewhere in stdout.
case "$out" in
  *"PR_CAP=3"*|*"cap=3"*|*"3-PR cap"*|*"cap is 3"*) : ;;
  *)
    echo "FAIL: cap not reported explicitly in stdout (looked for PR_CAP=3 / cap=3 / 3-PR cap)"
    failures=$((failures + 1))
    ;;
esac

# The first three signatures (in file order) should be the spawned ones.
first_three=(watchdog_recovery diagnose_timeout send_paste_drift)
last_two=(launch_cc_detect_only learning_emit_failed)

for sig in "${first_three[@]}"; do
  if ! printf '%s\n' "$out" | grep -E "WOULD spawn.*$sig" >/dev/null ; then
    echo "FAIL: expected signature '$sig' in a WOULD spawn line"
    failures=$((failures + 1))
  fi
done

for sig in "${last_two[@]}"; do
  if ! printf '%s\n' "$out" | grep -E "batched_to_issue.*$sig" >/dev/null ; then
    echo "FAIL: expected signature '$sig' in a batched_to_issue line"
    failures=$((failures + 1))
  fi
done

# Under DRY_RUN=1 the PR log must still NOT exist.
if [ -e "$PR_LOG" ]; then
  echo "FAIL: PR log was written under DRY_RUN=1: $PR_LOG"
  failures=$((failures + 1))
fi

echo
if [ "$failures" -eq 0 ]; then
  echo "PASS — 3 spawned, 2 batched, cap reported, no side effects."
  exit 0
else
  echo "FAIL — $failures assertion(s) failed."
  echo "----- output -----"
  echo "$out"
  echo "------------------"
  exit 1
fi
