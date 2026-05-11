# API-level testing — backend-only phase verification

This reference covers what to do when a phase has **no UI surface** — pure REST endpoint additions, gRPC handlers, queue consumers, schedulers, background jobs. The verify-gate (static checks + unit/integration tests) still runs as the first gate, but afterwards there is no browser to drive. Instead of skipping the post-verify step, we run **contract-level assertions** against the running service.

The methodology mirrors `references/browser_testing.md` one-to-one — same verify-gate-first ordering, same per-phase markdown contract, same fail-fast/Bug-found-protocol semantics — only the substrate is curl/HTTP instead of Chrome MCP.

## When this path runs

API-level testing replaces the browser-test step **for that phase only** when either of these is true:

1. **Explicit:** `BACKEND_ONLY=1` env var is set on the `/browser-test` invocation (or in `.cc/config.json` under the phase's overrides).
2. **Auto-detected:** the phase directive's "what to build" / acceptance criteria contain **no UI signal**. Heuristics, in order:
   - No `data-testid` mention.
   - No page or route mention (no `/login`, `/dashboard`, `routes/...`, `pages/...`, etc.).
   - No visible-text assertion ("user sees…", "the modal shows…", "the button reads…").
   - At least one signal that this is API work: endpoint mention (`/api/...`), HTTP verb in caps (`GET`, `POST`, `PUT`, `DELETE`), gRPC method (`<Service>.<Method>`), queue topic, schema file mention.
   - Tie-breaker: if the directive references `openapi.yaml`, `schema.graphql`, or `*.proto` but no `playwright`/`browser`/`Chrome MCP` strings, treat as backend-only.

When in doubt, **ask the user** rather than guess. False-positive (running API testing on a UI phase) is bad — you skip the only step that catches real-browser regressions. False-negative (opening Chrome on a backend-only phase) burns Cowork context with screenshots of empty pages.

The chosen path is recorded as a state event: `state.sh phase_test_mode mode=<browser|api> phase=<N>`.

## Schema source detection

Walk the workspace root once and record the union of:

| File | Contract surface |
|---|---|
| `openapi.yaml` / `openapi.json` / `swagger.yaml` | REST (OpenAPI 3.x or Swagger 2.x) |
| `schema.graphql` / `*.graphqls` | GraphQL SDL |
| `*.proto` (or `proto/**/*.proto`) | gRPC / protobuf |
| `asyncapi.yaml` / `asyncapi.json` | AsyncAPI (Kafka, AMQP, MQTT…) |
| `tests/api/fixtures/**.json` | Recorded fixtures (compared exact-match) |

Detection happens via a single shell pass; record what was found in `§ Schema sources discovered` of the per-phase api-test markdown. If **nothing** is found, the test still runs — but `schema-asserted` is `false` in the Result section, and the test relies on status-code + fixture comparison only. Note this as future work: hooking up schema validators is its own task.

## Per-endpoint test pattern

Every test case in the per-phase markdown follows the template at `assets/api_test_template.md`. The fields required for each case:

- **Method** — HTTP verb, gRPC RPC name, or queue topic action (publish/consume).
- **URL** — full path (REST) or service/method (gRPC) or topic (queue).
- **Headers** — `Content-Type`, `Authorization`, custom required headers. Auth is shared with the browser-test path (see "Auth handling" below).
- **Body** — request payload, JSON or raw. For binary, pointer to a fixture file under `tests/api/fixtures/phase-<N>/<case>.request.bin`.
- **Expected status** — exact integer.
- **Response shape** — either:
  - JSON Schema reference (`openapi.yaml#/components/schemas/Widget`), or
  - Exact-match against a fixture file (`tests/api/fixtures/phase-<N>/<case>.response.json`).
- **Idempotency** — `yes`, `no`, or `N/A`. See next section.

## Idempotency assertions

For safe methods (`GET`, `HEAD`, `OPTIONS`) and explicitly idempotent methods (`PUT`, `DELETE`), call the endpoint **twice** with the same input and assert the response is identical (status + relevant body fields; ignore timestamps + server-generated ids that are stable across calls).

For `POST` (and any case that mutates server state), idempotency is **not** asserted by default — `POST /widgets` is expected to create two widgets when called twice. If the endpoint is documented as idempotent (e.g. has an `Idempotency-Key` header in OpenAPI), flag it: the test should call twice with the same key and assert the response body is byte-equal.

Record per-case idempotency in the markdown.

## Auth handling

API testing **reuses the same auth state as browser testing**:

1. Source: `<workspace>/.cc/auth/storage-state.json` (Playwright shape — cookies + origins).
2. Freshness gate: same as browser-test — call `scripts/check_auth_state.sh <workspace>` first. If stale, drive the project's login flow once (browser MCP is allowed to be used solely for the login + dump step) and refresh storage-state.json.
3. Cookie → header conversion: when the API expects `Authorization: Bearer <token>`, extract from the cookie whose name matches `<workspace>/.cc/config.json` → `api_auth_cookie_name` (default `access_token`).
4. For pure header-auth (no cookie), look up `<workspace>/.cc/auth/api-headers.json` (gitignored), which is created once by the user with the headers their API needs.

Auth precedence: header file > storage-state cookie > unauthenticated (the api test asserts the 401 error path).

## Output artifacts (where things land)

Per phase, two artifacts:

```
<workspace>/
├── docs/
│   └── api-testing/
│       ├── phase-<N>-<feature-slug>.md     # human-readable test record (from assets/api_test_template.md)
│       └── (no specs subdir — the spec is emitted into the project's test tree, not here)
└── tests/
    └── api/
        ├── phase-<N>.test.ts                # OR phase-<N>_test.py — see "Spec emission" below
        └── fixtures/
            └── phase-<N>/
                ├── tc1.request.json
                └── tc1.response.json
```

The markdown is the human contract (same role as `docs/e2e-testing/phase-N-*.md`).
The emitted test file is the executable artifact (same role as `docs/e2e-testing/specs/phase-N.spec.ts`).

## Spec emission — language-detected runner

Look at the workspace to decide the test framework, in this priority order:

| Detector | File / dir | Framework | Output file |
|---|---|---|---|
| `package.json` exists with a `test` script | repo root | TypeScript / JS (vitest / jest — detect from `devDependencies`) | `tests/api/phase-<N>.test.ts` |
| `pyproject.toml` exists with `[tool.pytest]` or `pytest` in deps | repo root | pytest | `tests/api/test_phase_<N>.py` |
| `Cargo.toml` exists | repo root | Rust integration test | `tests/api/phase_<N>.rs` |
| `go.mod` exists | repo root | Go test | `tests/api/phase_<N>_test.go` |
| nothing recognized | — | fall back to a `curl`-based bash script | `tests/api/phase-<N>.sh` |

The emitted file mirrors the markdown's test cases one-for-one: one assertion block per `### tcN:` heading. Idempotency cases emit a second request in the same block with the same expected response.

**Runner integration is out of scope for v3.4.** The emitted file lives at the path above; whether it joins the project's test suite (and how) is a future task. For now, the test record exists; running it remains a project-specific call.

## How this fits the verify-gate and Bug-found protocol

1. **Verify-gate runs first.** Static + unit + integration. If red → Bug-found protocol. No API testing.
2. **API testing replaces the browser-test step** when backend-only. Run order:
   a. Start the API server if needed (re-use `scripts/wait_for_dev_server.sh` — `health_path` defaults to `/healthz` or `/health` for API mode).
   b. Run each test case in order, recording status + response.
   c. If any case fails → Bug-found protocol (same as browser-red). Write `.cc/bugs/phase-<N>-bug-<slug>.md`; reproduce in code (unit-test layer + API-test layer); fix; confirm; loop.
3. **Coverage / cross-link:** the per-phase api-test md links back to the directive (`.cc/phase-<N>.md`) and the verify-gate output. Same audit pattern as browser-test (`audit.sh` reports both `docs/e2e-testing/` and `docs/api-testing/` outputs).

## Tradeoffs vs browser-testing

| Aspect | Browser-test (UI phase) | API-test (backend-only phase) |
|---|---|---|
| Substrate | Chrome MCP | curl + JSON Schema validator |
| Source of truth | DOM + console + network | Status code + response body + schema |
| Auth | storage-state.json cookies | same source, cookie or header |
| Spec output | Playwright `*.spec.ts` | Project-native test (vitest / pytest / etc.) |
| Cost per phase | High (browser launch, DOM walks) | Low (a few curl calls) |
| Catches | UX regressions, console errors, race conditions | Contract regressions, status codes, schema drift |

If a phase has BOTH a UI surface AND new backend endpoints, run browser-test (the browser exercises the backend transitively). API-only is the substitute for **no-UI** phases, not an additional layer.

## Future work (NOT in scope here)

- **Runner integration.** Today the test file is emitted but not wired into the project's test suite or CI. A follow-up task should generate runner stubs (vitest `describe.skip` → `describe` after manual confirmation, pytest `@pytest.mark.api`, etc.) and update `emit_ci_workflow.sh` to surface api-test runs in the GitHub Actions workflow.
- **JSON Schema validator binary.** No validator is bundled. The methodology assumes the user has `ajv-cli`, `openapi-schema-validator`, or `prance` available in their dev environment; if not, the test record notes "schema-asserted: false". Bundling a vendored validator is a separate decision (license + size).
- **Pact / consumer-driven contracts.** Out of scope. If the user has Pact in their stack, the api-test markdown can reference Pact files in §7 Schema assertions, but generating Pact files is a different protocol.

## Don't

- **Don't open Chrome on a backend-only phase.** It wastes context and screenshots nothing useful.
- **Don't skip the verify-gate to "save time".** API testing presupposes a green test suite; running it on red is meaningless — you're chasing curl output against a known-broken service.
- **Don't bake credentials into the markdown or the emitted test file.** Reuse `.cc/auth/` like the browser path does.
- **Don't run against production.** Default to localhost. Staging requires `BROWSER_TEST_ALLOW_REMOTE=1` (same env as browser-test).
- **Don't emit the test file without the markdown.** The markdown is the contract; the test is the executable mirror. A spec without a markdown breaks the audit pattern.
