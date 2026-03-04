---
name: develop-like-sudipta
description: >
  MANDATORY for ALL software development. ALWAYS invoke this skill when the user asks about coding,
  development, testing, deployment, architecture, debugging, APIs, Docker, CI/CD, or any code changes.
  Do NOT write, modify, review, or debug code directly — use this skill first to ensure all 11 pillars
  are enforced. Works WITH superpowers plugin (brainstorming, TDD, code-review, subagent-development)
  and ADDS domain-specific enforcement: env var synchronization, OWASP security, distributed system
  patterns (SAGA, outbox, idempotent consumers), API design (REST, idempotency, cursor pagination),
  resilient error handling (retries, circuit breakers, structured logging), CI/CD pipeline (GitHub
  Actions, Docker, GHCR, Portainer), and script-enforced hooks for mechanical compliance checking.
  Triggers on: implementing, fixing, refactoring, reviewing, testing, debugging, documenting,
  designing, deploying, or discussing code. No exceptions.
---

# Develop Like Sudipta

Battle-tested development discipline. Sources: Google SRE, DORA, OWASP, Fowler, Thoughtworks.

**Why this discipline?** AI-assisted code increases PR volume 20% but incidents per PR rise
23.5% (CodeRabbit). AI-generated code introduces 322% more privilege escalation paths (Apiiro).
66% of developers say AI code is "almost right, not quite" (Stack Overflow, 90K devs).
Every pillar exists to close that quality gap.

**Integration:** Works WITH superpowers (brainstorming, TDD, subagents, code review, git
worktrees). This skill adds: domain pillars + script-enforced hooks.
Without superpowers: fully self-contained — all pillars + hooks work independently.

| # | Pillar | Core Principle | Enforcement |
|---|--------|---------------|-------------|
| 1 | **Plan First** | Evidence-based. Brainstorm → plan → verify → execute. | MD + superpowers:brainstorming |
| 2 | **Code Quality** | SOLID + DRY + KISS + defensive + audit-fix cycles. | MD + PostToolUse lint |
| 3 | **Env Sync** | Every env var change updates ALL surfaces simultaneously. | **Script** (PostToolUse) |
| 4 | **Security First** | OWASP Top 10. Validate input. Vault secrets. Scan deps. | **Script** (PostToolUse) |
| 5 | **Test-Driven** | TDD: failing test FIRST. 70/20/10 pyramid. ≥80% coverage. | **Script + superpowers:tdd** |
| 6 | **Resilience** | Structured logging. Retries. Circuit breakers. Distributed. | MD (LLM judgment) |
| 7 | **API Design** | RESTful. Versioned. Idempotent everywhere. | MD (LLM judgment) |
| 8 | **Git Discipline** | Conventional Commits. Trunk-based. Atomic. Protected. | MD + superpowers:git-worktrees |
| 9 | **Clean Codebase** | Zero dangling code. Safe debugging. | **Script** (PostToolUse) |
| 10 | **Latest Deps** | Research → learn → validate → implement. Pin versions. | MD (LLM judgment) |
| 11 | **CI/CD** | GitHub Actions → GHCR → Portainer. | **Script** (Dockerfile checks) |

## Superpowers Delegation

| When | Delegate To |
|---|---|
| Design/brainstorm | `superpowers:brainstorming` |
| Implementation plan | `superpowers:writing-plans` |
| Coding | `superpowers:subagent-driven-development` |
| TDD cycle | `superpowers:test-driven-development` |
| Code review | `superpowers:code-reviewer` |
| Debugging | `superpowers:systematic-debugging` |
| Git workflow | `superpowers:using-git-worktrees` |
| Branch finish | `superpowers:finishing-a-development-branch` |

Each pillar adds domain constraints (security, env sync, API design) that superpowers doesn't cover.

## Subagent Dispatch Protocol

Context pollution = implementation knowledge bleeds into test logic within one window.

- One subagent per task. Fresh context = clean reasoning.
- Dispatch via `Task` tool only. Never bash "launch" or "run" — misinterpreted as shell commands.
- Two-stage review: spec compliance first → code quality second.
- Test writer never sees implementation. Implementer never sees spec.
- After completion: review output in main context. Don't merge raw subagent state.

WHY: Single-context sessions degrade past ~50% usage. Subagents keep each task under 30%.

### MCP vs Skill Division

MCP = connectivity (API access, query formats). Skill = expertise (workflow logic, output structure).
Watch for conflicting instructions between MCP server prompts and skill instructions.

