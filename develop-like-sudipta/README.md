# develop-like-sudipta

**Version:** 3.2.0
**Tagline:** Battle-tested development discipline for Claude Code — 11 engineering pillars, real-browser verification, bug-driven TDD, and substrate-aware end-to-end Claude Code driving from Cowork.
**Author:** Sudipta Dhara — [github.com/sudipta26889](https://github.com/sudipta26889)
**Repository:** [claude-plugin-develop-like-sudipta](https://github.com/sudipta26889/claude-plugin-develop-like-sudipta)

---

## What this plugin does

This plugin enforces 11 engineering pillars (Plan First, Code Quality, Env Sync, Security First, Test-Driven, Resilience, API Design, Git Discipline, Clean Codebase, Latest Deps, CI/CD — plus a Preservation Protocol that wraps all changes to existing codebases) through a combination of skills, isolated-context agents, slash commands, and script-enforced hooks. Sources: Google SRE, DORA, OWASP, Martin Fowler, Thoughtworks Tech Radar. The discipline exists because AI-assisted PRs ship 23.5% more incidents per PR (CodeRabbit) and 322% more privilege-escalation paths (Apiiro) — every pillar closes a specific gap that current models still leave open.

Starting at v3.0 the plugin bundles the `sd-claude-code-access` skill, which lets Cowork drive Claude Code on your Mac end-to-end. You hand Cowork a workspace path and a goal; it brainstorms with you, writes the PRD and plan, then drives a long-running Claude Code session through file-based phase directives, a permission-prompt watchdog, hang detection, and resume-after-crash. v3.1 added a verify gate — static checks plus unit/integration tests (auto-detected per project: pytest, jest/vitest, cargo, go test, etc.) — that MUST go green before any browser test fires, and a bug-driven TDD protocol that refuses to land any fix without a new failing test first (both a unit test and a Playwright spec must reproduce the bug, then turn green together with the existing regression suite).

v3.2 added substrate detection. Earlier versions silently assumed `bash` plus `osascript` could reach your Mac; Cowork running outside that environment had no way to know what would actually work. Now every CC-driving session begins with a Step 0 probe of available MCPs — `Desktop_Commander` (Path A, preferred, direct on-Mac exec) → `computer-use` (Path B, fallback, `request_access` for Terminal at tier `click`) → manual (Path C, last resort, commands surfaced to the user). The chosen path and reason are reported back before anything runs.

---

## Installed components

### Skills

| Skill | Purpose |
|---|---|
| `develop-like-sudipta` | Routing hub for the 11 pillars; loads references progressively and delegates to agents and superpowers. |
| `code-hacker` | Red-team auditor — 23 attack categories, files a breach report. Invoked via `/hack`. |
| `sd-claude-code-access` | Drives Claude Code from Cowork end-to-end: substrate detection, file-based directives, watchdog, resume, per-phase browser verification, Playwright emission, audit retry. |

### Slash commands

| Command | Purpose |
|---|---|
| `/plan` | Create a development plan from scratch (brainstorm → plan file). |
| `/implement` | Execute an existing plan; skip re-planning. |
| `/audit` | Run code quality audit-fix cycle. |
| `/secure` | OWASP security review (lightweight, per-change). |
| `/hack` | Full 23-category red-team pen-test via `code-hacker`. |
| `/review` | Full review — quality + security + tests + git. |
| `/deploy` | CI/CD pipeline execution. |
| `/research-deps` | Package Selection Gate research before installs. |
| `/fix` | Bug-driven TDD entry point — regression test before fix. |
| `/refactor` | Preservation-protocol-wrapped refactoring. |
| `/cc-drive` | Drive a new project end-to-end via `sd-claude-code-access`. |
| `/cc-resume` | Resume after Cowork crash or take over mid-flight. |
| `/cc-send` | One-off keyboard relay of a single message to running CC. |
| `/browser-test` | Real-browser verification of one phase (Claude in Chrome MCP). |
| `/e2e-suite` | Stitch all per-phase tests into a project-wide Playwright suite. |
| `/cc-audit` | Verify a driving session actually followed the discipline. |
| `/reproduce-bug` | Bug-driven TDD: reproduce → red test → fix → green. |

### Agents

| Agent | Trigger | Isolated-context benefit |
|---|---|---|
| `test-writer` | Before any production code | Never sees implementation — clean TDD RED. |
| `implementer` | After failing tests exist | Takes plan + failing tests, writes minimum GREEN code. |
| `code-reviewer` | After code changes | SOLID/DRY/KISS audit-fix in a focused context. |
| `security-reviewer` | After endpoint/auth/input code | OWASP-only context, no noise. |
| `dep-researcher` | Before any package install | Searches latest, compares alternatives, checks banned lists. |
| `env-sync-checker` | After env var add/remove | Verifies every config surface in sync. |

### Hooks

| Hook | Event | Checks |
|---|---|---|
| `tdd-gate.sh` | PreToolUse (Write/Edit) | A test file exists for the module being edited. |
| `post-edit-check.sh` | PostToolUse (Write/Edit) | Env vars, secrets, lint (ruff F401/F841), Dockerfile, `.env` sync. |
| `completion-gate.sh` | Stop | Tests pass, coverage ≥80%, TODO count, baseline preserved. |
| `state-saver.sh` | PreCompact | Auto-save plan/progress state to `.claude/plans/`. |
| `setup.sh` | One-time install | Wires the four hooks above into your Claude Code config. |

---

## Compatibility

- **Works WITH `superpowers`:** delegates brainstorming, plan-writing, TDD orchestration, code review, git worktrees, and subagent-driven development to superpowers when present. Without superpowers it still functions — every pillar has a self-contained fallback (agents, commands, references).
- **Sibling Cowork plugins by Sudipta:** runs alongside `pm-toolkit`, `pm-product-discovery`, `pm-execution`, `pm-product-strategy`, `marketing-skills`, and `cowork-plugin-management`. No conflicts — different surface area.
- **macOS-only for the CC-driver path.** The `sd-claude-code-access` substrate paths target macOS Terminal/iTerm2; Linux and Windows are not supported for end-to-end driving. The other pillars (planning, code review, security, etc.) are platform-agnostic.
- **Cowork only for CC-driving.** `/cc-drive`, `/cc-resume`, `/browser-test`, `/e2e-suite`, `/cc-audit` need either `Desktop_Commander` or `computer-use` MCPs available in the session. If neither is present the skill drops to Path C (manual command surfacing).

---

## Quickstart

**Start a new project end-to-end with Claude Code:**
```
/cc-drive /absolute/path/to/new/workspace
```
Cowork probes substrate, brainstorms the project with you, writes the PRD + plan, then drives Claude Code phase by phase with per-phase verify-gate (unit/integration green) followed by browser verification (Playwright spec emitted into `docs/e2e-testing/`).

**Bug-driven TDD on a discovered issue:**
```
/reproduce-bug /absolute/path/to/workspace "checkout total off by 1 cent on multi-line orders"
```
A failing pytest case AND a failing Playwright step are written first, confirmed red, then the fix directive is sent to CC. No fix lands without a failing test pair.

**Verify the last feature CC built (or any specific phase):**
```
/browser-test /absolute/path/to/workspace 7
```
Fires Claude in Chrome against the dev server, writes structured evidence to `docs/e2e-testing/phase-7-<slug>.md`, emits `docs/e2e-testing/specs/phase-7.spec.ts`, reports green/red.

---

## Installation

**Marketplace install (recommended once published):**
```
/plugin marketplace add sudipta26889/claude-plugin-develop-like-sudipta
/plugin install develop-like-sudipta
```

**Local clone (for development / unpublished versions):**
```bash
git clone https://github.com/sudipta26889/claude-plugin-develop-like-sudipta.git
ln -s "$(pwd)/claude-plugin-develop-like-sudipta/develop-like-sudipta" \
      ~/.claude/plugins/develop-like-sudipta
```
Then restart Claude Code so it picks up the new skills, commands, agents, and hooks. Run `bash develop-like-sudipta/hooks/setup.sh` once to wire the four enforcement hooks into your Claude Code settings.

Updating: the plugin does NOT auto-update. Run `/plugin update develop-like-sudipta` (marketplace) or `git pull` (local clone) and restart Claude Code.

---

## Architecture (brief)

The plugin layers three things on top of Claude Code: (a) skills that load progressively when their triggers fire, (b) agents with isolated contexts that get clean reasoning per task, and (c) hooks that fire deterministically without trusting model memory. The skill SKILL.md files are short routing hubs; deep knowledge lives in `references/*.md` and loads only when the relevant pillar triggers. The 11 pillars below are the canonical contract:

| # | Pillar | Core Principle | Enforcement |
|---|--------|----------------|-------------|
| 0 | Preserve First | Never break what works. Baseline → atomic change → verify → rollback on failure. | Preservation Protocol + `completion-gate` hook |
| 1 | Plan First | Evidence-based. Brainstorm → plan → verify → execute. | MD + `superpowers:brainstorming` |
| 2 | Code Quality | SOLID + DRY + KISS + defensive + audit-fix cycles. | `code-reviewer` agent + PostToolUse lint |
| 3 | Env Sync | Every env var change updates ALL surfaces simultaneously. | `env-sync-checker` agent + PostToolUse script |
| 4 | Security First | OWASP Top 10. Validate input. Vault secrets. Scan deps. | `security-reviewer` agent + PostToolUse script |
| 5 | Test-Driven | TDD: failing test FIRST. 70/20/10 pyramid. ≥80% coverage. | `test-writer` agent + `tdd-gate` hook |
| 6 | Resilience | Structured logging. Retries. Circuit breakers. Distributed patterns. | `implementer` agent + `references/resilience.md` |
| 7 | API Design | RESTful. Versioned. Idempotent everywhere. MCP = OAuth 2.1. | `implementer` agent + `references/api-design.md` |
| 8 | Git Discipline | Conventional Commits. Trunk-based. Atomic. No AI co-author. | MD + `superpowers:git-worktrees` |
| 9 | Clean Codebase | Zero dangling code. Safe debugging. | PostToolUse ruff (F401/F841) |
| 10 | Latest Deps | Package Selection Gate. Research → validate → install. | `dep-researcher` agent |
| 11 | CI/CD | GitHub Actions → GHCR → Portainer. | PostToolUse Dockerfile checks |

---

## Versioning

- **2.x** — 11 pillars enforced via the original `develop-like-sudipta` skill, plus `code-hacker` for red-team audits. Agents, hooks, and the first 8 slash commands established.
- **3.0** — bundled `sd-claude-code-access` skill: end-to-end Claude Code driving from Cowork. Added `/cc-drive`, `/cc-resume`, `/cc-send`, `/browser-test`, `/e2e-suite`, `/cc-audit`. Per-phase real-browser verification via Claude in Chrome MCP, Playwright spec emission into `docs/e2e-testing/`.
- **3.1** — verify gate (static checks + unit/integration tests via auto-detected runner) MUST be green before browser-test. Bug-driven TDD protocol made mandatory — no fix without a failing test pair first. Added `/reproduce-bug` and `/fix`.
- **3.2** — substrate detection. Every CC-driving session probes available MCPs and selects Path A (`Desktop_Commander`, preferred), Path B (`computer-use`, `request_access` for Terminal at tier `click`), or Path C (manual command surfacing). The chosen path and reason are reported before anything runs.
- **3.3 (in progress)** — safety hardening. Danger-pattern audit and per-project extensions, commit-lag-aware audit retry, watchdog escalation on routine permission refusal, `state.json` salvage procedure. Doc refresh for the README and CC-driver prompts to match v3.2 reality.

---

## License + credits

License: see `LICENSE` in the repository root.
Built by Sudipta Dhara. Sources cited inline (Google SRE, DORA, OWASP, Fowler, Thoughtworks). Compatible with the `superpowers` plugin and Sudipta's sibling Cowork plugins.
