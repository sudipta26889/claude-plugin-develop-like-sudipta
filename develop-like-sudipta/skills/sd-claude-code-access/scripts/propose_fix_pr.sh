#!/usr/bin/env bash
# propose_fix_pr.sh — read a distillation priors file, route each
# cross-project signature through dispatch_signature.sh, and either
# (DRY_RUN=1) narrate what would happen, or actually spawn CC + open
# a draft PR via `gh pr create --draft`.
#
# Caps PR creation at PR_CAP (default 3) per call. Overflow → batched
# to a single GitHub issue.
#
# Env contract:
#   PRIORS_FILE       — markdown/text priors (one signature per line)
#   PR_LOG_FILE       — JSONL log (default ~/.cache/ccbridge/distillation/.pr_log.jsonl)
#   DRY_RUN=1         — no side effects, just narrate (skips PR log writes too)
#   PR_CAP=3          — max draft PRs per call
#   GH_OVERRIDE=mock  — never invoke the real `gh` binary
#   DISPATCH_SCRIPT   — path to dispatch_signature.sh (default: sibling in same dir)
#
# Wired by the ccbridge-propose-fix-pr scheduled-task SKILL. Installed to
# ~/.cache/ccbridge/propose_fix_pr.sh by install.sh so the SKILL.md can
# call it via a stable per-machine path.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DISPATCH_SCRIPT="${DISPATCH_SCRIPT:-$SCRIPT_DIR/dispatch_signature.sh}"
PRIORS_FILE="${PRIORS_FILE:-}"
PR_LOG_FILE="${PR_LOG_FILE:-$HOME/.cache/ccbridge/distillation/.pr_log.jsonl}"
DRY_RUN="${DRY_RUN:-0}"
PR_CAP="${PR_CAP:-3}"
GH_OVERRIDE="${GH_OVERRIDE:-}"

if [ -z "$PRIORS_FILE" ] || [ ! -f "$PRIORS_FILE" ]; then
  echo "ERROR: PRIORS_FILE not set or missing: '$PRIORS_FILE'" >&2
  exit 2
fi
if [ ! -f "$DISPATCH_SCRIPT" ]; then
  echo "ERROR: dispatch script missing: $DISPATCH_SCRIPT" >&2
  exit 2
fi

ts() { date -u +%Y-%m-%dT%H:%M:%SZ; }

log_pr() {
  # Append a JSONL row. Skipped under DRY_RUN to preserve no-side-effects.
  local sig="$1" action="$2" detail="$3"
  if [ "$DRY_RUN" = "1" ]; then
    return 0
  fi
  mkdir -p "$(dirname "$PR_LOG_FILE")" 2>/dev/null || true
  printf '{"ts":"%s","signature":"%s","action":"%s","detail":"%s"}\n' \
    "$(ts)" "$sig" "$action" "$detail" >> "$PR_LOG_FILE"
}

# parse_signature <line> — extract the routing key (event category) from a
# priors line. Priors lines come from distill_learnings.sh and look like:
#   category: signature
#   - **category**: signature (CROSS_N=2)
#   - category: signature (CROSS_N=3)
# Dispatch is on the CATEGORY half (e.g. `watchdog_recovery`) — the same
# prefixes that learning.sh emits and that the dispatch table is keyed on.
parse_signature() {
  local line="$1"
  line="$(printf '%s' "$line" | sed -E 's/^[[:space:]]*[-*][[:space:]]*//; s/^[[:space:]]+//')"
  line="$(printf '%s' "$line" | sed -E 's/[`*]//g')"
  case "$line" in
    *:*) line="${line%%:*}" ;;
  esac
  line="$(printf '%s' "$line" | sed -E 's/^[[:space:]]+//; s/[[:space:]].*$//')"
  printf '%s' "$line"
}

spawned=0
batched=0
skipped=0
BATCH_LINES=""

while IFS= read -r raw || [ -n "$raw" ]; do
  [ -z "$raw" ] && continue
  case "$raw" in
    \#*) continue ;;
  esac
  sig="$(parse_signature "$raw")"
  [ -z "$sig" ] && continue

  target="$(bash "$DISPATCH_SCRIPT" "$sig" 2>/dev/null)" || target=""
  if [ -z "$target" ]; then
    echo "[skip] signature=$sig reason=no_dispatch_target"
    log_pr "$sig" "no_dispatch_target" ""
    skipped=$((skipped + 1))
    continue
  fi

  if [ "$spawned" -lt "$PR_CAP" ]; then
    spawned=$((spawned + 1))
    if [ "$DRY_RUN" = "1" ]; then
      echo "[dry-run] WOULD spawn CC: signature=$sig target=$target"
    else
      echo "[live] WOULD spawn CC: signature=$sig target=$target"
      # Real launch + gh pr create --draft would happen here. The actual
      # invocation is owned by the SKILL.md procedure (it has access to
      # Desktop_Commander to drive Terminal.app and gh). This script
      # narrates the decision and logs it; it never shells out to `gh`
      # directly so a misconfigured cron run cannot leak PRs.
      log_pr "$sig" "spawn_requested" "$target"
    fi
  else
    batched=$((batched + 1))
    BATCH_LINES="$BATCH_LINES\n- $sig → $target"
    echo "[over-cap] batched_to_issue signature=$sig target=$target"
    log_pr "$sig" "batched_to_issue" "$target"
  fi
done < "$PRIORS_FILE"

echo
echo "── propose_fix_pr summary ──"
echo "  PR_CAP=$PR_CAP"
echo "  spawned=$spawned"
echo "  batched=$batched"
echo "  skipped=$skipped"
if [ "$DRY_RUN" = "1" ]; then
  echo "  DRY_RUN=1 (no PR log writes, no gh invocations)"
fi
if [ "$GH_OVERRIDE" = "mock" ]; then
  echo "  GH_OVERRIDE=mock (gh disabled)"
fi
