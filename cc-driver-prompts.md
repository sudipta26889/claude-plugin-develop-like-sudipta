# Claude Code driver — drop-in prompts for Cowork

After installing the `develop-like-sudipta` plugin v4.0.0, paste the variant that matches your scenario into a fresh Cowork chat. The `sd-claude-code-access` skill is bundled inside the plugin and triggers on the keywords below.

---

## How Cowork actually reaches your Mac

Cowork doesn't have a direct shell into your Mac — it has to pick a substrate from the MCPs available in the current session. Starting in v3.2 every variant below begins with a substrate probe (Step 0) and reports which path was chosen and why before running anything. There are four paths:

- **Path A — `Desktop_Commander` (preferred).** If `mcp__Desktop_Commander__*` tools are present in the session, Cowork executes commands directly on your Mac through that MCP. Fastest and most reliable; no app permissions needed.
- **Path B — `computer-use` (fallback).** If `mcp__computer-use__*` is present but `Desktop_Commander` is not, Cowork calls `request_access` for `Terminal` (or `iTerm2`) at tier `click` — enough to bring the app forward and click, but not to type. Typing happens via the SDK's keyboard relay paths described in the skill. Slower, requires per-app approval.
- **Path C — manual (last resort).** Neither MCP available: Cowork surfaces each command for you to paste into your Terminal. No autonomous execution, but the discipline still applies — directives, watchdog plan, audit, and browser-test commands are still written for you.
- **Path D — SSH / remote-Mac (added in v3.4).** When CC runs on a headless Mac mini or other remote host reachable via SSH + tmux: probe via the skill's `scripts/ssh_probe.sh`, then drive through a tmux session over SSH. Useful for always-on dev boxes or CI-like Macs. Falls back to Path C if SSH isn't reachable.

Full detail on probing, fallbacks, and what each path can and cannot do lives in the skill's `references/substrate_and_access.md`.

---

## 🅰️ Drive a new project end-to-end (plan + phased exec + per-phase browser verification)

```markdown
I want you to drive Claude Code (CC) end-to-end for a new project. Use the
`sd-claude-code-access` skill (bundled in the develop-like-sudipta plugin).

**Before driving anything:** probe substrate per the skill's
`references/substrate_and_access.md`:
- mcp__Desktop_Commander__* present? → Path A (preferred — direct on-Mac exec)
- mcp__computer-use__* present? → Path B (fallback — request_access for Terminal at tier "click")
- Neither? → Path C (manual — surface commands to user)

Tell me which path was chosen and WHY before running anything on my Mac.

**Workspace:** /absolute/path/to/my/new/project
**CC location:** running in macOS Terminal.app, single window, single tab
**My role:** I may step away mid-run; treat this as autonomous-mode-friendly

**What to do, in order:**
1. Read the skill's SKILL.md to load the methodology
2. Install the bridge: `bash <plugin-skill-path>/scripts/install.sh`
   (resolves to ~/.claude/plugins/marketplaces/.../develop-like-sudipta/skills/sd-claude-code-access/scripts/install.sh)
3. Run `~/.cache/ccbridge/diagnose.sh <workspace>`; confirm Terminal is healthy
4. Brainstorm the project with me first — use `superpowers:brainstorming`
5. Write PRD via `pm-execution:create-prd`, design doc, pre-mortem, implementation plan
6. Once I approve the plan: pre-write all phase directives to `.cc/phase-N.md`
7. Start the watchdog with `WORKSPACE=<workspace> bash ~/.cache/ccbridge/start_watchdog.sh`
8. Drive CC phase by phase via file-based directives
9. **After EACH phase completes:** invoke /browser-test — fire Claude in Chrome
   against the dev server, write `docs/e2e-testing/phase-N-<slug>.md`, emit
   `docs/e2e-testing/specs/phase-N.spec.ts`. Red test → write
   `.cc/phase-N-fix.md` and re-trigger CC. Don't advance on red.
10. Audit after every checkpoint with `audit.sh` (or /cc-audit)
11. At run end: /e2e-suite stitches the umbrella, run_summary.sh closes out

**Permissions you have from me up front:**
- Auto-approve routine dev permission prompts (the watchdog handles this)
- Refuse anything matching `danger_patterns.txt` (the watchdog also handles this)
- Use subagents for parallel audit / polling / directive-drafting if needed
- Write to `.cc/` in the workspace; add to `.gitignore` as Phase 1 step
- Write to `docs/e2e-testing/` (commit it — the test bank grows with the codebase)

**What I want from you:**
- Surface checkpoints + design questions only — don't ping me for routine prompts
- Update STATUS.md cumulatively after every phase
- Document blockers (anything needing my creds) for me to pick up later
- Tests live INSIDE the project at `docs/e2e-testing/`, not in the skill folder
```

Shortcut: `/cc-drive <workspace-path>` once the plugin is installed.

