---
name: autoresearch
description: >
  Karpathy-style self-improving skill optimizer for this plugin. Sets up the 3-file
  experiment loop (locked program.md goal + the ONE editable target file + automated
  score.sh) so a Claude (Cowork, Claude Code, or any agent) can run overnight,
  proposing edits to a skill's SKILL.md (or another single target), scoring each
  proposal with a hard numeric metric, and git-committing wins / git-resetting
  losses. Use this skill whenever someone says: "set up autoresearch for <skill>",
  "wire autoresearch on my plugin", "auto-tune the description", "improve this
  skill's trigger accuracy automatically", "score this skill", "I want overnight
  self-improvement", "make the eval better — run autoresearch", "Karpathy
  autoresearch for my plugin", "experiment loop on this skill", "self-improving
  loop", "automated skill optimization". The skill ships methodology +
  infrastructure (run_autoresearch.sh, git_experiment.sh, score.sh dispatcher,
  propose_hypothesis.sh stub) + templates (program_template.md, score_template.sh)
  + 5 references (program_md_schema, scoring_design, failure_modes, loop_mechanics,
  distributed_research) + a 7-case smoke eval. v4.1 ships infrastructure + docs;
  the mutation-proposer stub is wired manually (Cowork or CC supplies the next
  candidate) — full autonomy is a v4.2 task. Refuses to enable autoresearch on
  skills whose value is subjective (prose readability, personality, marketing
  copy) — those have no honest single-number metric and autoresearch will
  confidently optimize the wrong thing.
---

# autoresearch

A skill for **setting up Karpathy-style autoresearch loops on the skills in this
plugin**. The user picks a skill, this skill bootstraps a 3-file experiment
contract, and a Claude (Cowork, CC, or any agent that can read files and run
bash) drives the proposal loop — score, commit-or-reset, repeat — until budget
exhausts or scores plateau.

## What autoresearch is

Andrej Karpathy published [autoresearch](https://github.com/karpathy/autoresearch)
as a minimal harness for AI-driven ML research. Three files do all the work:

- `program.md` — the experiment instructions the agent reads each iteration. The
  human iterates on `program.md`; the agent does not modify it. Karpathy: *"The
  `program.md` file is essentially a super lightweight skill."*
- `train.py` — the ONE file the agent is allowed to edit between experiments.
- `prepare.py` — fixed constants, data prep, evaluation harness. NOT modified.

Each loop iteration: agent reads `program.md`, modifies `train.py`, runs the
evaluation, gets ONE number back (Karpathy uses `val_bpb` — bits per byte on a
val set, lower is better). Time-boxed (Karpathy: a fixed 5-minute wall-clock per
experiment so all candidates are compared on equal compute). Score improved?
`git commit`. Worse or equal? `git reset`. Loop overnight.

We are not optimizing ML training runs; we are optimizing **skills in this
plugin**. The mapping is direct: `program.md` becomes our locked experiment
contract, the editable target becomes a skill's `SKILL.md` (or one specific
reference doc), and `score.sh` runs the skill's own evals (trigger-accuracy on a
held-out query set, regex precision×recall on a labeled corpus, pillar
compliance on a fixture repo, etc.) and prints one number.

## When this skill applies

Trigger this skill when ANY of these are true:

- The user asks to "set up autoresearch", "wire autoresearch", or "enable
  self-improvement" on a skill or on this plugin.
- The user wants to "improve trigger accuracy automatically", "auto-tune the
  description", "score this skill", or "run experiments overnight" against a
  skill's eval suite.
