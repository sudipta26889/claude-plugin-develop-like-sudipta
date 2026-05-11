#!/usr/bin/env bash
# propose_hypothesis.sh — v4.1 STUB.
#
# In v4.1, autoresearch ships the methodology + infrastructure. The actual
# mutation proposer (the thing that reads program.md + the current target +
# .baselines.json and writes the next candidate target) is wired manually:
# Cowork, Claude Code, or any human-or-agent drives the proposal loop by
# writing to the target file and invoking run_autoresearch.sh --once to score
# the candidate.
#
# In v4.2 this script will be replaced by a real proposer (a Claude API call,
# or an integrated Cowork loop) that produces the candidate autonomously.
#
# Usage: propose_hypothesis.sh <skill-dir>
#
# Output: prints guidance to stdout. Does NOT mutate the target file.
# Exit code: always 0 (the stub itself is not a failure).
#
# Bash 3.2 compatible.

set -u

SKILL_DIR="${1:-}"
if [ -z "$SKILL_DIR" ]; then
  echo "Usage: propose_hypothesis.sh <skill-dir>" >&2
  exit 2
fi
[ -d "$SKILL_DIR" ] || { echo "skill-dir not a directory: $SKILL_DIR" >&2; exit 1; }
SKILL_DIR="$(cd "$SKILL_DIR" && pwd)"

cat <<EOF
[propose_hypothesis: STUB — v4.1]

This script signals where Cowork / Claude Code (or any agent) proposes the
next mutation. The v4.1 release ships the contract + the loop infrastructure;
proposing the next candidate is a manual step driven by you (or your Cowork
session reading program.md).

To produce the next candidate:

  1. Read the goal + constraints:
       $SKILL_DIR/autoresearch/program.md

  2. Read the current editable target (named in target.txt):
       cat $SKILL_DIR/autoresearch/target.txt

  3. Read the experiment history (what's been tried, what worked):
       tail -50 $SKILL_DIR/autoresearch/.baselines.json

  4. Write your proposed new target content directly to the target file.
     Atomic-write pattern:
       cp <target> <target>.bak
       \$EDITOR <target>     # or your agent writes a new version

  5. Score the candidate:
       bash skills/autoresearch/scripts/run_autoresearch.sh $SKILL_DIR --once

     The driver will detect the modified target and score / accept / reject.

v4.2 task: wire this script to a direct Claude API call so the loop runs
autonomously overnight without a human in the inner loop.
EOF

exit 0
