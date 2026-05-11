---
name: sd-claude-code-access
description: Drive a running Claude Code (CC) terminal session as a manager from Cowork — write directives, trigger phases, approve permission prompts, monitor progress, recover from hangs, and maintain full understanding of the codebase being built. Detects the execution substrate at session start (Cowork's bash runs in a Linux sandbox; osascript is macOS-only): prefers Desktop_Commander MCP for direct on-Mac command execution (Path A), falls back to computer-use MCP with explicit request_access for Terminal at tier "click" (Path B), and last-resort displays commands for the user to run manually (Path C). Surfaces the chosen path to the user before driving anything. Every phase passes through a verify gate (static checks + unit/integration tests via pytest/jest/vitest/cargo/go-test/etc., auto-detected per project) BEFORE opening a browser; only when those are green does Cowork fire Claude in Chrome to verify the feature actually works end-to-end in a real browser and emit a Playwright spec into the project. When ANY test goes red — unit OR browser — bug-driven TDD kicks in: write a NEW failing pytest case AND a NEW failing Playwright step that both reproduce the bug, confirm both are red, send the fix directive to CC, then confirm green on the new unit test, the new browser test, the full verify-gate (regression guard), and the original phase test. No fix lands without a failing test first. Use this skill any time the user asks Cowork to "drive Claude Code", "manage a development run", "automate Claude Code", "build a project end-to-end via Claude Code", "control my CC session", "test the feature in browser after CC finishes", "write playwright tests as we go", "e2e test what CC just built", "run unit tests AND browser tests", "reproduce this bug with a failing test first", "real user testing", or hands you a long-running multi-phase implementation that another agent should execute. Use it even if the user only mentions "talking to Claude Code from here" or "use Claude Code to build it" — this skill turns those casual asks into a controlled, observable, recoverable engineering process with a built-in red-test-first feedback loop. The skill bundles macOS AppleScript bridge scripts (paste-with-verify, terminal-buffer reader, single-key sender, permission-prompt watchdog with danger-pattern deny-list, hang-nudger with confirmation gate, driver-lock semaphore, state-event recorder, run-summary generator, pre-commit hook installer, diagnostic health-check), file-based directive patterns that bypass paste-truncation issues, hang/recovery procedures, resume-after-crash protocol via state.json, multi-Cowork conflict prevention via .driver.lock, iTerm2 support via TERMINAL_APP env var, an auto-detecting verify gate (lint + typecheck + project test suite) that fails fast before Chrome opens, a per-phase browser-test loop driven by the Claude-in-Chrome MCP, an end-to-end suite generator, structured browser-test markdown (Test ID, objective, preconditions, steps, expected results, screenshot anchors, console/network assertions, pass/fail/timestamps), automatic Playwright spec emission into the project's `docs/e2e-testing/` directory, a bug-driven-TDD protocol that mandates failing tests before any fix, a bug-report template under .cc/bugs/, and a checklist for keeping Cowork's own understanding of the project in lockstep with what CC actually built. Invoked by /cc-drive, /cc-resume, /cc-send, /browser-test, /e2e-suite, /cc-audit, /reproduce-bug.
---

# sd-claude-code-access

A skill for **operating Claude Code (CC) from Cowork as a manager**, end to end, across a multi-phase project. You are the keyboard, the reviewer, and the project memory; CC is the developer.

## When this skill applies

Trigger this skill when ANY of these are true:

- The user asks Cowork to drive Claude Code, control CC, or automate a CC session.
- A long-running implementation plan (e.g. `docs/plans/*-implementation.md`) is being executed in CC and you're acting as reviewer / approver / next-phase trigger.
- The user is sitting in CC's terminal but wants Cowork to do the heavy lifting (directive writing, prompt approving, progress tracking, status synthesis).
- The user mentions "phase 2", "phase N approved, do phase N+1", "send this to Claude Code", "tell CC to…", or any pattern where Cowork relays instruction to CC.
- The user wants Cowork's codebase understanding to stay in lockstep with what CC actually committed.
- The user wants resume-after-crash / multi-machine / iTerm2 support for an ongoing CC run.

If a much narrower skill is already loaded for the specific app the user wants to control (Slack MCP, Linear MCP, etc.), prefer it. This skill is specifically for **driving an interactive Claude Code TUI** that's running locally on macOS.

## Core insights

This skill captures methodology developed specifically for the Cowork↔CC bridge. The bits most likely to surprise you:

1. **Multi-line markdown can fail to paste reliably.** Long pastes silently truncate. Fix: **file-based directives** — write to `.cc/phase-N.md`, send a tiny "Read `.cc/phase-N.md` and proceed" message. Bullet-proof.
2. **Cmd+A/Delete + Cmd+V/Return must be ONE osascript invocation.** Splitting causes focus races. The bundled `send.sh` does the whole sequence in a single heredoc.
3. **Verify after every paste.** Compute a unique fragment from the message *middle*, grep scrollback for it. The bundled `send.sh` does this and exits non-zero on failure.
4. **Auto-approve permission prompts via background watchdog.** CC asks dozens of times per phase; handling each in a Cowork turn burns context. The watchdog auto-approves except when the prompt matches a danger pattern (deny-list).
5. **CC genuinely hangs.** Press Esc (key code 53) once to interrupt. The bundled `nudge_if_stuck.sh` automates detection with a 3-confirmation gate (no false interrupts on slow Docker builds).
6. **Drift between directive and reality is silent and lethal.** Use the bundled `audit.sh` after each phase to cross-reference what was directed vs what got committed.

## High-level loop

```
┌─ Pre-flight ───────────────────────────────────────────────────────────┐
│ 1. Verify CC is running in macOS Terminal.app (or iTerm2 with         │
│    TERMINAL_APP=iTerm2), single window/tab. Run `diagnose.sh`.        │
│ 2. Read STATUS.md, README.md, CLAUDE.md, ARCHITECTURE.md, recent       │
│    git log, .cc/state.json (if resuming) → know where the project is. │
│ 3. Install bridge scripts to ~/.cache/ccbridge/ (one-time per machine)│
│ 4. Acquire driver lock (.cc/.driver.lock) for this workspace.          │
│ 5. Start the watchdog (auto-approves prompts, blocks danger patterns). │
│ 6. Optionally start nudge_if_stuck.sh in background.                   │
└────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─ Per-phase loop ───────────────────────────────────────────────────────┐
│ 1. Write directive to <workspace>/.cc/phase-<N>.md                     │
│ 2. Log: state.sh phase_start phase=N                                   │
│ 3. Send tiny trigger: "Read `.cc/phase-<N>.md` and proceed."           │
│ 4. Poll terminal every 2-5 minutes (or use a long-poll subagent).      │
│ 5. At checkpoint: audit.sh --retry 3 --retry-interval 2 + read git     │
│    diff → review → run the VERIFY GATE (static + unit + integration)   │
│    → BROWSER-TEST STEP → log state.sh phase_complete only when green.  │
│ 6. If hung >10 min: nudge_if_stuck.sh handles it with 3-confirm gate.  │
└────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─ Verify gate (BEFORE browser-test, every phase) ──────────────────────┐
│ 1. Static checks — project-detected (ruff/mypy/eslint/tsc/cargo        │
│    check/go vet). Auto-detect or read .cc/config.json → "static".     │
│ 2. Unit + integration tests — pytest / jest / vitest / cargo test /    │
│    go test / mvn test. Auto-detect or read .cc/config.json →           │
│    "test_commands". Coverage check if pillar 5 requires it.            │
│ 3. Fail-fast: any red → JUMP to "Bug found protocol" below. Do NOT     │
│    open Chrome. Don't even bother.                                     │
│ 4. All green → state.sh phase_verify_passed → proceed to browser-test. │
└────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─ Browser-test step (after each feature) ──────────────────────────────┐
│ 1. Determine test target — read phase directive for what was built;    │
│    derive the URL (localhost dev server or staging) from project conf. │
│ 2. Open `docs/e2e-testing/phase-<N>-<feature-slug>.md` (create if new) │
│    using assets/browser_test_template.md.                              │
│ 3. Fire Claude-in-Chrome MCP: navigate, click, fill, screenshot,       │
│    assert visible text, check console errors, inspect network.         │
│ 4. Record results inline in the md (pass/fail, timestamps, screenshot  │
│    refs, console+network observations).                                │
│ 5. Emit Playwright spec at `docs/e2e-testing/specs/phase-<N>.spec.ts`  │
│    using assets/playwright_spec_template.ts. Idempotent — only         │
│    overwrite if directive changed.                                     │
│ 6. If browser test fails → JUMP to "Bug found protocol" below.         │
│ 7. If green: state.sh phase_browser_test_passed →                      │
│    state.sh phase_complete → proceed to phase N+1.                     │
└────────────────────────────────────────────────────────────────────────┘
                                    │
              ▼ (only if a red appears at any step above)
┌─ Bug found protocol (RED → REPRODUCE → FIX → CONFIRM) ────────────────┐
│  This is BUG-DRIVEN TDD. Mandatory order — no shortcuts:               │
│                                                                        │
│  1. CAPTURE — collect evidence (stack trace OR DOM excerpt + console + │
│     network + screenshot). Write to .cc/bugs/<bug-id>.md using         │
│     assets/bug_report_template.md.                                     │
│  2. REPRODUCE FIRST (in code, not in chat):                            │
│     a. Write a NEW failing unit/integration test (pytest/jest/etc.)    │
│        that captures the bug at the smallest scope. Run it — confirm   │
│        it's RED for the right reason.                                  │
│     b. Write a NEW failing Playwright spec (or extend the existing     │
│        per-phase spec with a `test.step` for the bug) that captures    │
│        the user-visible failure. Run it — confirm RED.                 │
│     c. NEITHER test is allowed to pass before the fix. If one passes   │
│        accidentally, the repro is wrong → rewrite until it's red.      │
│  3. FIX — write `.cc/phase-<N>-fix.md` referencing both failing tests  │
│     by path. Send to CC.                                               │
│  4. CONFIRM — after CC's fix commits:                                  │
│     a. Re-run the new unit test → must be GREEN.                       │
│     b. Re-run the new Playwright test → must be GREEN.                 │
│     c. Re-run the FULL verify-gate (static + all unit + integration)   │
│        → must be GREEN. (Guards against fix introducing regression.)   │
│     d. Re-run the browser test for the original phase → must be GREEN. │
│  5. LOG — state.sh bug_resolved bug=<id> phase=<N>. Update             │
│     docs/e2e-testing/phase-<N>-<slug>.md with a `## Re-run` section.   │
│  6. If any of 4a–4d red on the same fix → loop back to 2. After 3      │
│     consecutive failed attempts on the same bug → escalate to human.   │
└────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─ Post-run ─────────────────────────────────────────────────────────────┐
│ 1. Final verify: pytest, ruff, mypy, docker build, test counts.        │
│ 2. Read STATUS.md, confirm CC's claims match the file.                 │
│ 3. Generate run_summary.sh — captures the driving session itself.      │
│ 4. Stop watchdog, release driver lock.                                 │
│ 5. Surface blockers / deferred items as a punch list.                  │
└────────────────────────────────────────────────────────────────────────┘
```

## Pre-flight checklist (every new session)

**Step 0 — Substrate detection (MANDATORY, before anything else).** Cowork's bash runs in a Linux sandbox; `osascript` only exists on macOS. The bundled bridge scripts must execute on the user's Mac. Detect which path is available:

```
1. Confirm macOS host:
   - Mounted paths look like /Users/<name>/... ✓
   - Cowork is the chat host ✓
   If not macOS → tell user this skill is macOS-only and STOP.

2. Probe MCP availability (inspect tool list, no calls yet):
   - mcp__Desktop_Commander__* present?  → Path A (preferred local)
   - SSH_TARGET env var set?              → Path D (advanced — remote Mac via SSH;
                                            requires Path A + ssh_probe.sh exit 0)
   - mcp__computer-use__* present?       → Path B (fallback)
   - mcp__Claude_in_Chrome__* present?   → required for browser-test step
   - None of the above?                   → Path C (manual)

3. If considering Path D, run the SSH probe:
   mcp__Desktop_Commander__start_process(
     command="bash ~/.claude/plugins/.../scripts/ssh_probe.sh \"$SSH_TARGET\""
   )
   Exit 0 + "READY <macos-ver> <claude-ver>" → Path D viable.
   Exit 1/2/3/4 → Path D not viable; fall back to Path A.
   Surface the probe result to the user BEFORE driving anything.

4. Request access (Path B only):
   mcp__computer-use__request_access(applications=["Terminal"])
   Verify the response says tier="click" (Terminal/iTerm are tier-click).
   Remember: tier-click means TYPING is blocked at the MCP level.
   Anything that needs to type must shell out via Desktop_Commander
   (Path A) or be relayed to the user (Path C subset).

5. Choose path. Decision order:
     Path D (if SSH_TARGET set AND ssh_probe READY)
   > Path A (local Desktop_Commander, no SSH)
   > Path B (computer-use, tier-click constraints apply)
   > Path C (manual relay)
   Record the choice as:
   state.sh substrate_chosen path=<A|B|C|D> reason=<short>

6. Verify CC is actually running:
   Path A: DC → `pgrep -lf claude` + osascript tab-name probe
   Path D: DC → `ssh "$SSH_TARGET" 'pgrep -lf claude'` + remote osascript probe
   Path B: screenshot Terminal, visually confirm CC prompt
   Path C: ask user "Is CC running in your Terminal? Yes/no."
```

Full ladder, per-action mapping, request_access flow, tier-click reality, and failure modes by path: [`references/substrate_and_access.md`](references/substrate_and_access.md).

Only after Step 0 is complete and the chosen path is verified should you proceed:

1. **Run the diagnostic** to confirm everything's healthy:
   ```bash
   bash ~/.cache/ccbridge/diagnose.sh /path/to/workspace
   ```
   Reports: terminal app, window/tab count, watchdog status, claude path, danger-pattern count, lock holder, recent state events, recent commits.

2. **Single window / single tab** — multi-tab/multi-window Terminal layouts route keystrokes to the wrong place. `diagnose.sh` flags this.

3. **Read project state in order:**
   - `STATUS.md` (cumulative)
   - `README.md`, `CLAUDE.md`, `ARCHITECTURE.md`
   - `docs/plans/*-implementation.md`
   - `.cc/state.json` (resume-after-crash signal — see [`references/state_and_resume.md`](references/state_and_resume.md))
   - `git log --oneline -20` and `git status`

4. **Install bridge scripts** (one-time per machine). **Execution depends on the chosen path:**
   - **Path A:** `mcp__Desktop_Commander__start_process(command="bash <plugin-skill-path>/scripts/install.sh")` — runs on the user's Mac directly.
   - **Path B / C:** display the command in chat, ask user to run it once in their own Terminal:
     ```
     bash <plugin-skill-path>/scripts/install.sh
     ```
   Either way, the script installs to `~/.cache/ccbridge/` (persistent across reboots) and creates a `/tmp/ccbridge` symlink for back-compat.

5. **Acquire driver lock + start watchdog:**
   - **Path A:**
     ```
     mcp__Desktop_Commander__start_process(
       command="WORKSPACE=/path/to/workspace bash ~/.cache/ccbridge/start_watchdog.sh",
       background=true
     )
     ```
   - **Path B / C:** display the command, ask user to run it.

   The lock prevents two Cowork sessions driving the same CC simultaneously. The watchdog auto-approves prompts except those matching `danger_patterns.txt`.

6. **(Optional) Start hang detector in background:**
   ```bash
   nohup ~/.cache/ccbridge/nudge_if_stuck.sh 600 30 > /dev/null 2>&1 & disown
   ```

## The directive pattern (the most important habit)

**Default to file-based directives** for anything longer than ~3 sentences. Long markdown pastes are unreliable and the conversation transcript can lie about what landed. Files are durable, version-controlled, and CC reads them via its own Read tool with no paste mechanics.

**Process:**

1. `<workspace>/.cc/` exists and is gitignored.
2. Write directive to `<workspace>/.cc/phase-<N>.md`. Use [`assets/directive_template.md`](assets/directive_template.md) as starting point.
3. Trigger CC with a one-line message:
   ```
   Read `.cc/phase-<N>.md` and proceed.
   ```

A good directive: scope, per-task why/where/how/failure-modes/tests, acceptance gate, commit pattern, out-of-scope. See [`references/directive_patterns.md`](references/directive_patterns.md) for full guidance and worked examples.

## The verify gate (mandatory, every phase, before Chrome)

Static checks + project test suite run **first**. Opening Chrome on a phase that fails pytest is wasted work — and worse, a green browser test on a red unit suite is a lie. Order is:

1. **Static** — auto-detected per project: `ruff check .` + `mypy .` (Python), `eslint . && tsc --noEmit` (TS/JS), `cargo check && cargo clippy` (Rust), `go vet ./...` (Go). Override via `<workspace>/.cc/config.json` → `"static"`.
2. **Unit + integration** — auto-detected: `pytest -x` (Python), `npm test` / `vitest run` / `jest --ci` (JS/TS), `cargo test` (Rust), `go test ./...` (Go), `mvn test` (Java). Override via `.cc/config.json` → `"test_commands"`.
3. **Coverage gate** — if pillar 5 enforces ≥80%, run with `--cov` / `--coverage` and reject below threshold.

**Fail-fast:** the first red command stops the chain. Don't run the next one. Don't open Chrome. Jump straight to **Bug found protocol** (below).

Full runner-detection + config schema: [`references/verify_gate.md`](references/verify_gate.md).

## Bug found protocol (red → reproduce → fix → confirm)

This is **bug-driven TDD**. It applies whenever any test goes red at any layer — unit, integration, or browser. The rule:

> **No fix lands without a failing test first.** The failing test (or pair of tests) is the bug's signature. You cannot prove the fix worked unless something that was red is now green.

Mandatory sequence — do not skip steps, do not change order:

1. **Capture** — copy the failing assertion, stack trace, DOM excerpt, console error, network response, screenshot. Write all of it into `<workspace>/.cc/bugs/<bug-id>.md` using `assets/bug_report_template.md`. `<bug-id>` is `phase-<N>-bug-<short-slug>`.
2. **Reproduce in code (red first, two layers):**
   - **a. Unit-layer repro** — write a NEW pytest/jest/vitest/etc. test that asserts the *correct* behavior. Run it. It must be **red for the bug-specific reason** (not red because of an import error or missing fixture — that's a broken test, not a repro). Save under the project's tests dir using a `test_<bug-id>_<intent>` naming convention.
   - **b. Browser-layer repro** — extend the existing `docs/e2e-testing/phase-<N>-<slug>.md` with a `## Bug repro: <bug-id>` block AND add a `test.step('bug-<id>: <description>', ...)` to `specs/phase-<N>.spec.ts`. Run the Playwright spec. It must be **red**.
   - If either repro accidentally passes → the repro is wrong → rewrite until both are red. A bug you can't reproduce isn't a bug; it's a guess.
3. **Fix** — write `<workspace>/.cc/phase-<N>-fix.md` that:
   - References both failing test paths by relative path.
   - States the acceptance: both tests must go green, plus the full verify-gate must stay green.
   - Includes the captured evidence inline (or links to `.cc/bugs/<bug-id>.md`).
   Send the trigger: `Read \`.cc/phase-<N>-fix.md\` and apply the fix per the bug-driven-TDD protocol.`
4. **Confirm — four green lights in order:**
   - **a.** Re-run the new unit test → green.
   - **b.** Re-run the new browser test → green.
   - **c.** Re-run the **full verify-gate** (every static check + every project test) → green. This catches regressions the fix introduced elsewhere.
   - **d.** Re-run the phase's original browser test → green.
5. **Log** — `state.sh bug_resolved bug=<id> phase=<N>`. Append a `## Re-run YYYY-MM-DD HH:MM` section to the per-phase browser-test md with the timestamp and the bug-id link. Commit the new tests + fix as one logical change with a `fix:` Conventional Commits prefix.
6. **Loop** — if any of 4a–4d is red, the fix is incomplete. Loop back to step 2 with the new failure as evidence. After **3 consecutive failed fix attempts on the same bug**, stop the loop and escalate to the human reviewer with all evidence consolidated.

Worked examples (unit-only bug, browser-only bug, both-layer bug) + anti-patterns + audit pattern: [`references/bug_driven_tdd.md`](references/bug_driven_tdd.md).

## Browser-verifying every feature (Claude in Chrome)

CC's checkpoint summaries describe intent; a passing test suite describes correctness in code; **a real browser describes the truth**. After every feature/phase, drive the Claude-in-Chrome MCP (`mcp__Claude_in_Chrome__*`) against the dev server and capture the result as a structured markdown file inside the project — plus a Playwright spec so the test becomes durable.

**Default test root:** `<workspace>/docs/e2e-testing/` (override via `BROWSER_TEST_ROOT` env or project config). Two artifacts per phase:

1. `docs/e2e-testing/phase-<N>-<feature-slug>.md` — human-readable test record (Test ID, objective, preconditions, step-by-step actions, expected results per step, screenshot anchors, console/network assertions, pass/fail/timestamps).
2. `docs/e2e-testing/specs/phase-<N>.spec.ts` — Playwright spec emitted from the markdown so CI / re-runs are automated.

**Loop:**

1. After phase N's commit lands, read the directive's "what to build" + acceptance criteria → derive the test target URL.
2. Use `mcp__Claude_in_Chrome__navigate` to open it; if auth is needed, run the project's login flow once and reuse the session.
3. For each acceptance criterion, perform: `navigate` → `find` / `read_page` → `form_input` / `computer` actions → screenshot → `read_console_messages` → `read_network_requests`.
4. Write each step's outcome inline in `docs/e2e-testing/phase-<N>-<slug>.md` using the template at `assets/browser_test_template.md`.
5. Emit `docs/e2e-testing/specs/phase-<N>.spec.ts` using `assets/playwright_spec_template.ts`. The generated spec mirrors the markdown's steps as `test.step(...)` blocks with the same selectors and assertions.
6. Status:
   - **All green** → `state.sh phase_browser_test_passed` → advance.
   - **Any red** → `state.sh phase_browser_test_failed` → write `.cc/phase-<N>-fix.md` (DOM evidence, console error, expected vs actual screenshot) → send to CC → re-run from per-phase step 5.

**End of run:** the `/e2e-suite` command stitches all per-phase markdown into one `docs/e2e-testing/E2E-SUITE.md` and emits a `docs/e2e-testing/specs/e2e.spec.ts` umbrella spec.

> **Backend-only phases:** if a phase has no UI surface (REST endpoint additions, gRPC handlers, queue consumers, background jobs), the browser-test step is replaced by **API-level testing** — contract assertions against `openapi.yaml` / `*.proto` / `schema.graphql`, or curl-based fixture comparison when no schema source is present. Routing is automatic from the directive's acceptance criteria, or forced with `BACKEND_ONLY=1`. The per-phase output lives at `docs/api-testing/phase-<N>-<slug>.md` (mirrors browser-test's contract). See [`references/api_testing.md`](references/api_testing.md).

Detailed protocol: [`references/browser_testing.md`](references/browser_testing.md). Playwright emission patterns: [`references/playwright_generation.md`](references/playwright_generation.md). API-level analogue: [`references/api_testing.md`](references/api_testing.md).

## Reading the codebase like a real manager

Cowork's understanding of the project is fragile across long autonomous runs because CC writes the code, not Cowork. Combat drift by:

1. After every checkpoint, read `git log --oneline` for new commits and skim the diff for headline ones. Don't trust CC's checkpoint summary alone.
2. Use the bundled `audit.sh` to cross-reference directive vs commits:
   ```bash
   bash ~/.cache/ccbridge/audit.sh /path/to/workspace 7
   ```
   Reports: matched commit messages, missing files, files mentioned but not committed.
3. Re-read `.cc/phase-<N>.md` before approving — if you're rubber-stamping without re-reading, you've lost the thread.
4. Use parallel-audit subagent pattern when available — see [`references/subagent_patterns.md`](references/subagent_patterns.md).

Full protocol in [`references/codebase_understanding.md`](references/codebase_understanding.md).

## Failure modes you WILL hit

Recovery procedures live in [`references/failure_modes.md`](references/failure_modes.md). Top hits:

| Symptom | Recovery |
|---|---|
| Long paste appears truncated in scrollback | Redo as file-based directive |
| Watchdog quiet but a prompt is on-screen | Check it's running; update grep pattern; restart |
| CC stuck on same time-elapsed >10 min | `keys.sh esc` (or let `nudge_if_stuck.sh` handle after 3 confirms) |
| Watchdog refuses to approve a routine prompt | Check `watchdog.log` for `DANGER fp=… matched=…`; manually evaluate before pressing Enter yourself |
| Two Coworks fighting | Driver lock prevents this; second session exits 2 with `[lock] HELD by:` |
| Cross-machine setup | See [`references/ssh_variant.md`](references/ssh_variant.md) |
| iTerm2 instead of Terminal.app | `export TERMINAL_APP=iTerm2`; see [`references/iterm2.md`](references/iterm2.md) |

## Driving long autonomous runs

For runs > 30 min where the user is away:

1. **Pre-write all phase directives upfront.** Saves context budget — per-phase trigger is 1-line.
2. **Poll at 60–180s intervals**, not 15s. Watchdog handles routine approvals.
3. **Use `git log --oneline -1` as a cheap progress probe.**
4. **Generate a STATUS.md update per phase.**
5. **Document blockers explicitly.**
6. **Use subagents for parallel audit/poll/draft** if available — see [`references/subagent_patterns.md`](references/subagent_patterns.md).
7. **Run `state.sh` for every phase boundary** so resume-after-crash works.
8. **Generate `run_summary.sh` at session end.**

Full playbook: [`references/managing_long_runs.md`](references/managing_long_runs.md).

## Anti-patterns

- **Don't ad-hoc paste long markdown.** File-based for >3 sentences.
- **Don't poll every 15s during long phases.** 2-5 min is the floor.
- **Don't skip diffs because the checkpoint summary "looked good".** Summaries describe intent; diffs describe reality.
- **Don't disable the watchdog "for safety".** Use the danger deny-list instead.
- **Don't run the watchdog without `WORKSPACE` set** if you want resume-after-crash. State events get dropped.
- **Don't forget to `git rm --cached .cc/`.** Or run `install_precommit.sh` to install a hook that refuses such commits.
- **Don't trust paste verification on prefix-similar messages.** `send.sh` uses a *middle* fragment; don't override it.

## What the bundled scripts do

| Script | Purpose |
|---|---|
| `install.sh` | Copy all scripts + danger_patterns.txt to `~/.cache/ccbridge/`, create back-compat `/tmp/ccbridge` symlink. Idempotent. |
| `send.sh` | Read message from stdin → pbcopy → single-osascript Cmd+A/Del/Cmd+V/Return → verify by middle-fragment grep. Logs `message_sent` state event when `WORKSPACE` set. |
| `read.sh` | Visible terminal buffer. Respects `$TERMINAL_APP`. |
| `read_history.sh` | Full scrollback (Terminal.app); falls back to `contents` on iTerm2. |
| `keys.sh` | Single-key sender: `return`, `esc`, `up`, `down`, `tab`, or any printable char. Respects `$TERMINAL_APP`. |
| `watchdog.sh` | Background loop. Auto-presses Enter on permission prompts UNLESS the buffer matches a `danger_patterns.txt` regex (then logs LOUD and refuses). Logs state events. |
| `start_watchdog.sh` | Acquires driver lock if `WORKSPACE` set, then nohup-launches the watchdog. |
| `stop_watchdog.sh` | Kills watchdog. Releases lock. Logs `watchdog_stopped`. |
| `nudge_if_stuck.sh` | Hang detection with 3-confirmation gate. Esc-interrupts only on confirmed hang. Logs `nudge_sent`. |
| `audit.sh` | Cross-reference phase directive against git log. Reports matched commits, missing files, mentioned-but-uncommitted, expected commit messages. |
| `state.sh` | Append a structured event to `<workspace>/.cc/state.json`. JSONL format. |
| `lock.sh` | Driver-session semaphore. `acquire/release/status`. Detects stale locks from dead pids. |
| `diagnose.sh` | One-shot health check: terminal, watchdog, claude binary, danger patterns, lock holder, recent state, recent commits. |
| `run_summary.sh` | Generate `<workspace>/.cc/runs/<timestamp>.md` summarizing the driving session itself. |
| `install_precommit.sh` | Install a git pre-commit hook that refuses to commit anything under `.cc/`. |
| `danger_patterns.txt` | Deny-list of regex patterns that block auto-approval. 26 patterns covering filesystem destruction, git history rewriting, cloud destruction, database DROP/TRUNCATE, network/system commands, and secret-exfiltration smell. |

## What the bundled references cover

| Reference | Read when |
|---|---|
| `references/substrate_and_access.md` | **ALWAYS read first.** How Cowork actually reaches the user's Mac: Path A (Desktop_Commander), Path B (computer-use), Path C (manual). Tier-click reality, request_access flow, per-action mapping. |
| `references/bridge_mechanics.md` | First session, or when paste is misbehaving. Explains the AppleScript substrate that runs ON the user's Mac. |
| `references/directive_patterns.md` | Writing a directive — anatomy + worked example. |
| `references/codebase_understanding.md` | After a checkpoint, before approving. |
| `references/failure_modes.md` | Before first run, and any time something's off. |
| `references/managing_long_runs.md` | Multi-hour playbook: cadence, context budget, status hygiene. |
| `references/ssh_variant.md` | Cross-machine via headless `claude -p -c`. |
| `references/iterm2.md` | Driving CC in iTerm2 via `TERMINAL_APP=iTerm2`. |
| `references/state_and_resume.md` | Resume after crash via `.cc/state.json`. |
| `references/worktree_integration.md` | Running CC inside a git worktree — WORKSPACE resolution, driver lock per-worktree, multi-worktree parallelism, merge-time test bank handling. |
| `references/subagent_patterns.md` | Parallel audit/poll/draft when subagent spawning is available. |
| `references/browser_testing.md` | Per-phase browser-verification loop — Chrome MCP usage, test md schema, auth handling, screenshot conventions, fail→fix loop. |
| `references/playwright_generation.md` | Emitting Playwright spec files from test markdown — selectors, assertions, fixtures, naming, idempotent overwrite rules. |
| `references/api_testing.md` | Backend-only phase verification — replaces browser-test when no UI surface. Routing (`BACKEND_ONLY=1` + auto-detect), schema-source detection (OpenAPI / GraphQL / proto), per-endpoint test pattern, idempotency assertions, language-detected spec emission. |
| `references/verify_gate.md` | Auto-detection for static checks + project test runners (pytest/jest/vitest/cargo/go/maven), `.cc/config.json` schema, fail-fast semantics. |
| `references/bug_driven_tdd.md` | The red-test-first protocol. Worked examples for unit-only, browser-only, and both-layer bugs. Anti-patterns. Audit checklist for "did they write the failing test first?" |
| `references/danger_pattern_governance.md` | Adding/auditing a danger pattern, debugging a false positive, or wiring `WATCHDOG_DRYRUN`. |
| `references/audit_timing.md` | Tuning `--retry`/`--retry-interval` for commit-hook lag, or diagnosing an audit that surfaces drift on healthy phases. |

## Quick reference card

```bash
# One-time per machine
bash <skill-path>/scripts/install.sh

# One-time per session — set WORKSPACE for state-tracking + lock
export WORKSPACE=/path/to/workspace
bash ~/.cache/ccbridge/start_watchdog.sh

# Send anything (long content via file)
echo "Read \`.cc/phase-3.md\` and proceed." | ~/.cache/ccbridge/send.sh

# Read terminal state
~/.cache/ccbridge/read.sh | tail -30

# Read full scrollback (verification grep)
~/.cache/ccbridge/read_history.sh | grep -F "$UNIQUE_FRAGMENT"

# Approve a numeric prompt manually (option 2 / down + return)
~/.cache/ccbridge/keys.sh down && ~/.cache/ccbridge/keys.sh return

# Interrupt a hung CC
~/.cache/ccbridge/keys.sh esc

# Audit a phase
bash ~/.cache/ccbridge/audit.sh /path/to/workspace 7

# Health check
bash ~/.cache/ccbridge/diagnose.sh /path/to/workspace

# Mark a state event manually
~/.cache/ccbridge/state.sh /path/to/workspace phase_start phase=8

# Lock status / acquire / release
~/.cache/ccbridge/lock.sh status /path/to/workspace
~/.cache/ccbridge/lock.sh acquire /path/to/workspace
~/.cache/ccbridge/lock.sh release /path/to/workspace

# Install pre-commit hook (refuses to commit .cc/)
bash ~/.cache/ccbridge/install_precommit.sh /path/to/workspace

# Generate run summary at session end
bash ~/.cache/ccbridge/run_summary.sh /path/to/workspace

# Stop watchdog at end of session
bash ~/.cache/ccbridge/stop_watchdog.sh

# iTerm2 instead of Terminal.app
export TERMINAL_APP=iTerm2
```

## Closing principle

Your job is to be the keyboard, the reviewer, and the memory. The keyboard part is automated; the reviewer part requires that you actually look at diffs; the memory part requires `STATUS.md` updates after every phase + `state.json` events for resumability. If you're shipping markdown but skipping diffs, you're not managing — you're cheerleading. The skill exists to make the mechanical parts cheap so you can spend your context on the parts that actually matter: reading code, asking the right next question, and noticing when the directive and the implementation have diverged.
