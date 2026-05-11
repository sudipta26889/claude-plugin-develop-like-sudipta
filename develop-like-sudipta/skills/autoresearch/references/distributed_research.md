# Distributed research — v4.2 scaffolding

Karpathy frames autoresearch as a building block for **"SETI@home for AI
research"** — many machines, each running the same experiment loop on
different candidates, with a shared scoreboard picking the best-of-N at
the end of a wave.

v4.1 shipped a local per-skill loop. v4.2 ships the **scaffolding** for
multi-machine swarms: a shared scoreboard format and three small scripts
that read/write it correctly. Full multi-machine orchestration (gossip
protocols, work allocation, anti-cheat) is v5.0+.

This doc is concrete, not aspirational. If you have two MacBooks and a
shared folder, you can run a swarm today.

## The shared-filesystem assumption

v4.2 deliberately avoids a network protocol. Workers coordinate via a
shared directory — Dropbox, iCloud, NFS, an S3 bucket mounted with
rclone, whatever you've got. All operations are file-level (mkdir, mv,
append, atomic-rename) so they work cross-platform.

This is intentionally boring. A network protocol is a research project
in its own right; a shared folder is a Dropbox subscription. v4.2's job
is to prove the **data model** is right. Once two machines agree on a
manifest + a scoreboard line format + a proposal naming convention, the
rest is plumbing.

Trade-offs you accept by going shared-FS:
- **Eventual consistency.** Dropbox/iCloud sync is not instantaneous. A
  worker may publish a new global best 30 seconds before another worker
  sees it. Fine for autoresearch (waves are minutes-to-hours).
- **Best-effort atomicity.** We use temp-then-rename on the same FS,
  plus a `.swarm.lock` `mkdir`-lock around manifest+scoreboard writes.
  Two workers publishing at the exact same instant on the exact same
  Dropbox folder might still race; in practice, retries handle it.
- **No auth.** Anyone with write access to the folder can publish.
  Treat the swarm directory like a Git remote — share with people you
  trust.

v5.0+ would replace this with a real coordinator (gossip, signed
messages, replay-able experiments). The data model carries over.

## Directory layout

A swarm lives in any path whose root contains a `manifest.json`:

```
<swarm-dir>/
├── manifest.json          # swarm config (skills tracked, best_known_scores)
├── scoreboard.jsonl       # append-only log of every published experiment
├── proposals/             # candidate target contents (pure content, no meta)
│   └── <skill>-<sha8>-<score-pct>.<ext>
└── workers/               # per-worker heartbeats
    └── <worker-id>.json
```

Schemas: see `assets/scoreboard_schema.json` (JSON Schema draft 2020-12).

### `manifest.json`

```json
{
  "schema_version": 1,
  "swarm_name": "my-cluster",
  "created_at": "2026-05-11T12:00:00Z",
  "skills": ["sd-claude-code-access", "develop-like-sudipta", "code-hacker"],
  "max_workers": 8,
  "best_known_scores": {
    "sd-claude-code-access": 0.91,
    "develop-like-sudipta": 0.42,
    "code-hacker": 0.55
  }
}
```

`best_known_scores` is the only mutable field workers update. Everything
else is set once at swarm creation.

### `scoreboard.jsonl` line

```json
{
  "ts": "2026-05-11T14:23:00Z",
  "worker_id": "alice-macbook-pro",
  "skill": "sd-claude-code-access",
  "target_hash": "sha256:abc...",
  "score": 0.84,
  "scorer_mode": "wordlap",
  "accepted_locally": true,
  "proposal_id": "abc-12345",
  "delta_from_local_baseline": 0.06,
  "notes": "added 'autoresearch self-improvement' trigger phrase"
}
```

Append-only. Workers never rewrite earlier lines. A line is enough to
reproduce the experiment: pull the proposal file by `proposal_id`, run
the per-skill `score.sh`, verify the score.

### `proposals/<skill>-<sha8>-<score-pct>.<ext>`

Pure content of the target file at the moment it was published. No
metadata — that lives in `scoreboard.jsonl`. The filename encodes just
enough to find it: skill, short hash for uniqueness, percentage score
for sorting.

### `workers/<worker-id>.json`

```json
{
  "worker_id": "alice-mbp",
  "last_seen": "2026-05-11T14:23:00Z",
  "current_skill": "sd-claude-code-access",
  "pid": 41234,
  "hostname": "alice-mbp.local"
}
```

Refresh every ~60s. Stale > 5min (`SWARM_STALE_AFTER_SEC`, override in
env) → worker considered offline. A stale slot is reclaimable by a new
`swarm_join.sh` call with the same id.

## The three scripts

All live in `scripts/`. All are Bash 3.2 + python3, macOS-friendly, no
network calls.

### `swarm_join.sh <swarm-dir> <worker-id>`

