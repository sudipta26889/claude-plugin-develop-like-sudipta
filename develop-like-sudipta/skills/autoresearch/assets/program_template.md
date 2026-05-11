# Autoresearch program for <SKILL-NAME>

<!--
  Per-skill template. Fill in every section before enabling autoresearch.
  See: skills/autoresearch/references/program_md_schema.md
-->

## Goal

<!--
  ONE sentence. What we are optimizing in plain English.
  If you can't write it in one sentence, the goal isn't well-defined enough.

  Example: "Maximize trigger accuracy of <skill-name> on the combined eval
  suite — the description must reliably attract real-user queries about X
  while rejecting unrelated queries."
-->

## Metric

<!--
  Single number. State explicitly:
    - Direction (higher is better OR lower is better — never both)
    - Bounds (lower bound, upper bound, or "unbounded")
    - What's measured + how + with what weighting

  Example:
  Weighted trigger accuracy % on evals/trigger_evals.json. Higher is better.
  Lower bound 0.0, upper bound 100.0. Equal weight per item. See score.sh
  for the lexical-overlap proxy used in v4.1.
-->

## Constraints (locked — agent must obey)

- **Editable target**: `<path-relative-to-skill-dir>` (e.g. `SKILL.md`).
  Must match the contents of `autoresearch/target.txt`.
- **Scoring command**: `bash autoresearch/score.sh`
- **Time budget per experiment**: 300 seconds
- **Max experiments per run**: 30
- **Locked files**: `evals/*`, `references/*`, `scripts/*`, `assets/*`,
  `autoresearch/*` (everything except the editable target)

## Hypothesis seeds

<!--
  Numbered list of directions to try first. Not exhaustive — the agent
  generates its own once it has a few scored candidates. Seeds exist so
  iteration 1 doesn't waste compute on obvious dead-ends.

  Example seeds for a trigger-accuracy program:
    1. Add verbatim trigger phrases mined from positive eval queries.
    2. Tighten negative-rejection by stating when the skill does NOT apply.
    3. Reorder so the most-discriminative phrases come first.
    4. Cut filler — long descriptions dilute keyword density.
    5. Lead with concrete activities, not abstract concepts.
-->

1. <seed 1>
2. <seed 2>
3. <seed 3>

## Out of scope

<!--
  What NOT to change. Even if it would improve the metric.
-->

- Don't rename the skill.
- Don't add or remove files.
- Don't modify YAML frontmatter keys other than `description`.
- Don't modify eval JSONs.
- Don't break SKILL.md's YAML frontmatter syntax.