---

## 🅱️ Take over an already-running CC session (handoff mid-flight)

```markdown
Claude Code is already running in my Terminal at `/absolute/path/to/workspace`.
I've been driving it manually; take over and continue. Use the
`sd-claude-code-access` skill (bundled in develop-like-sudipta plugin).

**Before driving anything:** probe substrate per the skill's
`references/substrate_and_access.md`:
- mcp__Desktop_Commander__* present? → Path A (preferred — direct on-Mac exec)
- mcp__computer-use__* present? → Path B (fallback — request_access for Terminal at tier "click")
- Neither? → Path C (manual — surface commands to user)

Tell me which path was chosen and WHY before running anything on my Mac.

**Where we are:**
- Last completed phase: <N>  (e.g., "Phase 5 — Slack-status awareness")
- Current state: <CC is paused at checkpoint / mid-task / awaiting next phase>
- Implementation plan: /path/to/workspace/docs/plans/*-implementation.md
- Phase directives so far: /path/to/workspace/.cc/phase-1.md through phase-<N>.md
- Browser tests so far: /path/to/workspace/docs/e2e-testing/phase-*.md

**What to do:**
1. Read the skill's SKILL.md
2. Read `<workspace>/STATUS.md` + recent commits (`git log --oneline -15`)
3. Read `.cc/state.json` if it exists (resume probe)
4. Scan `docs/e2e-testing/` — which phases have passing tests, which are red, which never ran
5. `bash ~/.cache/ccbridge/diagnose.sh <workspace>`
6. `bash <plugin-skill-path>/scripts/install.sh` if bridge not yet installed
7. Start watchdog: `WORKSPACE=<workspace> bash ~/.cache/ccbridge/start_watchdog.sh`
8. Continue from where I left off — write next directive, send trigger, monitor,
   browser-test, then advance
```

Shortcut: `/cc-resume <workspace-path>` once the plugin is installed.

---

## 🆅 Resume after a Cowork crash (state.json exists)

```markdown
A previous Cowork session was driving Claude Code at /absolute/path/to/workspace
and died. Pick up the run. Use the `sd-claude-code-access` skill (bundled in
develop-like-sudipta plugin).

**Before driving anything:** probe substrate per the skill's
`references/substrate_and_access.md`:
- mcp__Desktop_Commander__* present? → Path A (preferred — direct on-Mac exec)
- mcp__computer-use__* present? → Path B (fallback — request_access for Terminal at tier "click")
- Neither? → Path C (manual — surface commands to user)

Tell me which path was chosen and WHY before running anything on my Mac.

**Resume protocol:**
1. Read the skill's SKILL.md and `references/state_and_resume.md`
2. Run `bash ~/.cache/ccbridge/diagnose.sh <workspace>`
3. Read `.cc/state.json` tail to reconstruct where the previous session was:
   `tail -30 <workspace>/.cc/state.json`
4. Cross-reference state events with `git log --oneline` — were the last
   commits the previous session's expected output?
5. Cross-reference browser-test artifacts — did the last phase get a green
   test in docs/e2e-testing/, or did it never run?
6. Check the driver lock — if stale (dead pid on this host), take it. If held
   by a live pid, abort and ask me.
7. Read the last `.cc/phase-N.md` to know what was in flight
8. Tell me your reconstruction in a short paragraph (phase state + test state
   + lock state), then ask whether to resume or replan
9. Once I confirm: restart watchdog, write next directive, continue
```

Shortcut: `/cc-resume <workspace-path>` once the plugin is installed.

---

## 🅓 One-off: just relay this single message to CC

```markdown
Send this message to my running Claude Code session. Use the
`sd-claude-code-access` skill (specifically `send.sh` and `read.sh`).

**Before driving anything:** probe substrate per the skill's
`references/substrate_and_access.md`:
- mcp__Desktop_Commander__* present? → Path A (preferred — direct on-Mac exec)
- mcp__computer-use__* present? → Path B (fallback — request_access for Terminal at tier "click")
- Neither? → Path C (manual — surface commands to user)

Tell me which path was chosen and WHY before running anything on my Mac.

**Message:**
<paste exact text — short messages inline; for long markdown write to
/path/to/workspace/.cc/oneshot.md and say "send 'Read .cc/oneshot.md and
apply it.' to CC">

**After sending:** poll CC's response for ~30s, summarize what came back,
report token-upload counter so I know if it's still working.
(No directive file, no watchdog, no audit — just keyboard-relay for this
one message.)
```

Shortcut: `/cc-send <message-or-path>` once the plugin is installed.

---

## 🅴 Browser-test a single phase (without driving CC)