Register this machine. Validates the manifest, refuses duplicate live
worker_ids, writes a heartbeat, prints `best_known_scores` so the agent
knows what to beat.

```bash
$ bash swarm_join.sh ~/Dropbox/autoresearch-swarm/main alice-mbp
[swarm_join] worker=alice-mbp registered at 2026-05-11T14:00:00Z
[swarm_join] best_known_scores (beat these):
  sd-claude-code-access: 0.91
  develop-like-sudipta: 0.42
```

### `swarm_publish.sh <swarm-dir> <skill> <target-file> <score> <scorer-mode>`

Publish one experiment result. Verifies inputs, sha256s the target,
reads local `.baselines.json` to compute `delta_from_local_baseline`,
appends a scoreboard line (under a `.swarm.lock` mkdir-lock), copies the
target into `proposals/`, and atomically updates the manifest if this
is a new global best.

```bash
$ SWARM_NOTES="added cancel-flow trigger" \
  bash swarm_publish.sh ~/Dropbox/autoresearch-swarm/main \
    sd-claude-code-access \
    ~/repo/skills/sd-claude-code-access/SKILL.md \
    0.93 wordlap
[swarm_publish] skill=sd-claude-code-access worker=alice-mbp
[swarm_publish] target_hash=sha256:a1b2c3...
[swarm_publish] score=0.930000 scorer_mode=wordlap
[swarm_publish] delta_from_local_baseline=+0.020000
[swarm_publish] proposal=.../proposals/sd-claude-code-access-a1b2c3d4-93.md
[swarm_publish] global_best_before=0.910000 -> after=0.930000 (updated=true)
```

Env overrides: `SWARM_WORKER_ID`, `SWARM_PLUGIN_ROOT`, `SWARM_NOTES`,
`SWARM_PROPOSAL_ID`.

### `swarm_merge_best.sh <swarm-dir> <skill> <local-plugin-skill-dir>`

Pick the highest-scoring experiment globally for one skill, compare to
local, and **propose** (not apply) a merge.

```bash
$ bash swarm_merge_best.sh ~/Dropbox/autoresearch-swarm/main \
    sd-claude-code-access \
    ~/repo/skills/sd-claude-code-access
[swarm_merge_best] skill=sd-claude-code-access
[swarm_merge_best] local_best=0.850000
[swarm_merge_best] global_best=0.930000
[swarm_merge_best] candidate proposal: .../proposals/sd-claude-code-access-a1b2c3d4-93.md
----- DIFF (local vs proposed) -----
--- /local/SKILL.md
+++ /proposals/sd-claude-code-access-a1b2c3d4-93.md
@@ -42,3 +42,4 @@
 ...
+- cancel flow / win-back / save offer
----- END DIFF -----

To apply, review the diff above and run:
  cp "/proposals/...md" "/local/SKILL.md"
  # then re-baseline:
  bash "/local/.../run_autoresearch.sh" "/local" --once

(v4.2 deliberately does NOT auto-apply — a buggy worker could poison
the swarm.)
```

If local ≥ global: prints "Local is current global champion".

## The "manual merge" default — and why

`swarm_merge_best.sh` deliberately does **not** apply the merge. It
prints a diff and the exact `cp` command.

The reason is failure-mode containment. Imagine a worker on someone's
laptop has a buggy `score.sh` (maybe it always returns 1.0). It
publishes a "perfect" candidate. If `swarm_merge_best.sh` auto-applied,
every other worker would silently overwrite their local target with the
buggy candidate the next time they pulled. The swarm would converge to
garbage in one wave.

v4.2's defense: a human (or a future v5.0 anti-cheat layer) vouches
for the merge. The script makes the operation cheap (one `cp`) and
visible (the diff is right there) but **deliberate**.

v5.0+ would add: signed scores, replay-on-coordinator before accepting,
diversity-bonus to reward different routes to the same answer.

## Failure modes

**Stale heartbeats.** A worker crashes mid-experiment. Its heartbeat
goes stale after 5 minutes. The next `swarm_join.sh` with the same id
reclaims the slot. No manual cleanup needed. (Tunable via
`SWARM_STALE_AFTER_SEC`.)

**Cross-FS atomic writes.** Temp-then-rename is atomic on the same
filesystem. On Dropbox/iCloud the rename happens locally, then sync
propagates; in the rare window between the publish and the sync, a
remote worker might see the manifest update before the proposal file.
The merge script tolerates this (it tries scoreboard lookup first, then
filename glob; surfaces a clear error if both fail).

**Score gaming.** Two ways: (a) a buggy or malicious scorer returns
inflated scores, (b) a worker publishes an artifact that overfits the
scorer but underperforms the real goal. v4.2 has **no defense** against
either. The "manual merge" default is the only mitigation — a human
inspects the diff before applying. v5.0+ would add coordinator-side
replay (re-run `score.sh` on a pinned env; reject if disagreement >
epsilon).

