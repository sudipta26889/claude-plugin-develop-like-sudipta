# Close 24+ Gaps in sd-claude-code-access — v3.2 → v4.0 Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` to implement this plan task-by-task.

**Goal:** Close every audited gap in the `sd-claude-code-access` skill bundled inside the `develop-like-sudipta` plugin so that a single Cowork session can drive a real Claude Code project from brainstorm → ship with verified user-experience testing, regression-proof bug fixes, and CI-ready artifacts.

**Architecture:** The skill is a flat-file methodology (markdown + bash scripts + JSON templates). All changes are file edits — no servers, no DBs. Each gap becomes 1–5 bite-sized tasks; tasks land in tiers (Tier 1 critical → Tier 3 polish). Version 3.2.0 → 4.0.0 because the API surface (commands, references, configuration) grows materially.

**Tech Stack:** Markdown, JSON, Bash, AppleScript (osascript), Python (for the test-output parser), shell-installed tooling (`jq`), Playwright TypeScript, Claude plugin manifest.

**Workspace:** `~/Workspace/personal/claude-plugin-develop-like-sudipta`
**Plugin root:** `~/Workspace/personal/claude-plugin-develop-like-sudipta/develop-like-sudipta/`
**Skill root:** `<plugin-root>/skills/sd-claude-code-access/`

---

## Pre-flight (before any task)

