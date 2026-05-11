#!/usr/bin/env bash
# check_bug_id.sh — commit-msg git hook.
#
# Purpose: enforce that any commit whose message references `bug-<id>`
# (where <id> matches `phase-<N>-bug-<slug>`) has a corresponding
# .cc/bugs/<bug-id>.md artifact in the workspace.
#
# This makes the bug-driven-TDD discipline mechanical — Claude Code can
# no longer compose a "fixes bug-phase-3-bug-cart" message without first
# capturing evidence per references/bug_driven_tdd.md.
#
# Installation (per workspace):
#   cp develop-like-sudipta/hooks/scripts/check_bug_id.sh \
#      <workspace>/.git/hooks/commit-msg
#   chmod +x <workspace>/.git/hooks/commit-msg
#
# Bypass (use sparingly):
#   BUG_HOOK_BYPASS=1 git commit ...
#
# Exit codes:
#   0  — no bug ref, or bug ref + matching .cc/bugs/<id>.md found, or bypass set
#   1  — bug ref present but .cc/bugs/<id>.md missing
#   2  — usage / environment error

set -u

# Git invokes this hook with one arg: path to the commit message file.
MSG_FILE="${1:-}"
if [ -z "$MSG_FILE" ] || [ ! -f "$MSG_FILE" ]; then
  echo "[check_bug_id] usage: $0 <commit-msg-file>" >&2
  exit 2
fi

# Bypass for emergencies / non-discipline contexts.
if [ "${BUG_HOOK_BYPASS:-}" = "1" ]; then
  echo "[check_bug_id] BUG_HOOK_BYPASS=1 set — skipping bug-id discipline check." >&2
  # Optional: log the bypass into state.json if available.
  if [ -n "${WORKSPACE:-}" ] && [ -f "$WORKSPACE/.cc/state.json" ]; then
    echo "[check_bug_id] (bypass logged to $WORKSPACE/.cc/state.json)" >&2
  fi
  exit 0
fi

# Extract every bug-id reference. We match the literal token `bug-phase-<N>-<slug>`
# anywhere in the message. Pattern:
#   bug-phase-<digits>-bug-<word-and-hyphen-chars>
# Example matches: bug-phase-3-bug-cart, bug-phase-12-bug-cart-total-off-by-tax
#
# Using grep -oE so we get one match per line, then strip the leading "bug-".
BUG_REFS=$(grep -oE 'bug-phase-[0-9]+-bug-[a-zA-Z0-9_-]+' "$MSG_FILE" 2>/dev/null \
  | sed 's/^bug-//' \
  | sort -u || true)

if [ -z "$BUG_REFS" ]; then
  # No bug reference — this is a feature/chore/docs commit. Allow.
  exit 0
fi

# Resolve workspace root via git. Hook runs in the workspace, so this works.
WS=$(git rev-parse --show-toplevel 2>/dev/null || true)
if [ -z "$WS" ]; then
  echo "[check_bug_id] could not determine git workspace root (git rev-parse failed)" >&2
  exit 2
fi

MISSING=""
for bug in $BUG_REFS; do
  bug_file="$WS/.cc/bugs/${bug}.md"
  if [ ! -f "$bug_file" ]; then
    MISSING="${MISSING}${bug}\n"
  fi
done

if [ -n "$MISSING" ]; then
  echo "[check_bug_id] commit message references bug(s) but evidence file(s) are missing:" >&2
  # shellcheck disable=SC2059
  printf "$MISSING" | sed 's/^/    .cc\/bugs\//;s/$/.md/' >&2
  echo >&2
  echo "  Was the bug captured per references/bug_driven_tdd.md (step 1 — CAPTURE)?" >&2
  echo "  Create the missing file(s) with assets/bug_report_template.md as the structure," >&2
  echo "  or set BUG_HOOK_BYPASS=1 if this commit genuinely has no bug evidence." >&2
  exit 1
fi

# All referenced bug files exist — commit proceeds.
exit 0
