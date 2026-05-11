# API Test: phase-<N>-<feature-slug>

<!--
This template is the contract for `<workspace>/docs/api-testing/phase-<N>-<feature-slug>.md`.
It is the API-level analogue of `assets/browser_test_template.md` — used when a phase has
no UI surface (REST endpoints, gRPC handlers, queue consumers, background jobs).

Routing logic + auto-detection: see `references/api_testing.md`.

The H2 section order below is load-bearing. A future runner will parse by H2 heading and
fail loudly on missing or reordered sections. Keep them as-is.
-->

## Test ID
phase-<N>-<feature-slug>

## Objective
<One sentence describing the contract this phase establishes — e.g. "Verify POST /api/widgets accepts a valid payload and returns 201 with the created resource shape.">

## Preconditions
- Dev server (API) running at `<API_BASE_URL>` (default `http://localhost:8000`)
- Auth state: `<unauthenticated | bearer-from-storage-state | api-key-from-env>`
  - When auth is required, reuse `<workspace>/.cc/auth/storage-state.json` (same source as browser tests). Extract the relevant cookie/header via `scripts/check_auth_state.sh` semantics.
- Fixtures loaded: `<fixture-name>` (e.g. `seed_widgets_v1`)
- Feature flags: `<flag>=<value>`
- Schema sources discovered (any of):
  - `openapi.yaml` / `openapi.json` at `<path>`
  - `schema.graphql` at `<path>`
  - `*.proto` files under `<path>`
  - `asyncapi.yaml` at `<path>`
  - _(if none present, schema assertions are skipped — note this in §7)_

## Setup
```bash
# Commands run once before the test cases execute.
<setup-command-1>     # e.g. docker compose -f compose.test.yaml up -d
<setup-command-2>     # e.g. pnpm db:seed -- --fixture=seed_widgets_v1
<setup-command-3>     # e.g. export API_BASE_URL=http://localhost:8000
```

## Endpoints under test
| Method | URL | Purpose |
|---|---|---|
| GET | `/api/widgets` | List widgets owned by current user |
| POST | `/api/widgets` | Create a widget |
| GET | `/api/widgets/{id}` | Fetch widget by id |
| PUT | `/api/widgets/{id}` | Replace widget by id |
| DELETE | `/api/widgets/{id}` | Delete widget by id |

## Test cases

### tc1: <short case description>
- **Request:**
  - **Method:** `POST`
  - **URL:** `/api/widgets`
  - **Headers:** `Content-Type: application/json`, `Authorization: Bearer <token>`
  - **Body:**
    ```json
    {"name": "alpha", "color": "blue"}
    ```
- **Expected response:**
  - **Status:** `201`
  - **Headers (subset):** `Content-Type: application/json`, `Location: /api/widgets/<id>`
  - **Body:** matches JSON Schema `WidgetCreated` (from `openapi.yaml#/components/schemas/Widget`)
    OR exact-match fixture `tests/api/fixtures/phase-<N>/tc1.response.json`
- **Idempotency:** `no` (POST creates new state)

### tc2: <short case description>
- **Request:**
  - **Method:** `GET`
  - **URL:** `/api/widgets/{id}` where `{id}` is the value returned in tc1
  - **Headers:** `Authorization: Bearer <token>`
  - **Body:** _(none)_
- **Expected response:**
  - **Status:** `200`
  - **Body:** matches schema `Widget`, with `id`, `name`, `color`, `created_at`
- **Idempotency:** `yes` (calling twice yields the same response)

### tc3: <short case description>
<add more cases as needed — one block per acceptance criterion>

## Schema assertions
For each endpoint that touched a schema source, record the operation/message mapping.

| Endpoint | Schema source | Operation / message | Notes |
|---|---|---|---|
| `POST /api/widgets` | `openapi.yaml` | `paths./api/widgets.post` | response `201` validates `Widget` |
| `GET /api/widgets/{id}` | `openapi.yaml` | `paths./api/widgets/{id}.get` | response `200` validates `Widget` |

If a schema source isn't present in the repo, write `none` in the source column and note "schema-asserted: false" in §10.

## Error-path assertions
| Case | Request mutation | Expected status | Expected body shape |
|---|---|---|---|
| Invalid input | Body with `name=null` | `400` or `422` | error envelope with `field=name` |
| Missing auth | Drop `Authorization` header | `401` | unauthorized error envelope |
| Forbidden | Use a token for a different tenant | `403` | forbidden error envelope |
| Not found | `{id}` set to a known-non-existent uuid | `404` | not-found error envelope |
| Rate limit (if applicable) | Burst N+1 requests | `429` | retry-after header present |

If an error path is not applicable (e.g. endpoint is public), write `N/A` in the row.

## Result
- **Status:** `<pass | fail | pass-with-warnings>`
- **Timestamp:** `YYYY-MM-DD HH:MM:SS TZ`
- **Runner:** sd-claude-code-access / api-testing step (BACKEND_ONLY=1)
- **CC commit at test time:** `<git rev-parse HEAD>`
- **Schema-asserted:** `<true | false>` (false when no schema source present in repo)

## Notes
<Free-form observations. Surprising responses, edge cases that emerged.
If failed: paste the failing curl invocation, the exact response body, response headers, and the diff against the expected schema/fixture. This is what gets fed into `.cc/phase-<N>-fix.md`.>

See `references/api_testing.md` for the routing logic, schema detection, and how this fits the verify-gate / Bug-found protocol.

---

<!-- For re-runs after a fix, append sections like the one below. Do NOT edit the original record. -->

## Re-run YYYY-MM-DD HH:MM
- **Status:** pass
- **Trigger:** fix applied via `.cc/phase-<N>-fix.md`
- **CC commit:** `<sha>`
- **Notes:** <what changed, what's now green>