**Read these first:**
- Current SKILL.md state — `<skill-root>/SKILL.md`
- The audit findings (gaps #1–#24) — see "Gap index" at the bottom of this plan
- Existing references to understand the prose style and depth — `<skill-root>/references/*.md`

**Use existing skills:**
- `superpowers:test-driven-development` for any script with logic (e.g. the test-output parser in Tier 2.3)
- `superpowers:verification-before-completion` before claiming each task done
- `superpowers:requesting-code-review` after each Tier completes
- `pm-execution:create-prd` is NOT needed — gaps are well-defined; we go straight to implementation

**Branching:**
- Create a worktree branch `feat/v4-close-skill-gaps` off main
- Commit after every task with Conventional Commits prefix
- One PR per tier (3 PRs total) — easier to review

---

## Tier 1 — Critical (close before next CC-driving run)

### Task 1.1: Audit + extend `danger_patterns.txt` (gap #1)

**Files:**
- Create: `<skill-root>/scripts/audit_danger_patterns.sh`
- Modify: `<skill-root>/scripts/danger_patterns.txt:end` (append section header for per-project extension hint)
- Create: `<skill-root>/references/danger_pattern_governance.md`
- Modify: `<skill-root>/scripts/watchdog.sh` (read `.cc/danger_patterns_extra.txt` if present, union with default)

**Step 1: Write the failing test (smoke)**
`<skill-root>/evals/test_danger_patterns.sh` (new):
```bash
#!/usr/bin/env bash
set -euo pipefail
PATTERNS=$(dirname "$0")/../scripts/danger_patterns.txt
# Must match destructive prompts
echo "Run rm -rf /" | grep -qEf "$PATTERNS" || { echo "FAIL: rm -rf /"; exit 1; }
echo "DROP TABLE users" | grep -qEf "$PATTERNS" || { echo "FAIL: DROP TABLE"; exit 1; }
echo "git push --force origin main" | grep -qEf "$PATTERNS" || { echo "FAIL: force push"; exit 1; }
# Must NOT match routine prompts
echo "Run pytest -x" | grep -qEf "$PATTERNS" && { echo "FAIL: pytest matched"; exit 1; }
echo "Read .cc/phase-3.md and proceed." | grep -qEf "$PATTERNS" && { echo "FAIL: read directive matched"; exit 1; }
echo "PASS"
```

**Step 2: Run test, expect FAIL**
Run: `bash <skill-root>/evals/test_danger_patterns.sh`
Expected: some pattern misses (current file may not cover all variants).

**Step 3: Audit + extend `danger_patterns.txt`**
Read the current file. Add (or confirm presence of) patterns for: `rm -rf [~/]?$` variants, `dd if=`, `mkfs`, `> /dev/sda`, `chmod -R 000`, `chown -R root`, `kubectl delete`, `terraform destroy`, `aws s3 rb`, `gcloud projects delete`, `docker system prune -a -f --volumes`, `truncate table` (case-insensitive), force-push variants, `git filter-branch`, `git reset --hard origin`, `npm publish` (allow-list dry-run), `pip install --break-system-packages` *(false positive — review)*, `curl … | bash`, `wget … | sh`, `sudo rm`, `eval $(`, base64-encoded payload smell.

**Step 4: Write the audit script**
`<skill-root>/scripts/audit_danger_patterns.sh` — bash that:
1. Reads `danger_patterns.txt` + optional `<workspace>/.cc/danger_patterns_extra.txt`
2. Tests each pattern against a hardcoded fixture file of (destructive vs routine) prompts
3. Reports false-positive risk + false-negative coverage as a markdown table

**Step 5: Update watchdog to read per-project extras**
Modify `watchdog.sh` so that just before the grep, it concatenates `<workspace>/.cc/danger_patterns_extra.txt` (if exists) with the base file into a temp file.

**Step 6: Write governance doc**
`<skill-root>/references/danger_pattern_governance.md`:
- How patterns are evaluated (regex, case-insensitive, anchor rules)
- Required process when adding a pattern: provide a destructive example + a routine counter-example
- Per-project extension via `.cc/danger_patterns_extra.txt`
- Dry-run mode: set `WATCHDOG_DRYRUN=1` → log "would-deny" instead of actually denying
- Quarterly review checklist

**Step 7: Run test, expect PASS**
Run: `bash <skill-root>/evals/test_danger_patterns.sh`
Expected: `PASS`

**Step 8: Commit**
```bash
git add scripts/danger_patterns.txt scripts/audit_danger_patterns.sh scripts/watchdog.sh references/danger_pattern_governance.md evals/test_danger_patterns.sh
git commit -m "feat(safety): audit danger patterns + per-project extensions (gap #1)"
```

---

### Task 1.2: Commit-lag-aware audit retry (gap #2)

**Files:**
- Modify: `<skill-root>/scripts/audit.sh`
- Modify: `<skill-root>/SKILL.md` (per-phase loop step 5 — note retry semantics)
- Create: `<skill-root>/references/audit_timing.md`

**Step 1: Failing test**
Create `<skill-root>/evals/test_audit_retry.sh`:
```bash
#!/usr/bin/env bash
# Simulate: directive references files that don't exist yet, then appear after 5s
mkdir -p /tmp/test_audit_repo && cd /tmp/test_audit_repo
git init -q && git commit --allow-empty -m "init" -q
echo "## Task: implement foo.py" > /tmp/test_directive.md
# Backgrounded: create + commit foo.py after 4s
( sleep 4 && touch foo.py && git add foo.py && git commit -q -m "feat: foo" ) &
# Run audit with retry — expect SUCCESS within 10s
START=$(date +%s)
bash <skill-root>/scripts/audit.sh /tmp/test_audit_repo /tmp/test_directive.md --retry 6 --retry-interval 2
END=$(date +%s)
[ $((END-START)) -lt 12 ] || { echo "FAIL: audit didn't retry quickly"; exit 1; }
echo "PASS"
```

**Step 2: Run test, expect FAIL** (audit.sh doesn't support --retry yet)

**Step 3: Add `--retry N --retry-interval SEC` flags to `audit.sh`**
- On "missing file" / "missing commit" findings → if retry budget > 0, sleep `retry-interval` and re-run
- Default: 3 retries × 2s = 6s tolerance for commit-hook lag
- Log each retry to stderr so the user sees the delay

**Step 4: Document in SKILL.md per-phase loop**
Inside step 5 of the per-phase loop, change `audit.sh + read git diff` → `audit.sh --retry 3 --retry-interval 2 + read git diff`.

**Step 5: Write `audit_timing.md`** explaining commit-hook lag patterns (pre-commit hooks, husky, lefthook, gpg signing) and recommended retry budgets per stack.

**Step 6: Run test, expect PASS**

**Step 7: Commit**
```bash
git add scripts/audit.sh SKILL.md references/audit_timing.md evals/test_audit_retry.sh
git commit -m "fix(audit): tolerate commit-hook lag with retry (gap #2)"
```

---

### Task 1.3: Watchdog escalation when routine prompt refused (gap #3)

**Files:**
- Modify: `<skill-root>/scripts/watchdog.sh`
- Modify: `<skill-root>/references/failure_modes.md`
- Create: `<skill-root>/scripts/escalate.sh`

**Step 1: Write test**
`<skill-root>/evals/test_watchdog_escalation.sh`:
- Pipe a fake terminal-buffer that contains BOTH a routine prompt AND a regex match to a known false-positive pattern
- Run watchdog with `WATCHDOG_TEST=1`
- Assert it writes to `<workspace>/.cc/escalations.log` with timestamp, pattern that matched, full prompt text

**Step 2: Update watchdog**
When `DANGER fp=... matched=...` is logged, ALSO append to `<workspace>/.cc/escalations.log` and run `escalate.sh` (no-op default; users can wire it to ntfy/Slack/email).

**Step 3: Write `escalate.sh`**
Default: write to `escalations.log`. Exposes an env hook: if `ESCALATE_CMD` is set, run it with the escalation payload on stdin.

**Step 4: Document in `failure_modes.md`**
New section: "Watchdog refused a routine prompt — what to do":
1. Check `escalations.log` for the matched pattern
2. Verify it really is routine (not a phrasing ambush)
3. Manually press Enter in Terminal (or use `keys.sh return`)
4. Add the prompt's normalization to `danger_patterns_extra.txt` to prevent the same false positive

**Step 5–6:** test pass + commit.

---

### Task 1.4: `state.json` salvage procedure (gap #4)

**Files:**
- Create: `<skill-root>/scripts/state_salvage.sh`
- Modify: `<skill-root>/references/state_and_resume.md` (new "Salvage" section)

**Step 1: Test**
Generate a corrupt state.json (truncated mid-write, invalid JSON line) and assert the salvage script:
1. Detects corruption (jq parse fails)
2. Splits into JSONL (line-by-line), discards malformed lines, keeps valid ones
3. Backs up the original to `state.json.bak.<timestamp>`
4. Rewrites a clean state.json
5. Exits 0 on success, prints a one-line summary of how many events were salvaged vs dropped

**Step 2–6:** standard TDD cycle.

---

### Task 1.5: Update plugin README for v3.2/v4 (gap #23)

**Files:**
- Modify: `<plugin-root>/README.md`

**Step 1:** read the current README.

**Step 2:** rewrite to cover:
- All 3 skills (`develop-like-sudipta`, `code-hacker`, `sd-claude-code-access`)
- All 17 commands (existing + new 7)
- The v3.2 capability table (substrate detection, verify-gate, browser-test, bug-driven TDD, e2e suite, audit)
- Compatibility with `superpowers` and other Sudipta plugins
- Installation: 2 paths — marketplace install vs local clone
- Quickstart: "I want to start a new project end-to-end" → use `/cc-drive`

**Step 3:** commit `docs(readme): cover v3.2 capabilities (gap #23)`.

---

### Task 1.6: Refresh `cc-driver-prompts.md` to align with v3.2 substrate detection (gap #24)

**Files:**
- Modify: `<plugin-root>/cc-driver-prompts.md`

**Step 1:** read current file.

**Step 2:** prepend a "Path A/B/C" preamble to each variant so the user pasting the prompt knows Cowork will probe.

**Step 3:** commit `docs(prompts): align drop-ins with v3.2 substrate detection (gap #24)`.

---

### Tier 1 review checkpoint

After Tasks 1.1–1.6, run `superpowers:requesting-code-review`. Open a PR. Repackage `.plugin` as v3.3.0 (not yet 4.0 — that's after Tier 2).

---

## Tier 2 — High (close before sharing with others)

### Task 2.1: API-level testing for backend-only phases (gap #5)

**Files:**
- Create: `<skill-root>/references/api_testing.md`
- Create: `<skill-root>/assets/api_test_template.md`
- Modify: `<skill-root>/SKILL.md` (verify-gate section — note API tests slot in here for backend phases)
- Modify: `<plugin-root>/commands/browser-test.md` (alias-route: if `BACKEND_ONLY=1`, run API tests instead of Chrome)

**Step 1: Spec**
A "backend-only phase" produces no UI but ships an HTTP/gRPC/queue contract. The skill must:
- Detect backend-only via directive metadata or a CLI flag
- Run contract-level tests: `curl` assertions for REST, `grpcurl` for gRPC, schema validation via OpenAPI/AsyncAPI files
- Emit a `docs/api-testing/phase-N-<slug>.md` (mirrors browser_test_template.md schema)
- Generate a `tests/api/phase-N.test.ts` (or pytest equivalent) for CI

**Step 2: Write `api_testing.md`** with:
- Auto-detection: presence of `openapi.yaml`, `schema.graphql`, `*.proto`
- Per-endpoint test pattern: method, URL, headers, body, expected status, response schema
- Idempotency assertion (call twice, same response on safe methods)
- Auth header reuse from `.cc/auth/storage-state.json`

**Step 3: Write the asset template + the new directive branch in browser-test.md.**

**Step 4: Test** — set up a fixture FastAPI with one endpoint, run the new flow end-to-end, assert artifacts get written.

**Step 5: Commit** `feat(api-testing): verify backend-only phases with contract tests (gap #5)`.

---

### Task 2.2: GitHub Actions workflow generator (gap #6)

**Files:**
- Create: `<skill-root>/assets/github_actions_e2e_template.yml`
- Create: `<skill-root>/scripts/emit_ci_workflow.sh`
- Modify: `<plugin-root>/commands/e2e-suite.md` (at end-of-run, also emit `.github/workflows/e2e.yml`)

**Step 1:** Write the workflow template — runs on PR, installs deps, brings up dev server, plays Playwright suite, uploads HTML report as artifact.

**Step 2:** Detect the project's package manager (npm/pnpm/yarn) + Python runner (poetry/uv/pip) and adapt the template's install commands.

**Step 3:** Idempotent overwrite (hash-tagged comment like the spec generator).

**Step 4:** Test: run the generator against a fixture repo, assert valid YAML, assert key jobs/steps present.

**Step 5:** Commit `feat(ci): auto-emit GitHub Actions e2e workflow (gap #6)`.

---

### Task 2.3: Structured test-runner output parser (gap #8)

**Files:**
- Create: `<skill-root>/scripts/parse_test_output.py`
- Create: `<skill-root>/references/test_output_parsing.md`
- Modify: `<skill-root>/references/bug_driven_tdd.md` (Step 1 capture now uses parser)

**Step 1: TDD via `superpowers:test-driven-development`.**
Write Python tests for each parser dialect (pytest, jest, vitest, cargo, go, mvn) using fixture outputs in `<skill-root>/evals/fixtures/`. Parser should normalize to a JSON schema:
```json
{
  "runner": "pytest",
  "exit_code": 1,
  "summary": {"passed": 12, "failed": 3, "skipped": 1, "errors": 0},
  "failures": [
    {
      "test": "tests/unit/test_cart.py::test_total_includes_tax",
      "file": "src/cart.py",
      "line": 42,
      "assertion": "assert total == Decimal('11.00')",
      "expected": "Decimal('11.00')",
      "actual": "Decimal('10.00')",
      "traceback": "..."
    }
  ]
}
```

**Step 2:** implement minimal regex-based parsers; not a full lexer.

**Step 3:** doc the JSON schema in `test_output_parsing.md`; show how `bug_driven_tdd.md` step 1 consumes it.

**Step 4:** wire bug-report-template generation to fill in the parsed fields automatically.

**Step 5:** all parser tests pass.

**Step 6:** commit `feat(parser): structured test-output extraction (gap #8)`.

---

### Task 2.4: Flake retry + flake whitelist (gap #9)

**Files:**
- Modify: `<skill-root>/references/verify_gate.md`
- Create: `<skill-root>/assets/flake_whitelist.example.json`
- Modify: `<skill-root>/references/bug_driven_tdd.md` (don't write a bug for a known flake)

**Step 1:** add config knob `flake_retries: 2` to `.cc/config.json` and `flake_whitelist: ["tests/integration/test_websocket_race.py::test_reconnect"]`.

**Step 2:** verify-gate logic on red:
1. Is the failing test in `flake_whitelist`? → log + skip → continue
2. Else: re-run JUST the failing tests up to `flake_retries`
3. Still red → real bug → bug-found protocol

**Step 3:** write tests using a fake test runner that fails deterministically the first N times.

**Step 4:** commit `feat(verify): flake retry + whitelist (gap #9)`.

---

### Task 2.5: `data-testid` directive enforcement (gap #16)

**Files:**
- Modify: `<skill-root>/assets/directive_template.md` (add a checkbox: "UI components have `data-testid` on every interactive element")
- Modify: `<skill-root>/references/directive_patterns.md` (worked example shows the testid requirement)
- Modify: `<skill-root>/references/playwright_generation.md` (cross-reference)

**Step 1–3:** simple edits, no new code. Verify the SKILL.md + browser-test command continue to recommend the same selector hierarchy.

**Step 4:** commit `feat(directive): mandate data-testid on UI work (gap #16)`.

---

### Task 2.6: SSH/remote Mac path (Path D) (gap #7)

**Files:**
- Modify: `<skill-root>/references/substrate_and_access.md` (add Path D)
- Modify: `<skill-root>/SKILL.md` Step 0 (include SSH probe)
- Modify: `<skill-root>/references/ssh_variant.md` (cross-link)
- Create: `<skill-root>/scripts/ssh_probe.sh`

**Step 1:** spec — Path D = user has SSH access to a remote Mac running CC. Cowork uses Desktop_Commander on the local Mac, but the local Mac SSHes to the remote and runs bridge scripts there.

**Step 2:** `ssh_probe.sh` checks `ssh ${SSH_TARGET} 'which osascript && which claude'` and returns the remote tier.

**Step 3:** wire into substrate detection ladder as a checkbox after Path A.

**Step 4:** test against a fixture SSH config (or document as manual-only with the test marked skipped).

**Step 5:** commit `feat(substrate): add Path D — remote Mac via SSH (gap #7)`.

---

### Task 2.7: Auth state lifecycle (gap #10)

**Files:**
- Modify: `<skill-root>/references/browser_testing.md` (Auth section)
- Create: `<skill-root>/scripts/check_auth_state.sh`

**Step 1:** check_auth_state.sh validates `storage-state.json` is fresh:
- File mtime < `auth_max_age_minutes` (default 30 from config)
- Cookies haven't all expired (parse `cookies[].expires`)
- Bearer token (if present) isn't 401-rejected by a known health endpoint
On any fail → trigger re-login flow.

**Step 2:** update browser_testing.md to call this before every browser-test step.

**Step 3:** TDD — fake auth states (expired cookies, missing cookies, 401-rejected token) drive the script.

**Step 4:** commit `fix(auth): validate storage-state freshness before each test (gap #10)`.

---

### Task 2.8: Dev-server orchestration (gap #11)

**Files:**
- Create: `<skill-root>/scripts/wait_for_dev_server.sh`
- Modify: `<skill-root>/references/browser_testing.md` (dev-server section)

**Step 1:** wait_for_dev_server.sh:
- Accepts `URL`, `MAX_WAIT_SEC` (default 60), `HEALTH_PATH` (default `/`)
- Polls every 1s until 2xx response (any 4xx/5xx counts as "not ready")
- If `<workspace>/docker-compose.yml` exists → bring up `docker compose up -d` first
- If `<workspace>/package.json` has a `dev` script → start it in background and capture PID for cleanup
- If `<workspace>/.cc/config.json` has a `dev_server_start_cmd` → use that verbatim

**Step 2:** browser_testing.md docs this as the prelude to step 3 (Drive Chrome MCP).

**Step 3:** commit `feat(devserver): wait + orchestrate dev server before browser-test (gap #11)`.

---

### Tier 2 review checkpoint

After Tasks 2.1–2.8, run `superpowers:requesting-code-review`. Open PR #2. Repackage as v3.4.0.

---

## Tier 3 — Medium (polish, ship as v4.0)

### Task 3.1: Test artifact lifecycle (gap #12)

**Files:**
- Create: `<skill-root>/scripts/cleanup_test_artifacts.sh`
- Modify: `<skill-root>/references/browser_testing.md`

**Step 1:** script accepts `WORKSPACE`, `RETENTION_DAYS` (default 30).
- Screenshots older than retention → archive to `.cc/screenshots-archive/<YYYY-MM>.tar.gz`, delete originals
- Per-phase specs whose phase doesn't exist in current state.json → move to `docs/e2e-testing/archive/`
- Report what was archived

**Step 2:** docs + commit.

---

### Task 3.2: Cross-browser / mobile project entries (gap #13)

**Files:**
- Modify: `<skill-root>/assets/playwright_spec_template.ts`
- Modify: `<skill-root>/references/playwright_generation.md`
- Create: `<skill-root>/assets/playwright.config.template.ts` (with chromium + firefox + webkit + Pixel-5 + iPhone-13)

**Steps:** Update the config emitter to include all five projects, gated on a config flag `browsers: ["chromium", "firefox", "webkit", "mobile-chrome", "mobile-safari"]` (default `["chromium"]` for speed).

---

### Task 3.3: A11y assertions (gap #14)

**Files:**
- Modify: `<skill-root>/assets/browser_test_template.md` (new section: A11y assertions)
- Modify: `<skill-root>/assets/playwright_spec_template.ts` (import `axe-playwright` if installed)
- Modify: `<skill-root>/references/playwright_generation.md`

**Steps:** doc + template edits + optional `axe-playwright` integration.

---

### Task 3.4: WebSocket / SSE / streaming testing (gap #15)

**Files:**
- Create: `<skill-root>/references/streaming_testing.md`
- Update: `<skill-root>/references/browser_testing.md` (link)

**Steps:** doc-only. Covers `page.on('websocket', ...)`, intercepting frames, asserting message order; SSE via `EventSource` + `fetch` with manual stream reads.

---

### Task 3.5: Agents for parallel work (gap #17)

**Files:**
- Create: `<plugin-root>/agents/audit-agent.md`
- Create: `<plugin-root>/agents/bug-triage-agent.md`
- Create: `<plugin-root>/agents/playwright-spec-reviewer.md`

**Steps:** Define each agent with `<example>` blocks per the Cowork plugin agent schema. Wire into existing commands where helpful.

---

### Task 3.6: Hooks for the new flow (gap #18)

**Files:**
- Modify: `<plugin-root>/hooks/hooks.json` (commit-msg hook: refuse commit referencing bug-id not present in `.cc/bugs/`)
- Create: `<plugin-root>/hooks/scripts/check_bug_id.sh`
- Create: `<plugin-root>/hooks/scripts/check_test_paired_with_src.sh`

**Steps:** Each hook with a clear refuse-vs-pass criterion + a test fixture.

---

### Task 3.7: Worktree integration doc (gap #19)

**Files:**
- Create: `<skill-root>/references/worktree_integration.md`
- Modify: `<skill-root>/SKILL.md` (cross-link in pre-flight)

**Steps:** doc-only. When using `superpowers:using-git-worktrees`, CC runs in worktree-dir → `WORKSPACE` env should resolve to worktree, not main repo. Show example with multiple parallel worktrees.

---

### Task 3.8: Approval cadence (gap #20)

**Files:**
- Modify: `<skill-root>/references/managing_long_runs.md` (new "Human checkpoint cadence" section)
- Modify: `<skill-root>/assets/config.example.json` (`pause_at: ["phase_complete", "bug_resolved", "verify_gate_red"]`)

---

### Task 3.9: Selector evolution / auto-regen (gap #21)

**Files:**
- Modify: `<skill-root>/scripts/regenerate_phase_specs.sh` (NEW)
- Modify: `<skill-root>/references/playwright_generation.md`

**Steps:** when phase-N changes a UI element, the script walks earlier specs, detects stale selectors via running them and observing "element not found" errors, proposes updates as patches the user can review.

---

### Task 3.10: Evals for new logic (gap #22)

**Files:**
- Create: `<skill-root>/evals/substrate_detection_evals.json`
- Create: `<skill-root>/evals/verify_gate_evals.json`
- Create: `<skill-root>/evals/bug_driven_tdd_evals.json`

**Steps:** Use the `superpowers:writing-skills` pattern (trigger phrases + expected skill invocation). Run via `claude eval` (if available) or document manual eval procedure.

---

### Task 3.11: Final polish + v4.0.0 bump

**Files:**
- Modify: `<plugin-root>/.claude-plugin/plugin.json` → version `"4.0.0"`
- Regenerate `<plugin-root>/README.md` to reflect all v4 capabilities
- Update `<plugin-root>/cc-driver-prompts.md` to add `/api-test` and `/regen-specs` and reflect Path D

**Steps:** edit + commit.

---

### Tier 3 review checkpoint

After Tasks 3.1–3.11, run `superpowers:requesting-code-review`. Open PR #3. Repackage as **v4.0.0**. Update STATUS.md.

---

## Gap index (24 audited gaps → tier mapping)

| # | Gap | Tier | Task |
|---|-----|------|------|
| 1 | danger_patterns audit + per-project extension | T1 | 1.1 |
| 2 | commit-lag-aware audit retry | T1 | 1.2 |
| 3 | watchdog escalation on routine refusal | T1 | 1.3 |
| 4 | state.json salvage procedure | T1 | 1.4 |
| 5 | API-level testing for backend-only phases | T2 | 2.1 |
| 6 | GitHub Actions e2e workflow generator | T2 | 2.2 |
| 7 | SSH/remote Mac path (Path D) | T2 | 2.6 |
| 8 | structured test-runner output parser | T2 | 2.3 |
| 9 | flake retry + flake whitelist | T2 | 2.4 |
| 10 | auth state lifecycle | T2 | 2.7 |
| 11 | dev-server orchestration | T2 | 2.8 |
| 12 | test artifact lifecycle | T3 | 3.1 |
| 13 | cross-browser / mobile | T3 | 3.2 |
| 14 | a11y assertions | T3 | 3.3 |
| 15 | WebSocket / SSE / streaming | T3 | 3.4 |
| 16 | data-testid directive enforcement | T2 | 2.5 |
| 17 | agents shipped | T3 | 3.5 |
| 18 | hooks for new flow | T3 | 3.6 |
| 19 | worktree integration doc | T3 | 3.7 |
| 20 | approval cadence | T3 | 3.8 |
| 21 | selector evolution / auto-regen | T3 | 3.9 |
| 22 | evals for new logic | T3 | 3.10 |
| 23 | plugin README refresh | T1 | 1.5 |
| 24 | cc-driver-prompts refresh | T1 | 1.6 |

---

## Versioning ladder

| Tier complete | Version | Capability added |
|---|---|---|
| Tier 1 | 3.3.0 | Safer watchdog, accurate audit, recoverable state, accurate docs |
| Tier 2 | 3.4.0 | Backend testing, CI, flake/auth/devserver robustness, SSH path |
| Tier 3 | **4.0.0** | Cross-browser, a11y, agents, hooks, evals, polish — production-ready |

---

## Risks + mitigations

| Risk | Mitigation |
|---|---|
| Test-output parser is brittle across runner versions | Cover only the JSON / `--reporter=json` modes when available; fall back to regex |
| GitHub Actions workflow becomes stale as project deps change | Idempotent regeneration on every `/e2e-suite` invocation |
| SSH/Path D adds maintenance burden | Mark as experimental; gate behind explicit `SSH_TARGET` env |
| `data-testid` enforcement annoys teams who use semantic queries | Make the directive checkbox a recommendation, not a hard fail; document the alternative `getByRole` path |
| Auto-regenerating specs corrupts hand-edited tweaks | Source-hash check (already present); refuse overwrite if a `// preserve` comment exists |
| Hooks block legitimate commits | All hooks have a `--bypass` env flag for emergencies; logged to `state.json` |

---

## Out of scope (deliberate)

- Visual regression testing (snapshot diffs) — flaky without curated baselines; defer to v4.x
- Self-hosted CI (Jenkins, Drone) — only GitHub Actions in v4.0
- Windows / Linux host support — macOS-only by design
- Replacing osascript with a native Swift bridge — too much work for marginal gain
- AI-assisted danger-pattern review — manual review for now

---

## How to execute this plan

Open a new Cowork or Claude Code session with this plan in scope. Use:

```
/cc-drive ~/Workspace/personal/claude-plugin-develop-like-sudipta

(when CC asks for the plan)
Read `docs/plans/2026-05-11-close-skill-gaps-v4.md` and proceed task by
task. Apply the bug-driven-TDD discipline for any logic introduced.
Use the verify-gate before claiming each Tier complete. Open one PR per
Tier.
```

The skill we're improving will be the skill that drives its own improvement. Eat the dogfood.
