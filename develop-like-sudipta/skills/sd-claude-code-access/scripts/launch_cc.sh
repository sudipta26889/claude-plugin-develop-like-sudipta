#!/usr/bin/env bash
# launch_cc.sh — detect-or-spawn Claude Code for a specific workspace.
#
# Why: /cc-drive previously assumed the user had already typed `claude` in a
# terminal tab. That's a manual step we can automate. This script:
#   1. Scans running processes for a real terminal-mode `claude` binary
#      (NOT Cowork-embedded — filters out anything under Claude.app/Contents/).
#   2. For each match, reads its cwd via `lsof -a -p <pid> -d cwd`.
#   3. If ANY claude PID's cwd matches the requested workspace → echo that PID,
#      exit 0. No spawn needed — that's our target tab.
#   4. If NONE match → spawn a new tab via osascript in the chosen terminal
#      app, `cd "$WORKSPACE" && claude --continue --chrome` (configurable),
#      then poll up to 30s for the new claude PID to register with the right
#      cwd. Echo the new PID, exit 0.
#   5. Timeout → exit 2 with a clear error.
#
# Usage:
#   launch_cc.sh <workspace>
#
# Env / config (in order of precedence):
#   CC_LAUNCH_FLAGS    space-separated flags passed to claude on spawn.
#                      Default: "--continue --chrome"
#   TERMINAL_APP       "Terminal" (default) | "iTerm2"
#   LAUNCH_TIMEOUT_S   poll seconds to wait for spawned CC. Default: 30
#
# Output (stdout, last line):
#   <pid>          on success
#
# Exit codes:
#   0  CC is running for this workspace (existing or newly spawned)
#   1  bad usage / workspace not a dir
#   2  spawn timed out (CC didn't appear within LAUNCH_TIMEOUT_S)
#   3  unsupported TERMINAL_APP
#
# Flag note (v4.6 D2): --continue resumes the most recent session for the cwd. On a
# brand-new workspace with no <workspace>/.claude/projects/, --continue may either
# show a session-picker menu OR open a fresh session — depends on CC version.
# Recommend CC_LAUNCH_FLAGS="--chrome" (drop --continue) for brand-new workspaces.

set -euo pipefail

DETECT_ONLY=0
DRY_RUN=0
ARGS=()
for arg in "$@"; do
  case "$arg" in
    --detect-only) DETECT_ONLY=1 ;;
    --dry-run)     DRY_RUN=1 ;;
    *) ARGS+=("$arg") ;;
  esac
done
set -- "${ARGS[@]:-}"

WS="${1:?usage: launch_cc.sh <workspace> [--detect-only]}"
WS_ABS=$(cd "$WS" 2>/dev/null && pwd -P) || { echo "[launch_cc] ERROR: not a directory: $WS" >&2; exit 1; }

CC_LAUNCH_FLAGS="${CC_LAUNCH_FLAGS:---continue --chrome}"
TERMINAL_APP="${TERMINAL_APP:-Terminal}"
LAUNCH_TIMEOUT_S="${LAUNCH_TIMEOUT_S:-30}"

