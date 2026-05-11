#!/usr/bin/env bash
# state_salvage.sh — recover a corrupted <workspace>/.cc/state.json.
#
# state.json is JSONL (one event per line, see state.sh). If a writer is
# killed mid-flush — Cowork sandbox restart, OOM, forced session kill —
# the tail may be truncated or carry trailing garbage. cc-resume then
# fails opaquely because the file no longer parses as JSONL.
#
# Recovery procedure:
#   1. Detect: read every line, attempt to parse as JSON.
#   2. If all lines parse (or file is empty / absent), do nothing.
#   3. Otherwise: copy original to state.json.bak.<UTC-timestamp>,
#      write only the valid lines to a temp file, atomically replace
#      state.json with the temp.
#   4. Print a one-line summary so the caller can decide whether to retry
#      cc-resume immediately or investigate further.
#
# Usage:
#   state_salvage.sh <workspace>
#
# Exit codes:
#   0 — nothing to do, OR salvage succeeded
#   2 — refused to run (e.g. state.json larger than the safety bound)
#
# Bash 3.2 compatible. Uses python3 (always present on macOS) for JSON
# validation so we don't depend on jq.
set -u

WS="${1:-}"
if [ -z "$WS" ]; then
  echo "usage: state_salvage.sh <workspace>" >&2
  exit 2
fi

STATE_FILE="$WS/.cc/state.json"

# --------------------------------------------------------------------------
# 1. Missing file — idempotent no-op.
# --------------------------------------------------------------------------
if [ ! -e "$STATE_FILE" ]; then
  echo "no state.json to salvage at $STATE_FILE"
  exit 0
fi

# --------------------------------------------------------------------------
# Safety bound: refuse to chew through a runaway log. 100MB cap.
# --------------------------------------------------------------------------
MAX_BYTES=$((100 * 1024 * 1024))
# `wc -c` is portable; `stat -c%s` differs between macOS and Linux.
SIZE_BYTES="$(wc -c < "$STATE_FILE" | tr -d ' ')"
if [ "$SIZE_BYTES" -gt "$MAX_BYTES" ]; then
  echo "state_salvage: refusing — $STATE_FILE is $SIZE_BYTES bytes (> 100MB cap). Inspect manually." >&2
  exit 2
fi

# --------------------------------------------------------------------------
# 2. Empty file — trivially clean.
# --------------------------------------------------------------------------
if [ ! -s "$STATE_FILE" ]; then
  echo "state.json clean, nothing to do"
  exit 0
fi

# --------------------------------------------------------------------------
# 3. Single-pass validation + collection. Build a clean JSONL into TMP and
#    count GOOD / BAD as we go. If BAD == 0 at the end the file is already
#    clean; otherwise we promote TMP into place.
# --------------------------------------------------------------------------
TMP="$(mktemp "${TMPDIR:-/tmp}/state-salvage.XXXXXX")"
# Cleanup on any exit path before we've moved TMP into place.
trap 'rm -f "$TMP"' EXIT INT TERM

GOOD=0
BAD=0
# IFS= read -r preserves embedded whitespace; the final line may lack a
# trailing newline, so we handle the read-failure-with-data case too.
while IFS= read -r line || [ -n "$line" ]; do
  # A line that's only whitespace is treated as bad (a real event line
  # always parses as a JSON object).
  if [ -z "$line" ]; then
    BAD=$((BAD + 1))
    continue
  fi
  if python3 -c "import json,sys; json.loads(sys.stdin.read())" <<EOF >/dev/null 2>&1
$line
EOF
  then
    printf '%s\n' "$line" >> "$TMP"
    GOOD=$((GOOD + 1))
  else
    BAD=$((BAD + 1))
  fi
done < "$STATE_FILE"

# --------------------------------------------------------------------------
# 4. Already clean — leave file alone, no backup.
# --------------------------------------------------------------------------
if [ "$BAD" -eq 0 ]; then
  echo "state.json clean, nothing to do"
  exit 0
fi

# --------------------------------------------------------------------------
# 5. Salvage: back up original, atomically replace with cleaned file.
#    Timestamp is UTC and sortable so successive runs don't collide.
# --------------------------------------------------------------------------
TS="$(date -u +%Y%m%dT%H%M%SZ)"
BAK="$STATE_FILE.bak.$TS"

cp -f "$STATE_FILE" "$BAK"

# Same filesystem (both under $WS/.cc/) so mv is atomic.
mv -f "$TMP" "$STATE_FILE"
# TMP no longer exists; disarm the cleanup trap so we don't error.
trap - EXIT INT TERM

echo "$GOOD events salvaged, $BAD dropped (saved backup: $BAK)"
exit 0