---

## Anti-Rationalization Table

When you think a pillar doesn't apply, check here FIRST:

| Excuse | Rebuttal |
|--------|----------|
| "Just a quick fix" | Quick fixes cause most production incidents. Plan it (1). |
| "Only one line" | One-line changes need tests. Failing test first (5). |
| "I'll add tests later" | NO. TDD: failing test BEFORE production code. No exceptions. |
| "Temporary code" | Temporary becomes permanent. All pillars or mark EXPERIMENTAL + TODO. |
| "Skill is overkill" | 1% chance a pillar applies → follow it. |
| "I know the latest API" | Training data is stale. Research-first is MANDATORY (10). |
| "Security doesn't matter here" | Every endpoint is an attack surface. Validate input. Always (4). |
| "Don't need a plan" | The task that doesn't need a plan is exactly the one that does (1). |
| "Env vars are fine" | Check ALL surfaces. Drift = bug. One missing = production outage (3). |
| "Works on my machine" | Add health checks, Docker, CI. Local ≠ production (11). |
| "Tests are passing" | Real behavior or mocking everything? Run anti-pattern scan (5). |
| "I'll clean up later" | Boy Scout Rule: leave it better NOW. Zero dangling code (9). |
| "This package works fine" | Is it maintained? Superseded? Search before installing (10). |
| "API key is simpler" | No rotation, no scoping, no revocation. Use OAuth 2.1 + PKCE (7). |

---

# Pillar 1 — Plan First

**Non-negotiable:** No code without a plan. No ✅ without tool-verified evidence.
**Superpowers:** `brainstorming` → `writing-plans` for full workflow.

```
BRAINSTORM → Problem? Why? Constraints? Trade-offs? Edge cases?
PLAN       → .claude/plans/<n>.md with goal, approach, files, risks
VERIFY     → Tools confirm reality before documenting status
EXECUTE    → Follow plan step-by-step. Update if scope changes.
```

**Verify with tools, not assumptions:**
Files → read content, not existence. Endpoints → `curl`. Tests → run + check output.
Services → `docker compose ps` + logs. Migrations → check files have content.

Verdicts: ✅ Verified (evidence) | ⏳ Partial | ❌ Not started

---

# Pillar 2 — Code Quality + Audit-Fix

**Standard:** Code violating these principles does not enter the codebase.
**Enforced:** PostToolUse runs ruff (F401/F841).

## SOLID — Procedures, Not Rules

Before writing any code:
1. **Single responsibility** — describe in one sentence without "and"?
2. **Open/Closed** — Protocol/interface to extend? Don't modify stable code.
3. **Liskov** — subtype honors ALL base type contracts?
4. **Interface segregation** — clients depend on unused methods? Split.
5. **Dependency inversion** — business logic instantiating concretes? Inject abstractions.

## Beyond SOLID

DRY (Rule of Three), KISS ("junior-understandable?"), YAGNI, Fail Fast (guard clauses),
Law of Demeter (no train wrecks), Composition > Inheritance (depth >2 = smell),
Command-Query Separation (mutate OR return, never both).

## Defensive Programming

- **Preconditions** — validate inputs at entry. `assert` in dev, explicit checks in prod.
- **Postconditions** — verify outputs before returning. Critical for financial/security ops.
- **Class invariants** — validate after every mutation.
- **Design by Contract** — document caller promises (pre) + function guarantees (post).

## Audit-Fix Cycle

```
AUDIT → SOLID, redundancy, orphans, docs, types, security, defensive checks
PRIORITIZE → P0 Critical → P1 High → P2 Medium → P3 Low
FIX → By priority. Tests pass between waves.
RE-AUDIT → Findings > 0? Repeat. Findings = 0? Done.
```

WHY-First docs: every function/class: **WHY** → **THOUGHT** → **HOW** (if non-obvious).

### End-of-Session Review (Complex Tasks)

For large changes (>5 files), launch parallel review agents:
1. Guide accuracy — do READMEs/docs match current code?
2. Cross-file consistency — naming, patterns, imports aligned?
3. Hook/skill alignment — did corrections reveal a missing rule?
Triage → fix → re-check (max 5 rounds).

---

# Pillar 3 — Env Var Synchronization

**Hard rule:** Every env var change reflects in ALL config surfaces simultaneously.
**Enforced:** PostToolUse detects env var patterns → injects sync reminder.

