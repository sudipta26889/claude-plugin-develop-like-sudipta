# Failure modes

Autoresearch fails confidently. A high score on a wrong metric looks the same
as a high score on a right metric — both are big numbers in
`.baselines.json`. The risk is shipping an "improved" skill that's actually
worse in production because the eval was lying.

Each failure mode below has: a **symptom** (what you see), a **root cause**
(what's actually wrong), and a **recovery** (concrete steps to get back to a
trustworthy run). Recovery happens BETWEEN runs — never modify scoring or
program.md mid-run, the baselines become meaningless.

## 1. Subjective metric

**Symptom.** Scores improve every iteration. The improved description /
target file feels worse when a human reads it.

**Root cause.** The metric measures a proxy of taste, not taste itself
(Flesch-Kincaid, word counts, "more keywords"). The agent learns to game the
proxy.

**Recovery.**

1. Stop the run (`Ctrl-C` releases the lock cleanly).
2. Reset to the last commit BEFORE autoresearch started (`git log
   --oneline` → find the pre-experiment commit → `git reset --hard <sha>`).
3. Replace the metric with one that's genuinely objective. If you can't,
   the skill is not eligible for autoresearch — see
   `references/scoring_design.md` § Anti-examples.

## 2. Slow feedback

**Symptom.** Overnight run produced only 8 experiments. Two of them
improved baseline by 0.3%; the rest were noise. You can't tell if there's
real signal.

**Root cause.** `score.sh` is too slow. Budget allows N experiments per
hour at `--time T`, with N ≈ 3600 / T. T=30 → 120/hr; T=300 → 12/hr;
T=1800 → 2/hr.

**Recovery.**

1. Profile `score.sh` — what's slow?
   - Loading data: cache it across iterations (but cache invalidates if
     the eval set is the editable target, which would be a different bug).
   - Running tests: scope to the smallest relevant subset; full project
     test suite is overkill if you're optimizing one description field.
   - LLM calls: batch them; use the cheapest model that preserves the
     metric's signal.
2. Lower `--time` to match the new median scorer runtime + 50% headroom.
3. Re-baseline (one new `--once` run on current state) and resume.

## 3. Wrong metric

**Symptom.** Score went up 20% across the overnight run. You eyeball the
new target file and it's clearly worse for real usage. The eval no longer
reflects what you care about.

**Root cause.** Goodhart. The metric was a proxy and the agent found the
gap between proxy and reality.

**Recovery.**

1. Stop, reset to pre-experiment commit (see #1).
2. Audit the top-3 winning experiments: WHY did they win? Look at the
   diffs. The exploitation pattern will be visible.
3. Add adversarial cases to the eval set that punish the specific
   pattern (keyword-stuffing → add `should_trigger=false` queries that
   share keywords; length exploitation → add a length penalty).
4. Re-run baseline scoring on the original target to confirm the new
   eval set scores the original WORSE than the exploited version did
   under the old eval. If yes, the eval is hardened. If no, keep
   iterating on the eval, not the target.

## 4. Reward hacking (degenerate target)

**Symptom.** The winning target file is unreadable, repetitive, or
contains nonsense that nonetheless scores high.

**Root cause.** Same family as #3, but more flagrant — the agent found a
degenerate input that maxes the metric.

**Recovery.**

1. Stop, reset.
2. Add a **structural validator** to `score.sh` — reject inputs that fail
   sanity checks BEFORE scoring. Examples:
   - SKILL.md must have valid YAML frontmatter.
   - SKILL.md description length must be 200–2000 chars.
   - target file must not contain a duplicated paragraph (catch loops).
   - regex file must have ≤ N patterns of ≤ M chars each.
3. Score = -infinity (or 0) on validator failure; agent learns the
   constraint.

## 5. Plateau

**Symptom.** Score has been flat for the last N iterations. The agent is
trying variations and none improves.

**Root cause.** The search space at the current granularity is exhausted.
The agent has found the best target file reachable by the current
`program.md`'s hypothesis seeds + constraints.

**Recovery.**

1. The human edits `program.md`. Specifically:
   - Add new hypothesis seeds (look at the BEST candidates so far — what
     direction would the NEXT improvement come from?).
   - Loosen constraints if any are over-restrictive (e.g., allow longer
     descriptions, allow editing the bullet list as well as the prose).
   - Refine the metric (often a plateau means the metric saturated, not
     that improvement is impossible — see #3).
2. Re-run autoresearch with the new `program.md`. The lock file +
   `.baselines.json` preserve the previous run's history.

## 6. Divergence (too many simultaneous changes)

**Symptom.** Winning experiments make huge edits across many sections at
once. You can't tell what helped.

**Root cause.** The agent has too much freedom per iteration. Even with
ONE editable file, that file might be large; rewriting all of it makes
bisection impossible.

**Recovery.**

1. Add a change-size cap to `program.md`'s `## Constraints` section:
   "Each candidate may modify at most N lines from the previous
   baseline."
2. Add the same cap to `score.sh`: if `git diff --stat` exceeds the cap,
   reject the candidate (score = -infinity / 0).
3. The agent will learn to make focused, bisectable changes.

## 7. Stale baselines

**Symptom.** `.baselines.json` has scores in the 70s but a fresh `--once`
run on current state scores 55.

**Root cause.** Something locked changed between runs (eval set was
edited, score.sh was modified, a referenced reference doc moved).
Previous baselines are no longer comparable.

**Recovery.**

1. Archive the old `.baselines.json` → `.baselines.<timestamp>.json`.
2. Run a fresh `--once` to establish the new baseline.
3. Resume autoresearch. The agent treats the new baseline as starting
   point.

## 8. Lock-file leftover

**Symptom.** `run_autoresearch.sh` refuses to start with "another instance
holds the lock", but no process is running.

**Root cause.** Previous run crashed (SIGKILL, OOM, machine reboot) and
the lock file at `<skill>/autoresearch/.lock` wasn't released.

**Recovery.**

1. Check the lock holder: `cat <skill>/autoresearch/.lock` shows pid +
   hostname + start time.
2. Verify the pid is dead: `ps -p <pid>` returns no row.
3. Delete the lock: `rm <skill>/autoresearch/.lock`. Resume.

If the pid IS alive, you have a real running instance — find and stop
it; don't break the lock.

## 9. Score parse failure

**Symptom.** `run_autoresearch.sh` logs "could not parse score from
score.sh output" and rejects every candidate.

**Root cause.** `score.sh` is printing extra lines AFTER the score line,
or the score isn't on the last line, or it's not a parseable float.

**Recovery.**

1. Run `bash <skill>/autoresearch/score.sh <skill>` manually. Inspect the
   last line of stdout.
2. The last line must match `^-?[0-9]+(\.[0-9]+)?$` (signed or unsigned
   float). Fix score.sh to redirect debug output to stderr (not stdout).
3. Re-run autoresearch.

## 10. Parallel-skill collision

**Symptom.** Two autoresearch runs on different skills both made commits
to the same branch. `git log` shows interleaved experiment commits, half
of which are now meaningless because the OTHER skill's commits invalidate
their baselines.

**Root cause.** Two runs sharing one git working tree. Each run thought
it owned the branch.

**Recovery.**

1. Stop both runs.
2. `git reset --hard` to the last pre-experiment commit.
3. For future parallel runs: use separate git worktrees per skill
   (`git worktree add ../skill-A-autoresearch`), one autoresearch
   process per worktree. Merge the winning targets back at the end.
4. Alternatively: run autoresearch on one skill at a time, serialized.
