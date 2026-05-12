# develop-like-sudipta

**Version:** 5.0.0
**Tagline:** Battle-tested development discipline for Claude Code — 11 engineering pillars, real-browser verification, bug-driven TDD, substrate-aware end-to-end CC driving from Cowork, three operating modes (A greenfield phased build / B SRE monitor / C single hotfix), the v5.0 continuous-loop architecture (L1 `--auto` per-call reviewer + L2 `cc-orchestrator` per-minute reasoning watcher + L3 `cc-coordinator-keepalive` watchdog-over-watchdog + cross-machine learnings sync), safety-net-only watchdog with a manager-decides default, cross-browser/mobile + a11y + streaming testing, worktree-aware orchestration, commit-time bug-TDD enforcement via git hooks, and Karpathy-style autoresearch (self-improving skills via overnight propose-score-commit loops).
**v5.0.0 (May 2026):** Continuous-loop architecture — three layers (L1/L2/L3) + cross-machine sync. Six bundled scheduled tasks, `WATCHDOG_AUTO_APPROVE=0` default, `## Modes` section in the skill, `references/active_watcher.md` + `references/multi_machine.md`. Backed by `docs/plans/research-continuous-cowork-2026-05-12.md`.
**v4.1.x (May 2026):** Karpathy autoresearch — every skill ships with `autoresearch/{program.md, score.sh, target.txt}`, a new `autoresearch` meta-skill drives the loop, 4 new slash commands operate the system.
**v4.0.0 (May 2026):** Tier 3 hardening complete — 3 new agents, 2 new git hooks, cross-browser/mobile Playwright projects, opt-in a11y, streaming-protocol testing, worktree integration, approval cadence, stale-spec detection, screenshot archival, trigger-phrase evals.
**Author:** Sudipta Dhara — [github.com/sudipta26889](https://github.com/sudipta26889)
**Repository:** [claude-plugin-develop-like-sudipta](https://github.com/sudipta26889/claude-plugin-develop-like-sudipta)

---

## What this plugin does

This plugin enforces 11 engineering pillars (Plan First, Code Quality, Env Sync, Security First, Test-Driven, Resilience, API Design, Git Discipline, Clean Codebase, Latest Deps, CI/CD — plus a Preservation Protocol that wraps all changes to existing codebases) through a combination of skills, isolated-context agents, slash commands, and script-enforced hooks. Sources: Google SRE, DORA, OWASP, Martin Fowler, Thoughtworks Tech Radar. The discipline exists because AI-assisted PRs ship 23.5% more incidents per PR (CodeRabbit) and 322% more privilege-escalation paths (Apiiro) — every pillar closes a specific gap that current models still leave open.

Starting at v3.0 the plugin bundles the `sd-claude-code-access` skill, which lets Cowork drive Claude Code on your Mac end-to-end. You hand Cowork a workspace path and a goal; it brainstorms with you, writes the PRD and plan, then drives a long-running Claude Code session through file-based phase directives, a permission-prompt watchdog, hang detection, and resume-after-crash. v3.1 added a verify gate — static checks plus unit/integration tests (auto-detected per project: pytest, jest/vitest, cargo, go test, etc.) — that MUST go green before any browser test fires, and a bug-driven TDD protocol that refuses to land any fix without a new failing test first (both a unit test and a Playwright spec must reproduce the bug, then turn green together with the existing regression suite).

v3.2 added substrate detection. Earlier versions silently assumed `bash` plus `osascript` could reach your Mac; Cowork running outside that environment had no way to know what would actually work. Now every CC-driving session begins with a Step 0 probe of available MCPs — `Desktop_Commander` (Path A, preferred, direct on-Mac exec) → `computer-use` (Path B, fallback, `request_access` for Terminal at tier `click`) → manual (Path C, last resort, commands surfaced to the user) → SSH/remote-Mac (Path D, added in v3.4 for headless servers). The chosen path and reason are reported back before anything runs.

v3.4 expanded the CC-driver toolkit: GitHub Actions e2e workflow auto-emission, structured test-output parsing (pytest/jest/vitest/cargo/go/maven), flake retry + whitelist, auth-state freshness, dev-server orchestration with auto-start, data-testid directive enforcement, API-level testing for backend-only phases, and the SSH/remote-Mac substrate.

v4.0 closes the remaining skill gaps from the 24-gap audit. Three new isolated-context agents (`audit-agent`, `bug-triage-agent`, `playwright-spec-reviewer`) handle audit summarization, bug intake, and spec QA. Two new git hooks (`check_bug_id.sh`, `check_test_paired_with_src.sh`) enforce bug-TDD discipline at commit time. Cross-browser/mobile Playwright projects (`assets/playwright.config.template.ts`) and opt-in `axe-playwright` a11y assertions widen real-browser coverage. WebSocket / SSE / HTTP-streaming testing patterns (`references/streaming_testing.md`) cover non-request-response surfaces. Worktree-aware orchestration (`references/worktree_integration.md`) keeps driver lock + WORKSPACE resolution sane across parallel feature branches. Approval cadence with `pause_at` config gives users explicit human checkpoints. Source-hash compare auto-detects stale per-phase specs and triggers regen. Old screenshots get archived and stale specs quarantined via `scripts/cleanup_test_artifacts.sh`. Trigger-phrase eval coverage for substrate / verify-gate / bug-TDD is now in `evals/`.

v4.1 introduces Karpathy-style autoresearch — the plugin now self-improves its own skills overnight. Every shipped skill carries an `autoresearch/` subdirectory containing three files: `program.md` (the goal in plain English), `score.sh` (a deterministic metric — F1 on a trigger corpus, accuracy on a routing benchmark, etc.), and `target.txt` (the file under mutation, typically the skill's SKILL.md or a routing reference). The new `autoresearch` meta-skill drives a tight propose-score-commit loop: read program → propose ONE mutation to the target → score it → commit if better, reset if worse, then iterate. Four new slash commands operate the system: `/autoresearch <skill>` starts a run, `/autoresearch-status` shows accept rate and best score so far, `/autoresearch-resume` picks up an interrupted run, and `/autoresearch-baseline` re-runs the baseline scorer without mutating anything. Three skills ship with baselines today: `sd-claude-code-access` (F1 = 0.78 on trigger-phrase classification), `develop-like-sudipta` (accuracy = 47.91 on pillar-routing benchmark), `code-hacker` (F1 = 0.31 on attack-category classification). The baselines were intentionally chosen to leave substantial headroom — overnight loops have room to climb. Based on [karpathy/autoresearch](https://github.com/karpathy/autoresearch).

v5.0 ships the continuous-loop architecture in three layers (backed by `docs/plans/research-continuous-cowork-2026-05-12.md`). **L1** — `launch_cc.sh` defaults `CC_LAUNCH_FLAGS` to `--continue --chrome --auto`, routing every CC tool call through Anthropic's April-2026 Sonnet-4.6 server-side reviewer. **L2** — new `cc-orchestrator` scheduled task (`* * * * *`) is the per-minute reasoning watcher: reads `<workspace>/.cc/active-job.json`, polls CC's buffer, decides approve/deny/revise, advances phases on `phase_complete`, escalates stalls. **L3** — `cc-coordinator-keepalive` (`*/5 * * * *`) is the watchdog over the orchestrator: detects heartbeat staleness, fires Slack/email when configured, and self-disables both scheduled tasks once every active job hits its `done_criteria`. The architectural pivot also flips the v4.x watchdog default to **safety-net-only** (`WATCHDOG_AUTO_APPROVE=0`) — the manager (Cowork or human) decides every non-danger prompt deliberately, the watchdog only refuses `danger_patterns.txt` matches. A new `## Modes` section in the skill maps three use cases to artifact patterns: **Mode A** (greenfield phased build — pre-written `docs/plans/` + `.cc/phase-N.md` directives), **Mode B** (SRE monitor — watch a running system, fix anomalies as they arise, phase numbering = bug ID), **Mode C** (single hotfix — one `.cc/fix-<slug>.md`, two commits, done in under an hour). Cross-machine learnings sync arrives via `sync_learnings.sh` (rsync-over-SSH; per-peer best-effort) + the new `ccbridge-sync-learnings` scheduled task (`0 */6 * * *`); aggregator walks `learnings/remote-*/*.jsonl` with `source_host` tags and distillation gains a `cross-machine?` dimension that weights cross-machine signatures strictly higher than single-machine cross-project. Stop conditions are mandatory: `max_cycles`, `max_duration_hours`, `<ws>/.cc/monitor.stop` kill switch, `max_fix_attempts_per_cycle` cooldown, `cycle_timeout_s` wall-clock cap. Six bundled scheduled tasks now (see table below). New references: `references/active_watcher.md` (manager-decides model + job spec + escalation channels) and `references/multi_machine.md` (peer setup + privacy + bandwidth + failure modes).

---

## Installed components

### Skills

| Skill | Purpose |
|---|---|
| `develop-like-sudipta` | Routing hub for the 11 pillars; loads references progressively and delegates to agents and superpowers. |
| `code-hacker` | Red-team auditor — 23 attack categories, files a breach report. Invoked via `/hack`. |
| `sd-claude-code-access` | Drives Claude Code from Cowork end-to-end: substrate detection, file-based directives, watchdog, resume, per-phase browser verification, Playwright emission. v3.3 adds: per-project danger-pattern extensions via `<workspace>/.cc/danger_patterns_extra.txt`; watchdog dryrun mode via `WATCHDOG_DRYRUN=1` (logs "would-deny" without blocking); commit-lag-aware audit retry (`--retry N --retry-interval SEC`); watchdog refusal escalation to `.cc/escalations.log` + optional `ESCALATE_CMD` hook; `state.json` salvage via `state_salvage.sh` (recover from corrupted JSONL). |
| `autoresearch` | Karpathy-style self-improvement meta-skill. Reads any skill's `autoresearch/{program.md, score.sh, target.txt}` triple, proposes one mutation per iteration, scores it, commits if better. Drives the 4 `/autoresearch-*` commands. |

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
| `/autoresearch` | Run a Karpathy-style overnight loop on a wired skill: propose → score → commit-if-better. |
| `/autoresearch-status` | Report accept rate, best score so far, biggest single jump for the active run. |
| `/autoresearch-resume` | Resume an interrupted autoresearch run from the last `.baselines.json` entry. |
| `/autoresearch-baseline` | Re-run the baseline scorer for a skill without proposing any mutation. |

### Agents

| Agent | Trigger | Isolated-context benefit |
|---|---|---|
| `test-writer` | Before any production code | Never sees implementation — clean TDD RED. |
| `implementer` | After failing tests exist | Takes plan + failing tests, writes minimum GREEN code. |
| `code-reviewer` | After code changes | SOLID/DRY/KISS audit-fix in a focused context. |
| `security-reviewer` | After endpoint/auth/input code | OWASP-only context, no noise. |
| `dep-researcher` | Before any package install | Searches latest, compares alternatives, checks banned lists. |
| `env-sync-checker` | After env var add/remove | Verifies every config surface in sync. |
| `audit-agent` | After a CC-driving session ends | Runs `audit.sh`, summarizes drift / refusal / escalation logs in isolated context. |
| `bug-triage-agent` | When a bug report arrives | Classifies severity, extracts repro steps, drafts the failing-test pair before `/fix`. |
| `playwright-spec-reviewer` | After per-phase spec emission | Reviews generated `phase-N.spec.ts` for selector hygiene, brittle assertions, a11y opt-ins. |

### Hooks

| Hook | Event | Checks |
|---|---|---|
| `tdd-gate.sh` | PreToolUse (Write/Edit) | A test file exists for the module being edited. |
| `post-edit-check.sh` | PostToolUse (Write/Edit) | Env vars, secrets, lint (ruff F401/F841), Dockerfile, `.env` sync. |
| `completion-gate.sh` | Stop | Tests pass, coverage ≥80%, TODO count, baseline preserved. |
| `state-saver.sh` | PreCompact | Auto-save plan/progress state to `.claude/plans/`. |
| `check_bug_id.sh` | pre-commit (opt-in via `setup.sh`) | Blocks commits to `/fix/*` branches that lack a `Bug:` trailer + linked failing-test commit. |
| `check_test_paired_with_src.sh` | pre-commit (opt-in via `setup.sh`) | Blocks commits where production code is added without a paired test file change. |
| `setup.sh` | One-time install | Wires the hooks above into your Claude Code config and (opt-in) installs the git pre-commit hooks. |

### Scheduled tasks (Cowork-registered via `/ccbridge-init`)

| Task | Cron | Purpose |
|---|---|---|
| `ccbridge-aggregate-learnings` | `15 2 * * *` (daily 02:15) | Merge every workspace's `~/.cache/ccbridge/learnings/*.jsonl` tail (plus `learnings/remote-*/` peer pulls) into per-day aggregated jsonl. |
| `ccbridge-distill-and-propose` | `30 3 * * 0` (Sundays 03:30) | Turn 7-day aggregates into a top-N-signatures markdown report. Tags `cross-project?` AND `cross-machine?` (v5.0). |
| `ccbridge-propose-fix-pr` | `0 9 * * 1` (Mondays 09:00) | Walk distilled priors → route signatures through dispatch table → spawn CC against plugin clone → drive bug-driven TDD → open draft PR via `gh pr create --draft`. |
| `cc-orchestrator` (v5.0 L2) | `* * * * *` (every minute) | Per-minute reasoning watcher. Reads `<ws>/.cc/active-job.json`, polls CC's buffer, decides approve/deny/revise, advances phases, escalates stalls. Step-1 early-exits on idle machines (no quota burn). |
| `cc-coordinator-keepalive` (v5.0 L3) | `*/5 * * * *` (every 5 min) | Watchdog over `cc-orchestrator`. Detects heartbeat staleness, fires Slack/email when `<ws>/.cc/active-job.json` has `notify_*` channels set, self-disables both scheduled tasks once every active job hits `done_criteria`. |
| `ccbridge-sync-learnings` (v5.0) | `0 */6 * * *` (every 6h) | rsync-over-SSH pull of peer Macs' learning tails into `learnings/remote-<host>/`. Opt-in via `~/.cache/ccbridge/peers.json`; absent file = no sync. |

`/ccbridge-init` registers/refreshes all six idempotently, preserving any user-customized cron expressions.

---

## Compatibility

- **Works WITH `superpowers`:** delegates brainstorming, plan-writing, TDD orchestration, code review, git worktrees, and subagent-driven development to superpowers when present. Without superpowers it still functions — every pillar has a self-contained fallback (agents, commands, references).
- **Sibling Cowork plugins by Sudipta:** runs alongside `pm-toolkit`, `pm-product-discovery`, `pm-execution`, `pm-product-strategy`, `marketing-skills`, and `cowork-plugin-management`. No conflicts — different surface area.
- **macOS-only for the CC-driver path.** The `sd-claude-code-access` substrate paths target macOS Terminal/iTerm2; Linux and Windows are not supported for end-to-end driving. The other pillars (planning, code review, security, etc.) are platform-agnostic.
- **Cowork only for CC-driving.** `/cc-drive`, `/cc-resume`, `/browser-test`, `/e2e-suite`, `/cc-audit` need either `Desktop_Commander` or `computer-use` MCPs available in the session. If neither is present the skill drops to Path C (manual command surfacing).

---

## Quickstart

Pick the [mode](#modes) (A / B / C) that matches your use case. Each lands a different artifact pattern under `<workspace>/.cc/`.

**Mode A — Greenfield phased build:**
```
/cc-drive /absolute/path/to/new/workspace
```
Cowork probes substrate, brainstorms the project with you, writes the PRD + plan in `docs/plans/`, then drives Claude Code phase by phase through `.cc/phase-1.md`, `.cc/phase-2.md`, ... — each with verify-gate (unit/integration green) + browser verification (Playwright spec emitted into `docs/e2e-testing/`). CC is launched with `--auto` by default (v5.0), so every tool call goes through Anthropic's server-side reviewer; the safety-net-only watchdog (`WATCHDOG_AUTO_APPROVE=0`) refuses `danger_patterns.txt` matches and logs every other prompt as `prompt_pending` for the manager to attend. See [`references/active_watcher.md`](skills/sd-claude-code-access/references/active_watcher.md) for the manager-decides decision tree.

**Mode B — SRE monitor (v5.0 L1+L2+L3):**
```
cp skills/sd-claude-code-access/assets/active-job.example.json /path/to/ws/.cc/active-job.json
# edit job_id, plan_path, max_duration_hours, done_criteria, notify_* channels
# (one-time per machine, if not already done)
/ccbridge-init
```
The `cc-orchestrator` scheduled task picks up the new `active-job.json` within ≤ 60 s and starts the per-minute reasoning loop. `cc-coordinator-keepalive` watches the orchestrator's heartbeat every 5 minutes; on stalls (≥ 7 min stale) it escalates via Slack/email if the workspace's `notify_*` channels are set, and on `done_criteria` met it self-disables both scheduled tasks. Stop a run any time with `touch /path/to/ws/.cc/monitor.stop` (clean stop) or `rm /path/to/ws/.cc/active-job.json` (kill switch).

**Mode C — Single hotfix:**
```
/reproduce-bug /absolute/path/to/workspace "checkout total off by 1 cent on multi-line orders"
```
A failing pytest case AND a failing Playwright step are written first, confirmed red, then the fix directive is sent to CC. No fix lands without a failing test pair. Two commits land (`test(...)` red, `fix(...)` green); manager emits `state.sh bug_resolved` on four greens.

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

Newest first. One line per release, sourced from the accreting changelog in `develop-like-sudipta/.claude-plugin/plugin.json` `description`.

v5.0.1 (May 2026): BUG-2 — watchdog's `trap … TERM` handler now exits the poll loop cleanly on SIGTERM/SIGINT (silently re-entered the loop before).
v5.0.0 (May 2026): Continuous-loop architecture — L1 `--auto`, L2 `cc-orchestrator` (every minute), L3 `cc-coordinator-keepalive` (every 5 min) + cross-machine learnings sync via `sync_learnings.sh` + `ccbridge-sync-learnings` (6h). Safety-net-only watchdog default, Modes A/B/C, six bundled scheduled tasks.
v4.8.0 (May 2026): F-AUTOPR — `ccbridge-propose-fix-pr` scheduled task (Mondays 09:00) routes cross-project signatures through a dispatch table, drives bug-driven TDD on a plugin clone, opens a draft PR. Capped at 3/week.
v4.7.0 (May 2026): First objective watchdog-prompt classification eval (20 hand-labeled rows). Baseline 0.85 → 1.0 after closing the C6 verb list + ❯-menu form + cloud-storage recursive-delete patterns.
v4.6.2 (May 2026): Swarm-vs-Compose `pull_policy: always` gap documented — Compose honors the field, Swarm silently drops it. Per-orchestrator recovery routes added to `references/cicd-deployment.md`.
v4.6.1 (May 2026): Portainer-native deploy policy — `/deploy` step 6 bans manual `gh auth | ssh docker login + docker pull`; three Portainer-native recovery routes documented; `pull_policy: always` per service.
v4.6.0 (May 2026): Polish wave + continuous-drive mode. H1 second-CC-opens-new-window, H2 `learning.sh` stderr confirms + validation, F2 `launch_cc.sh --dry-run`, F3 `state.sh tail`, F4 `check_no_hardcoded_paths.sh` pre-commit, F5 stdin body on `learning.sh`, user-direct-input detection.
v4.5.1 (May 2026): Three critical fixes from M1 Max field testing — C2 `is_terminal_cc` excludes Cursor IDE-agent + no-TTY processes, C3 `send.sh` verify-by-fragment goes ASCII-only, C4 `diagnose.sh` wraps every inner `osascript` in `|| echo "?"`.
v4.5.0 (May 2026): `/ccbridge-status` — at-a-glance health-check: bridge install, watchdog process, 7-day event counts, latest distillation + cross-project signature count, best autoresearch score per skill, one-word HEALTH verdict.
v4.4.0 (May 2026): `launch_cc.sh` auto-launch — detect-or-spawn a terminal-mode CC for a specific workspace; cwd matching via `lsof`; `--detect-only` mode (exit 4 if no match); wired into `start_watchdog.sh` self-bootstrap.
v4.3.4 (May 2026): Two real second-Mac rollout bugs — `setup_ccbridge.sh` now captures `install.sh` stdout to a tmpfile (SIGPIPE-safe under `set -euo pipefail`) and self-`git pull`s + self-re-execs before installing.
v4.3.3 (May 2026): Portable scheduled-task paths — `install.sh` copies `aggregate_learnings.sh` + `distill_learnings.sh` into `~/.cache/ccbridge/`; bundled SKILLs reference those stable per-machine paths, not plugin-relative ones.
v4.3.2 (May 2026): Three-layer `WORKSPACE` resolution in `start_watchdog.sh` — honor env, else auto-detect from running `claude` cwd via `lsof`, else fail-fast loudly. Closes the silent-learning-loss foot-gun.
v4.3.1 (May 2026): `/ccbridge-init` — one idempotent slash command per machine that runs `setup_ccbridge.sh` then registers/refreshes Cowork scheduled tasks (preserves user-customized crons).
v4.3.0 (May 2026): Runtime-learning closed loop — workspaces auto-register via `register_project.sh`; `learning.sh` dual-writes to `<ws>/.cc/learnings.jsonl` + central tail; nightly aggregator + weekly distill-and-propose.
v4.2.1 (May 2026): Closed the autoresearch loop's last gap — `run_autoresearch.sh` now actually calls `propose_hypothesis.sh` per iteration (was a stub in v4.1).
v4.2.0 (May 2026): Autoresearch backlog close-out — real proposer (file + API), opt-in LLM scoring via Haiku-4.5 + cost guard, per-skill scorers normalized to F1 in [0,1], distributed-swarm scaffolding.
v4.1.0 (May 2026): Karpathy-style autoresearch meta-skill + 4 `/autoresearch-*` commands. Each skill ships `autoresearch/{program.md, score.sh, target.txt, .baselines.json}`.
v4.0.0 (May 2026): Tier 3 hardening — 3 new agents (audit/bug-triage/playwright-spec-reviewer), 2 git pre-commit hooks, cross-browser Playwright projects, opt-in axe a11y, streaming patterns, worktree integration, `pause_at`, source-hash spec drift.

---

## License + credits

License: see `LICENSE` in the repository root.
Built by Sudipta Dhara. Sources cited inline (Google SRE, DORA, OWASP, Fowler, Thoughtworks). Compatible with the `superpowers` plugin and Sudipta's sibling Cowork plugins.
