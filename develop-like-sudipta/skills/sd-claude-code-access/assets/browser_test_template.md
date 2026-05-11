# Test: phase-<N>-<feature-slug>

## Test ID
phase-<N>-<feature-slug>

## Objective
<One sentence in plain English describing what user-visible behavior this verifies.>

## Preconditions
- Dev server running at `<DEV_SERVER_URL>` (default `http://localhost:5173`)
- Database seeded with `<fixture-name>` (run: `<setup-command>`)
- Env vars set: `<list>`
- Auth state: `<unauthenticated | logged-in-as-<role>>`
- Feature flags: `<flag>=<value>`

## Setup
```bash
# Commands run before the test starts
<setup-command-1>
<setup-command-2>
```

## Steps

### s1: <short action description>
- **Action:** <what the test does — e.g. "Navigate to /login">
- **Expected:** <observable result — e.g. "Login form visible with Email + Password fields and a Submit button">
- **Chrome MCP calls:** `navigate("/login")` → `read_page()` → assert form fields exist
- **Screenshot:** `screenshots/phase-<N>/s1.png`

### s2: <short action description>
- **Action:** Fill email = `test@example.com`, password = `<from env E2E_PASS>`, click Submit
- **Expected:** Redirect to `/dashboard`, no console errors, welcome message visible
- **Chrome MCP calls:** `form_input` × 2 → `computer` click submit → `navigate` wait → `read_page`
- **Screenshot:** `screenshots/phase-<N>/s2.png`

### s3: <...>
<add more as needed; one block per acceptance criterion>

## Screenshot anchors
- s1 → `screenshots/phase-<N>/s1.png` — landing page
- s2 → `screenshots/phase-<N>/s2.png` — post-login dashboard
- s3 → `screenshots/phase-<N>/s3.png` — <description>

## Console assertions
**Must NOT contain (substring match, case-insensitive):**
- `error`
- `uncaught`
- `failed to fetch`

**Must contain (optional — usually empty):**
- _(none)_

## Network assertions
| Method | URL pattern | Expected status |
|---|---|---|
| GET | `/api/me` | 200 |
| POST | `/api/login` | 200 |
| GET | `/api/dashboard` | 200 |

No 4xx/5xx allowed on any listed endpoint. Unlisted endpoints are ignored.

## Result
- **Status:** `<pass | fail | pass-with-warnings>`
- **Timestamp:** `YYYY-MM-DD HH:MM:SS TZ`
- **Runner:** sd-claude-code-access / browser-test step
- **CC commit at test time:** `<git rev-parse HEAD>`

## Notes
<Free-form observations. Anything that surprised you. Follow-up items.
If failed: paste the failing screenshot reference, the console error, the network response. This is what gets fed into `.cc/phase-<N>-fix.md`.>

---

<!-- For re-runs after a fix, append sections like the one below. Do NOT edit the original record. -->

## Re-run YYYY-MM-DD HH:MM
- **Status:** pass
- **Trigger:** fix applied via `.cc/phase-<N>-fix.md`
- **CC commit:** `<sha>`
- **Notes:** <what changed, what's now green>