**Cross-mode scoring.** Scoreboard entries record `scorer_mode`
(`wordlap`, `regex`, `llm`, etc.). Comparing scores across modes is
meaningless. `swarm_merge_best.sh` does not yet enforce mode equality —
in v4.2, if you mix modes in the same swarm, that's on you. v5.0+: the
manifest should pin a single `scorer_mode` per skill.

**Lock contention.** Two workers publishing at the exact same instant
contend for `.swarm.lock` (a `mkdir`). The loser spins for up to ~10s
with 100ms backoff. On a shared FS this is plenty.

## Worked example: Alice and Bob, two MacBooks, one Dropbox

Day 0 — Alice initializes the swarm:

```bash
$ mkdir -p ~/Dropbox/autoresearch-swarm/main
$ cat > ~/Dropbox/autoresearch-swarm/main/manifest.json <<'JSON'
{
  "schema_version": 1,
  "swarm_name": "main",
  "created_at": "2026-05-11T12:00:00Z",
  "skills": ["sd-claude-code-access"],
  "max_workers": 4,
  "best_known_scores": {}
}
JSON
```

Day 1 — Alice joins and runs autoresearch overnight on her local repo:

```bash
$ bash swarm_join.sh ~/Dropbox/autoresearch-swarm/main alice-mbp
[swarm_join] best_known_scores: (none yet)
$ bash run_autoresearch.sh ~/repo/skills/sd-claude-code-access --budget 20
# ... loop accepts a candidate, local baseline now 0.78 ...
$ bash swarm_publish.sh ~/Dropbox/autoresearch-swarm/main \
    sd-claude-code-access \
    ~/repo/skills/sd-claude-code-access/SKILL.md 0.78 wordlap
[swarm_publish] global_best_before=none -> after=0.780000 (updated=true)
```

Day 1 — Bob, on a different MacBook, sees Dropbox sync; joins:

```bash
$ bash swarm_join.sh ~/Dropbox/autoresearch-swarm/main bob-mbp
[swarm_join] best_known_scores: sd-claude-code-access: 0.78
# Now Bob knows what to beat.
```

Day 2 — Bob's loop finds a better candidate:

```bash
$ bash swarm_publish.sh ~/Dropbox/autoresearch-swarm/main \
    sd-claude-code-access \
    ~/repo/skills/sd-claude-code-access/SKILL.md 0.86 wordlap
[swarm_publish] global_best_before=0.780000 -> after=0.860000 (updated=true)
```

Day 3 — Alice pulls Bob's improvement:

```bash
$ bash swarm_merge_best.sh ~/Dropbox/autoresearch-swarm/main \
    sd-claude-code-access \
    ~/repo/skills/sd-claude-code-access
[swarm_merge_best] local_best=0.780000 global_best=0.860000
[swarm_merge_best] candidate proposal: .../proposals/sd-claude-code-access-9a8b7c-86.md
----- DIFF -----
... Bob's edits ...
----- END DIFF -----
To apply: cp <proposal> <local-target>; re-baseline.
```

Alice reads the diff, decides she likes Bob's change, runs the `cp`,
then `run_autoresearch.sh --once` to re-baseline locally. The new local
baseline is now ≥ Bob's published score. The cycle continues.

## Future work (v5.0+)

- **Gossip protocols.** Replace shared-FS with a peer-to-peer overlay
  (libp2p or similar). Workers exchange scoreboard deltas. No central
  store.
- **Work allocation.** Coordinator hands out (skill, hypothesis-seed)
  tuples to workers so two workers don't waste cycles trying the same
  thing. Wave-based scheduling.
- **Anti-cheat.** Signed scores (worker pubkey), coordinator-side
  replay of `score.sh` on a pinned env, statistical detection of
  outlier scorers, diversity-bonus to reward different routes.
- **Auto-merge.** With anti-cheat + replay, the v4.2 manual-merge
  default can flip to "auto-merge if coordinator-replayed score ≥
  global best by ε".
- **Multi-target candidates.** v4.x is single-file diff. Multi-file
  changes become tractable once anti-cheat exists.

## Current state (v4.2)

What ships:
- The 3 scripts (`swarm_join`, `swarm_publish`, `swarm_merge_best`)
- The JSON schema (`assets/scoreboard_schema.json`)
- 7-case smoke test (`evals/test_swarm.sh`)
- This doc

What does **not** ship:
- A coordinator or network service
- Work allocation between workers
- Anti-cheat, signed scores, replay
- Auto-merging

The scaffolding is enough to run a real swarm with people you trust,
synced via Dropbox/iCloud/NFS. Anything more ambitious is v5.0.
