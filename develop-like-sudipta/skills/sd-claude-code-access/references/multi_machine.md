# Multi-machine learnings sync

## Why this exists

The plugin's autoresearch loop already handles **cross-project** signal: every
workspace on this Mac writes to `~/.cache/ccbridge/learnings/<ws_id>.jsonl`,
the nightly aggregator merges them, and the weekly distillation flags
signatures that appear in ≥2 workspaces as systemic (vs idiosyncratic).

But "every workspace on this Mac" is still one machine. If you've got an M4
and an M1 Max — or a personal Mac plus a Mac mini in the closet — each
accumulates its own learning history. The autoresearch loop sees neither
half's data when run on the other. A signature that shows up on **both
machines** is much stronger evidence of a plugin-level issue than one that
only shows up locally: different hardware, different installs, different
project mixes converging on the same pattern.

Multi-machine sync is how those signals cross the air gap.

## SSH setup

Each Mac that wants to pull peer data needs passwordless SSH into the peers
it'll sync FROM. One-time setup per peer pair:

```bash
# On the LOCAL Mac (the one running the scheduled task)
ssh-keygen -t ed25519 -C "ccbridge-sync@$(hostname -s)"   # if no key yet
ssh-copy-id <peer-host>                                   # prompts for password ONCE
ssh -o BatchMode=yes <peer-host> 'echo ok'                # confirm passwordless
```

`sync_learnings.sh` invokes ssh with `BatchMode=yes`, so any peer that still
requires a password gets silently refused. The `echo ok` smoke test catches
this before the scheduled task starts swallowing the failure on cron time.

You only need keys in one direction (LOCAL → PEER). Each Mac independently
pulls from its peers — nothing is pushed.

## `peers.json` schema

`~/.cache/ccbridge/peers.json`:

```json
{
  "version": 1,
  "peers": ["m1-max.local", "old-mini.local"]
}
```

Hostnames as the user types them on the command line. Anything `ssh <host>`
resolves on this Mac is fine: `.local` mDNS names, `/etc/hosts` aliases,
DNS-A records, IP addresses, or full `user@host:port` forms. The sync script
passes them through verbatim.

Empty `peers` array (or absent file): no sync happens. The scheduled task's
Step 1 early-exits cleanly.

## Privacy

What gets synced:

- **Per-workspace `.jsonl` tails** from `~/.cache/ccbridge/learnings/*.jsonl`.
  Each tail is a list of timestamped learning events: category, signature
  fields, fingerprints. Workspace identity travels as a sha256-of-path
  hash (`ws_id`), not as the raw workspace path.

What does NOT get synced (intentionally local-only):

- `aggregated/*.jsonl` — derived locally from each Mac's tails. Different
  Macs will compute different aggregates from different inputs; mixing them
  would double-count events.
- `distillation/*.md` — the proposer's priors. Local to each Mac so each
  one's autoresearch loop can experiment independently.
- `projects.json` — the registry of workspaces on this Mac. Raw paths live
  here; they don't leave.
- `.aggregate_cursor` — incremental sweep cursor. Local-only by definition.

The hash-not-path approach means a workspace called
`~/Workspace/personal/secret-side-project/` shows up on every peer as
`5e1f3a...`, not as the directory name. The directory name never enters the
sync.

## Bandwidth

Typical sizes:

- One `.jsonl` tail: **tens of KB to a few MB**. A heavily-used workspace
  with a year of daily activity might reach 5–10 MB.
- One Mac's full learnings dir: **<100 MB** for typical use.
- Per sweep: `rsync --update` only transfers the delta since last sync, so
  steady-state cost per 6-hour fire is a few MB at most.

Over a residential network this is invisible. Over LTE / metered links the
6-hour cadence keeps daily transfer well under 50 MB even in worst case.

The `--az` flags compress in transit and preserve modification times, which
keeps `--update` accurate across re-runs.

## Quota

The sync itself is **non-Claude**: just `rsync` + `ssh` shell-outs. No
`api.anthropic.com` calls. Zero Anthropic-quota cost.

The `ccbridge-sync-learnings` scheduled task IS a Cowork agent firing every
6 hours, so it consumes a tiny amount of subscription budget for the
**reasoning step** (probe → invoke → report). The agent's work is bounded
to <2000 tokens per fire by design — the heavy lifting is the shell script,
not the agent.

If you're on Pro and tight on budget, the once-every-6-hours cadence is
already conservative. You can stretch it to every 12 hours (`0 */12 * * *`)
or daily (`0 4 * * *`) by passing a custom cron to
`mcp__scheduled-tasks__create_scheduled_task` — `/ccbridge-init` preserves
user-customized crons across re-runs.

## Failure modes

Per-fire failure modes, all best-effort:

- **Peer offline** — ssh ConnectTimeout=5 fires, the script logs
  `(or peer unreachable)` and moves to the next peer. The local autoresearch
  loop just doesn't get fresh data from that peer this cycle; the next sweep
  retries.
- **Peer SSH key not set up** — `BatchMode=yes` causes immediate auth
  failure, same handling as offline. Once you run `ssh-copy-id <peer>`, the
  next sweep picks up where it left off (rsync `--update` is incremental;
  nothing is lost).
- **Disk full on local Mac** — rsync writes fail mid-transfer. The script
  prints `[sync] WARN: rsync failed for ...` and continues. Next fire
  re-attempts after the user frees space. No silent data loss; partial
  files are rewritten cleanly.
- **`peers.json` malformed** — Python json-parse fails in the sweep dispatch.
  The script exits with the parse error in stderr; the scheduled task's
  report surfaces it on the next fire. Fix: validate with
  `python3 -m json.tool ~/.cache/ccbridge/peers.json`.
- **Local rsync missing** — won't happen on modern macOS (rsync ships
  built-in), but on a stripped install: the script would error at the first
  rsync invocation. Install via Homebrew: `brew install rsync`.
- **One peer's failure does NOT abort the sweep.** The sweep mode wraps each
  per-peer call in `|| rc=$?` so the script reaches every peer and exits with
  the worst rc. Cowork's scheduled-task report shows which peers succeeded
  and which didn't.
