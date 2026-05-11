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

## Watchdog refused a routine prompt — what to do

**Symptoms:**
- Watchdog log shows `DANGER fp=... matched=<pattern> - REFUSING to auto-approve`
- The actual prompt on screen is something routine (e.g., reading a file, running tests) that you'd normally approve
- The run is stalled — CC is waiting for Enter, watchdog won't press it
- `<workspace>/.cc/escalations.log` has a fresh entry (this is the canonical signal — escalations.log is the on-disk receipt every refusal writes)

**Cause:** A danger pattern matched a routine prompt. Two flavours:

- **False positive in the pattern** — the regex was too loose (e.g., `delete` matched a noun in surrounding documentation, not a verb in a command). This is what the audit script's "loose" verdict warns about; see `danger_pattern_governance.md`.
- **Phrasing ambush** — the rendered Terminal buffer contained words that *look* destructive but weren't part of the proposed action (e.g., the file being edited has `rm -rf` in a code comment). The watchdog matches against the whole visible buffer, not just the command.

**Recovery:**

| Step | What | Why |
| ---- | ---- | --- |
| 1 | `tail -20 <workspace>/.cc/escalations.log` | See timestamp, matched pattern, and prompt snippet. Confirms whether the refusal was recent and what triggered it. |
| 2 | Read the actual buffer (`~/.cache/ccbridge/read.sh` or visually) | Decide: is this truly routine, or did the pattern catch something genuinely risky? |
| 3 | Manually press Enter if routine: `~/.cache/ccbridge/keys.sh return` | Unblock the immediate run. CC will resume. |
| 4 | Decide the longer-term fix (see below) | One press doesn't prevent the next stall. |
| 5 | Re-run `scripts/audit_danger_patterns.sh` after editing | Confirm the change moves the pattern from "loose" to "healthy" and didn't kill destructive coverage. |

**Longer-term fix — pick one:**

- **The pattern itself is wrong.** Edit `scripts/danger_patterns.txt` to tighten it. Add a routine fixture in `evals/test_danger_patterns.sh` AND `scripts/audit_danger_patterns.sh` that captures the false positive, so the regression is locked in. See the "Required process to add a pattern" section of `danger_pattern_governance.md` — same discipline applies to tightening an existing one.
- **The pattern is fine globally, but this project needs an exception.** Add an allow-comment to `<workspace>/.cc/danger_patterns_extra.txt`:
  ```
  # allow: <pattern> false-fires on our internal phrasing — example: ...
  ```
  This doesn't actually carve out an exception (extras are union-only, not subtraction) — but it documents the decision for the next operator. The real action is still tightening the global pattern.
- **The phrasing ambush is genuinely unavoidable.** Some buffers will look scary. The watchdog erring on the side of "wake the human" is the correct trade-off; just press Enter and move on. Log it in `escalations.log` notes for the quarterly review.

**Don't:**

- Don't disable the watchdog because one prompt was a false positive — that's how `rm -rf /` ships to prod.
- Don't add a workspace exception without also fixing the global pattern. The next workspace will hit the same false positive.
- Don't ignore repeated entries in `escalations.log`. Three of the same pattern in a week means the audit script will likely flag it as loose next quarter — fix it now.

**Wire up notifications (optional but recommended):**

Export `ESCALATE_CMD` before starting the watchdog to get pushed alerts. The escalate payload contains literal newlines and may contain quotes — so anything pushing it as JSON MUST encode it via `jq` (or equivalent). Naively interpolating `$(cat)` into a JSON string produces invalid JSON the moment the payload contains a newline or a `"` character.

```bash
# ntfy.sh — accepts plain text, no JSON encoding needed
export ESCALATE_CMD='curl --data-binary @- https://ntfy.sh/your-private-topic'

# Slack webhook — payload MUST be JSON-encoded. `jq -Rs '{text: .}'` reads
# stdin raw (-R) and slurps the whole thing into one JSON-encoded string
# (-s), producing valid JSON regardless of newlines/quotes in the payload.
# Requires jq (brew install jq).
export WEBHOOK_URL='https://hooks.slack.com/services/...'
export ESCALATE_CMD='jq -Rs "{text: .}" | curl -X POST -H "Content-Type: application/json" --data-binary @- "$WEBHOOK_URL"'

~/.cache/ccbridge/start_watchdog.sh
```

`escalate.sh` will still write `escalations.log` as the local audit trail; `ESCALATE_CMD` is additive.

Cross-link: `danger_pattern_governance.md` covers the deny-list discipline; this section is about what to do when discipline fails in practice.

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
