#!/usr/bin/env bash
# v5.0.5 — pin the deploy-phase doctrine + directive-template contents so
# future text drift trips this eval before it ships.
#
# Field report (GuardianAI 20-phase deploy) surfaced 8 failure modes that
# all map to specific phrases the SKILL.md "Known footguns" section and
# the directive_template.md "Deploy phase template" section must contain.
# This eval grep-asserts the phrases. Drift → fail → fix the docs.
#
# Contracts (each `assert_contains` is one contract):
#   FAILURE 1 — Docker base image not cached     → preflight docker image inspect
#   FAILURE 2 — Port conflict not detected       → preflight ss -tlnp
#   FAILURE 3 — xargs env loading                → set -a && source .env
#   FAILURE 4 — Interrupted UI not handled       → Interrupt recovery section
#   FAILURE 5 — Parallel SSH+CC Docker conflict  → Parallel-ops warning
#   FAILURE 6 — No venv fallback                 → Option B venv ladder
#   FAILURE 7 — LLM rate limit silent kill       → OLLAMA_MODEL_FALLBACK
#   FAILURE 8 — No tmux layout spec              → tmux new-window -t cc
#   FAILURE 9 — No mandatory health check        → curl /health acceptance
set -uo pipefail

PLUGIN_ROOT="$(cd "$(dirname "$0")/../../../.." && pwd)"
SKILL_MD="$PLUGIN_ROOT/develop-like-sudipta/skills/sd-claude-code-access/SKILL.md"
DIRECTIVE_MD="$PLUGIN_ROOT/develop-like-sudipta/skills/sd-claude-code-access/assets/directive_template.md"

test -f "$SKILL_MD"     || { echo "FAIL: SKILL.md missing"; exit 1; }
test -f "$DIRECTIVE_MD" || { echo "FAIL: directive_template.md missing"; exit 1; }

assert_contains() {
  local file="$1" pattern="$2" why="$3"
  if grep -qE "$pattern" "$file"; then
    return 0
  fi
  echo "FAIL: $(basename "$file") missing '$why' — pattern: $pattern"
  return 1
}

ERR=0

# SKILL.md "Known footguns" section + each footgun
assert_contains "$SKILL_MD" '^## Known footguns' \
  'Known footguns section header' || ERR=1
assert_contains "$SKILL_MD" 'set -a && source \.env && set \+a' \
  'FAILURE 3 fix: set -a && source .env && set +a' || ERR=1
assert_contains "$SKILL_MD" 'Parallel-ops conflict|do NOT run the same command' \
  'FAILURE 5 fix: parallel-ops warning' || ERR=1
assert_contains "$SKILL_MD" 'Interrupt recovery|Interrupted ·' \
  'FAILURE 4 fix: interrupt recovery doc' || ERR=1
assert_contains "$SKILL_MD" 'prompt_interrupted' \
  'state event name documented' || ERR=1
assert_contains "$SKILL_MD" 'skip_nudge_patterns' \
  'FAILURE 10 fix: skip-nudge patterns doc' || ERR=1

# directive_template.md — Deploy phase template + each preflight
assert_contains "$DIRECTIVE_MD" '## .Optional. Deploy phase template' \
  'Deploy phase template section' || ERR=1
assert_contains "$DIRECTIVE_MD" 'docker image inspect' \
  'FAILURE 1 fix: docker base image cache check' || ERR=1
assert_contains "$DIRECTIVE_MD" 'ss -tlnp' \
  'FAILURE 2 fix: port conflict preflight' || ERR=1
assert_contains "$DIRECTIVE_MD" 'set -a && source \.env && set \+a' \
  'FAILURE 3 fix: env loading in directive' || ERR=1
assert_contains "$DIRECTIVE_MD" 'Option B|venv fallback|Direct venv' \
  'FAILURE 6 fix: venv fallback ladder' || ERR=1
assert_contains "$DIRECTIVE_MD" 'OLLAMA_MODEL_FALLBACK' \
  'FAILURE 7 fix: LLM fallback env var' || ERR=1
assert_contains "$DIRECTIVE_MD" 'tmux new-window -t cc' \
  'FAILURE 8 fix: tmux layout' || ERR=1
assert_contains "$DIRECTIVE_MD" 'curl.*-o /dev/null.*-w.*http_code.*/health' \
  'FAILURE 9 fix: mandatory health check' || ERR=1
assert_contains "$DIRECTIVE_MD" 'Do not mark .phase_complete. without' \
  'health gate prose enforcement' || ERR=1

if [ "$ERR" -eq 0 ]; then
  echo "PASS — v5.0.5 deploy doctrine present in SKILL.md + directive_template.md"
  exit 0
fi
echo "FAIL — v5.0.5 doctrine drift detected"
exit 1
