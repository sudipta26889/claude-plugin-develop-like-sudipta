# Distributed research (forward-looking)

Karpathy frames autoresearch as a building block for **"SETI@home for AI
research"** — many machines, each running the same experiment loop on
different candidates, with a central scoreboard picking the best-of-N at
the end of a wave.

This doc is **aspirational, not implemented**. v4.1 ships the per-skill
loop. v4.2+ may add distributed coordination. The point of writing it
now: the design constraints that make distribution possible (portable
`program.md`, portable `score.sh`, stateless target file, deterministic
metric) are also the constraints that make local autoresearch honest.
Building for distribution from day one keeps us honest.

## The vision in one paragraph

You publish a `program.md` to a central registry. N machines (your
laptop, your friend's laptop, a CI runner, a cloud spot instance) pull
the program, run the local loop overnight against their own working
copies, and at the end of the wave submit their best candidate
(target-file diff + score + reproducer command) to a scoreboard. A
coordinator picks the top-scoring candidate, verifies the score
reproduces on a clean machine, and commits it to main. Wave N+1 starts
from the new baseline.

## Why this works for skills

A `<skill>/autoresearch/` directory is already self-contained:
`program.md`, `target.txt`, `score.sh`, eval fixtures. Everything a
distributed worker needs to reproduce the experiment is in version
control. No external state, no proprietary data, no GPU coordination.

The win condition is well-defined: highest score on the same eval set
wins, ties broken by smallest diff (Occam — prefer the candidate that
changed less to achieve the same score).

## What v4.1 does to lay the foundation

- **Portable `program.md`** with a fixed schema (see
  `references/program_md_schema.md`) — every worker reads the same
  contract.
- **Portable `score.sh`** with one-number output — the scoreboard can
  rank candidates from any worker.
- **Single editable target** — winners are a single-file diff, trivial
  to apply on the coordinator.
- **`.baselines.json` JSONL append-only** — each worker's history is
  shareable, mergeable.
- **`git hash-object` of target on every iteration** — candidates are
  content-addressable; the scoreboard can dedupe identical proposals
  from different workers.

## What v4.2+ would add

1. **Scoreboard service**: a thin HTTP server that accepts
   `(program_hash, target_diff, score, worker_id, runtime)` and
   maintains a leaderboard per `program_hash`.
2. **Reproducibility gate**: before accepting a top candidate, the
   coordinator re-runs `score.sh` on a pinned machine to verify the
   submitted score. Disagreement → rejected (probable
   environment-specific cheat).
3. **Diversity reward**: bonus points for candidates that score within
   N% of the leader via a different route (different diff). Prevents
   one-strategy domination.
4. **Wave protocol**: time-bounded rounds (24h "waves"); commit
   winning candidate at wave-end; new wave starts from new baseline.

## Constraints (what NOT to add)

- **No worker-specific scoring.** If `score.sh` produces different
  numbers on different machines, the scoreboard is meaningless. Pin
  the scorer environment.
- **No multi-file targets.** Distribution requires that "the
  candidate" is a single artifact. Multi-file changes are coordinator
  hell.
- **No human-in-the-loop scoring.** "Send me the diffs and I'll pick
  one" doesn't scale.

## Current state (May 2026)

In-progress / future. The plugin ships the per-skill methodology + the
file contract that distributed work would build on. There is no
scoreboard, no coordinator, no protocol — only the building blocks.
Treat this doc as a design constraint for the v4.x roadmap, not a
spec.