On any env var add/remove/modify, update ALL in SAME operation:
`.env.example` → `.env` → `docker-compose*.yml` → `portainer/stack-*.yml` → config model → CI/CD → docs

Standards: SCREAMING_SNAKE_CASE, domain-prefixed (`AUTH_*`, `DB_*`), `# SECRET` marker,
Pydantic `Field()` with `ge`/`le`. **Drift = bug.**

---

# Pillar 4 — Security First

**Iron Law:** Security is designed in, not bolted on.
**Enforced:** PostToolUse scans for hardcoded secrets, raw SQL concat.

> **Full OWASP checklist, JWT, headers, SAST/DAST:** Read `references/security.md`

Before writing any endpoint:
1. Define input schema (Pydantic/Zod with type, length, format).
2. Parameterize all queries — never string-concat user input.
3. Check auth + authz — endpoint has auth? RBAC check?
4. Scan for secrets — creds in source? Vault them.
5. Review headers — CSP, HSTS, X-Frame-Options: DENY, nosniff.
6. Audit deps — Snyk/Trivy. Block HIGH/CRITICAL.
7. JWT — RS256/ES256, 15-min access, HttpOnly/Secure, refresh rotation.

---

# Pillar 5 — Test-Driven Integrity

**Iron Law:** NO PRODUCTION CODE WITHOUT A FAILING TEST FIRST.
**Superpowers:** `test-driven-development` enforces RED→GREEN→REFACTOR.
**Enforced:** PreToolUse checks test file existence. Stop hook runs test suite.

## TDD Protocol

```
RED    → Write failing test defining expected behavior
GREEN  → MINIMUM production code to pass
REFACTOR → Clean up, tests stay green
REPEAT → Next behavior? Back to RED
```

**Hard restart triggers** (superpowers also enforces):
- Production code before test → STOP, restart from RED
- Test passes immediately → test isn't testing anything
- Test modified to pass → fix production code instead

## Anti-Pattern Detection

| Anti-Pattern | Signal | Impact |
|---|---|---|
| Over-mocking | >5 `Mock()` per test | False confidence |
| Circular assertions | `mock.return_value = X; assert == X` | Tautology |
| Weak assertions | Only `is not None` | Misses bugs |
| No error paths | Zero `pytest.raises` | Untested errors |
| Testing internals | Checks private methods | Brittle |
| No DB tests | All DB ops mocked | Schema untested |
| Implementation leakage | Test knows HOW not WHAT | Coupled |

≥80% coverage (CI blocks below), AAA pattern, happy + error paths, VCR.py for APIs,
test isolation (no shared state), flaky test SLA (30-day fix-or-remove).

---

# Pillar 6 — Resilience & Observability

**Principle:** Systems fail gracefully, log structurally, retry intelligently, expose health.

> **Retry/circuit breaker, OpenTelemetry:** Read `references/resilience.md`
> **SAGA, outbox, distributed locks:** Read `references/distributed-patterns.md`

Structured JSON logging (no `print()`), retry w/ backoff+jitter, circuit breakers,
health checks (`/healthz`, `/ready`), graceful degradation, correlation IDs,
Four Golden Signals, observability-first (telemetry BEFORE business logic).

Before multi-service/async work: identify failure modes → choose consistency model →
add idempotency → implement outbox → set timeouts everywhere.

---

# Pillar 7 — API & Idempotent Design

**Standard:** Idempotency isn't just for REST — it's for DB writes, queues, webhooks, migrations.

> **Pagination, errors, rate limiting:** Read `references/api-design.md`
> **DB/queue/webhook idempotency:** Read `references/distributed-patterns.md`
> **MCP server OAuth 2.1 authentication:** Read `references/mcp-auth.md`

### MCP Server Authentication — OAuth 2.1 Mandatory

When building ANY MCP server: use OAuth 2.1 with PKCE. No API keys. No basic auth.

Required endpoints: discovery (RFC 8414 + 9728), dynamic client registration (RFC 7591),
authorization code + PKCE S256 (RFC 7636), token exchange with rotation, revocation (RFC 7009),
bearer token auth (RFC 6750). See `references/mcp-auth.md` for full implementation pattern.

| Layer | Pattern | Implementation |
|---|---|---|
| API | `Idempotency-Key` header | Redis: key → response, 24h TTL |
| Database | `ON CONFLICT` / upserts | Natural keys + unique constraints |
| Queues | Dedup ID per message | Consumer tracks processed IDs |
| Webhooks | Event ID dedup | `processed_events` table, always 200 |
| Migrations | Re-runnable DDL | `IF NOT EXISTS`, `CREATE OR REPLACE` |
| Celery | Task ID dedup | `task_id` + Redis lock |

