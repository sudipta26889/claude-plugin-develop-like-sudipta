# Autoresearch program for develop-like-sudipta

## Goal
Maximize trigger accuracy on the held-out `autoresearch/trigger_corpus.json` fixture. The
description should fire on coding / architecture / refactor / CI-CD / debugging / security-review
prompts but NOT on unrelated topics (cooking, travel, accounting, scheduling, generic writing).

## Metric
F1 score on `autoresearch/trigger_corpus.json` (TP / FP / TN / FN as defined in
`references/scoring_design.md` from the autoresearch skill). The proxy used here is lexical
content-word overlap between query and `SKILL.md` description: overlap >= 0.60 of query content
words counts as a "match". From the per-query matches we compute precision, recall, and F1, and
report the F1 score on stdout as a single float in [0.0, 1.0] (higher is better).

This 0–1 F1 scale matches the other v4.1+ wired skills (sd-claude-code-access, code-hacker) so the
`/autoresearch` baselines and proposed-vs-current deltas are directly comparable across skills.

## Constraints (locked)
- Editable target: `SKILL.md` (description field in YAML frontmatter)
- Scoring command: `bash autoresearch/score.sh` (no args; paths resolve from script location)
- Time budget per experiment: 300 sec
- Max experiments per run: 50
- Locked files: everything else in skill dir
  - `references/*`
  - `evals/*`
  - `autoresearch/trigger_corpus.json` (the scoring contract)
  - `autoresearch/score.sh`, `autoresearch/program.md`, `autoresearch/target.txt`
  - any agent definitions referenced by this skill

## Hypothesis seeds
1. Make pillars enumerable as trigger keywords (env-sync, OWASP, retries, circuit breakers,
   idempotency, SAGA, outbox, structured logging, Docker, GHCR, Portainer, pytest).
2. Add "discipline" / "rigor" / "review" / "audit" / "engineering practice" terms so disciplined-
   review prompts match even without listing a pillar by name.
3. Strengthen negative anti-triggers ("NOT for general writing", "NOT for personal coaching",
   "NOT for marketing copy", "NOT for scheduling").
4. Group triggers by user intent — writing code / fixing bugs / deploying / auditing / reviewing —
   so each intent class has a dedicated lexical hook.
5. Mention superpowers integration triggers explicitly (brainstorming, TDD, code-review,
   subagent-driven-development, git-worktrees) since users often phrase requests that way.

## Scoring modes

This skill ships two scorers:

1. **score.sh (default — word-overlap)**: deterministic 60%-overlap match between query and description. Fast, free, lexical.
2. **score-llm.sh (opt-in — Claude Haiku judgment)**: asks Claude Haiku 4.5 whether each query would invoke this skill. Slower (~100ms/query), costs API credits (~$0.01/100 queries), semantic.

Select via `autoresearch/config.json`:
```json
{ "scorer_mode": "llm" }
```

Default is `"wordlap"`. Use LLM for the final hill-climb after lexical optimization plateaus. Requires `ANTHROPIC_API_KEY`. See `skills/autoresearch/references/llm_scoring.md` for cost, caching, and failure-mode details.

## Out of scope
- Don't change SKILL.md body (only the description field in YAML frontmatter is editable)
- Don't change `references/`
- Don't introduce external dependencies
- Don't modify `trigger_corpus.json` (locked scoring contract)
- Don't break SKILL.md YAML frontmatter syntax
- Don't rename the skill
