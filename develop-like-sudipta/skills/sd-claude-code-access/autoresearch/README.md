# Autoresearch for sd-claude-code-access

This directory opts the skill into Karpathy-style autoresearch (see `skills/autoresearch/SKILL.md` for the methodology).

## How to invoke

```
/autoresearch sd-claude-code-access
```

Or manually for a single cycle (Cowork or human supplies the proposed new SKILL.md content):

```bash
bash skills/autoresearch/scripts/run_autoresearch.sh \
  skills/sd-claude-code-access \
  --single-cycle /tmp/proposed_skill_md.txt
```

## Files

- **program.md** — the goal + locked constraints (must not be modified by experiments)
- **score.sh** — scoring function: returns a single float on stdout. Higher is better.
- **target.txt** — names the single editable file (`SKILL.md`)
- **.baselines.json** — auto-managed history of scores (created on first run; gitignored if you don't want it tracked)

## What gets optimized

The `description:` field of `SKILL.md`'s YAML frontmatter is the trigger-magnet for Claude's skill-routing layer. Improving it = more reliable invocation on real user queries.

## Scoring method (v4.1 proxy)

The scorer uses **lexical term-overlap** between query and description as a proxy for "would Claude route this query to this skill?". Real LLM-based scoring (embedding similarity or query-as-prompt) is deferred to v4.2 since it requires API access per experiment.

This proxy is honest about its limits:
- High overlap on `should_trigger: true` queries → score up
- Low overlap on `should_trigger: false` queries → score up

It will reward descriptions that contain the right keywords. It will NOT catch semantic-meaning failures (e.g., a description that uses the right words in a confusing way). v4.2's LLM-based scorer will close that gap.

## Caveats

- This is a single-skill optimization. Don't run autoresearch on multiple skills in parallel against the same git tree — branches will clash.
- The proxy scorer favors keyword stuffing. Trust the result up to ~5% gain; beyond that, manually review for prose quality before merging.
- After every autoresearch run, regenerate trigger_evals.json's negative cases to keep the scorer honest (otherwise the description can overfit to the existing negatives).