- The user references Karpathy's autoresearch or describes the same
  methodology ("3-file loop", "program.md + one editable file", "score and
  commit-or-reset").
- The user wants the methodology + infrastructure but will drive the proposal
  loop themselves (this is the v4.1 mode — see Invocation below).

If the user wants the skill's own SKILL.md description optimized, fine. If they
want their prose, agent personality, or marketing copy "improved by AI" — refuse
and explain why (see *What skills CANNOT be autoresearched* below). The skill's
value is in honest experiments; participating in dishonest ones is a failure.

## The 3-file architecture

| Karpathy's repo | Our plugin equivalent | Mutability |
|---|---|---|
| `program.md` | `<skill>/autoresearch/program.md` | locked (human edits between runs, not during) |
| `train.py` | the ONE file named in `<skill>/autoresearch/target.txt` (typically `SKILL.md`) | editable (the only file the loop mutates) |
| `prepare.py` | the existing `<skill>/evals/*` + `<skill>/autoresearch/score.sh` | locked (changing these mid-run is cheating) |

The contract is enforced by `scripts/run_autoresearch.sh`: it refuses to start
if any of the three are missing, it only ever writes to the file in
`target.txt`, and it reads `program.md` and `score.sh` but never edits them.

## The loop

```
┌───────────────────────────────────────────────────────────────────────┐
│  baseline = run score.sh on the current state of <target>             │
│                                                                       │
│  for i in 1..budget:                                                  │
│    1. read program.md          (the locked goal + constraints)        │
│    2. read current <target>    (the editable file)                    │
│    3. read .baselines.json     (what we've tried, what worked)        │
│    4. propose new <target>     (Cowork / CC writes the candidate)     │
│    5. write candidate          (atomic — temp file + mv)              │
│    6. score = bash score.sh    (time-boxed to --time SEC, default 300)│
│    7. if score > baseline:                                            │
│         git_experiment.sh accept → commit                             │
│         baseline = score                                              │
│       else:                                                           │
│         git_experiment.sh reject → checkout -- <target>               │
│    8. append {ts, hash, score, accepted} to .baselines.json           │
│                                                                       │
│  stop when: budget exhausted, score plateaued N iterations, or        │
│             user Ctrl-C (lock file lets us resume cleanly).           │
└───────────────────────────────────────────────────────────────────────┘
```

## The 3 success conditions (directly from Karpathy)

A skill is a valid autoresearch target only if **all three** hold. If any one
fails, the loop will confidently optimize the wrong thing.

1. **Clear single metric.** ONE number, monotonic direction explicit. "Higher is
   better, range 0–100" or "Lower is better, range 0+, no upper bound". No
   composites without a published weighting function.
2. **Automated evaluation.** `score.sh` runs without human input, finishes
   inside the time budget, and emits the number on the last line of stdout.
3. **Exactly one editable file.** Multiple editable files = the agent will make
   correlated changes you can't disentangle, and reverting a bad experiment
   becomes a 3-way merge instead of a checkout.

## Failure modes

When autoresearch breaks, it breaks confidently — a high score on a wrong
metric looks indistinguishable from real progress. Full recovery procedures in
[`references/failure_modes.md`](references/failure_modes.md). Headlines:

- **Subjective metric.** "Better prose" / "feels right" / "more readable" — no
  honest single number exists. Refuse to enable autoresearch on these.
- **Slow feedback.** Score takes 30 min → you get 16 experiments overnight, not
  500. Either speed up the scorer or pick a smaller target.
- **Wrong metric (Goodhart's law).** The score goes up, the actual quality
  doesn't. Add adversarial cases to the eval set; harden the metric.
- **Reward hacking.** The agent finds a degenerate target file that scores high
  by exploiting the metric (e.g., keyword-stuffs the description). Detect via
  human spot-check every N iterations + harden eval.
- **Plateau.** Same score for N consecutive iterations. The search space is
  exhausted at this granularity — human edits `program.md` to expand it (add
  hypothesis seeds, allow a wider target, refine the metric).
- **Divergence.** Too many simultaneous changes per iteration → can't bisect
  what helped. Restrict to one editable file by design (we do); restrict the
  agent's change-size in `program.md` if needed.

## What skills CAN be autoresearched

Anything with an honest single-number metric. Examples:

- **Trigger accuracy** on a held-out `evals/trigger_evals.json` of `(query,
  should_trigger)` pairs. Optimize the SKILL.md description, score by % correct.
- **Regex coverage** on a labeled corpus — precision × recall on the
  `danger_patterns.txt` deny-list against a fixture of approved/rejected lines.
- **Audit accuracy** of a skill that scans a fixture repo for vulnerabilities,
  scored against a labeled answer key.
- **Eval-suite pass rate** of a SKILL.md when measured against a smoke test
  that exercises every reference doc it claims to load.

## What skills CANNOT be autoresearched

If you can't write a 20-line `score.sh` that emits an unambiguous number, the
skill is not eligible. Refuse politely and explain:

- **Prose readability** of references/methodology docs (no honest numeric
  metric; "Flesch-Kincaid" is a worse-than-nothing proxy).
- **Agent personality / tone** — same problem.
- **Marketing copy** — the metric you'd want (conversion) lives outside the
  plugin.
- **Anything where the human's taste IS the metric** — Karpathy's whole point
  is to remove the human from the inner loop; if the human IS the metric, you
  can't.

When asked to autoresearch one of these, surface the failure mode and offer
alternatives: "I can't score 'better prose' honestly. I can score (a)
trigger-accuracy on a held-out query set, (b) coverage on a labeled corpus, or
(c) end-to-end smoke test pass-rate. Which fits your goal?"

## Invocation

```
/autoresearch <skill-name> [--budget N] [--time SEC] [--once]
```

The 4 sibling slash commands (`/autoresearch`, `/autoresearch-status`,
`/autoresearch-resume`, `/autoresearch-baseline`) live under `commands/` and are
wired by a parallel task. They all shell into `scripts/run_autoresearch.sh`.

Manual single-cycle (for testing the contract before turning it loose):

```bash
bash skills/autoresearch/scripts/run_autoresearch.sh \
  skills/<skill-name> \
  --once \
  --time 60
```

### v4.1 reality check

**This release ships methodology + infrastructure + docs.** The
`propose_hypothesis.sh` script is a stub — it prints a message saying "TODO:
Cowork or CC drives this". In v4.1 you (the human or your Cowork session) read
`program.md`, look at `.baselines.json` for what's been tried, read the current
`<target>`, write the next candidate to a temp file, then call
`run_autoresearch.sh --once` to score / commit / reset that candidate. The full
autonomous loop — where a Claude API call IS the proposer, no human in the
inner loop — is a v4.2 task. The methodology and the file contract are
identical; only the proposer wiring changes.

## References

| Reference | Read when |
|---|---|
| [`references/program_md_schema.md`](references/program_md_schema.md) | Writing or reviewing a `<skill>/autoresearch/program.md`. Required sections, mutability rules, 2 worked examples. |
| [`references/scoring_design.md`](references/scoring_design.md) | Designing the metric. Monotonicity, nuisance-variable independence, cheat-resistance, per-skill-type examples, anti-examples. |
| [`references/failure_modes.md`](references/failure_modes.md) | Diagnosing a broken autoresearch run. Per-failure recovery procedures. |
| [`references/loop_mechanics.md`](references/loop_mechanics.md) | Building or debugging the loop itself. Time-boxing, score parsing, git semantics, baselines file format, parallelism, resume. |
| [`references/distributed_research.md`](references/distributed_research.md) | The "SETI@home for AI research" vision. Forward-looking — read when planning v4.2+ multi-machine experiments. |

## Closing principle

Autoresearch is honest if and only if the metric is honest. The 80% of the
work in setting up autoresearch on a skill is designing the score function —
NOT writing the loop. If you skip that work, you'll get a beautiful overnight
run that improves a number you don't actually care about. Spend time on
`score.sh`. The infrastructure is shared; the metric is yours.
