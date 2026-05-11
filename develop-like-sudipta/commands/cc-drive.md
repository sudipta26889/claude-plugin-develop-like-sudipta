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

## Don't

- Don't paste long markdown directly into CC. Use file-based directives.
- **Don't open Chrome on a red verify-gate.** First fix unit tests, then browser-test.
- **Don't advance phases on a red browser test OR a red unit test.**
- **Don't fix anything without writing a failing test first.** Bug-driven TDD is mandatory — see `references/bug_driven_tdd.md`.
- **Don't delete repro tests after the fix.** They stay in the suite as regression guards.
- Don't run two `/cc-drive` sessions against the same workspace — the driver lock will block but only with `WORKSPACE` set.
- Don't skip `read.sh`/`audit.sh` between phases. Diff reality vs directive.

Now begin: read the skill, run diagnose, and report the pre-flight state to the user before sending a single keystroke.
