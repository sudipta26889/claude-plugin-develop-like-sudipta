#!/usr/bin/env bash
# propose_via_file.sh — file-based proposer (Cowork/Claude Code pickup pattern).
#
# Builds a context prompt from program.md + the current target + recent history,
# writes it to <skill>/autoresearch/.proposed_prompt.txt, and BLOCKS waiting
# for <skill>/autoresearch/.proposed_target.txt to appear. A Cowork or
# Claude Code session (or any external agent) reads the prompt, generates a
# proposed mutation, and writes the new target content to .proposed_target.txt.
#
# When the target file appears, this script:
#   1. Reads it,
#   2. Emits its contents to stdout (the new proposed target content),
#   3. Deletes both .proposed_prompt.txt and .proposed_target.txt,
#   4. Exits 0.
#
# Configuration:
#   PROPOSER_FILE_TIMEOUT  Seconds to wait for .proposed_target.txt (default 5).
#                          Cowork/interactive callers should set this to ~600.
#   PROPOSER_FILE_POLL_SEC Poll interval (default 5).
#
# Usage: propose_via_file.sh <skill-dir>
#
# Exit codes:
#   0  success — proposed content emitted to stdout
#   1  generic error (bad args, missing files, etc.)
#   2  bad invocation
#   5  timed out waiting for .proposed_target.txt
#
# Bash 3.2 compatible. macOS-friendly.

set -u
set -o pipefail

SKILL_DIR="${1:-}"
if [ -z "$SKILL_DIR" ]; then
  echo "Usage: propose_via_file.sh <skill-dir>" >&2
  exit 2
fi
[ -d "$SKILL_DIR" ] || { echo "skill-dir not a directory: $SKILL_DIR" >&2; exit 1; }
SKILL_DIR="$(cd "$SKILL_DIR" && pwd)"

AR_DIR="$SKILL_DIR/autoresearch"
PROGRAM_MD="$AR_DIR/program.md"
TARGET_TXT="$AR_DIR/target.txt"
BASELINES="$AR_DIR/.baselines.json"
PROMPT_FILE="$AR_DIR/.proposed_prompt.txt"
TARGET_PROPOSAL="$AR_DIR/.proposed_target.txt"

for required in "$PROGRAM_MD" "$TARGET_TXT"; do
  if [ ! -f "$required" ]; then
    echo "ERROR: missing $required" >&2
    exit 1
  fi
done

TARGET_REL="$(head -1 "$TARGET_TXT" | tr -d '[:space:]')"
[ -n "$TARGET_REL" ] || { echo "ERROR: target.txt is empty" >&2; exit 1; }
TARGET_FILE="$SKILL_DIR/$TARGET_REL"
[ -f "$TARGET_FILE" ] || { echo "ERROR: target file not found: $TARGET_FILE" >&2; exit 1; }

TIMEOUT="${PROPOSER_FILE_TIMEOUT:-5}"
POLL="${PROPOSER_FILE_POLL_SEC:-5}"
# guard against silly values
case "$TIMEOUT" in (*[!0-9]*) TIMEOUT=5 ;; esac
case "$POLL" in     (*[!0-9]*) POLL=5 ;; esac
[ "$POLL" -lt 1 ] && POLL=1

# ---- build the prompt ----
{
  echo "# Autoresearch proposer prompt"
  echo "# Skill dir: $SKILL_DIR"
  echo "# Target file (the ONE editable file): $TARGET_REL"
  echo ""
  echo "## Goal + constraints (program.md)"
  echo ""
  cat "$PROGRAM_MD"
  echo ""
  echo "## Current target content ($TARGET_REL)"
  echo ""
  echo '```'
  cat "$TARGET_FILE"
  echo '```'
  echo ""
  echo "## Recent experiment history (last 5 baselines)"
  echo ""
  if [ -f "$BASELINES" ]; then
    tail -5 "$BASELINES"
  else
    echo "(no history yet — this is the first proposal)"
  fi
  echo ""
  echo "## Your task"
  echo ""
  echo "Propose the next mutation to the target. Write the FULL new content"
  echo "of the target file (no diff, no preamble, no markdown fences) to:"
  echo ""
  echo "  $TARGET_PROPOSAL"
  echo ""
  echo "The autoresearch driver will read that file, score it, and"
  echo "accept-or-reject the mutation."
} > "$PROMPT_FILE"

# Always clean up the prompt file on exit (success or failure).
cleanup() {
  rm -f "$PROMPT_FILE" "$TARGET_PROPOSAL"
}
trap cleanup EXIT INT TERM

# ---- inform the user/agent on stderr ----
{
  echo "[propose_via_file] wrote prompt: $PROMPT_FILE"
  echo "[propose_via_file] waiting for: $TARGET_PROPOSAL (timeout ${TIMEOUT}s, poll ${POLL}s)"
  echo "[propose_via_file] Cowork/CC: read the prompt with:"
  echo "                    cat \"$PROMPT_FILE\""
  echo "[propose_via_file] then write the proposed new target content to:"
  echo "                    \"$TARGET_PROPOSAL\""
} >&2

# ---- poll for the proposal ----
elapsed=0
while [ "$elapsed" -lt "$TIMEOUT" ]; do
  if [ -f "$TARGET_PROPOSAL" ]; then
    # The file may still be mid-write; give it a beat in case of large content.
    # Heuristic: size unchanged across a short pause = settled.
    s1="$(wc -c < "$TARGET_PROPOSAL" 2>/dev/null | tr -d ' ' || echo 0)"
    sleep 1
    s2="$(wc -c < "$TARGET_PROPOSAL" 2>/dev/null | tr -d ' ' || echo 0)"
    if [ "$s1" = "$s2" ]; then
      cat "$TARGET_PROPOSAL"
      # cleanup() trap removes the files
      exit 0
    fi
  fi
  sleep "$POLL"
  elapsed=$((elapsed + POLL))
done

echo "[propose_via_file] TIMEOUT after ${TIMEOUT}s waiting for $TARGET_PROPOSAL" >&2
exit 5
