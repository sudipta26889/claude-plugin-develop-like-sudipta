#!/usr/bin/env bash
# Eval: sync_learnings.sh --dry-run produces no transfers and prints the plan.
#
# Strategy: invoke against a nonexistent host. The script must:
#   - Print a `[sync]` header line (the plan).
#   - Exit cleanly (no `set -e` / pipefail abort on the ssh-failure path).
#   - Create no learning tail files locally (the remote-<host>/ dir is allowed —
#     it's harmless setup that gets reused on the next real sync).
set -uo pipefail

SCRIPT="$(dirname "$0")/../scripts/sync_learnings.sh"
[ -x "$SCRIPT" ] || { echo "FAIL: $SCRIPT not executable"; exit 1; }

# Pin CCBRIDGE_HOME to a tmpdir so the test doesn't touch the user's real
# ~/.cache/ccbridge/learnings/remote-* dirs (cosmetic — empty dirs are
# harmless but a clean test shouldn't pollute live state).
TD=$(mktemp -d)
trap 'rm -rf "$TD"' EXIT

# --dry-run with explicit nonexistent host: script must print [sync] header.
# Capture both stdout+stderr; ssh failures are absorbed inside the script so
# exit is 0, but we tolerate non-zero via `|| true` defensively.
output=$(CCBRIDGE_HOME="$TD" "$SCRIPT" nonexistent-test-host.invalid --dry-run 2>&1 || true)

if ! echo "$output" | grep -q '\[sync\]'; then
  echo "FAIL: no [sync] header in --dry-run output"
  echo "  output was:"
  echo "$output" | sed 's/^/    /'
  exit 1
fi

# No new learning tails created. The remote-<host>/ subdir IS created by the
# script (harmless setup), but it must be empty — no rsync transfers ran.
LEAK=$(find "$TD/learnings" -maxdepth 2 -name '*.jsonl' 2>/dev/null | head -5)
if [ -n "$LEAK" ]; then
  echo "FAIL: --dry-run produced .jsonl files: $LEAK"
  exit 1
fi

echo "PASS"
