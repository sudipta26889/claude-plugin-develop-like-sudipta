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
3. Verify the server is reachable before driving Chrome. **Don't hand-roll the probe** — use `wait_for_dev_server.sh` (see next section). It already encodes the URL-resolution priority, knows how to start docker-compose / `npm run dev` / a project-specific command, and surfaces a single-line status.

### Dev-server orchestration

Before invoking the Chrome MCP, ensure the dev server is up. Use:

```bash
bash ~/.cache/ccbridge/wait_for_dev_server.sh <workspace>
```

Optional flags: `--url URL`, `--max-wait SEC`, `--health-path PATH`.

The script handles three scenarios:

1. **Already running** — probes the URL once, exits 0 immediately with `already-running`. No side effects.
2. **Not running, can be started** — detects in this order:
   - `<workspace>/.cc/config.json` → `dev_server_start_cmd` (explicit override)
   - `<workspace>/docker-compose.test.yml` → `docker compose -f docker-compose.test.yml up -d`
   - `<workspace>/docker-compose.yml` → `docker compose up -d`
   - `<workspace>/package.json` → `scripts.dev` → `npm run dev` (or `pnpm dev` / `yarn dev` based on lockfile)

   Spawns the start command in the background via `nohup`, persists PID to `<workspace>/.cc/dev-server.pid` and stdout/stderr to `<workspace>/.cc/dev-server.log`, then polls the health-path every 1s up to `--max-wait` (default 60s). On 2xx → exit 0 with `started-and-ready elapsed=Ns pid=N source=...`. On timeout → kills the started process tree, dumps the last 20 lines of the log to stderr, exits 1 with `start-failed`.
3. **Not running, no start command** — exits 2 with `not-running-no-start-cmd`. Caller decides: prompt user, skip the browser-test, or write a `.cc/start-dev.md` directive.

Exit codes:

| Exit | Status token | Meaning |
|---|---|---|
| 0 | `already-running` | URL responded 2xx on the first probe |
| 0 | `started-and-ready` | URL responded 2xx after the script started the server |
| 1 | `start-failed` | Start command ran but URL never responded within `--max-wait` |
| 2 | `not-running-no-start-cmd` | URL didn't respond and no start command was detected |
| 3 | (misconfiguration) | Bad URL, non-integer `--max-wait`, unknown flag, etc. |

Configuration keys read from `<workspace>/.cc/config.json`:

- `dev_server_url` — base URL, default `http://localhost:5173`
- `dev_server_start_cmd` — override the auto-detected start command (e.g. `make dev` or `docker compose -f docker-compose.local.yml up -d`)
- `dev_server_health_path` — path to probe, default `/`
- `dev_server_max_wait` — startup timeout in seconds, default 60

After the run finishes, tear down via the PID file (recursive walk handles `npm`-spawned children):

```bash
pid="$(cat <workspace>/.cc/dev-server.pid 2>/dev/null)"
[ -n "$pid" ] && kill "$pid" 2>/dev/null
rm -f <workspace>/.cc/dev-server.pid
```

Or, for docker-compose: `docker compose down` (the script intentionally does not auto-stop containers — leave that to the user to keep their workflow intact).

If you previously wrote `.cc/start-dev.md` directives asking CC to start the server, retire them — the orchestrator owns that responsibility now. Reserve a directive-style nudge only for case 3 (no start cmd found) when the project's start sequence is too bespoke to auto-detect.

## Auth handling

If the feature is behind a login wall, every browser-test step starts with a freshness check via `check_auth_state.sh`. **Don't skip this** — without it, an expired session lands you on a login form and the next assertion fails against the wrong DOM.

```bash
bash ~/.cache/ccbridge/check_auth_state.sh <workspace>
```

The script prints exactly one token on stdout and uses the exit code to classify the verdict:

| Reason | Exit | What it means | Action |
|---|---|---|---|
| `fresh` | 0 | Storage state recent + cookies valid (+ liveness check passed if configured) | Proceed to the browser test |
| `missing` | 1 | No `<workspace>/.cc/auth/storage-state.json` on disk | Run the project's login flow once, persist via the Chrome MCP's storage-state save |
| `stale-by-age` | 2 | File older than `auth_max_age_minutes` (default 30) | Refresh — re-drive the login flow OR re-save existing session |
| `stale-by-cookie-expiry` | 3 | Critical session cookies (`session`, `auth`, `token`, `JSESSIONID`, `sb-*`) expired | Re-drive login flow |
| `stale-by-401` | 4 | Liveness `GET` returned 401/403 | Server-side session revoked — re-drive login flow |

On any non-zero exit: drive the login flow once with the Claude-in-Chrome MCP (`navigate` + `form_input` + `computer` click on submit), save fresh storage state, then **re-run `check_auth_state.sh`** until it returns `fresh`. Only then call `mcp__Claude_in_Chrome__navigate` for the actual feature under test.

The driver loop pattern:

```bash
# Pseudocode — wire into the per-phase browser-test directive.
reason="$(bash ~/.cache/ccbridge/check_auth_state.sh "$WS")"
case "$reason" in
  fresh) ;;                                  # go
  missing|stale-by-age|stale-by-cookie-expiry|stale-by-401)
    # signal CC to drive login_flow.md, then refresh storage state
    state.sh auth_refresh_required reason="$reason"
    ;;
esac
```

Configuration via `<workspace>/.cc/config.json`:
- `auth_max_age_minutes` — max age before age-based staleness fires (default 30).
- `auth_health_url` — optional URL hit with the cookies to verify the session is still valid server-side (e.g. `https://app.local/api/me`). Skip it if you don't have a cheap authenticated endpoint.

Never bake credentials into the markdown or spec. Use env vars (`E2E_USER`, `E2E_PASS`) and reference them in the Playwright fixture. The login flow markdown at `<workspace>/.cc/auth/login_flow.md` describes the one-time sequence (URL, selectors, success criterion) and reads credentials from the env at run time.

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

> For streaming features (WebSocket / SSE / HTTP chunked), see `references/streaming_testing.md` — assertions about frame content and message timing need a different pattern than the table above.

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
