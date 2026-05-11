#!/usr/bin/env bash
# test_propose_fix_pr_dispatch.sh — smoke test for dispatch_signature.sh.
#
# Asserts: each known signature prefix routes to the expected plugin file,
# unknown signatures return non-zero, and empty input is rejected.
#
# Exit 0 on PASS, non-zero on any miss.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DISPATCH="$SCRIPT_DIR/../scripts/dispatch_signature.sh"

if [ ! -f "$DISPATCH" ]; then
  echo "FAIL: dispatch script missing at $DISPATCH"
  exit 2
fi

# "signature|expected substring of returned path"
CASES=(
  "watchdog_recovery_started|skills/sd-claude-code-access/scripts/watchdog.sh"
  "diagnose_timeout|skills/sd-claude-code-access/scripts/diagnose.sh"
  "send_paste_drift|skills/sd-claude-code-access/scripts/send.sh"
  "launch_cc_detect_only|skills/sd-claude-code-access/scripts/launch_cc.sh"
  "learning_emit_failed|skills/sd-claude-code-access/scripts/learning.sh"
  "state_salvage_required|skills/sd-claude-code-access/scripts/state.sh"
  "audit_clean|skills/sd-claude-code-access/scripts/audit.sh"
  "scheduled_skill_missing|assets/scheduled-tasks"
  "cc_drive_substrate|commands/cc-drive.md"
  "directive_template_drift|assets/directive_template.md"
  "verify_gate_red|references/verify_gate.md"
  "bug_driven_tdd_skipped|references/bug_driven_tdd.md"
  "substrate_path_b|references/substrate_and_access.md"
)

UNKNOWN=(
  "totally_unknown_prefix"
  "deploy_failed"
  "browser_test_timeout"
)

failures=0

# --- positive cases ---
for case in "${CASES[@]}"; do
  sig="${case%%|*}"
  expect="${case#*|}"
  out="$(bash "$DISPATCH" "$sig" 2>/dev/null)"
  rc=$?
  if [ "$rc" -ne 0 ]; then
    echo "FAIL: signature='$sig' exited rc=$rc (expected 0)"
    failures=$((failures + 1))
    continue
  fi
  case "$out" in
    *"$expect"*) : ;;
    *)
      echo "FAIL: signature='$sig' got='$out' expected substring='$expect'"
      failures=$((failures + 1))
      ;;
  esac
done

# --- unknown cases ---
for sig in "${UNKNOWN[@]}"; do
  out="$(bash "$DISPATCH" "$sig" 2>/dev/null)"
  rc=$?
  if [ "$rc" -eq 0 ] && [ -n "$out" ]; then
    echo "FAIL: unknown signature='$sig' matched something: '$out'"
    failures=$((failures + 1))
  fi
done

# --- empty input must NOT return rc=0 with a non-empty target ---
out="$(bash "$DISPATCH" "" 2>/dev/null)"
rc=$?
if [ "$rc" -eq 0 ] && [ -n "$out" ]; then
  echo "FAIL: empty input produced a target: '$out'"
  failures=$((failures + 1))
fi

# --- zero args must not crash ungracefully ---
bash "$DISPATCH" >/dev/null 2>&1
rc=$?
if [ "$rc" -eq 0 ]; then
  echo "FAIL: dispatch_signature.sh with no args returned rc=0 (expected non-zero)"
  failures=$((failures + 1))
fi

echo
if [ "$failures" -eq 0 ]; then
  echo "PASS — ${#CASES[@]} signatures dispatched, ${#UNKNOWN[@]} unknowns rejected, empty/no-arg rejected."
  exit 0
else
  echo "FAIL — $failures case(s) wrong."
  exit 1
fi
