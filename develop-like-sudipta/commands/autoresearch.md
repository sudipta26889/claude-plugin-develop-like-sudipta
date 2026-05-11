---
description: Run Karpathy-style autoresearch on a target skill — read its program.md, iterate the editable target, score each experiment, commit if better, reset if worse, repeat
argument-hint: <target-skill-name> [--budget N] [--time SEC] [--once]
---

Run the autoresearch loop on the target skill.

**You MUST invoke the `autoresearch` skill first** — read its SKILL.md and `references/loop_mechanics.md` before sending the first experiment trigger.

## Inputs
- `$1` — target skill name (e.g. `sd-claude-code-access`, `develop-like-sudipta`, `code-hacker`)
- `--budget N` — max experiments (default 50)
- `--time SEC` — wall-clock seconds per experiment (default 300)
- `--once` — run a single experiment for smoke-testing

## Procedure

0. Substrate detection (Path A preferred for shell ops on user's Mac — see `sd-claude-code-access/references/substrate_and_access.md`).
1. Verify target skill has autoresearch wiring: `<plugin>/skills/<target>/autoresearch/{program.md, score.sh, target.txt}` all exist. Refuse if missing.
2. Read program.md fully. Surface the Goal + Metric + Constraints to the user as a one-paragraph confirmation BEFORE running anything.
3. Run baseline: `bash <plugin>/skills/autoresearch/scripts/run_autoresearch.sh <plugin>/skills/<target> --once` to confirm score.sh works and produces a baseline.
4. If user confirms, run the full loop:
   `bash <plugin>/skills/autoresearch/scripts/run_autoresearch.sh <plugin>/skills/<target> --budget <N> --time <SEC>`
5. Per iteration (this is where Cowork/CC acts as the agent in v4.1 — `propose_hypothesis.sh` is a stub):
   - Read program.md, target file, recent .baselines.json entries
   - Propose ONE mutation to the target file (a hypothesis-seeded change, e.g., adding a trigger phrase)
   - Write the new target content
   - Loop driver runs score.sh, compares to baseline, commits or resets
6. Report progress every 10 experiments OR when a new best score lands. Surface the diff.
7. On completion (budget exhausted OR --once done), summarize: starting score, ending best score, % of experiments accepted, final target hash.

## Don't
- Don't run autoresearch on skills without a clear metric (see `references/failure_modes.md`)
- Don't modify program.md, score.sh, or any locked file during the run
- Don't commit experiments that didn't actually improve the score
- Don't run two autoresearch sessions on the same skill (lock contention)