RESTful, version from day one, cursor pagination, RFC 7807 errors, rate limiting,
OpenAPI spec, backwards compatibility (additive only within version).

---

# Pillar 8 — Git Discipline

**Standard:** Every commit tells a story.
**Superpowers:** `using-git-worktrees` + `finishing-a-development-branch`.

> **Branching, hooks, CODEOWNERS:** Read `references/git-workflow.md`

Conventional Commits, trunk-based (<1-2 day branches), atomic commits, SemVer,
branch protection, pre-commit hooks (format, lint, secrets), PR <400 lines.

**No AI attribution in commits.** Never use `Co-authored-by`, `Signed-off-by`, or any
credit to Claude, Cursor, Copilot, Anthropic, or any AI tool. All commits authored
by Sudipta Dhara only. AI is a tool, not a co-author.

---

# Pillar 9 — Clean Codebase

**Zero tolerance:** No dangling code ships.
**Enforced:** PostToolUse runs `ruff check --select F401,F841` on edited Python files.

Unused imports/functions/dead branches → remove immediately.
Debugging: preserve (`# ORIGINAL CODE` tag) → simplify → restore → verify tests.
Commented code: valid ONLY with `[CONTEXT TAG]` + explanation + TODO.

---

# Pillar 10 — Latest Dependencies

**Non-negotiable:** Never assume training knowledge is current. Never install from memory.

> **Python banned/modern packages:** Read `references/python-practices.md`
> **TypeScript banned/modern packages:** Read `references/typescript-practices.md`
> **Performance/DB:** Read `references/performance-db.md`

## Package Selection Gate

Before ANY `pip install`, `uv add`, `npm install`, `pnpm add`, or equivalent:

1. **STOP** — Do NOT install from memory. Training data is stale.
2. **SEARCH** — `web_search "<package> vs alternatives 2025"` or `"best <category> python/node package 2025"`
3. **VERIFY** — Actively maintained? Last release <6 months? Not deprecated? Not superseded?
4. **COMPARE** — Modern replacement exists? Check banned lists in language reference files.
5. **INSTALL** — Only after verification. Pin exact version.

### Known Cross-Language Legacy → Modern Replacements

| Legacy (NEVER use in new projects) | Modern (USE THIS) | Why |
|---|---|---|
| `requests` | `httpx` | Async-native, HTTP/2, drop-in API |
| `flask` (new projects) | `fastapi` | Async, auto-docs, Pydantic validation |
| `pip` / `poetry` | `uv` | 20x faster, Rust-based, replaces all |
| `flake8` + `black` + `isort` | `ruff` | Single tool, 100x faster, Rust-based |
| `unittest` | `pytest` | Simpler, fixtures, plugins |
| `logging` (stdlib) | `structlog` | Structured JSON, context binding |
| `moment.js` | `dayjs` or native `Temporal` | Moment deprecated, 70KB |
| `create-react-app` | `vite` | CRA abandoned |
| `jest` (new projects) | `vitest` | Vite-native, faster, ESM-first |
| `tslint` | `eslint + typescript-eslint` | TSLint deprecated 2019 |
| `require()` / CommonJS | ES Modules (`import`) | CJS is legacy in new projects |

**Exception:** Existing codebases — don't rewrite working deps. Gate applies to NEW additions only.

## Research-First Protocol

`web_search` latest version → `web_fetch` official docs → validate API signatures → implement.
Pin versions, audit CVEs, automate updates (Renovate/Dependabot).

---

# Pillar 11 — CI/CD & Deployment

**Principle:** Code not deployed is inventory, not value.
**Enforced:** PostToolUse checks Dockerfiles for non-root USER, no secrets.

> **Full pipeline, Dockerfiles, Portainer:** Read `references/cicd-deployment.md`

Pipeline: GitHub Actions → Security Audit → Build+Push GHCR (latest+SHA) → Trivy scan.
Two-environment Docker (compose local, stack prod), YAML anchors for DRY, non-root users,
external networks, feature flags lifecycle (create→enable→remove→delete, 90-day SLA).

---

# Script-Enforced Hooks

Hooks fire deterministically via Claude Code's hook system — no LLM memory needed.

> **Full hook architecture, script details, enforcement boundaries, and lightweight alternatives:**
> Read `references/enforcement-hooks.md`

