---
description: Run the post-phase Claude-in-Chrome verification for the current phase — write structured test markdown + emit Playwright spec into the project
argument-hint: <workspace-path> [phase-number]
---

Browser-verify the most recent (or specified) phase using Claude in Chrome MCP. Produce two artifacts inside the project: a human-readable test record (`docs/e2e-testing/phase-<N>-<slug>.md`) and a Playwright spec (`docs/e2e-testing/specs/phase-<N>.spec.ts`).

**You MUST invoke the `sd-claude-code-access` skill first** — specifically `references/browser_testing.md` and `references/playwright_generation.md`. Do not skip either. The markdown is the source of truth for humans; the spec is the source of truth for CI.

## Inputs

- `$1` — workspace path (required)
- `$2` — phase number (optional; if omitted, infer from `$1/.cc/state.json` most-recent `phase_complete` event, or the highest-numbered `$1/.cc/phase-*.md`)

## Procedure

0. **Substrate + MCP check.** This command needs TWO things to work:
   - **A way to run shell commands on the user's Mac** (for the verify gate). Probe for `mcp__Desktop_Commander__*` (Path A preferred). If absent, fall back to `mcp__computer-use__*` (Path B — and ask the user to paste test output) or Path C (manual run). Read `references/substrate_and_access.md` before proceeding.
   - **The Claude-in-Chrome MCP** (for the browser-test itself). Probe for `mcp__Claude_in_Chrome__*`. If absent, tell the user "I cannot drive a real browser without the Claude-in-Chrome MCP installed" and stop. Don't fake it.
1. **Load the skill** — read `references/substrate_and_access.md`, `references/verify_gate.md`, `references/browser_testing.md`, `references/playwright_generation.md`, `references/bug_driven_tdd.md`. All five are mandatory; the protocol depends on each.
2. **Run the verify gate FIRST** — static checks + project test suite per `references/verify_gate.md`. Run per chosen path (Path A → DC exec; Path B/C → relay to user). Auto-detect runners or read `$1/.cc/config.json` → `static` + `test_commands`. Fail-fast: first red command stops the chain. **If red → jump to Bug found protocol, do NOT open Chrome.**
2a. **Backend-only routing.** If `BACKEND_ONLY=1` is set in the env, OR the phase directive (`$1/.cc/phase-$2.md`) has no UI element in its acceptance criteria — no `data-testid`, no page/route mention (`/login`, `/dashboard`, `routes/...`, `pages/...`), no visible-text assertion (`user sees…`, `the modal shows…`) — route to **API testing per [`references/api_testing.md`](../skills/sd-claude-code-access/references/api_testing.md) instead of opening Chrome**.
   - Write `$1/docs/api-testing/phase-$2-<feature-slug>.md` using [`assets/api_test_template.md`](../skills/sd-claude-code-access/assets/api_test_template.md). Follow the exact H2 order — a future runner parses by heading.
   - Detect schema sources in the workspace (`openapi.yaml` / `openapi.json` / `schema.graphql` / `*.proto` / `asyncapi.yaml`) and record them in the Preconditions and Schema-assertions sections.
   - Emit a project-language-detected test file (`tests/api/phase-$2.test.ts` for TS/JS, `tests/api/test_phase_$2.py` for Python, `tests/api/phase_$2_test.go` for Go, etc.). See "Spec emission" in `references/api_testing.md`.
   - Reuse `.cc/auth/storage-state.json` for auth (same source as browser-test). Run `scripts/check_auth_state.sh $1` first; refresh once via the project login flow if stale.
   - Auto-detection tie-breaker: if the directive references `openapi.yaml`, `schema.graphql`, or `*.proto` but no `playwright`/`browser`/`Chrome MCP` strings, treat as backend-only. When unsure, ask the user — a false positive (skipping Chrome on a real UI phase) is worse than asking.
   - Log: `state.sh phase_test_mode mode=api phase=$2`, then proceed straight to step 11. **Do NOT open Chrome. Do NOT emit a Playwright spec.** Skip steps 3-10.
