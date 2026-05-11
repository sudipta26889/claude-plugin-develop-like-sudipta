# Trigger evaluation

## Files

- `trigger_evals.json` — 20 hand-crafted prompts (10 should-trigger + 10 should-not). Each is a realistic-looking user query with file paths, jargon, casual speech, etc. Designed to test description triggering.
- `evals.json` — 5 functional test cases (will trigger the skill = should trigger the skill's CONTENT, not just the description). Reserved for the SKILL.md eval-viewer flow.
- `run_loop.log` — output of skill-creator's `run_loop.py` (description optimizer).

## How to (re)run the description optimizer

```bash
cd <path-to-skill-creator>     # e.g., the cached one in claude-hostloop-plugins
PATH="$HOME/.local/bin:$PATH" python3 -u -m scripts.run_loop \
    --eval-set <skill-dir>/evals/trigger_evals.json \
    --skill-path <skill-dir> \
    --model claude-opus-4-7 \
    --max-iterations 3 \
    --verbose
```

The loop:
1. Splits the eval set 60% train / 40% test (deterministic seed).
2. Evaluates the current `description` field against each query 3 times (to average out trigger-decision noise) → trigger rate.
3. Calls Claude to propose a new description aimed at boosting trigger rate on misses without losing the should-not-trigger cases.
4. Re-evaluates the new description.
5. Repeats up to `--max-iterations` (default 5).
6. Selects `best_description` by **test** score (not train) to avoid overfitting.

## How to apply the result

When the loop completes it prints (and the report HTML shows) `best_description`. Manually paste it into `SKILL.md`'s frontmatter `description:` field. Commit.

## Expected result for this skill

The starting description hits the right keywords (drive Claude Code, manage CC, etc.) but its phrasing is verbose. Expected outcomes from a healthy run:

- Iteration 1 train: ~0.75-0.85 trigger rate on should-trigger; ~0.85-0.95 non-trigger rate on should-not
- Iteration 3 best test: ~0.90+ on both classes

If the test score plateaus or drops vs train, that's overfitting — pick the earlier iteration.

## Time + cost estimate

~15-20 min per iteration on Opus 4.7 (60 `claude -p` calls × ~15s each). 3 iterations ≈ 45-60 min total. ~$1-2 in API cost on Anthropic-billed tier.

## When NOT to re-run

- If the description hasn't changed materially since the last run, the result will be the same. Re-run after substantive description edits.
- If the skill's scope is in flux (e.g. you're debating whether it should also handle tmux setups), evaluate the *scoping question* manually first; running optimization on an unsettled scope is wasted compute.
