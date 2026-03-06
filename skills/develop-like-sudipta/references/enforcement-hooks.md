# Enforcement Hooks & Script Reference

Three-layer enforcement architecture:
1. **Superpowers plugin** — brainstorming, TDD, code review, subagent workflow (external)
2. **Shell hook scripts** — deterministic checks via Claude Code hooks (mechanical)
3. **MD instructions** — judgment-based guidance for LLM (cognitive)

Compliance data: MD-only ≈ 50%. MD + hooks ≈ 84%. MD + hooks + superpowers ≈ 95%.

---

## Hook Scripts (`hooks/` directory)

### Setup

```bash
bash ~/.claude/skills/develop-like-sudipta/hooks/setup.sh
```

Then merge `hooks/hooks.json` into Claude Code settings.

### tdd-gate.sh (PreToolUse — Write/Edit/MultiEdit)

Before any production code edit, checks if a corresponding test file exists.
If none found → injects `additionalContext` reminding about TDD RED phase.

**Detection logic:**
- Python: `test_<name>.py` or `<name>_test.py` in same dir, `tests/`, or project root `tests/`
- TypeScript/JS: `<name>.test.ts` or `<name>.spec.ts` in same dir, `__tests__/`, or `tests/`
- Go: `<name>_test.go` in same directory

**Exemptions (no test required):**
Test files themselves, config (`.env`, `docker-compose.yml`, `pyproject.toml`, `.json`, `.yaml`),
docs (`.md`, `.rst`, `.txt`), CI/CD (`.github/workflows/*`), assets (`.css`, `.html`, `.svg`, images).

**Limitation:** Only checks test file EXISTS — not that it was written FIRST (requires superpowers TDD)
or that tests are meaningful (requires LLM judgment).

### post-edit-check.sh (PostToolUse — Write/Edit/MultiEdit)

After any file edit, runs a 5-check pipeline:

1. **Env Var Detection (Pillar 3):** Greps for `os.environ`, `os.getenv`, `process.env`,
   `settings.UPPER_CASE`, `Field(env=...)` → warns about surface sync.
2. **Secret Scanning (Pillar 4):** Regex for `password=`, `api_key=`, `secret=`, `token=`,
   `AWS_SECRET`, `PRIVATE_KEY=`. Excludes test files and `.env.example`.
3. **Dead Code (Pillar 9):** Python files + ruff installed → `ruff check --select F401,F841`
   for unused imports (F401) and unused variables (F841).
4. **Dockerfile Standards (Pillar 11):** No `USER` directive → warn. `ENV` with SECRET/PASSWORD →
   warn. `FROM :latest` → warn about unpinned base.
5. **Env Example Sync (Pillar 3):** `.env` or `.env.example` edited → reminder to sync all surfaces.

### completion-gate.sh (Stop hook)

Before agent finishes responding:
1. **Test Suite:** Runs `pytest` (Python) or `npm test` (Node). FAILED → injects warning.
2. **Coverage:** `coverage report --fail-under=80`. Below 80% → injects percentage.
3. **TODO Count:** Greps changed files (`git diff --name-only HEAD`) for TODOs. Reports count.

Only runs inside a git repo with a detectable test setup.

### state-saver.sh (PreCompact hook)

Before context compaction:
- Creates `.claude/plans/auto-save-<timestamp>.md`
- Saves: git status, changed files, current branch, active plan list
- Includes recovery instructions

Ensures progress survives context compaction.

---

## Hook Architecture

```
SessionStart ──→ Inject skill bootstrap + load context

PreToolUse (Write/Edit) ──→ tdd-gate.sh: test file exists for this module?
                            If NO → inject "write failing test first"

PostToolUse (Write/Edit) ──→ Pipeline on edited file:
  ├── env-var-detector     → Pillar 3 sync warning
  ├── secret-scanner       → Pillar 4 block on hardcoded secrets
  ├── lint-check (ruff)    → Pillar 9 unused imports/vars
  ├── dockerfile-check     → Pillar 11 USER, no ENV SECRET
  └── env-example-sync     → Pillar 3 all-surface reminder

Stop ──→ completion-gate.sh
  ├── Run test suite (pytest/npm test)
  ├── Check coverage ≥80%
  └── Grep for uncommitted TODOs

PreCompact ──→ state-saver.sh → save state to .claude/plans/
```

---

## What Scripts CAN vs CANNOT Enforce

| Enforceable (Script) | Not Enforceable (MD/LLM) |
|---|---|
| Test file exists before production edit | Test QUALITY (meaningful assertions) |
| No hardcoded secrets in code | Proper secret management architecture |
| Unused imports/variables detected | SOLID principle adherence |
| Env var pattern → sync reminder | Whether env var is properly configured |
| Dockerfile has USER directive | Whether multi-stage build is optimal |
| Tests pass before completion | Whether tests cover right behaviors |
| Coverage ≥80% metric | Whether coverage is meaningful |
| Conventional commit format | Whether commit is truly atomic |

Scripts catch mechanical violations. MD guides judgment calls. Together: ~95% compliance vs ~50% from MD alone.

---

## TDD Enforcement (3-Layer, Zero Gaps)

| Layer | Tool | Catches |
|---|---|---|
| Script (`tdd-gate.sh`) | Checks test file EXISTS before production edit | "No test at all" |
| Superpowers (`superpowers:tdd`) | Enforces RED→GREEN→REFACTOR ordering, deletes code written before tests | "Wrong order" |
| MD (Pillar 5 anti-pattern table) | Detects over-mocking, circular assertions, weak assertions | "Bad test quality" |

---

## 10-Token Questions Pattern (Lightweight Alternative)

Instead of heavy scripts, hooks can inject tiny questions before tool use:
- Before non-test file edit: **"Is there a failing test for this change?"**
- Before git commit: **"Are you on the right branch?"**
- Before completion: **"Did you verify with tools, not assumptions?"**

These fire deterministically outside the agentic loop. Mike Lane's research shows
this pattern replaces 800 lines of instructions with 10-token checks.

**Use when:** Script overhead too high, projects without Python/ruff, or as a complement
to existing hooks for extra nudges.

---

## Progressive Disclosure — When to Load References

| Reference File | Load When |
|---|---|
| `references/security.md` | Security review, auth, input validation |
| `references/api-design.md` | API design, pagination, idempotency |
| `references/resilience.md` | Error handling, retries, logging |
| `references/distributed-patterns.md` | Multi-service, queues, webhooks, SAGA |
| `references/git-workflow.md` | Branching, commits, PRs |
| `references/python-practices.md` | Python tooling, FastAPI, Pydantic |
| `references/typescript-practices.md` | TypeScript, Zod, ESLint, React |
| `references/performance-db.md` | Query optimization, caching, migrations |
| `references/cicd-deployment.md` | Docker, GitHub Actions, Portainer |
| `references/enforcement-hooks.md` | Hook details, script behavior |
| `references/mcp-auth.md` | MCP server development, OAuth 2.1, PKCE |

---

## Anti-Rationalization Enforcement

When catching yourself thinking "this pillar doesn't apply":
1. **STOP** — check the anti-rationalization table in SKILL.md
2. **Default to compliance** — if unsure, follow the pillar
3. **Log the decision** — if genuinely exempt, document WHY in plan file

**The 1% Rule:** If there's even a 1% chance a pillar applies, follow it.
