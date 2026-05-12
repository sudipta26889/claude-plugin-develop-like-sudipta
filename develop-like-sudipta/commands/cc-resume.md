---
description: Resume a previous Claude Code run after Cowork crash or session restart — reconstruct state from .cc/state.json + git log, decide whether to continue or replan
argument-hint: <workspace-path>
---

Resume a previously running Claude Code session at `$1`.

**You MUST invoke the `sd-claude-code-access` skill first** — specifically `references/state_and_resume.md`. Do not start sending keystrokes until the reconstruction step is done and the user has confirmed.

## Resume protocol

0. **Substrate detection (MANDATORY first step).** Read `skills/sd-claude-code-access/references/substrate_and_access.md`. Probe MCP availability and choose Path A (`Desktop_Commander`) / B (`computer-use` with `request_access` for Terminal at tier "click") / C (manual). Surface the chosen path to the user. Without this, you cannot honestly resume anything — you don't know how you'll reach the Mac.
1. **Read the skill's `references/state_and_resume.md`** to understand the resume contract.
2. **Run diagnose** per chosen path:
   - Path A: `mcp__Desktop_Commander__start_process(command="bash ~/.cache/ccbridge/diagnose.sh \"$1\"")`
   - Path B/C: ask user to run `bash ~/.cache/ccbridge/diagnose.sh "$1"` and paste output.
3. **Reconstruct state** — read the tail of `$1/.cc/state.json`:
   ```bash
   tail -30 "$1/.cc/state.json"
   ```
4. **Cross-reference state events with git** — `git -C "$1" log --oneline -20`. Were the last commits the expected output of the last phase the state log mentions?
5. **Check the driver lock** — `bash ~/.cache/ccbridge/lock.sh status "$1"`. If held by a live pid on this host: ABORT and tell the user. If stale (dead pid): take it.
6. **Read the last `.cc/phase-N.md`** to know what was in flight.
7. **Check browser-test state** — look in `$1/docs/e2e-testing/` for the most recent `phase-N-*.md`. Was it green, red, or never run?
8. **Tell the user your reconstruction** in a short paragraph:
   - Last completed phase: …
   - Last state event: …
   - Last browser-test status: …
   - Driver lock state: …
   - Recommendation: resume from phase X / replan from phase Y / abort.
9. **Wait for confirmation.** Do not proceed until the user says go.
10. **Once confirmed:** acquire lock, start watchdog, write the next directive, send the trigger, resume the per-phase loop including the browser-test step.

    **Re-enter the v5.0.3 continuous-manager loop** — don't end your turn until one of: `job_complete`, `<workspace>/.cc/monitor.stop` exists, or 3 consecutive failed unblock attempts on the same fingerprint. A resumed session inherits the same no-sleep contract as a fresh `/cc-drive` run: poll, decide, act, repeat. See `skills/sd-claude-code-access/SKILL.md` `## Continuous-manager doctrine` for the full contract (end-of-turn conditions, polling cadence, unblock escalation).

## Edge cases

- **Stale `.driver.lock` from this same host but dead pid** — take it.
- **Lock held by a live pid on this host** — second Cowork is driving the same workspace; abort.
- **`state.json` missing** — `WORKSPACE` was not set on the previous run; reconstruct from `git log` + recent `docs/e2e-testing/` mtimes.
- **Last browser test was red and never re-run** — propose to re-trigger the fix loop before advancing.
- **Disagreement between state.json and git** — trust git, update state.json with a corrective event, surface the discrepancy.

Now begin: diagnose, reconstruct, propose. Don't touch the keyboard until the user confirms the plan.
