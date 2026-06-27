#!/usr/bin/env bash
# Install the bridge scripts into ~/.cache/ccbridge/. Idempotent.
# Persistent across reboots (unlike /tmp). Run once per machine.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEST="${CCBRIDGE_DIR:-$HOME/.cache/ccbridge}"
mkdir -p "$DEST"

SCRIPTS=(
  send.sh read.sh read_history.sh keys.sh
  watchdog.sh start_watchdog.sh stop_watchdog.sh
  nudge_if_stuck.sh audit.sh
  state.sh state_salvage.sh lock.sh diagnose.sh run_summary.sh
  install_precommit.sh
  escalate.sh
  # v4.3 — runtime-learning capture
  register_project.sh learning.sh
  # v4.4 — auto-launch CC if not already running for the workspace
  launch_cc.sh
  # v4.5 — at-a-glance health-check (also callable standalone)
  ccbridge_status.sh
  # v4.8 — distill → CC writes fix → draft-PR pipeline. The dispatch table
  # is its own script so the dryrun + cap evals can exercise it in isolation.
  dispatch_signature.sh propose_fix_pr.sh
  # v5.0 — cross-machine sync. The ccbridge-sync-learnings scheduled task
  # calls $DEST/sync_learnings.sh by canonical bridge-dir path (same pattern
  # as aggregate/distill — stable across plugin install location).
  sync_learnings.sh
  # v5.0.2 — manager-side detect+navigate for multi-option prompts (BUG-4).
  unblock_cc.sh
)

# v5.0.5 — non-executable data file: skip_nudge_patterns.txt. Same install path
# as the scripts above so nudge_if_stuck.sh can find it via $DEST without an
# extra plugin-root probe. Copied separately because it doesn't need chmod +x.
DATA_FILES=(
  skip_nudge_patterns.txt
)

# v4.3 — bootstrap ccbridge data subdirs so learning.sh + register_project.sh
# can dual-write immediately after install. Idempotent.
mkdir -p "$DEST/learnings" "$DEST/aggregated" "$DEST/distillation"
[ -f "$DEST/projects.json" ] || echo '{"version":1,"projects":[]}' > "$DEST/projects.json"

# v4.3.3 — copy aggregate/distill scripts into the canonical bridge dir so
# the scheduled tasks have a STABLE per-machine path to call, independent
# of where the plugin happens to be installed on disk. The bundled scheduled-
# task SKILL.md files reference these paths under ~/.cache/ccbridge/, NOT the
# plugin-relative path that would break the moment the plugin is re-installed
# at a different location on a different machine.
AUTORESEARCH_SCRIPTS_DIR="$HERE/../../autoresearch/scripts"
for f in aggregate_learnings.sh distill_learnings.sh; do
  if [ -f "$AUTORESEARCH_SCRIPTS_DIR/$f" ]; then
    cp -f "$AUTORESEARCH_SCRIPTS_DIR/$f" "$DEST/$f"
    chmod +x "$DEST/$f"
  fi
done

for f in "${SCRIPTS[@]}"; do
  cp -f "$HERE/$f" "$DEST/$f"
  chmod +x "$DEST/$f"
done

# Copy the danger-pattern allow/deny list (consulted by watchdog).
cp -f "$HERE/danger_patterns.txt" "$DEST/danger_patterns.txt"

# v5.0.5 — non-executable data files (e.g. skip_nudge_patterns.txt for
# nudge_if_stuck.sh's FAILURE 10 fix).
for f in "${DATA_FILES[@]}"; do
  if [ -f "$HERE/$f" ]; then
    cp -f "$HERE/$f" "$DEST/$f"
  fi
done

# Backwards-compat symlink so old docs still work.
if [ ! -L /tmp/ccbridge ] && [ ! -e /tmp/ccbridge ]; then
  ln -s "$DEST" /tmp/ccbridge
elif [ -L /tmp/ccbridge ]; then
  ln -snf "$DEST" /tmp/ccbridge
fi

echo "[ccbridge] installed to $DEST"
echo "[ccbridge] /tmp/ccbridge -> $DEST (compat symlink)"
echo
echo "Quick health check:"
# v4.3.4 — defensive SIGPIPE handling. `diagnose.sh | head -25` was causing
# install.sh to exit non-zero (under set -euo pipefail) when diagnose.sh wrote
# past 25 lines and got SIGPIPE'd by head's early exit. Wrap in `|| true` so
# the install always reports success regardless of head's truncation behavior.
"$DEST/diagnose.sh" 2>/dev/null | head -25 || true
