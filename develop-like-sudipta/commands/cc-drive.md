---
description: Start driving a Claude Code session end-to-end — install bridge, watchdog, write directives, run phased implementation with per-phase browser verification
argument-hint: <workspace-path> [optional: terminal-app, dev-server-url]
---

Drive a Claude Code (CC) terminal session at `$1` from start to finish.

**You MUST invoke the `sd-claude-code-access` skill before doing anything else.** That skill carries the full methodology — bridge install, watchdog, directive patterns, browser-test loop, Playwright generation, resume-after-crash, state events. Do not improvise; follow the skill.

## Workflow

0. **Substrate detection (MANDATORY first step).** Read `skills/sd-claude-code-access/references/substrate_and_access.md`. Probe MCP availability:
   - `mcp__Desktop_Commander__*` present → **Path A** (preferred).
   - `mcp__computer-use__*` present → **Path B** (fallback). Call `mcp__computer-use__request_access(applications=["Terminal"])` and verify tier="click".
   - Neither → **Path C** (manual; surface commands to user).
   Tell the user which path was chosen and why, **before** running anything on their Mac.
1. **Read the skill** — open `skills/sd-claude-code-access/SKILL.md` and follow its pre-flight checklist (Step 0 already covered above).
2. **Diagnose** — run per chosen path:
   - Path A: `mcp__Desktop_Commander__start_process(command="bash ~/.cache/ccbridge/diagnose.sh \"$1\"")`
   - Path B/C: ask user to run `bash ~/.cache/ccbridge/diagnose.sh "$1"` and paste output
   If anything's red, fix before proceeding.
3. **Install bridge if needed:**
   - Path A: `mcp__Desktop_Commander__start_process(command="bash <plugin-skill-path>/scripts/install.sh")`
   - Path B/C: display the install command, wait for user to confirm done.
4. **Acquire driver lock + start watchdog:**
   - Path A: `mcp__Desktop_Commander__start_process(command="WORKSPACE=\"$1\" bash ~/.cache/ccbridge/start_watchdog.sh", background=true)`
   - Path B/C: display command, wait for user to run it.
5. **Brainstorm with the user** — use `superpowers:brainstorming` if a clear spec doesn't already exist.
6. **Write the implementation plan** — use `superpowers:writing-plans`. Save under `$1/docs/plans/`.
7. **Pre-write all phase directives** to `$1/.cc/phase-N.md` using `assets/directive_template.md`.
8. **Per-phase loop:**
   - Trigger CC: `Read \`.cc/phase-N.md\` and proceed.`
   - Poll every 2–5 min.
   - At checkpoint: `audit.sh`, read diff.
   - **Verify gate (mandatory)** — run static checks + project test suite per `references/verify_gate.md`. Auto-detect runners (pytest/jest/vitest/cargo/go test/maven). Read `<workspace>/.cc/config.json` for overrides. **Fail-fast** — first red command stops the chain; don't open Chrome.
   - **Browser-test step** — only if verify-gate green: invoke the post-phase Claude-in-Chrome flow per `references/browser_testing.md`. Write `docs/e2e-testing/phase-N-<slug>.md` + emit `docs/e2e-testing/specs/phase-N.spec.ts`.
   - **Bug found protocol (if ANY red — unit OR browser):** apply `references/bug_driven_tdd.md` strictly. Capture evidence into `.cc/bugs/<bug-id>.md`. Write NEW failing unit test + NEW failing browser test step. Confirm both red. Then write `.cc/phase-N-fix.md` referencing both tests by path; send to CC. After CC's fix: re-run new unit → new browser → FULL verify-gate → original phase test (four greens, in order). Loop if any red; escalate after 3 failed attempts.
   - Log `state.sh phase_complete` only when ALL greens are confirmed.
   - Advance only on green.
9. **End-of-run** — `/e2e-suite` to stitch the umbrella suite, `run_summary.sh` for the session record, stop watchdog, release lock.

## Permissions you have up-front

- Auto-approve routine permission prompts via watchdog.
- Refuse anything matching `scripts/danger_patterns.txt`.
- Use subagents for parallel audit / polling / directive-drafting where it saves context.
- Write to `$1/.cc/` (must be gitignored — Phase 1 task adds this if missing).

## Continuous-manager doctrine (v5.0.3 — the no-sleep contract; read FIRST)

You (Cowork) are the manager. **You never end your turn while an active job exists.** The cc-orchestrator scheduled task fires once per minute but its 60s fire-gap leaves windows where nothing is watching; the manager covers those windows by staying in the single turn.

**End-of-turn conditions (the only five):**
1. `state.sh job_complete` event lands in `<workspace>/.cc/state.json`.
2. `done_criteria` from `active-job.json` is satisfied.
3. `<workspace>/.cc/monitor.stop` file appears (user kill switch).
4. The user EXPLICITLY tells you to stop in plain language.
5. **3 consecutive failed unblock attempts** on the same prompt fingerprint — surface as `BLOCKED:` summary.

Outside those five, returning to the user is the anti-pattern.

**Per-cycle actions inside the turn (every 30-60s):**

