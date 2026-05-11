#!/usr/bin/env bash
# test_watchdog_prompts.sh — regression test + autoresearch scorer
# for watchdog.sh's prompt classification.
#
# For each entry in watchdog_prompt_evals.json:
#   1. Extract the prompt_excerpt as the simulated terminal buffer.
#   2. Apply watchdog's PROMPT_PATTERN regex (extracted from scripts/watchdog.sh).
#   3. If matched, apply danger_patterns.txt — if any danger pattern matches,
#      the action is "refuse"; otherwise "approve".
#   4. If PROMPT_PATTERN didn't match, the action is "ignore".
#   5. Compare predicted vs expected_action; count correct.
#
# Output (last line): "ACCURACY=<float>" — single number in [0.0, 1.0].
# Format chosen for autoresearch consumption: `tail -1 | cut -d= -f2`.
#
# Exit 0 on PASS (accuracy >= 0.90), non-zero otherwise.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
WATCHDOG="$SKILL_DIR/scripts/watchdog.sh"
DANGER="$SKILL_DIR/scripts/danger_patterns.txt"
FIXTURE="$SCRIPT_DIR/watchdog_prompt_evals.json"

for f in "$WATCHDOG" "$DANGER" "$FIXTURE"; do
  [ -f "$f" ] || { echo "FAIL: missing $f" >&2; exit 2; }
done

command -v python3 >/dev/null 2>&1 || { echo "FAIL: python3 required" >&2; exit 3; }

# Extract PROMPT_PATTERN from watchdog.sh (the line that defines it).
PROMPT_PATTERN=$(grep -E "^PROMPT_PATTERN=" "$WATCHDOG" | head -1 \
  | sed -E "s/^PROMPT_PATTERN='([^']*)'.*/\1/")
if [ -z "$PROMPT_PATTERN" ]; then
  # Try double quotes
  PROMPT_PATTERN=$(grep -E "^PROMPT_PATTERN=" "$WATCHDOG" | head -1 \
    | sed -E 's/^PROMPT_PATTERN="([^"]*)".*/\1/')
fi
if [ -z "$PROMPT_PATTERN" ]; then
  echo "FAIL: could not extract PROMPT_PATTERN from $WATCHDOG" >&2
  exit 4
fi

# Drive the eval in python BUT shell out to `grep -qiE` for the actual
# pattern matching — that way semantics exactly mirror watchdog.sh
# (which uses `grep -qE` for PROMPT_PATTERN and `grep -qiE` for danger).
# Python's `re` doesn't 1:1 translate grep -E (POSIX bracket classes,
# alternation precedence, etc.), and we want the eval baseline to reflect
# real watchdog behavior, not our approximation of it.
python3 - "$FIXTURE" "$DANGER" "$PROMPT_PATTERN" <<'PY'
import json
import subprocess
import sys

fixture_path, danger_path, prompt_pattern = sys.argv[1], sys.argv[2], sys.argv[3]

with open(fixture_path) as f:
    fixture = json.load(f)

# Load danger patterns (one regex per non-blank, non-comment line — same as watchdog)
danger_patterns = []
with open(danger_path) as f:
    for line in f:
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        danger_patterns.append(line)

def grep_matches(pattern, buffer, case_insensitive=False):
    """Run `grep -qE` (or -qiE) against the buffer. Returns True on match."""
    flags = "-qiE" if case_insensitive else "-qE"
    try:
        result = subprocess.run(
            ["grep", flags, pattern],
            input=buffer,
            text=True,
            timeout=2,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        return result.returncode == 0
    except subprocess.TimeoutExpired:
        return False

correct = 0
total = 0
mismatches = []

for row in fixture["evals"]:
    total += 1
    buf = row["prompt_excerpt"]
    expected = row["expected_action"]

    # Step 1: PROMPT_PATTERN match? (case-sensitive, mirrors watchdog.sh)
    if not grep_matches(prompt_pattern, buf, case_insensitive=False):
        predicted = "ignore"
    else:
        # Step 2: any danger pattern? (case-insensitive, mirrors watchdog.sh)
        predicted = "approve"
        for pat in danger_patterns:
            if grep_matches(pat, buf, case_insensitive=True):
                predicted = "refuse"
                break

    if predicted == expected:
        correct += 1
    else:
        mismatches.append((row["id"], expected, predicted, row["rationale"][:80]))

accuracy = correct / total if total else 0.0

if mismatches:
    print(f"\n[mismatches: {len(mismatches)} of {total}]", file=sys.stderr)
    for mid, exp, pred, why in mismatches:
        print(f"  row {mid}: expected={exp} predicted={pred}  — {why}", file=sys.stderr)

print(f"correct={correct} total={total}")
print(f"ACCURACY={accuracy:.4f}")
sys.exit(0 if accuracy >= 0.90 else 1)
PY
RC=$?

if [ "$RC" -eq 0 ]; then
  echo "PASS"
else
  echo "FAIL (accuracy below 0.90 threshold)" >&2
fi
exit $RC
