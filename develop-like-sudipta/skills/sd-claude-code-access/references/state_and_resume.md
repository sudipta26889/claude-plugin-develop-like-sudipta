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
