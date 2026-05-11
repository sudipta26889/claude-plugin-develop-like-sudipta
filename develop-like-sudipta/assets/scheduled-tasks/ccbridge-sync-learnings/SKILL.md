---
name: ccbridge-sync-learnings
description: Periodic SSH-rsync of peer Macs' learning tails into local remote-<host>/ namespace. Runs every 6 hours when peers.json is configured. (subscription, no ANTHROPIC_API_KEY)
---

You are `ccbridge-sync-learnings`. You run every 6 hours as a Cowork scheduled
task. Your job: pull peer Macs' learning tails into this Mac's
`~/.cache/ccbridge/learnings/remote-<host>/` so the local autoresearch loop
sees cross-MACHINE signal, not just cross-project.

The heavy lifting is `~/.cache/ccbridge/sync_learnings.sh` (rsync over SSH).
This SKILL is the per-fire wrapper: probe → run → report.

## Substrate

`mcp__Desktop_Commander__*` for shell ops. The peer pull uses `ssh` + `rsync`
(both ship with macOS); Cowork's sandbox bash cannot reach `~/.cache/` or open
outbound SSH connections, so every shell step goes through Desktop_Commander.
Subscription Claude — DO NOT call `api.anthropic.com`.

## Procedure (each fire — must finish in <30s of agent work)

### Step 1 — probe: any peers configured?

```
test -f ~/.cache/ccbridge/peers.json
```

If absent: write a one-line `[sync-learnings] no peers configured (skip)` log
and exit. The user opted out of multi-machine sync — don't ssh into the void.

If present but `.peers` is empty: same behavior; treat as opt-out.

### Step 2 — run the sweep

Invoke the canonical bridge-dir script (NOT a plugin-relative path — that path
would break the moment the plugin is reinstalled elsewhere on the user's Mac):

```
bash ~/.cache/ccbridge/sync_learnings.sh
```

This sweeps every peer in `peers.json`. The script:

- Is best-effort across peers — one peer offline / DNS-fail / key-missing
  doesn't abort the remaining peers; the sweep accumulates a non-zero rc and
  exits with it. You log the rc but DO NOT escalate (peer downtime is
  expected; the user investigates when it's persistent).
- Uses `BatchMode=yes` so SSH never prompts for a password. If the user
  didn't run `ssh-copy-id <peer>` once before turning on the scheduled
  task, the peer will silently fail to authenticate. The setup is documented
  in `references/multi_machine.md`; this task does NOT attempt to fix it.

### Step 3 — show per-peer counts

Parse the script's output for `[sync] done: <host> (<N> file(s))` lines and
present a compact summary in your report:

```
[sync-learnings] peers swept: 2
  - m1-max.local: 14 tail(s) pulled
  - old-mini.local: 0 tail(s) (peer unreachable)
```

If everything succeeded (exit 0): one-line `[sync-learnings] OK <N> peers,
<M> tail(s) total` summary. The aggregator (`ccbridge-aggregate-learnings`,
runs nightly at 02:15) will walk the new `learnings/remote-*/` tails on its
next fire.

### Step 4 — exit cleanly

Per-fire wall-clock cap: stop after 25s of agent work even if peers are slow.
The next 6-hourly fire will retry; the underlying rsync is incremental
(`--update`) so partial-sync state is durable across reruns.

## Don't

- **Don't call `ssh-keygen` or modify `~/.ssh/config`.** Peer SSH setup is a
  one-time manual step the user runs (see `references/multi_machine.md`).
  A scheduled task that mutates SSH config without consent is a security
  smell.
- **Don't add peers to `peers.json` automatically.** If the user wants to
  add a Mac, they edit the file. Auto-discovery (mDNS, bonjour, etc.) is
  out of scope and would risk pulling from unintended hosts.
- **Don't bidirectionally sync.** Phase 6 is local-pulls-remote only. Each
  machine pulls peers independently; nothing is pushed. This keeps the
  trust model simple: every machine owns its own learning history.
- **Don't escalate on transient peer offline.** Macs sleep, networks blip,
  laptops travel. A single failed sweep is noise; persistent failures across
  many fires would warrant a separate keepalive-style watchdog (out of scope
  for this task).
- **Don't burn quota when no peers are configured.** Step 1's early-exit
  is mandatory — the user explicitly opted out.