| Hook | Trigger | Checks |
|---|---|---|
| `tdd-gate.sh` | PreToolUse (Write/Edit) | Test file exists for module? |
| `post-edit-check.sh` | PostToolUse (Write/Edit) | Env vars, secrets, lint, Dockerfile, .env sync |
| `completion-gate.sh` | Stop | Tests pass, coverage ≥80%, TODO count |
| `state-saver.sh` | PreCompact | Auto-save state to `.claude/plans/` |

Scripts catch mechanical violations. MD guides judgment calls.
Together: ~95% compliance vs ~50% from MD alone.

---

# Context Window Management

1. **Manual compact at 50%** — never trust auto-compaction. `/compact` proactively.
2. **State in files** — plans, progress, findings → `.claude/plans/`. Rebuilt from files.
3. **PreCompact hook** — auto-saves state before compaction.
4. **Progressive disclosure** — load references only when pillar triggers.
5. **Offload heavy tasks** — research, audits → subagent.

### Reference Loading Guide

| Reference File | Load When |
|---|---|
| `security.md` | Security review, auth, input validation |
| `api-design.md` | API design, pagination, idempotency |
| `resilience.md` | Error handling, retries, logging |
| `distributed-patterns.md` | Multi-service, queues, webhooks, SAGA |
| `git-workflow.md` | Branching, commits, PRs |
| `python-practices.md` | Python tooling, patterns |
| `typescript-practices.md` | TypeScript/JS tooling, patterns |
| `performance-db.md` | Query optimization, caching, migrations |
| `cicd-deployment.md` | Docker, GitHub Actions, Portainer |
| `enforcement-hooks.md` | Hook details, script behavior |
| `mcp-auth.md` | MCP server development, OAuth 2.1, PKCE |

### Skill Frontmatter for Isolation

- `context: fork` — run skill in subagent with isolated context
- `disable-model-invocation: true` — only user can invoke (for /deploy, /commit)
- `user-invocable: false` — only Claude can invoke (background knowledge)
- `allowed-tools: Read, Grep, Glob` — restrict tool access per skill

### Agent Memory (MEMORY.md)

First 200 lines of `.claude/MEMORY.md` inject into agent system prompt at startup.
Use for persistent project conventions, team standards, cross-session state.

### Skill Self-Evolution

After repeated corrections on a pattern, update the relevant reference file.
Add rules based on what Claude gets wrong, not upfront. CLAUDE.md is a living guardrail.

### Description Budget

All skill descriptions share a 15,000-character budget. Exceeding silently drops skills.
Current description: ~950 chars. Monitor when adding new skills.

---

# Unified Workflow

```
 1. BRAINSTORM (1)      → superpowers:brainstorming OR manual plan
 2. WRITE PLAN (1)      → superpowers:writing-plans OR .claude/plans/<n>.md
 3. RESEARCH DEPS (10)  → web_search latest version, web_fetch docs
 4. FAILING TEST (5)    → superpowers:tdd RED phase. Script verifies test exists.
 5. IMPLEMENT (2)       → superpowers:tdd GREEN phase. SOLID + defensive.
 6. REFACTOR (2+5)      → superpowers:tdd REFACTOR. PostToolUse lint runs.
 7. SECURE (4)          → Script scans secrets. Manual auth/input review.
 8. SYNC ENV (3)        → Script detects env vars. Manual surface sync.
 9. DESIGN APIs (7)     → RESTful, versioned, idempotent everywhere
10. RESILIENCE (6)      → Logging, retries, circuit breakers, distributed patterns
11. CODE REVIEW (2)     → superpowers:code-reviewer + audit-fix cycle
12. COMMIT (8)          → Conventional Commits, atomic, PR <400 lines
13. CLEAN (9)           → Script catches dead code. Manual TODO/debug review.
14. BUILD & DEPLOY (11) → Docker build, CI green, push GHCR, Portainer deploy
15. VERIFY (Stop hook)  → Script: tests + coverage. Manual: evidence-based status.
```

---

# The Bottom Line

Plan with evidence. Research before importing. Failing test FIRST. SOLID code with defensive
checks and WHY docs. Secure every endpoint. Sync every env var. Idempotent API contracts.
Resilience and distributed safety built in. Disciplined commits. Clean codebase. CI/CD deployed.
Tool-verified before claiming done.

Scripts enforce mechanics. MD guides judgment. Superpowers orchestrates workflow. Together: no gaps.