- **Read CC buffer** via `read.sh`. If `❯ N. <text>` line detected → invoke `unblock_cc.sh` directly. **Don't wait for the orchestrator's next fire** (up to 60s of latency).
- **Check `git log`** for new commits since job-start sha.
- **Read `.cc/state.json` tail** — if `phase_complete N` seen and `phase-(N+1).md` exists, send phase trigger manually via `send.sh` rather than waiting for the orchestrator. Manual phase trigger is acceptable when faster than the orchestrator's fire-gap.
- **Trigger the next phase automatically** when the current phase emits `phase_complete`. Don't ask the user "should I proceed?" — the plan is the answer; advance unless a phase is genuinely red.
- **Sleep 30-60s** then repeat. Never end the turn between cycles.

**Parallel work the manager can do inside the turn** (without pausing CC):

- Bug-driven TDD fixes to plugin scripts/SKILLs when bugs surface during the run.
- Audit checkpoints (`audit.sh`) at each phase boundary.
- Live SKILL refresh (assets/ + ~/Documents/Claude/Scheduled/ + MCP update_scheduled_task — three places in one batch).

**The CC side mirrors this contract** — see the "Operating mode" section that the directive template injects into every per-phase directive. CC also doesn't wait for pings within a phase.

If you find yourself ABOUT to ask the user "want me to continue?", stop and instead: (1) advance to the next phase, OR (2) escalate with a one-line `BLOCKED:` summary. There is no third option.

## User-direct input (rare but real)

**Default model:** the user talks to Cowork; Cowork talks to CC. You are the only voice into CC's terminal. The user does NOT type directly into the CC tab.

**Exception:** the user CAN type into CC directly (e.g. to override a stuck state, give CC private context, or experiment ad-hoc). When this happens you have to detect it so you don't get confused or duplicate work.

**Detection on each poll cycle:**

1. Read the CC scrollback via `read_history.sh`.
2. Compare against the `message_sent` events you logged to `<workspace>/.cc/state.json` — each event has the `frag` you used to verify your own paste.
3. Any user prompt in CC that lacks a matching `frag` in `state.json` → user-direct input.
4. When detected:
   - Log a `state.sh user_direct_input snippet="<first 80 chars>"` event for the audit trail.
   - **Don't repeat work CC may already be doing in response to that input.** Wait one extra poll cycle before sending your next directive.
   - **Don't drop your own plan** — your phase directives still apply. Just acknowledge in your next interaction with the user ("noticed you typed X to CC directly; I'm coordinating around it") and continue.

If user-direct input happens repeatedly in one phase (≥3 times), pause your phase loop and ask the user once: "you're driving CC directly — should I step back, or keep advancing the plan?" That's the only acceptable "ask the user" interruption.

## Plugin layout (orientation)

```
<plugin-root>/                          (=develop-like-sudipta/)
├── .claude-plugin/plugin.json          ← version + description
├── agents/                             ← 9 isolated-context subagents
├── commands/                           ← 23 slash commands (this dir)
├── assets/
│   └── scheduled-tasks/                ← bundled SKILL.md for Cowork cron tasks
│       ├── ccbridge-aggregate-learnings/SKILL.md
│       └── ccbridge-distill-and-propose/SKILL.md
├── skills/
│   ├── sd-claude-code-access/
│   │   ├── SKILL.md                    ← the methodology
│   │   ├── references/                 ← deep-dives (verify_gate, bug_TDD, etc.)
│   │   ├── assets/                     ← directive_template, bug_report_template, etc.
│   │   └── scripts/                    ← what install.sh copies into ~/.cache/ccbridge/
│   ├── autoresearch/scripts/           ← aggregate_learnings, distill_learnings
│   ├── code-hacker/
│   └── develop-like-sudipta/
└── hooks/                              ← git pre-commit hooks
    └── scripts/
        ├── check_no_hardcoded_paths.sh ← refuses /Users/<name>/ commits
        └── install_precommit_path_check.sh
```

## Don't

- Don't paste long markdown directly into CC. Use file-based directives.
- **Don't open Chrome on a red verify-gate.** First fix unit tests, then browser-test.
- **Don't advance phases on a red browser test OR a red unit test.**
- **Don't fix anything without writing a failing test first.** Bug-driven TDD is mandatory — see `references/bug_driven_tdd.md`.
- **Don't delete repro tests after the fix.** They stay in the suite as regression guards.
- Don't run two `/cc-drive` sessions against the same workspace — the driver lock will block but only with `WORKSPACE` set.
- Don't skip `read.sh`/`audit.sh` between phases. Diff reality vs directive.

## v4.3 — emit substrate choice as learning

Immediately after the substrate handshake settles, before sending the first keystroke:

```bash
SCRIPTS="${CLAUDE_PLUGIN_ROOT}/skills/sd-claude-code-access/scripts"
"$SCRIPTS/learning.sh" "$1" substrate_choice \
  "path=<A|B|C|D>" \
  "reason=<one-line why this path was picked>" \
  "mcps_available=<comma-list>"
```

This is the single most-useful signal for autoresearch: which substrate gets picked across
projects directly tells us where docs need to be sharper or where a new MCP recommendation
would land. Best-effort — never abort the run if the learning emit fails.

Now begin: read the skill, run diagnose, and report the pre-flight state to the user before sending a single keystroke.