# Per-project config override — read CC_LAUNCH_FLAGS from <ws>/.cc/config.json
# if "cc_launch_flags" is set. Allows per-repo customization without touching env.
if [ -f "$WS_ABS/.cc/config.json" ]; then
  FLAGS_FROM_CONFIG=$(python3 -c '
import json, sys
try:
    d = json.load(open(sys.argv[1]))
    v = d.get("cc_launch_flags")
    if isinstance(v, list):
        print(" ".join(v))
    elif isinstance(v, str):
        print(v)
except Exception:
    pass
' "$WS_ABS/.cc/config.json" 2>/dev/null || true)
  if [ -n "${FLAGS_FROM_CONFIG:-}" ]; then
    CC_LAUNCH_FLAGS="$FLAGS_FROM_CONFIG"
  fi
fi

echo "[launch_cc] workspace:    $WS_ABS" >&2
echo "[launch_cc] terminal app: $TERMINAL_APP" >&2
echo "[launch_cc] launch flags: $CC_LAUNCH_FLAGS" >&2

# ──────────────────────────────────────────────────────────────────────────
# is_terminal_cc <pid>
#   Returns 0 if PID is a TERMINAL-mode claude TUI (drivable via osascript
#   keystrokes), 1 otherwise. Filters caught by field testing on M1 Max:
#     - /Applications/Claude.app/Contents/MacOS/claude (Cowork-embedded CC)
#     - ~/.cursor/extensions/.../claude-code/.../claude (Cursor IDE agent)
#     - any claude with `--output-format stream-json` (IDE-agent telltale)
#     - any claude without a controlling TTY (tty=`??` in `ps -o tty=`)
# Real terminal CCs have tty like `ttys003` and don't use stream-json.
# ──────────────────────────────────────────────────────────────────────────
is_terminal_cc() {
  local pid="$1"
  local cmd; cmd=$(ps -o command= -p "$pid" 2>/dev/null || true)
  [ -z "$cmd" ] && return 1
  case "$cmd" in
    */Claude.app/Contents/*) return 1 ;;
    */.cursor/extensions/*claude-code*) return 1 ;;
    *"--output-format stream-json"*) return 1 ;;
  esac
  local tty; tty=$(ps -o tty= -p "$pid" 2>/dev/null | tr -d ' ')
  [ -n "$tty" ] && [ "$tty" != "??" ]
}

# ──────────────────────────────────────────────────────────────────────────
# detect_cc_for_workspace <workspace_abs>
#   Echoes PID of a terminal-mode claude whose cwd matches the workspace,
#   or empty if none found. Uses is_terminal_cc filter (see above).
# ──────────────────────────────────────────────────────────────────────────
detect_cc_for_workspace() {
  local target_ws="$1"
  local found_pid=""
  while IFS= read -r pid; do
    [ -z "$pid" ] && continue
    is_terminal_cc "$pid" || continue
    local cwd; cwd=$(lsof -a -p "$pid" -d cwd 2>/dev/null | awk 'NR==2 {print $NF}' || true)
    if [ -n "$cwd" ] && [ "$cwd" = "$target_ws" ]; then
      found_pid="$pid"
      break
    fi
  done < <(ps -axo pid=,command= 2>/dev/null | awk '$2 ~ /\/claude$/ {print $1}')
  # v4.5.1 — ALWAYS return 0 + echo (possibly empty). Otherwise the function's
  # exit status (1 when found_pid is empty) propagates through $(...) and
  # set -euo pipefail aborts the caller before it can fall into the spawn
  # or --detect-only branch.
  echo "$found_pid"
  return 0
}

# ──────────────────────────────────────────────────────────────────────────
# Step 1 — detect existing CC for this workspace.
# ──────────────────────────────────────────────────────────────────────────
EXISTING_PID=$(detect_cc_for_workspace "$WS_ABS")
if [ -n "$EXISTING_PID" ]; then
  echo "[launch_cc] found existing CC for this workspace: pid=$EXISTING_PID" >&2
  echo "$EXISTING_PID"
  exit 0
fi

if [ "$DETECT_ONLY" = "1" ]; then
  echo "[launch_cc] --detect-only: no spawn. No CC running for $WS_ABS" >&2
  exit 4   # 4 = no match, no spawn attempted
fi

# v4.6 — H1: if another terminal-mode CC is already running (for a DIFFERENT
# workspace), open in a separate window instead of a new tab in the same
# window. Tabs share the same osascript "front window" target, so the
# watchdog and send.sh would route keystrokes to the wrong CC.
ANOTHER_CC=""
while IFS= read -r _pid; do
  [ -z "$_pid" ] && continue
  is_terminal_cc "$_pid" || continue
  ANOTHER_CC="$_pid"
  break
done < <(ps -axo pid=,command= 2>/dev/null | awk '$2 ~ /\/claude$/ {print $1}')

if [ -n "$ANOTHER_CC" ]; then
  echo "[launch_cc] another terminal CC is running (pid=$ANOTHER_CC) for a different workspace — will open a NEW WINDOW (not a tab)" >&2
fi

echo "[launch_cc] no CC running for $WS_ABS — spawning new tab" >&2

# ──────────────────────────────────────────────────────────────────────────
# Step 2 — spawn a new tab/window via osascript.
# Quote the workspace path for shell safety (single quotes inside double).
# ──────────────────────────────────────────────────────────────────────────
SHELL_CMD="cd '$WS_ABS' && claude $CC_LAUNCH_FLAGS"

# v4.6 — F2: dry-run prints what would happen and exits 0.
if [ "$DRY_RUN" = "1" ]; then
  echo "[launch_cc] --dry-run: would spawn in $TERMINAL_APP:" >&2
  if [ -n "$ANOTHER_CC" ]; then
    echo "  mode: NEW WINDOW (another CC running pid=$ANOTHER_CC)" >&2
  else
    echo "  mode: same-window-tab (no other CC running)" >&2
  fi
  echo "  cmd:  $SHELL_CMD" >&2
  exit 0
fi

case "$TERMINAL_APP" in
  Terminal|Terminal.app)
    if [ -n "$ANOTHER_CC" ]; then
      # New window: `do script` without `in window …` creates a new window on
      # Terminal.app by default (verified macOS 14+). Adding `activate` brings
      # the new window forward so the watchdog/send.sh target it correctly.
      osascript <<EOF
tell application "Terminal"
  activate
  do script "$SHELL_CMD"
end tell
EOF
    else
      osascript <<EOF
tell application "Terminal"
  activate
  do script "$SHELL_CMD"
end tell
EOF
    fi
    ;;
  iTerm2|iTerm)
    if [ -n "$ANOTHER_CC" ]; then
      # iTerm2: explicitly create a new window.
      osascript <<EOF
tell application "iTerm"
  activate
  create window with default profile
  tell current session of current window
    write text "$SHELL_CMD"
  end tell
end tell
EOF
    else
      osascript <<EOF
tell application "iTerm"
  activate
  create window with default profile
  tell current session of current window
    write text "$SHELL_CMD"
  end tell
end tell
EOF
    fi
    ;;
  *)
    echo "[launch_cc] ERROR: unsupported TERMINAL_APP=$TERMINAL_APP (expected Terminal|iTerm2)" >&2
    exit 3
    ;;
esac

# ──────────────────────────────────────────────────────────────────────────
# Step 3 — poll for the new claude PID to appear with matching cwd.
# CC startup involves Node spawn + auth handshake + plugin sync — give it 30s
# by default (override via LAUNCH_TIMEOUT_S).
# ──────────────────────────────────────────────────────────────────────────
echo "[launch_cc] polling up to ${LAUNCH_TIMEOUT_S}s for new CC PID..." >&2
elapsed=0
while [ "$elapsed" -lt "$LAUNCH_TIMEOUT_S" ]; do
  NEW_PID=$(detect_cc_for_workspace "$WS_ABS")
  if [ -n "$NEW_PID" ]; then
    echo "[launch_cc] spawned CC for $WS_ABS: pid=$NEW_PID" >&2
    echo "$NEW_PID"
    exit 0
  fi
  sleep 2
  elapsed=$((elapsed + 2))
done

echo "[launch_cc] ERROR: CC did not appear within ${LAUNCH_TIMEOUT_S}s" >&2
echo "[launch_cc]   check the new Terminal tab — claude may have failed to start" >&2
echo "[launch_cc]   common causes: claude not on PATH, --chrome unsupported in your CC version" >&2
exit 2
