# State tracking and resume-after-crash

When a Cowork session driving CC dies mid-run (network blip, sandbox restart, browser crash), the watchdog keeps approving prompts but no human-equivalent is reading checkpoints or sending the next phase trigger. To recover, a fresh Cowork session needs to know exactly where the run was when the previous session died.

That's what `<workspace>/.cc/state.json` is for.

## What gets written

The bundled `state.sh` appends one JSON object per line (JSONL) for every important event:

```jsonl
{"ts":"2026-05-09T19:23:12Z","event":"watchdog_started","pid":"81234"}
{"ts":"2026-05-09T19:23:18Z","event":"phase_start","phase":"7"}
{"ts":"2026-05-09T19:23:50Z","event":"prompt_approved","fp":"a1b2c3d4"}
{"ts":"2026-05-09T19:24:10Z","event":"prompt_approved","fp":"e5f6g7h8"}
{"ts":"2026-05-09T19:30:01Z","event":"phase_complete","phase":"7","commits":"5","tests":"280"}
{"ts":"2026-05-09T19:30:15Z","event":"message_sent","len":"387","frag":"Phase 7 approved..."}
{"ts":"2026-05-09T19:31:42Z","event":"phase_start","phase":"8"}
```

Events captured automatically:
- `watchdog_started`, `watchdog_stopped` (when start_watchdog.sh / stop_watchdog.sh sees `$WORKSPACE`)
- `prompt_approved` — every time the watchdog presses Enter on a permission prompt
- `danger_blocked` — every time the watchdog refuses to auto-approve due to a danger pattern
- `nudge_sent` — when nudge_if_stuck.sh detects a hang and presses Esc
- `message_sent`, `message_send_failed` — when send.sh runs (verified or failed)

Events you should write manually (or have CC's directives instruct it to write):
- `phase_start`, `phase_complete` — bracket each phase you trigger
- `checkpoint_paused` — when CC pauses for review
- `directive_authored` — when you finish writing `.cc/phase-N.md`

## Resume probe

When picking up a session, run:

```bash
WS=/path/to/workspace
echo "Last 20 events:"
tail -20 $WS/.cc/state.json
echo
echo "Last phase started:"
grep '"event":"phase_start"' $WS/.cc/state.json | tail -1
echo
echo "Phases completed:"
grep '"event":"phase_complete"' $WS/.cc/state.json | wc -l
echo
echo "Recent danger blocks:"
grep '"event":"danger_blocked"' $WS/.cc/state.json | tail -5
```

Reconstructs the run state in <3 seconds.

## Manual annotation

Inside Cowork bash:

```bash
~/.cache/ccbridge/state.sh /path/to/workspace phase_start phase=8
```

Or with multiple key=value pairs:

```bash
~/.cache/ccbridge/state.sh /path/to/workspace phase_complete \
  phase=8 commits=4 tests=296 elapsed=14m
```

## Salvage — recovering a corrupted state.json

state.json writes are append-only (`echo "$JSON" >> "$F"` in `state.sh`), but they aren't atomic. If a writer is killed mid-flush — Cowork sandbox forcibly restarted, OOM, host crash — the tail of the file may be truncated, or a later writer's offset may have landed past trailing junk. When that happens `cc-resume` fails with an opaque parse error and the run looks dead.

The fix is `state_salvage.sh`, bundled alongside `state.sh`.

### When to invoke

- `cc-resume` reports `.cc/state.json` is malformed (JSON parse failure, unexpected EOF, etc.).
- A Cowork session was forcibly killed and you don't yet know whether the tail was flushed cleanly.
- `tail -5 $WS/.cc/state.json` shows a half-written line.

It's also safe to run prophylactically before any resume — the script is idempotent and a no-op when the file is already clean.

### Invocation

```bash
bash ~/.cache/ccbridge/state_salvage.sh /path/to/workspace
```

(Single positional arg: the workspace whose `.cc/state.json` you want to clean. No flags.)

### What it does

1. If `.cc/state.json` is missing → prints `no state.json to salvage` and exits 0.
2. If the file is over the 100MB safety cap → refuses (logs to stderr) and exits 2. Inspect manually.
3. If the file is empty or every line already parses as JSON → prints `state.json clean, nothing to do` and exits 0. The file is left untouched and no backup is made.
4. Otherwise:
   - Copies the original to `.cc/state.json.bak.<UTC-timestamp>` (e.g. `state.json.bak.20260509T193015Z`).
   - Walks the file line-by-line, keeping each line that `python3 -c "import json; json.loads(...)"` accepts; dropping the rest.
   - Atomically replaces `.cc/state.json` with the cleaned version.
   - Prints `<N> events salvaged, <M> dropped (saved backup: <path>)` and exits 0.

### Reading the output

```
3 events salvaged, 2 dropped (saved backup: /workspace/.cc/state.json.bak.20260509T193015Z)
```

- `N events salvaged` — how many lines survived. Compare against the pre-salvage line count (`wc -l` on the backup) to confirm the drop fraction is small. If salvage kept 3 lines out of 200, something more than a tail truncation went wrong; treat the backup as suspect.
- `M dropped` — how many lines were rejected. Typically 1 (truncated tail). Anything in double digits warrants inspecting the backup with `python3 -c "import json,sys; [json.loads(l) for l in sys.stdin]" < backup`.
- Backup path — keep it. `state_salvage.sh` doesn't rotate or delete old `.bak.*` files; they're cheap and useful if you ever need to reconstruct manually.

### When salvage isn't enough

If the surviving events look wrong (out-of-order timestamps, missing `phase_start`/`phase_complete` pairs, fingerprints from a different run), state.json alone can't be trusted. Reconstruct from two more reliable sources:

1. **CC's commits — `git log --oneline --since='1 day ago' --all`.** Each phase ends with a commit (or several). The commit messages tell you which phase finished and roughly when. This is the ground truth for "what code exists."
2. **Cowork's directives — `ls -lt $WS/.cc/phase-*.md`.** Each `phase-N.md` you authored corresponds to a `phase_start` you intended to send. Compare the file list against the `phase_start` events in the salvaged state.json.

From those two together you can hand-author a minimal state.json containing just the high-water `phase_start` and `phase_complete` events and resume.

See [`failure_modes.md`](./failure_modes.md) for the broader catalog of recovery procedures.

### Idempotency

Re-running `state_salvage.sh` on an already-clean file is safe and cheap — it exits 0 with `state.json clean, nothing to do` and leaves the file untouched. Bake it into resume scripts if you want belt-and-suspenders.

## What state.json is NOT

- **Not the source of truth for the codebase** — that's git. state.json captures *bridge* events.
- **Not authoritative on phase completion** — verify with `git log --oneline` and `audit.sh`. state.json reflects what we *thought* happened, not what's actually committed.
- **Not safe to delete during a run** — it's append-only and consulted by run_summary.sh + diagnose.sh.

## Garbage collection

After a run completes (and `run_summary.sh` has been generated), state.json can be archived:

```bash
mv $WS/.cc/state.json $WS/.cc/runs/state.json.$(date +%Y%m%d-%H%M%S)
```

The next run starts fresh.
