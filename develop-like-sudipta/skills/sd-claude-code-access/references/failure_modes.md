# Failure modes & recoveries

A catalog of failure modes that have actually happened, and the procedure for each. Read this once before your first run; refer back when something's misbehaving.

## Paste truncation / silent loss

**Symptoms:**
- Long markdown paste appears to succeed but CC's response shows it processing only the first line.
- `read_history.sh | grep -F "$UNIQUE_FRAGMENT_FROM_MIDDLE"` returns nothing.
- CC asks "what did you mean by X?" where X is something you DID specify in the message.

**Causes:**
- TUI input box wraps/truncates around its width column
- Cmd+A/Delete failed (because Cmd+A doesn't always select-all in CC's TUI), so the paste appended to existing text and the combined message overflowed the input field
- Focus changed between osascript invocations (split-osascript bug — fixed in `send.sh`)

**Recovery:**
1. Don't try to re-paste — switch to file-based directive immediately
2. Write the content to `<workspace>/.cc/phase-N.md`
3. Send a tiny trigger: `Read \`.cc/phase-N.md\` and proceed.`

## Watchdog missing prompts

**Symptoms:**
- Permission prompt visible on screen ("Do you want to proceed?")
- `/tmp/ccbridge/watchdog.log` shows no recent activity
- CC stalls

**Causes:**
- New CC version added a prompt format the regex doesn't match
- Watchdog process died silently
- watchdog is running but its `last_seen` fingerprint locked onto a prior identical screen

**Recovery:**
1. Check it's running: `pgrep -f /tmp/ccbridge/watchdog.sh`
2. Tail the log: `tail -20 /tmp/ccbridge/watchdog.log`
3. If pattern is new, edit the regex in `watchdog.sh` and restart:
   ```bash
   bash /tmp/ccbridge/stop_watchdog.sh
   bash /tmp/ccbridge/start_watchdog.sh
   ```
4. Manually press the right key to unblock the immediate prompt:
   ```bash
   /tmp/ccbridge/keys.sh return    # for default-Yes prompts
   /tmp/ccbridge/keys.sh down && /tmp/ccbridge/keys.sh return  # for option 2
   ```

## CC genuinely hung

**Symptoms:**
- Same time-elapsed counter for >10 min in CC's status line
- Token-upload counter not advancing
- No new commits via `git log`
- Buffer hash unchanged via repeated `read.sh`

**Cause:** A long-running tool call (often pytest in a complex docker setup, or a Vertex API timeout) wedged.

**Recovery:**
1. Press Esc once to interrupt: `/tmp/ccbridge/keys.sh esc`
2. CC will display "Interrupted · What should Claude do instead?" and pick up your queued message (if any)
3. If the queued message was the right next instruction, do nothing
4. Otherwise send a clarifying message: "The pytest call hung. Skip the slow integration tests for now (`pytest -m 'not slow'`) and continue."

The bundled `nudge_if_stuck.sh` automates detection. Run it as a background watchdog companion if you're away.

## Cross-machine setup confusion

**Symptoms:**
- Cowork on one machine (e.g., `Sudipta-MBA-M4`)
- CC on another (e.g., `Sudipta-MBP-M1-Max` via SSH)
- `claude` not on PATH from Cowork's shell
- `~/.claude/projects/...` doesn't have the project

**Cause:** The two machines have separate `~/.claude` storage. Cowork's `claude --continue` would start a NEW session, not resume CC's.

**Recovery:** see `ssh_variant.md` — bridge over SSH using headless `claude -p -c` invocations on the remote machine.

## .cc directives accidentally committed

**Symptoms:**
- `git log` shows a commit with `.cc/phase-*.md` files
- `STATUS.md` references the directives as if they were docs

**Recovery:**
1. Add `.cc/` to `.gitignore` if not already
2. `git rm --cached .cc/*.md` and commit
3. Force-pushing only if the branch hasn't been merged

This was caught in real runs by Phase 6 — easy to fix forward.

## Multiple Terminal tabs/windows

**Symptoms:**
- Keystrokes go to a different tab than CC
- `read.sh` returns content from the wrong tab

**Cause:** `selected tab of front window` — if the user clicks on a different tab/window, that becomes "selected".

**Recovery:**
1. Verify which tab is selected:
   ```bash
   osascript -e 'tell application "Terminal" to return name of selected tab of front window'
   ```
2. If wrong, ask the user to click on the CC tab and bring its window forward
3. Optionally reduce risk: ask the user to maintain a single Terminal window for the session

## CC permissions changed mid-session

**Symptoms:**
- Watchdog suddenly approves prompts that change behavior
- New prompt formats appear

**Cause:** CC version update auto-installed during the session, or the user toggled something in `/config`.

**Recovery:**
1. Read CC's status line for version: should match what it was at session start
2. If version changed, check `claude --version` and update watchdog regex if needed
3. If permissions toggled, the user usually intends it — confirm with them before disabling watchdog

## Permission denied for AppleScript

**Symptoms:**
- `osascript` returns "execution error: System Events got an error: Not authorized"

**Cause:** macOS Privacy & Security → Accessibility doesn't include the Cowork process or Terminal where you're running bash.

**Recovery:**
1. Open System Settings → Privacy & Security → Accessibility
2. Add the relevant app (usually Terminal.app, sometimes the IDE running Cowork)
3. Restart the affected app
4. Re-run the failing command

## Clipboard collision

**Symptoms:**
- Paste verification passes but the content seems off
- User complains their clipboard contents got overwritten

**Cause:** The bridge uses `pbcopy` which clobbers the user's clipboard.

**Mitigation (already in send.sh): none, but you can add:**
```bash
# Save & restore clipboard
SAVED=$(pbpaste)
printf '%s' "$MSG" | pbcopy
# ... do the paste ...
sleep 1
printf '%s' "$SAVED" | pbcopy
```

Trade-off: the user's old clipboard is restored even if they copied something during your send. Most users don't notice the brief overwrite. Skip unless the user complains.

## Slack channel allowlist out of sync

(Not a bridge issue, but it's bitten enough times to mention.)

**Symptoms:** CC writes captured-mention rows but the channel ID doesn't match the database.

**Cause:** Test seeded a channel with a slug that doesn't match the test event payload.

**Recovery:** standard pytest debug — read the test fixture, fix the seed slug. Not a manager-level concern; CC handles it.
