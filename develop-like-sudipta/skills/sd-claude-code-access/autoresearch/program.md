# Autoresearch program for sd-claude-code-access

## Goal
Maximize trigger accuracy on the held-out `evals/trigger_evals.json` fixture without losing coverage on existing positive trigger phrases.

## Metric
**Trigger accuracy (F1)** on `evals/trigger_evals.json`:
- Positive cases: the description should trigger (should_trigger=true)
- Negative cases: the description should NOT trigger (should_trigger=false)
- F1 = 2·P·R / (P + R)
- Higher is better. Range 0.0 to 1.0.
- Baseline: the current SKILL.md description scores **F1 ≈ 0.82** under `score.sh` (deterministic lexical-overlap scorer, threshold 0.30 — calibrated to the trigger_evals fixture; see `score.sh` for the rationale and how to retune if the fixture changes).

## Constraints (locked — agent must obey)
- **Editable target:** `SKILL.md` (the YAML frontmatter `description` field ONLY — body text is locked, even though it's in the same file)
- **Scoring command:** `bash autoresearch/score.sh` (run from skill dir; emits F1 to stdout)
- **Time budget per experiment:** 300 seconds (default; configurable via --time flag on run_autoresearch.sh)
- **Max experiments per run:** 50 (default)
- **Locked files:** everything else in `develop-like-sudipta/skills/sd-claude-code-access/`

## Hypothesis seeds
1. Add concrete trigger phrases for common user phrasings (e.g., "drive Claude Code", "run unit tests AND browser tests")
2. Make negative-trigger phrases visible in the description so the LLM can disambiguate
3. Group trigger phrases by category (driving CC vs browser-test vs bug-TDD)
4. Tighten the description by removing redundant clauses while keeping all trigger keywords
5. Add anti-trigger phrases ("do NOT use this skill for…") to suppress false positives

## Out of scope
- Don't modify body text of SKILL.md
- Don't change evals/ files (they ARE the scoring contract)
- Don't change descriptions of other skills
- Don't change scripts/
- Don't introduce new dependencies
