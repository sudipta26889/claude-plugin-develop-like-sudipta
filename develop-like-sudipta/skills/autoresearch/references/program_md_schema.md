# `program.md` schema

The `program.md` file is the locked experiment contract. The agent reads it
every iteration but never modifies it. Karpathy: *"essentially a super
lightweight skill"* — it tells the agent the goal, the constraints, and where
to look for inspiration.

## Required sections

A valid `<skill>/autoresearch/program.md` has these sections, in this order. The
`scripts/run_autoresearch.sh` driver checks the headings exist before starting
the loop. Missing or empty sections → fail-fast with a clear error.

### `# Autoresearch program for <skill-name>`

Title. Use the exact skill name from `<skill>/SKILL.md` frontmatter.

### `## Goal`

One sentence. What we are optimizing in plain English. Examples:

- "Maximize trigger accuracy of the `sd-claude-code-access` skill on the
  combined eval suite."
- "Minimize false-positive rate of `danger_patterns.txt` on a 1000-line
  fixture of approved shell commands while keeping recall ≥ 0.95 on the
  attack-pattern fixture."

If you cannot write this in one sentence, the goal is not well-defined enough
for autoresearch.

### `## Metric`

Single number. State **explicitly**:

- **Direction**: higher is better, OR lower is better. Never both, never "it
  depends".
- **Bounds**: lower bound, upper bound (or "unbounded" — but bounded is
  better, the loop can detect plateaus).
- **What's actually measured**: not just "accuracy" — accuracy on WHAT eval set,
  computed HOW, with WHAT weighting if more than one source.

Example:

> Weighted trigger accuracy %, higher is better. Lower bound 0.0, upper bound
> 100.0. Computed by `score.sh`, which loads
> `evals/{trigger,substrate_detection,verify_gate,bug_driven_tdd}_evals.json`,
> measures lexical term-overlap between the SKILL.md description and each
> query, and rewards high overlap on `should_trigger=true` cases / low overlap
> on `should_trigger=false` cases. Equal weight per eval item across all four
> files.

### `## Constraints (locked — agent must obey)`

A bullet list. The driver enforces some of these mechanically; others are
honor-system but documented so the agent can self-check.

Required bullets:

- **Editable target**: relative path from `<skill-dir>/` to the ONE file the
  loop may write. Matches `<skill-dir>/autoresearch/target.txt` exactly. The
  driver refuses to start if they disagree.
- **Scoring command**: `bash autoresearch/score.sh` (invoked from the
  skill-dir). The driver runs this; the agent should not invoke it directly.
- **Time budget per experiment**: in seconds (default 300). The driver wraps
  each `score.sh` call in a timeout; experiments that exceed this are treated
  as rejected.
- **Max experiments per run**: integer (default 50). Hard cap on iterations
  per `run_autoresearch.sh` invocation. Prevents runaway token spend overnight.
- **Locked files**: everything except the editable target. List the
  conspicuous ones (evals dir, references, scripts) so the agent has no
  excuse for editing them.

### `## Hypothesis seeds`

A numbered list of directions to try first. Not exhaustive — the agent should
generate its own once it has scored a few candidates. Seeds exist so iteration
1 doesn't waste compute trying obvious dead-ends.

Example seeds for a trigger-accuracy program:

1. Add more verbatim trigger phrases mined from positive eval queries.
2. Tighten negative-rejection by stating when the skill does NOT apply.
3. Reorder description so the most-discriminative phrases come first.
4. Cut filler — long descriptions dilute keyword density.
5. Lead with concrete activities, not abstract concepts.

### `## Out of scope`

What NOT to change. Even if it would improve the metric. Examples:

- Don't rename the skill.
- Don't add or remove files.
- Don't modify YAML frontmatter keys (only the `description` body).
- Don't modify the eval JSONs (they're the scoring contract).
- Don't break SKILL.md's YAML frontmatter syntax.

## Mutability rules

| File | Who edits | When |
|---|---|---|
| `program.md` | **Human** | Between runs, when expanding the search space after a plateau or after a Goodhart-style reward hack is discovered. NEVER during a run. |
| Editable target | **Agent** (or Cowork acting as agent in v4.1) | Every iteration. The ONLY file the loop writes to. |
| `score.sh`, evals, references, other skill files | **Human** | Between runs, to harden the metric or expand coverage. NEVER during a run — changing the scoring rules mid-run invalidates `.baselines.json`. |
| `.baselines.json` | **`run_autoresearch.sh`** | Appended after each experiment. JSONL. Read-only for the agent. |
| `target.txt` | **Human** | Once at setup time. Names the editable target relative to skill-dir. |

## Worked example 1 — trigger accuracy of `sd-claude-code-access`

```markdown
# Autoresearch program for sd-claude-code-access

## Goal
Maximize trigger accuracy of `sd-claude-code-access` on the combined eval suite —
the description must reliably attract real-user queries about driving Claude
Code while rejecting unrelated queries.

## Metric
Weighted trigger accuracy % on
evals/{trigger,substrate_detection,verify_gate,bug_driven_tdd}_evals.json.
Higher is better. Lower bound 0.0, upper bound 100.0. Equal weight per item
across all four files. See score.sh for the lexical-overlap proxy used in v4.1.

## Constraints (locked — agent must obey)
- Editable target: `SKILL.md`
- Scoring command: `bash autoresearch/score.sh`
- Time budget per experiment: 300 seconds
- Max experiments per run: 30
- Locked files: `evals/*`, `references/*`, `scripts/*`, `assets/*`, `autoresearch/*`

## Hypothesis seeds
1. Add verbatim trigger phrases mined from positive eval queries.
2. Tighten negative rejection by stating when the skill does NOT apply.
3. Reorder so the most-discriminative phrases come first.
4. Cut filler — long descriptions dilute density.
5. Add a one-sentence "what this skill does" lead.
6. Split into a short skim paragraph + a verbose detail tail.

## Out of scope
- Don't rename the skill.
- Don't change YAML frontmatter keys other than `description`.
- Don't add or remove files.
- Don't modify eval JSONs.
- Don't break YAML syntax.
```

## Worked example 2 — danger-pattern coverage

```markdown
# Autoresearch program for danger-patterns-regex

## Goal
Maximize F1 of `scripts/danger_patterns.txt` against a labeled fixture of
1000 approved shell commands (negative class) and 200 destructive commands
(positive class). The regex set must catch real destructive commands without
flagging routine dev work.

## Metric
F1 score (2·P·R / (P+R)) on the labeled fixture. Higher is better. Lower
bound 0.0, upper bound 1.0. Reported as a percentage by score.sh (×100).

## Constraints (locked — agent must obey)
- Editable target: `scripts/danger_patterns.txt`
- Scoring command: `bash autoresearch/score.sh`
- Time budget per experiment: 60 seconds (small file, fast scorer)
- Max experiments per run: 50
- Locked files: everything else, especially `evals/fixtures/*.txt` (the
  labeled corpus is the scoring contract — changing it = cheating)

## Hypothesis seeds
1. Tighten existing patterns to require word boundaries (\b) to cut false
   positives on substrings of approved commands.
2. Add patterns for destructive commands that currently slip through (audit
   the false-negative list at evals/fixtures/false_negatives.txt).
3. Replace `.*` with bounded `.{0,N}` where the unbounded form catches
   approved commands.
4. Order patterns by frequency — most common destructive ops first
   (short-circuits the regex engine).

## Out of scope
- Don't modify the labeled fixture (that's the scoring contract).
- Don't add or remove files.
- Don't change the regex flavor (the watchdog uses bash 3.2 grep -E).
```
