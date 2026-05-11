# Scoring design

The 80% of the work in setting up autoresearch on a skill is designing the
metric. The loop is shared; the metric is unique to each skill, and is the
ONLY thing standing between you and a confidently-wrong overnight run.

A good metric is **monotonic**, **independent of nuisance variables**,
**fast**, and **hard to cheat**. Anti-examples — metrics that fail one or more
of these — are at the bottom; refuse to autoresearch them.

## Monotonic

The metric is one number and the direction is explicit. "Higher is better,
range 0–100" or "lower is better, range 0+, unbounded above". No composites
without a published weighting function — "accuracy + speed" is not a metric,
it's two metrics in a trenchcoat.

If you need a composite (e.g., F1 of precision and recall), define the
combining function in `score.sh` and document it in `program.md`'s `## Metric`
section. Don't leave it to the agent to guess.

## Independent of nuisance variables

Karpathy chose bits-per-byte (`val_bpb`) over perplexity specifically because
bpb is **vocabulary-size-independent** — when the agent experiments with the
tokenizer, perplexity scores shift for reasons unrelated to model quality, but
bpb stays comparable. Identify your equivalent nuisance variables and design
them out:

- **Trigger-accuracy on Claude routing**: nuisance = which model version. Use
  a fixed surrogate (lexical overlap in v4.1; a single pinned model in v4.2)
  rather than "ask Claude" which drifts.
- **Regex precision/recall**: nuisance = corpus size. Always report ratios,
  never raw counts.
- **Eval-suite pass rate**: nuisance = test runtime. Either pin the runner /
  hardware, or measure pass-rate not elapsed-time.

## Fast

The score function must finish inside the time budget that
`run_autoresearch.sh --time SEC` enforces (default 300s). Faster is
strictly better: 30s per experiment → 1000 experiments overnight; 300s per
experiment → 100 experiments overnight; 30 min per experiment → 16
experiments overnight, which is barely enough to bisect anything.

Profiling tactics:

- Cache anything deterministic across iterations (eval-data parsing, model
  loading, fixture compilation).
- Run only the eval suite, not the project's full test suite.
- For trigger-accuracy: pre-tokenize the eval queries once; only re-extract
  the description on each iteration.

## Hard to cheat (Goodhart's law)

> When a measure becomes a target, it ceases to be a good measure.

The agent will optimize the metric you wrote, not the one you meant. If those
diverge, you get reward hacking. Common patterns:

- **Keyword stuffing**: if the metric rewards term-overlap, the agent stuffs
  the description with every term in the eval set. Defense: add adversarial
  cases (`should_trigger=false` queries that share keywords); penalize
  length; rotate eval corpus between runs.
- **Length exploitation**: if the metric counts "how many keywords appear at
  least once", a 10K-char description trivially wins. Defense: penalize
  length explicitly or compute density (matches per char).
- **Frontmatter abuse**: if the metric reads the whole file, the agent might
  stuff scoring-relevant text outside the `description` block. Defense:
  scope the metric reader to the exact field.
- **Eval-set leakage**: if `score.sh` reads the same file the eval set is
  derived from, the agent can edit the eval set. Defense: hash the eval
  files at start and abort if they change mid-run. (`run_autoresearch.sh`
  hashes `program.md` and `score.sh` for the same reason.)

## Per-skill-type examples

### Trigger-accuracy skill (description optimization)

**Metric**: weighted % accuracy on `(query, should_trigger)` pairs.

```
TP = count(should_trigger=true   AND description_matches(query))
TN = count(should_trigger=false  AND NOT description_matches(query))
N  = total
score = 100 * (TP + TN) / N
```

`description_matches(query)` is the cheap surrogate. v4.1 uses lexical
term-overlap above a threshold. v4.2 will use an LLM call ("does this
description claim to handle this query? yes/no") for higher fidelity at
higher cost.

### Regex-coverage skill (deny-list optimization)

**Metric**: F1 = 2·P·R / (P+R) on a labeled corpus.

```
P = TP / (TP + FP)   # of patterns that fired, how many fired correctly
R = TP / (TP + FN)   # of true-positive lines, how many did the regex catch
```

Report as percentage (×100). Corpus must be labeled (positive class = lines
the deny-list should block, negative = lines it should allow). Corpus is
locked during a run.

### Audit / pillar-compliance skill

**Metric**: % of expected findings the audit produces on a fixture repo
with known vulnerabilities.

```
expected = {finding_id_1, finding_id_2, ...}   # ground truth
got      = {f.id for f in audit_output}
score    = 100 * |expected ∩ got| / |expected|
```

Penalize false positives separately (precision component) and combine into
F1 if both matter. Run audit against a frozen fixture commit so behavior
is reproducible.

### Documentation / completeness skill (smoke test)

**Metric**: % of references the SKILL.md claims to load that actually exist
and pass a markdown lint.

```
claims = parse_references_table(SKILL.md)
exist  = [r for r in claims if file_exists(r) and markdownlint(r) == 0]
score  = 100 * len(exist) / len(claims)
```

Bounded above by 100 (every reference exists and lints clean). Trivially
fast. Easy to harden by adding "and contains the claimed sections" checks.

## Anti-examples — refuse these

These look like metrics but aren't honest single numbers. If a user asks to
autoresearch one of these, surface the failure mode and offer alternatives.

- **"Looks better"** — taste, not a metric. No reproducible scorer.
- **"Feels right" / "more natural"** — same.
- **"More readable"** — Flesch-Kincaid scores correlate weakly with actual
  readability; agents game them with short words and short sentences that
  read worse, not better.
- **"More engaging"** — engagement is downstream of the audience, not the
  text alone. Can't measure without the audience.
- **"Better personality"** — personality is the human's taste; the human is
  the metric, which means there's no automatable scorer.
- **"Improves marketing copy"** — the metric you actually want (conversion
  rate) lives outside the plugin; no scorer here can measure it.

## Decision tree before enabling autoresearch on a skill

1. **Can you write `score.sh` in 20 lines that returns one number?**
   No → refuse.
2. **Does the metric direction have a single, explicit answer (higher OR
   lower is better)?** No → refuse.
3. **Does the metric run in under 5 minutes?** No → either fix the scorer
   or shrink the target.
4. **Can you list 3 ways an adversarial agent could game the metric, and
   defenses for each?** No → harden the eval first.
5. **Is there exactly one editable file?** No → restructure the target
   (e.g., autoresearch the SKILL.md alone, not the whole skill dir).

All five yes → enable autoresearch. Any no → fix the gap before running a
single experiment.
