#!/usr/bin/env bash
# v5.0.3 doctrine regression — SKILL.md + cc-drive.md must encode the
# manager no-sleep contract.
#
# Why this exists:
# The v5.0.x stability run (2026-05-12) exposed that the prior SKILL.md text
# ("Poll at 60–180s intervals", "Default to file-based directives") was
# insufficient guidance during an active CC session. Manager (Cowork) ended
# its turn between status checks → CC stalled in 30-min windows the user
# explicitly named ("everyone slept"). The fix that worked was a CONTINUOUS
# single-turn polling loop that never returns to the user until job_complete
# OR a hard escalation triggers. That doctrine MUST be documented in the
# SKILL so future manager sessions follow it without re-discovery.
#
# Contracts this test enforces (all must hold on every plugin release):
#   1. SKILL.md has a "Continuous-manager doctrine" section header.
#   2. SKILL.md documents the no-sleep contract (end-of-turn conditions).
#   3. SKILL.md prescribes proactive unblock via unblock_cc.sh.
#   4. SKILL.md notes manual phase triggers are acceptable when faster
#      than waiting for the orchestrator.
#   5. SKILL.md's anti-pattern list bans ending the turn while an active
#      job exists.
#   6. cc-drive.md command instructions mirror the no-sleep contract.
#
# Exit 0 = doctrine present, exit 1 = drift / missing.
set -uo pipefail

PLUGIN_ROOT="$(cd "$(dirname "$0")/../../../.." && pwd)"
SKILL_MD="$PLUGIN_ROOT/develop-like-sudipta/skills/sd-claude-code-access/SKILL.md"
CC_DRIVE_MD="$PLUGIN_ROOT/develop-like-sudipta/commands/cc-drive.md"

test -f "$SKILL_MD"     || { echo "FAIL: SKILL.md missing at $SKILL_MD"; exit 1; }
test -f "$CC_DRIVE_MD"  || { echo "FAIL: cc-drive.md missing at $CC_DRIVE_MD"; exit 1; }

assert_contains() {
  local file="$1" pattern="$2" why="$3"
  if grep -qiE "$pattern" "$file"; then
    return 0
  fi
  echo "FAIL: $(basename "$file") missing '$why' — pattern: $pattern"
  return 1
}

ERR=0

# 1. Section header in SKILL.md
assert_contains "$SKILL_MD" '^## Continuous-manager doctrine' \
  'Continuous-manager doctrine section' || ERR=1

# 2. No-sleep contract — end-of-turn conditions explicitly enumerated
assert_contains "$SKILL_MD" 'never end (your )?turn while .*active' \
  'no-sleep contract phrase' || ERR=1

assert_contains "$SKILL_MD" 'job_complete|done_criteria' \
  'end-of-turn condition: job_complete' || ERR=1

assert_contains "$SKILL_MD" 'monitor\.stop' \
  'end-of-turn condition: monitor.stop' || ERR=1

# 3. Proactive unblock via unblock_cc.sh directly
assert_contains "$SKILL_MD" 'unblock_cc\.sh.*direct|directly.*unblock_cc\.sh|don.t wait for the orchestrator' \
  'proactive unblock_cc.sh guidance' || ERR=1

# 4. Manual phase trigger acceptable
assert_contains "$SKILL_MD" 'manual phase trigger|send\.sh.*directly|phase trigger.*manually' \
  'manual phase trigger guidance' || ERR=1

# 5. Anti-pattern: ending turn while active job exists
assert_contains "$SKILL_MD" "Don.t end the turn while|Don.t return to (the )?user while .*active" \
  'anti-pattern: ending turn while active job' || ERR=1

# 6. cc-drive.md command mirrors the doctrine
assert_contains "$CC_DRIVE_MD" 'no-sleep|continuous-manager|never end (your )?turn' \
  'cc-drive.md mirrors no-sleep doctrine' || ERR=1

if [ "$ERR" -eq 0 ]; then
  echo "PASS — no-sleep doctrine present in SKILL.md + cc-drive.md"
  exit 0
fi
echo "FAIL — v5.0.3 doctrine drift detected; update SKILL.md / cc-drive.md"
exit 1
