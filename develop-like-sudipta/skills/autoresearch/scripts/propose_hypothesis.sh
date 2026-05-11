#!/usr/bin/env bash
# propose_hypothesis.sh — v4.2 proposer dispatcher.
#
# Selects between two proposer modes:
#   1. "file" — propose_via_file.sh writes a prompt file and blocks waiting
#                for an external agent (Cowork, Claude Code) to write back
#                the proposed target content. Used when no API key is
#                available or when interactive picking is preferred.
#   2. "api"  — propose_via_api.sh curls api.anthropic.com directly. Used
#                for fully autonomous loops (overnight runs, CI, swarms).
#
# Mode selection (highest priority first):
#   1. <skill-dir>/autoresearch/config.json -> "proposer_mode" key
#   2. $PROPOSER_MODE env var
#   3. autodetect — ANTHROPIC_API_KEY set => "api", else "file"
#
# Usage: propose_hypothesis.sh <skill-dir>
#
# The selected sub-script's stdout (the proposed new target content) and
# exit code are passed through unchanged.
#
# Bash 3.2 compatible.

set -u
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

SKILL_DIR="${1:-}"
if [ -z "$SKILL_DIR" ]; then
  echo "Usage: propose_hypothesis.sh <skill-dir>" >&2
  exit 2
fi
[ -d "$SKILL_DIR" ] || { echo "skill-dir not a directory: $SKILL_DIR" >&2; exit 1; }
SKILL_DIR="$(cd "$SKILL_DIR" && pwd)"

AR_DIR="$SKILL_DIR/autoresearch"
PROGRAM_MD="$AR_DIR/program.md"
TARGET_TXT="$AR_DIR/target.txt"
SKILL_SCORE="$AR_DIR/score.sh"
BASELINES="$AR_DIR/.baselines.json"
CONFIG="$AR_DIR/config.json"

# ---- contract check ----
for required in "$PROGRAM_MD" "$TARGET_TXT" "$SKILL_SCORE"; do
  if [ ! -f "$required" ]; then
    echo "ERROR: missing $required" >&2
    exit 1
  fi
done
if [ ! -f "$BASELINES" ]; then
  # OK to be missing on first run, but require the directory exists.
  if [ ! -d "$AR_DIR" ]; then
    echo "ERROR: autoresearch dir missing: $AR_DIR" >&2
    exit 1
  fi
fi

# ---- pick the mode ----
MODE=""

# 1. config.json (best-effort; tolerate missing python3 or malformed JSON)
if [ -f "$CONFIG" ] && command -v python3 >/dev/null 2>&1; then
  MODE_FROM_CONFIG="$(
    python3 - "$CONFIG" <<'PY' 2>/dev/null || true
import json, sys
try:
    with open(sys.argv[1]) as f:
        cfg = json.load(f)
    m = cfg.get("proposer_mode")
    if isinstance(m, str) and m:
        sys.stdout.write(m.strip())
except Exception:
    pass
PY
  )"
  if [ -n "${MODE_FROM_CONFIG:-}" ]; then
    MODE="$MODE_FROM_CONFIG"
  fi
fi

# 2. env var override
if [ -z "$MODE" ] && [ -n "${PROPOSER_MODE:-}" ]; then
  MODE="$PROPOSER_MODE"
fi

# 3. autodetect
if [ -z "$MODE" ]; then
  if [ -n "${ANTHROPIC_API_KEY:-}" ]; then
    MODE="api"
  else
    MODE="file"
  fi
fi

# ---- dispatch ----
case "$MODE" in
  api)
    echo "[propose_hypothesis] mode=api (delegating to propose_via_api.sh)" >&2
    exec bash "$SCRIPT_DIR/propose_via_api.sh" "$SKILL_DIR"
    ;;
  file)
    echo "[propose_hypothesis] mode=file (delegating to propose_via_file.sh)" >&2
    exec bash "$SCRIPT_DIR/propose_via_file.sh" "$SKILL_DIR"
    ;;
  *)
    echo "ERROR: unknown proposer mode '$MODE' (expected 'api' or 'file')" >&2
    exit 1
    ;;
esac
