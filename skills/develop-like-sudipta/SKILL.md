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
worktrees). This skill adds: domain pillars + script-enforced hooks + specialized agents.
Without superpowers: fully self-contained — all pillars + hooks + agents work independently.

| # | Pillar | Core Principle | Enforcement |
|---|--------|---------------|-------------|
| 1 | **Plan First** | Evidence-based. Brainstorm → plan → verify → execute. | MD + superpowers:brainstorming |
| 2 | **Code Quality** | SOLID + DRY + KISS + defensive + audit-fix cycles. | `code-reviewer` agent + PostToolUse lint |
| 3 | **Env Sync** | Every env var change updates ALL surfaces simultaneously. | `env-sync-checker` agent + PostToolUse script |
| 4 | **Security First** | OWASP Top 10. Validate input. Vault secrets. Scan deps. | `security-reviewer` agent + PostToolUse script |
| 5 | **Test-Driven** | TDD: failing test FIRST. 70/20/10 pyramid. ≥80% coverage. | `test-writer` agent + tdd-gate hook |
| 6 | **Resilience** | Structured logging. Retries. Circuit breakers. Distributed. | `implementer` agent + `references/resilience.md` |
| 7 | **API Design** | RESTful. Versioned. Idempotent everywhere. MCP = OAuth 2.1. | `implementer` agent + `references/api-design.md` |
| 8 | **Git Discipline** | Conventional Commits. Trunk-based. Atomic. No AI co-author. | MD + superpowers:git-worktrees |
| 9 | **Clean Codebase** | Zero dangling code. Safe debugging. | PostToolUse ruff (F401/F841) |
| 10 | **Latest Deps** | Package Selection Gate. Research → validate → install. | `dep-researcher` agent |
| 11 | **CI/CD** | GitHub Actions → GHCR → Portainer. | PostToolUse Dockerfile checks |

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

## Plugin Agents — When to Invoke

| Agent | Trigger | Isolated Context Benefit |
|---|---|---|
| `test-writer` | Before any production code | NEVER sees implementation — clean TDD RED |
| `implementer` | After failing tests exist | Takes plan + tests, writes minimum GREEN code |
| `code-reviewer` | After code changes | SOLID/audit-fix in focused context |
| `security-reviewer` | After endpoint/auth/input code | OWASP-only context, no noise |
| `dep-researcher` | Before ANY package install | Searches latest, compares alternatives |
| `env-sync-checker` | After env var add/remove | Lightweight check across all config surfaces |

## Subagent Dispatch Protocol

Context pollution = implementation knowledge bleeds into test logic within one window.

- One subagent per task. Fresh context = clean reasoning.
- Dispatch via `Task` tool only. Never bash "launch" or "run".
- Test writer never sees implementation. Implementer never sees spec.
- After completion: review output in main context. Don't merge raw subagent state.

WHY: Single-context sessions degrade past ~50% usage. Subagents keep each task under 30%.

### MCP vs Skill Division

MCP = connectivity (API access, query formats). Skill = expertise (workflow logic, output structure).
Watch for conflicting instructions between MCP server prompts and skill instructions.

### When to Use Agent Teams

For large implementations (>5 files touching multiple layers), suggest an agent team:
- Each teammate owns a layer — no file conflicts
- Team lead coordinates via shared task list + mailbox messaging
- Teammates can share findings and challenge each other (unlike subagents)

Example: "Create an agent team. Teammate 'backend' owns src/services/ and src/routes/.
Teammate 'frontend' owns src/components/. Teammate 'tests' writes integration tests.
Teammate 'reviewer' reviews PRs from other teammates."

Don't use agent teams for: quick fixes (<3 files), single-layer changes, research (use Explore).

---

## Anti-Rationalization Table

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
| "Let me write a plan first" | Plan/design doc already provided? SKIP planning, START implementing (1). |

---

## Pillar Summaries (Detail in Agents + References)

### Pillar 1 — Plan First
**Plan Already Exists? Skip to Execution.** Read existing plan → verify actionable → execute.
User saying "implement" = "execute this spec NOW." Use `/implement` command or `subagent-driven-development`.
**No Plan?** Brainstorm → `.claude/plans/<n>.md` → verify with tools → execute.
Verdicts: ✅ Verified (evidence) | ⏳ Partial | ❌ Not started

### Pillar 2 — Code Quality → `code-reviewer` agent
SOLID + DRY + KISS + defensive programming. Audit-fix cycles.
WHY-First docs: **WHY** → **THOUGHT** → **HOW**. PostToolUse runs ruff (F401/F841).
> Full details in `code-reviewer` agent + `references/enforcement-hooks.md`

### Pillar 3 — Env Sync → `env-sync-checker` agent
Every env var change reflects in ALL surfaces: .env.example → .env → docker-compose → Portainer → config → CI/CD → docs.
> PostToolUse detects env var patterns → `env-sync-checker` agent verifies all surfaces.

### Pillar 4 — Security → `security-reviewer` agent
OWASP Top 10. Input validation. Parameterized queries. JWT RS256/ES256. Headers. Dep audit.
> Full OWASP checklist: `references/security.md`