3. **Resolve test target** (only if verify-gate green) — find dev-server URL via env `DEV_SERVER_URL`, `.cc/config.json`, `package.json` scripts, framework configs. Verify it's reachable (`curl -o /dev/null -w "%{http_code}"`).
4. **Resolve test root** — default `$1/docs/e2e-testing/`, override via env `BROWSER_TEST_ROOT` or `.cc/config.json` → `browser_test_root`. Create if missing.
5. **Read the phase directive** — `$1/.cc/phase-$2.md` — extract "what to build" + acceptance criteria.
6. **Check auth requirements** — if behind login, drive the login flow once and persist storage state to `$1/.cc/auth/storage-state.json` (gitignored).
7. **Walk each acceptance criterion** as a numbered test step using Chrome MCP tools (`mcp__Claude_in_Chrome__*`):
   - `navigate` → `find` / `read_page` → `form_input` / `computer` → screenshot → `read_console_messages` → `read_network_requests`
8. **Write the test record** to `$1/docs/e2e-testing/phase-$2-<feature-slug>.md` using `assets/browser_test_template.md`. Follow the exact section order — the spec generator parses by H2 heading.
9. **Emit the Playwright spec** to `$1/docs/e2e-testing/specs/phase-$2.spec.ts` using `assets/playwright_spec_template.ts`. Insert the source-hash comment. Idempotent — only overwrite if the `## Steps` content hash changed.
10. **Scaffold once if absent:** `specs/fixtures.ts`, `specs/playwright.config.ts`, `docs/e2e-testing/RUNNING.md`.
11. **Log state:**
    - Green → `state.sh phase_browser_test_passed phase=$2`
    - Red → jump to Bug found protocol.
12. **Report to the user** — paste the test md path, the spec path, pass/fail summary for verify-gate + browser, and a one-line headline of what was verified.

## Bug found protocol (if ANY red — verify-gate OR browser)

Apply `references/bug_driven_tdd.md` strictly:

1. **Capture** evidence into `$1/.cc/bugs/phase-$2-bug-<slug>.md` using `assets/bug_report_template.md`. Include the exact failing command, last 200 lines of output, failing assertion, and for browser failures: screenshot path + console + network + DOM excerpt.
2. **Reproduce in code, two layers, both red BEFORE the fix:**
   - **a.** Write a NEW failing unit test (`test_<bug-id>_<intent>`) at the smallest scope. Run it. Confirm red for the bug-specific reason.
   - **b.** Add a NEW failing `test.step('bug-<id>: ...')` to `docs/e2e-testing/specs/phase-$2.spec.ts`. Run it. Confirm red.
   - If either accidentally passes → the repro is wrong; rewrite until both red.
3. **Fix** — write `$1/.cc/phase-$2-fix.md` referencing both failing tests by path. Acceptance: both new tests + full verify-gate + original phase test all green. Send to CC.
4. **Confirm — four greens in order:**
   - **a.** new unit test → green
   - **b.** new browser test step → green
   - **c.** FULL verify-gate → green (regression guard)
   - **d.** original phase-$2 browser test → green
5. **Log** — `state.sh bug_resolved bug=<id> phase=$2`. Append `## Re-run YYYY-MM-DD HH:MM` to the per-phase md.
6. **Loop** — if any of 4a–4d red, re-attempt from step 2. After 3 consecutive failed fix attempts on the same bug, escalate to the human reviewer.

## Don't

- **Don't open Chrome on a red verify-gate.** First fix unit tests.
- **Don't fix without a failing test first.** Bug-driven TDD is mandatory.
- **Don't delete the repro tests after the fix.** They stay as regression guards.
- Don't write tests for code that wasn't built in this phase.
- Don't skip console + network assertions. A page that "looks right" with a red console is still broken.
- Don't run against production. Default to localhost; staging requires `BROWSER_TEST_ALLOW_REMOTE=1`.
- Don't bake credentials into the markdown or spec. Use env vars.
- Don't emit only the spec without the markdown. The markdown is the contract.
