# Verify gate — static checks + project test suite, every phase, before Chrome

This is the mandatory pre-browser gate. It runs **after CC commits the phase** and **before Cowork opens Chrome**. The principle: if pytest is red, a "green" browser test is meaningless.

## What it runs

Two tiers, in order, fail-fast:

### Tier 1 — Static
- **Lint** — formatting, style, unused imports.
- **Typecheck** — static types, type narrowing.

### Tier 2 — Tests
- **Unit tests** — fast, isolated, per-function.
- **Integration tests** — module-level, real dependencies (DB, queues) via fixtures.
- **Coverage** — if pillar 5 requires ≥80%, fail below threshold.

Each tier is fail-fast — the first red command stops the chain. Don't run the next. Don't open Chrome.

## Auto-detection (when `.cc/config.json` has no `"static"` / `"test_commands"`)

Project type is inferred from files present in the workspace root:

| Indicator file(s) | Language | Static commands | Test commands |
|---|---|---|---|
| `pyproject.toml` / `setup.py` / `requirements*.txt` | Python | `ruff check .`, `mypy .` (if `mypy.ini` / `[tool.mypy]`) | `pytest -x --tb=short` (or `--cov` if `[tool.coverage]`) |
| `package.json` with `"typescript"` dep | TypeScript | `npx eslint .`, `npx tsc --noEmit` | `npm test -- --run` / `npx vitest run` / `npx jest --ci` (detect from `package.json` scripts.test) |
| `package.json` no TS | JavaScript | `npx eslint .` | `npm test` |
| `Cargo.toml` | Rust | `cargo check`, `cargo clippy -- -D warnings` | `cargo test --workspace` |
| `go.mod` | Go | `go vet ./...`, `gofmt -l .` (fail if non-empty) | `go test ./...` |
| `pom.xml` | Java (Maven) | `mvn -q -B compile` | `mvn -q -B test` |
| `build.gradle*` | JVM (Gradle) | `./gradlew check -x test` | `./gradlew test` |
| `mix.exs` | Elixir | `mix format --check-formatted`, `mix credo --strict` | `mix test` |

**Monorepo:** if multiple indicators exist at the root, run all matching gates in sequence. If indicators exist only in subdirs (e.g. `frontend/package.json` + `backend/pyproject.toml`), run each in its subdir.

**Containers:** if the project has a `Makefile` with a `test` target or a `docker-compose.test.yml`, prefer those — they're the project's blessed entry points. `make test` / `docker compose -f docker-compose.test.yml run --rm test` overrides auto-detection.

## Configuration — `<workspace>/.cc/config.json`

Override auto-detection per-project:

```json
{
  "dev_server_url": "http://localhost:5173",
  "browser_test_root": "docs/e2e-testing",
  "static": [
    "ruff check .",
    "mypy backend/",
    "eslint frontend/"
  ],
  "test_commands": [
    "pytest -x --cov=backend --cov-fail-under=80",
    "npm --prefix frontend test -- --run"
  ],
  "skip_static_on": [],
  "skip_tests_on": [],
  "coverage_min": 80
}
```

Field semantics:
- `static` / `test_commands` — exact shell commands, run in order, fail-fast. Commands inherit the parent env + `PATH`.
- `skip_static_on` / `skip_tests_on` — phase numbers or commit-message prefixes to skip (e.g. `["docs:", "chore:"]`). Use sparingly; phases that touch code should never skip.
- `coverage_min` — numeric percent; if a test command emits a coverage report, this is enforced after the command completes successfully.

## How Cowork runs it

For each command, Cowork:

1. Runs it via the project's working directory (the workspace root unless specified).
2. Captures stdout + stderr + exit code.
3. On non-zero exit → **STOP**. Capture the last 200 lines + the failing assertion → feed into the bug-found protocol (see `bug_driven_tdd.md`).
4. On zero exit → log `state.sh phase_verify_step_passed step="<command>"` and continue.

When all commands pass: `state.sh phase_verify_passed phase=<N>` and advance to browser-test.

## Subagent pattern (large suites)

For projects with multi-minute test runs:

1. Spawn a subagent with the test command + timeout.
2. While it runs, Cowork drafts the browser-test markdown speculatively (won't be saved until verify passes).
3. On verify-green: proceed to browser-test with the pre-drafted md.
4. On verify-red: discard the draft, run bug-found protocol.

This is the only place where speculative work is acceptable — and only because the markdown is throwaway until written.

## Coverage handling

If the test command produces a coverage report (pytest-cov, Jest --coverage, vitest --coverage, cargo-tarpaulin, go test -cover):

1. Read the summary line — pytest: `TOTAL ... NN%`; Jest: `All files | NN`; etc.
2. Compare against `coverage_min`.
3. Below threshold → fail the gate with reason `coverage <NN%> below min <coverage_min>%`. This counts as a red verify and triggers the bug-found protocol (write a test that covers the missing path).

## Don't

- **Don't skip the gate** to "save time." A red unit test + green browser test means the browser test is wrong or the unit test is testing the wrong contract — either way, the phase isn't done.
- **Don't run linters that don't exist** — auto-detection should silently skip a tier if no relevant config is found. Tell the user, don't pretend you ran it.
- **Don't run formatters in `--fix` mode.** The gate verifies; it doesn't mutate. If the formatter would change files, that's a red.
- **Don't cache results across phases.** Each phase's commit changes the codebase; re-run.
- **Don't aggregate red signals.** First red wins. Stop, capture, escalate to bug-found. Running more tests after a red just consumes context.

## Evidence capture on red

When a command fails:

```
.cc/bugs/phase-<N>-bug-<short-slug>.md  ← bug report
  ├── Captured command: <the exact shell command>
  ├── Exit code: <N>
  ├── Last 200 lines of output (verbatim)
  ├── Failing assertion / test name (extracted)
  ├── Stack trace (if present)
  └── Files mentioned in the trace (resolved to absolute paths)
```

This is the input to step 1 (Capture) of the bug-found protocol — see `bug_driven_tdd.md`.