### Pillar 5 — Test-Driven → `test-writer` agent
TDD: RED → GREEN → REFACTOR. Failing test FIRST. ≥80% coverage. AAA pattern.
Anti-patterns: over-mocking, circular assertions, weak assertions, no error paths.
> `test-writer` agent for RED phase. `implementer` agent for GREEN. Hook runs test suite at Stop.

### Pillar 6 — Resilience → `implementer` agent
Structured JSON logging. Retry w/ backoff+jitter. Circuit breakers. Health checks.
> Full patterns: `references/resilience.md` + `references/distributed-patterns.md`

### Pillar 7 — API & Idempotent Design → `implementer` agent
Idempotency everywhere: API, DB, queues, webhooks, migrations. RESTful, versioned, cursor pagination.
**MCP servers: OAuth 2.1 + PKCE mandatory.** No API keys. No basic auth.
> Full patterns: `references/api-design.md` + `references/mcp-auth.md`

### Pillar 8 — Git Discipline
Conventional Commits, trunk-based, atomic, SemVer, PR <400 lines.
**No AI attribution.** Never Co-authored-by Claude/Cursor/Copilot. All commits by Sudipta Dhara.
> Full patterns: `references/git-workflow.md`

### Pillar 9 — Clean Codebase
Zero dangling code. Unused imports/functions → remove immediately. PostToolUse ruff enforces.

### Pillar 10 — Latest Deps → `dep-researcher` agent + `/research-deps` command
**Package Selection Gate:** STOP → SEARCH → VERIFY → COMPARE → INSTALL.
Never install from memory. Research latest, check banned lists.
> Banned packages: `references/python-practices.md` + `references/typescript-practices.md`

### Pillar 11 — CI/CD
GitHub Actions → GHCR (latest+SHA) → Trivy → Portainer. Non-root Docker. Feature flags lifecycle.
> Full pipeline: `references/cicd-deployment.md`

---

## Script-Enforced Hooks

Hooks fire deterministically — no LLM memory needed.
> Full architecture: `references/enforcement-hooks.md`

| Hook | Trigger | Checks |
|---|---|---|
| `tdd-gate.sh` | PreToolUse (Write/Edit) | Test file exists for module? |
| `post-edit-check.sh` | PostToolUse (Write/Edit) | Env vars, secrets, lint, Dockerfile, .env sync |
| `completion-gate.sh` | Stop | Tests pass, coverage ≥80%, TODO count |
| `state-saver.sh` | PreCompact | Auto-save state to `.claude/plans/` |

---

## Context Window Management

1. **Manual compact at 50%** — `/compact` proactively. Never trust auto-compaction.
2. **State in files** — plans, progress, findings → `.claude/plans/`. Rebuilt from files.
3. **PreCompact hook** — auto-saves state before compaction.
4. **Progressive disclosure** — load references only when pillar triggers.
5. **Offload heavy tasks** — delegate to agents (they get their own context).

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
- `allowed-tools: Read, Grep, Glob` — restrict tool access per skill

### Agent Memory (MEMORY.md)
First 200 lines of `.claude/MEMORY.md` inject at startup. Use for project conventions.

### Description Budget
All skill descriptions share a 15,000-character budget. Current: ~950 chars. Monitor.

---

# Unified Workflow

**ENTRY POINT:** If plan/design doc already exists → START AT STEP 3 or 4.
Do NOT repeat steps 1-2. Use `/implement` command.

```
 1. BRAINSTORM (1)      → superpowers:brainstorming OR /plan command
 2. WRITE PLAN (1)      → superpowers:writing-plans OR .claude/plans/<n>.md
    ─── SKIP 1-2 IF PLAN/DESIGN DOC ALREADY EXISTS ───
 3. RESEARCH DEPS (10)  → dep-researcher agent OR /research-deps command
 4. FAILING TEST (5)    → test-writer agent. RED phase. Hook verifies test exists.
 5. IMPLEMENT (2)       → implementer agent. GREEN phase. SOLID + defensive.
 6. REFACTOR (2+5)      → superpowers:tdd REFACTOR. PostToolUse lint runs.
 7. SECURE (4)          → security-reviewer agent OR /secure command
 8. SYNC ENV (3)        → env-sync-checker agent. Script detects, agent verifies.
 9. DESIGN APIs (7)     → RESTful, versioned, idempotent, OAuth 2.1 for MCP
10. RESILIENCE (6)      → Logging, retries, circuit breakers, distributed patterns
11. CODE REVIEW (2)     → code-reviewer agent OR /review command
12. COMMIT (8)          → Conventional Commits, atomic, PR <400 lines. No AI co-author.
13. CLEAN (9)           → PostToolUse catches dead code. Manual TODO/debug review.
14. BUILD & DEPLOY (11) → Docker build, CI green, push GHCR, Portainer deploy. /deploy
15. VERIFY (Stop hook)  → Script: tests + coverage. Manual: evidence-based status.
```

---

# The Bottom Line

Plan with evidence (or skip planning if plan exists). Research before importing.
Failing test FIRST. SOLID code with defensive checks and WHY docs. Secure every endpoint.
Sync every env var. Idempotent API contracts. OAuth 2.1 for MCP. Resilience built in.
Disciplined commits (no AI co-author). Clean codebase. CI/CD deployed. Tool-verified before done.

Scripts enforce mechanics. Agents enforce quality in isolated contexts.
MD guides judgment. Superpowers orchestrates workflow. Together: no gaps.
