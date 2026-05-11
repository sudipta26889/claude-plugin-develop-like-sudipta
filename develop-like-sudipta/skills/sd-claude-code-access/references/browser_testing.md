# Browser testing — per-phase Claude-in-Chrome verification loop

This reference covers the **post-implementation browser verification step** that runs after every CC phase commits. The goal: prove the feature works in a real browser, capture evidence, and turn it into a durable Playwright spec — all inside the project so the test bank grows organically with the codebase.

## When this loop runs

Trigger automatically after `state.sh phase_complete`. Skip only if the phase has no user-visible surface (pure backend migration, internal refactor, infra-only). When skipping, still log `state.sh phase_browser_test_skipped reason=...` so the run summary is honest.

## Output contract (two files per phase)

1. **`<workspace>/docs/e2e-testing/phase-<N>-<feature-slug>.md`**
   - Human-readable test record.
   - Schema in `assets/browser_test_template.md`.
   - One file per phase. Never overwrite without reason — if a phase is re-tested, append a `## Re-run YYYY-MM-DD HH:MM` section.

2. **`<workspace>/docs/e2e-testing/specs/phase-<N>.spec.ts`**
   - Playwright spec mirroring the markdown's steps.
   - One spec per phase. Idempotent overwrite — regenerate only if the markdown's `## Steps` section has changed.
   - Pattern: see `references/playwright_generation.md`.

`docs/e2e-testing/` is the **default** test root. Override per-project via:
- env var `BROWSER_TEST_ROOT=/abs/or/relative/path`
- `<workspace>/.cc/config.json` → `"browser_test_root": "..."`
- project's `package.json` → `"sd-cc": { "browser_test_root": "..." }`

Resolution order: env > `.cc/config.json` > `package.json` > default.

## Test target derivation

1. Read the phase directive for "what to build" + acceptance criteria.
2. Look for the dev-server URL in this order:
   - env `DEV_SERVER_URL`
   - `<workspace>/.cc/config.json` → `"dev_server_url"`
   - `package.json` scripts (`"dev"` / `"start"`) — extract `--port` or default 3000/5173/8080
   - `vite.config.*`, `next.config.*`, `webpack.config.*`
   - Recent commits/CHANGELOG mentioning a port
3. Verify the server is reachable before driving Chrome — `curl -sS -o /dev/null -w "%{http_code}\n" $URL`. If it's not running, write a `.cc/start-dev.md` directive asking CC to start it, send the trigger, wait.

## Auth handling

If the feature is behind a login wall:

1. First phase that hits auth → drive Chrome through the login flow once. Capture the storage state.
2. Save to `<workspace>/.cc/auth/storage-state.json` (gitignored).
3. Subsequent phases → `mcp__Claude_in_Chrome__navigate` with the stored session (or replay cookies via `javascript_tool`).
4. If session expires mid-run → detect via `read_page` returning a login form → re-run the login flow, update storage state, retry.

Never bake credentials into the markdown or spec. Use env vars (`E2E_USER`, `E2E_PASS`) and reference them in the Playwright fixture.

## Per-step Chrome MCP actions

Map each acceptance criterion to a short sequence:

| Intent | Chrome MCP calls |
|---|---|
| Open page | `navigate` |
| Inspect rendered text | `get_page_text` or `read_page` |
| Find element | `find` (DOM-aware, prefer over coord clicks) |
| Click button / link | `computer` with action `click` and the element reference from `find` |
| Fill form field | `form_input` |
| Submit form | `computer` click on submit, or `key` Enter |
| Screenshot | implicit via `read_page` / explicit via `computer` screenshot |
| Console errors | `read_console_messages` after each interaction |
| Network failures | `read_network_requests` — assert no 4xx/5xx on critical endpoints |
| File upload | `file_upload` |
| Drag-drop / complex gesture | `computer` with precise actions; document the gesture in the md |

**Anti-patterns:**
- Don't use coordinate clicks if a `find`-based selector works.
- Don't `wait` blindly — poll with `find` until the element exists, max 10s.
- Don't ignore console errors. A red console with the page "looking right" is still a fail.

## Test markdown schema (recap)

Every per-phase md must have these sections in this order:

1. **Test ID** — `phase-<N>-<feature-slug>` (matches the filename).
2. **Objective** — one sentence, plain English.
3. **Preconditions** — dev server running, fixtures loaded, env vars set, auth state.
4. **Setup** — exact commands run before the test (DB seed, feature flag toggle, etc.).
5. **Steps** — numbered list of action + expected. Each step gets a short ID (`s1`, `s2`, …) for reference by the spec.
6. **Screenshot anchors** — file paths under `docs/e2e-testing/screenshots/phase-<N>/<step-id>.png`.
7. **Console assertions** — list of substrings that MUST NOT appear and substrings that MUST appear.
8. **Network assertions** — list of `(method, url-pattern, expected-status)` tuples.
9. **Result** — `pass` / `fail` / `pass-with-warnings` + timestamp.
10. **Notes** — any human-readable observations, screenshots that surprised you, follow-up tasks.

Use `assets/browser_test_template.md` to scaffold. Do not deviate from the section order — `references/playwright_generation.md` parses these sections by H2 heading.

## Failure → fix loop

A red browser test is not a stop sign; it's a directive trigger. Procedure:

1. Capture evidence — failing screenshot, console error, failing network request, DOM excerpt from `read_page`.
2. Write `<workspace>/.cc/phase-<N>-fix.md` with:
   - **What you expected** (quote the acceptance criterion).
   - **What actually happened** (the evidence above).
   - **Hypothesis** (optional — keep short, let CC investigate).
   - **Acceptance:** test md goes green on re-run, no console errors, all network 200s on the asserted endpoints.
3. `state.sh phase_browser_test_failed phase=N evidence_dir=<rel/path>`
4. Send to CC: `Read \`.cc/phase-<N>-fix.md\` and apply.`
5. After CC commits the fix → re-run the browser test. Append a `## Re-run YYYY-MM-DD HH:MM` section to the md.

Three failed iterations on the same phase → escalate: stop the auto-loop, surface to the human reviewer with the consolidated evidence.

## End-of-run E2E suite

When the user invokes `/e2e-suite` (or auto at run end if configured):

1. Read all `docs/e2e-testing/phase-*.md` files in phase order.
2. Stitch into `docs/e2e-testing/E2E-SUITE.md` — a single readable narrative of the entire app.
3. Emit `docs/e2e-testing/specs/e2e.spec.ts` — umbrella spec that imports + re-exports per-phase tests so `npx playwright test e2e.spec.ts` runs the full surface.
4. Generate a coverage table at the top: phase → feature → green/red/skipped → last-run date.

## Idempotency rules

- Re-running the per-phase loop on an unchanged phase → no-op (detect via directive hash + last commit sha).
- Re-emitting Playwright spec → only overwrite if test md's `## Steps` H2 section content hash changed.
- `state.sh` events are append-only — no edits to past events.

## Don't

- Don't write tests speculatively (testing what *might* be there). Test only what the directive said to build and what's in HEAD.
- Don't skip the markdown and emit only Playwright. The markdown is the source of truth for humans; the spec is the source of truth for CI.
- Don't commit screenshots > 500 KB. Compress or store in `.cc/screenshots-cache/` (gitignored) and reference paths.
- Don't run browser tests against production URLs. Default to localhost. Staging requires explicit `BROWSER_TEST_ALLOW_REMOTE=1`.
- Don't let auth secrets leak into committed files. Strip them from network logs before writing.