```markdown
Run /browser-test for phase <N> at /absolute/path/to/workspace. Use the
`sd-claude-code-access` skill (references/browser_testing.md +
references/playwright_generation.md).

**Before driving anything:** probe substrate per the skill's
`references/substrate_and_access.md`:
- mcp__Desktop_Commander__* present? → Path A (preferred — direct on-Mac exec)
- mcp__computer-use__* present? → Path B (fallback — request_access for Terminal at tier "click")
- Neither? → Path C (manual — surface commands to user)

Tell me which path was chosen and WHY before running anything on my Mac.

Fire Claude in Chrome, verify the feature against the dev server, write
`docs/e2e-testing/phase-<N>-<slug>.md` with structured evidence
(Test ID, objective, preconditions, steps, expected results, screenshots,
console + network assertions, pass/fail/timestamps), emit Playwright spec
at `docs/e2e-testing/specs/phase-<N>.spec.ts`. Report green/red with the
file paths.

**Backend-only phase?** If the phase has no UI yet (pure API/job/migration),
route to the API-testing path described in `references/api_testing.md`
instead of opening Chrome — pytest + httpx/requests against the dev server,
evidence written to the same `docs/e2e-testing/phase-<N>-<slug>.md` shape.
The skill auto-detects backend-only phases from the directive (no
`browser:` block / no `data-testid` references) and routes accordingly.

If red: bundle evidence into `.cc/phase-<N>-fix.md` so I can ship it to CC.
```

Shortcut: `/browser-test <workspace> <phase-number>` once the plugin is installed.

---

## 🅵 Generate the end-to-end suite at run completion

```markdown
Run /e2e-suite at /absolute/path/to/workspace. Use the `sd-claude-code-access`
skill (references/browser_testing.md end-of-run E2E suite section).

**Before driving anything:** probe substrate per the skill's
`references/substrate_and_access.md`:
- mcp__Desktop_Commander__* present? → Path A (preferred — direct on-Mac exec)
- mcp__computer-use__* present? → Path B (fallback — request_access for Terminal at tier "click")
- Neither? → Path C (manual — surface commands to user)

Tell me which path was chosen and WHY before running anything on my Mac.

Stitch every `docs/e2e-testing/phase-*.md` into
`docs/e2e-testing/E2E-SUITE.md` (with a coverage table). Emit
`docs/e2e-testing/specs/e2e.spec.ts` as the umbrella that imports each
per-phase spec. Scaffold `specs/fixtures.ts`, `specs/playwright.config.ts`,
and `docs/e2e-testing/RUNNING.md` if missing.

Report: green/red/skipped counts, paths to the new files, and the one-line
command to run the whole suite.
```

Shortcut: `/e2e-suite <workspace-path>` once the plugin is installed.

---

## Knobs to tweak per use

| Variable | Default | When to override |
|---|---|---|
| `TERMINAL_APP` | `Terminal` | If you use iTerm2: prepend `export TERMINAL_APP=iTerm2` |
| Plugin location | `~/.claude/plugins/.../develop-like-sudipta/` | Auto-resolved if installed via marketplace |
| `~/.cache/ccbridge/` | bridge install dir | Override via `CCBRIDGE_DIR=/custom/path` |
| Watchdog interval | 4s | Edit `watchdog.sh` if too aggressive/slow |
| Hang threshold | 600s (10 min) | Adjust `nudge_if_stuck.sh 600 30` args |
| Poll cadence | 60–180s | Use 30s only for short critical phases |
| `BROWSER_TEST_ROOT` | `<workspace>/docs/e2e-testing/` | Override per-project via env or `.cc/config.json` |
| `DEV_SERVER_URL` | inferred from project config | Set explicitly if inference fails |
| `BROWSER_TEST_ALLOW_REMOTE` | unset (localhost only) | Set to `1` to test against staging |

## Tips that always apply

- **Add `.cc/` to `.gitignore`** before Cowork writes its first directive. Phase 1 directive should include this.
- **Commit `docs/e2e-testing/`** — the per-phase tests are the project's regression bank; they grow as CC builds.
- **Single Terminal window/tab** while a run is active. Multi-window setups silently route keystrokes wrong.
- **Set `WORKSPACE` env var** before calling `start_watchdog.sh` so state events get logged for resumability.
- **Don't open two Cowork chats driving the same workspace.** The driver lock blocks it, but only if `WORKSPACE` is set.
- **Don't advance a phase on a red browser test.** Write the fix directive, re-trigger CC, re-test.
- **At session end, run `run_summary.sh` + `/e2e-suite`** — captures both the driving session record and the project-wide test umbrella.

---

**All 6 variants now require substrate detection as Step 0.** If Cowork's tool list doesn't show `Desktop_Commander` or `computer-use`, expect Path C (manual) or Path D (SSH/remote-Mac if SSH is reachable) — Cowork will surface commands for you to run manually or pipe them through tmux over SSH. See the skill's `references/substrate_and_access.md` for the full probing protocol and the per-path capability matrix.
