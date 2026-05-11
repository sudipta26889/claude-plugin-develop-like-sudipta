#!/usr/bin/env bash
# ssh_probe.sh — probe a remote Mac for the "Path D" substrate.
#
# Path D in the substrate-detection ladder is: Cowork's bash sits on the
# LOCAL Mac (via Desktop_Commander), but CC is driven on a REMOTE Mac via
# SSH. The bridge scripts (send.sh, watchdog.sh, etc.) need to live on the
# REMOTE Mac. This probe verifies the remote is reachable and that the
# essentials (osascript + claude CLI) are present BEFORE we offer Path D
# to the user.
#
# Usage: ssh_probe.sh [SSH_TARGET]
#   SSH_TARGET — user@host (or any value ssh accepts). Read from env
#                $SSH_TARGET first; falls back to $1 if env not set.
#
# Exit codes:
#   0  READY — remote reachable, osascript + claude both present.
#       Stdout: "READY <macos-version> <claude-version>"
#   1  no-ssh-target — SSH_TARGET not in env and no positional arg.
#   2  ssh-failed — `ssh ... echo READY` returned non-zero.
#   3  no-osascript-on-remote — `command -v osascript` empty (not macOS).
#   4  no-claude-cli-on-remote — `command -v claude` empty.
#
# Each path emits one line on stdout that starts with the status keyword,
# making it grep-friendly for the caller (Desktop_Commander reads stdout).
#
# Bash 3.2 / macOS. Avoid heredocs over SSH for portability — single-quoted
# command strings only. BatchMode=yes prevents password prompts hanging.

set -u

# ---------------------------------------------------------------------------
# 1. Resolve SSH_TARGET (env > positional arg)
# ---------------------------------------------------------------------------
TARGET="${SSH_TARGET:-}"
if [ -z "$TARGET" ] && [ $# -gt 0 ]; then
  TARGET="$1"
fi

if [ -z "$TARGET" ]; then
  echo "no-ssh-target — set SSH_TARGET=user@host or pass as arg 1"
  exit 1
fi

# ---------------------------------------------------------------------------
# 2. Probe SSH connectivity (BatchMode prevents interactive password prompt)
# ---------------------------------------------------------------------------
# We send a sentinel ('echo READY') over a short-timeout connection. If
# the connection fails for ANY reason (DNS, refused, auth, host-key) ssh
# exits non-zero — we treat all of those as ssh-failed.
SSH_OUT="$(ssh -o ConnectTimeout=5 -o BatchMode=yes "$TARGET" 'echo READY' 2>&1)"
SSH_RC=$?
if [ $SSH_RC -ne 0 ] || [ "$SSH_OUT" != "READY" ]; then
  # Include the ssh stderr tail so the user can diagnose, but keep the
  # status keyword as the first token for grep semantics.
  echo "ssh-failed — ssh \"$TARGET\" 'echo READY' returned rc=$SSH_RC: $SSH_OUT"
  exit 2
fi

# ---------------------------------------------------------------------------
# 3. Probe for osascript on the remote (proxy for "is this macOS?")
# ---------------------------------------------------------------------------
OSASCRIPT_PATH="$(ssh -o BatchMode=yes "$TARGET" 'command -v osascript' 2>/dev/null)"
if [ -z "$OSASCRIPT_PATH" ]; then
  echo "no-osascript-on-remote — remote does not appear to be macOS (command -v osascript empty)"
  exit 3
fi

# ---------------------------------------------------------------------------
# 4. Probe for claude CLI on the remote
# ---------------------------------------------------------------------------
CLAUDE_PATH="$(ssh -o BatchMode=yes "$TARGET" 'command -v claude' 2>/dev/null)"
if [ -z "$CLAUDE_PATH" ]; then
  echo "no-claude-cli-on-remote — install claude on $TARGET first (curl -fsSL https://...)"
  exit 4
fi

# ---------------------------------------------------------------------------
# 5. All checks passed — collect versions and emit READY
# ---------------------------------------------------------------------------
# sw_vers -productVersion → "14.5" (macOS). Trim newline/CR for clean output.
MACOS_VERSION="$(ssh -o BatchMode=yes "$TARGET" 'sw_vers -productVersion' 2>/dev/null | tr -d '\r\n')"
[ -z "$MACOS_VERSION" ] && MACOS_VERSION="unknown"

# `claude --version` may print extra text; take the first line and trim.
CLAUDE_VERSION="$(ssh -o BatchMode=yes "$TARGET" 'claude --version' 2>/dev/null | head -1 | tr -d '\r')"
[ -z "$CLAUDE_VERSION" ] && CLAUDE_VERSION="unknown"

echo "READY $MACOS_VERSION $CLAUDE_VERSION"
exit 0
