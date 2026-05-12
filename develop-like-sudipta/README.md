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

- **5.0.0** (2026-05-12) — Continuous-loop architecture. Three layers (L1 `--auto` per-call reviewer in `launch_cc.sh` defaults; L2 `cc-orchestrator` scheduled task at `* * * * *` doing per-minute reasoning over `<ws>/.cc/active-job.json`; L3 `cc-coordinator-keepalive` at `*/5 * * * *` doing stall escalation + self-disable on done) backed by `docs/plans/research-continuous-cowork-2026-05-12.md`. Cross-machine learnings sync via `scripts/sync_learnings.sh` (rsync-over-SSH) + `ccbridge-sync-learnings` scheduled task (`0 */6 * * *`); aggregator walks `learnings/remote-*/*.jsonl` with `source_host` tags; distillation gains `cross-machine?` dimension. Watchdog default flipped to safety-net-only (`WATCHDOG_AUTO_APPROVE=0`) — the manager (Cowork or human) decides every non-danger prompt deliberately via the `prompt_pending` event stream; legacy auto-approve is opt-in for unattended scheduled-task runs. New `## Modes` section in the skill (A greenfield / B SRE monitor / C hotfix). New references: `references/active_watcher.md`, `references/multi_machine.md`. Stop conditions enforced (`max_cycles`, `max_duration_hours`, `<ws>/.cc/monitor.stop`, cooldown after 3 failed fix attempts, `cycle_timeout_s` wall-clock cap). Six bundled scheduled tasks total; `/ccbridge-init` registers/refreshes all six idempotently. BUG-1 (`launch_cc.sh` regex missed bare-name `claude` argv[0]) fixed via bug-driven TDD; eval hardened to run in non-interactive runners. H4/D2/D3/D4/D5 doc + tooling gaps closed. 35+ commits across 7 plan phases.
- **2.x** — 11 pillars enforced via the original `develop-like-sudipta` skill, plus `code-hacker` for red-team audits. Agents, hooks, and the first 8 slash commands established.
- **3.0** — bundled `sd-claude-code-access` skill: end-to-end Claude Code driving from Cowork. Added `/cc-drive`, `/cc-resume`, `/cc-send`, `/browser-test`, `/e2e-suite`, `/cc-audit`. Per-phase real-browser verification via Claude in Chrome MCP, Playwright spec emission into `docs/e2e-testing/`.
- **3.1** — verify gate (static checks + unit/integration tests via auto-detected runner) MUST be green before browser-test. Bug-driven TDD protocol made mandatory — no fix without a failing test pair first. Added `/reproduce-bug` and `/fix`.
- **3.2** — substrate detection. Every CC-driving session probes available MCPs and selects Path A (`Desktop_Commander`, preferred), Path B (`computer-use`, `request_access` for Terminal at tier `click`), or Path C (manual command surfacing). The chosen path and reason are reported before anything runs.
- **3.3.0** (2026-05-11) — Tier 1 hardening (4 user-visible gaps + 2 doc gaps closed):
  - `feat(safety)` — danger-pattern audit + per-project extensions (`<workspace>/.cc/danger_patterns_extra.txt`) + dryrun mode (`WATCHDOG_DRYRUN=1`) (gap #1).
  - `fix(audit)` — commit-lag-aware retry with `--retry`/`--retry-interval` flags so `audit.sh` no longer flags drift on healthy phases mid commit-hook (gap #2).
  - `feat(safety)` — watchdog escalation on refused prompts: appends to `.cc/escalations.log` and fires optional `ESCALATE_CMD` hook (gap #3).
  - `feat(state)` — `state.json` salvage script for corrupted JSONL recovery (`state_salvage.sh`) (gap #4).
  - `docs(readme + prompts)` — README refreshed for v3.2/v3.3; CC-driver prompt drop-ins now lead with the Path A/B/C substrate detection clause (gaps #23 + #24).
- **3.4.0** (2026-05-11) — Tier 2 CC-driver expansion (8 gaps closed):
  - `feat(ci)` — GitHub Actions e2e workflow auto-emission so CI runs the same Playwright suite the per-phase driver runs (gap #5).
  - `feat(parse)` — structured test-output parser across pytest / jest / vitest / cargo / go-test / maven; driver reads pass/fail counts and per-test names instead of substring sniffing (gap #6).
  - `feat(testids)` — `data-testid` directive enforcement: per-phase directives explicitly require stable selectors and the spec emitter refuses to write XPath/index-based assertions (gap #7).
  - `feat(auth)` — auth-state lifecycle: `check_auth_state.sh` validates storageState freshness before browser-test runs, auto-refreshes when stale (gap #8).
  - `feat(flake)` — flake retry + whitelist with documented decision tree; retries are bounded and recorded, whitelist entries require a comment (gap #9).
  - `feat(devserver)` — dev-server orchestration with `wait_for_dev_server.sh`, auto-start when down, port-probe with backoff (gap #10).
  - `feat(api)` — API-level testing reference for backend-only phases — pytest + requests/httpx pattern when no UI exists yet (gap #16).
  - `feat(ssh)` — SSH / remote-Mac substrate (Path D) — drive a headless Mac mini from Cowork via SSH + tmux; probe via `ssh_probe.sh` (gap #16).
- **4.8.0** (2026-05-12) — F-AUTOPR: distill → CC writes fix → draft PR.
  - New scheduled task `ccbridge-propose-fix-pr` (cron `0 9 * * 1`): walks `priors-*.md` from the latest distill, routes each cross-project signature through a dispatch table to the matching plugin file, spawns CC against the plugin repo clone, drives bug-driven TDD, opens a *draft* PR via `gh pr create --draft`. Maintainer reviews/merges — never auto-merge.
  - New `scripts/dispatch_signature.sh` — bash 3.2 case-statement dispatch (testable in isolation; 13 signature prefixes covered).
  - New `scripts/propose_fix_pr.sh` — procedure runner with `DRY_RUN=1` (no side effects), `PR_CAP=3` cap (overflow → one batched GH issue), `GH_OVERRIDE=mock` for evals. Installed to `~/.cache/ccbridge/` by `install.sh`.
  - New evals: `test_propose_fix_pr_{dispatch,dryrun,cap}.sh` — 3 red → 3 green before commit.
  - `/ccbridge-init` and `/ccbridge-status` updated to register/report on the third scheduled task.
- **4.1.0** — Karpathy autoresearch (2026-05-11)
  - New skill: `autoresearch` (3-file architecture mapping — program.md + score.sh + target.txt).
  - Per-skill wiring: `sd-claude-code-access`, `develop-like-sudipta`, `code-hacker` each ship `autoresearch/{program.md, score.sh, target.txt, trigger_corpus.json, .baselines.json}`.
  - 4 new commands: `/autoresearch`, `/autoresearch-status`, `/autoresearch-resume`, `/autoresearch-baseline`.
  - Baselines established (F1 0.78 / acc 47.91 / F1 0.31).
  - Based on https://github.com/karpathy/autoresearch.
- **4.0.0** (2026-05-11) — Tier 3 final hardening (10 gaps closed; 24-gap audit complete):
  - `feat(cleanup)` — `scripts/cleanup_test_artifacts.sh`: archive screenshots older than N days, quarantine stale specs whose source markdown no longer exists (gap #12).
  - `feat(crossbrowser)` — `assets/playwright.config.template.ts` ships `chromium / firefox / webkit / Mobile Safari / Mobile Chrome` projects out of the box (gap #13).
  - `feat(a11y)` — opt-in `axe-playwright` a11y assertions gated by `.cc/config.json → axe_enabled: true`; spec template uses `A11Y BEGIN/END` markers so disabled mode emits clean output (gap #14).
  - `feat(streaming)` — `references/streaming_testing.md` documents WebSocket / SSE / HTTP-chunked testing patterns and assertion strategies (gap #15).
  - `feat(agents)` — three new isolated-context agents: `audit-agent`, `bug-triage-agent`, `playwright-spec-reviewer` (gap #17).
  - `feat(hooks)` — two new git pre-commit hooks: `check_bug_id.sh` (enforces `Bug:` trailer + failing-test commit on `/fix/*` branches), `check_test_paired_with_src.sh` (no production code without paired test change) (gap #18).
  - `feat(worktree)` — `references/worktree_integration.md` documents driving CC inside a git worktree: WORKSPACE resolution, driver lock per-worktree, multi-worktree parallelism, merge-time test bank handling (gap #19).
  - `feat(cadence)` — approval cadence with `pause_at` config: explicit human checkpoints after planning, after phase verify, before commit, before push (gap #20).
  - `feat(specs)` — automated stale-spec detection: source-hash compare between `## Steps` content in `phase-N.md` and the `// source-hash:` header in `phase-N.spec.ts`; triggers regen on drift (gap #21).
  - `feat(evals)` — trigger-phrase coverage for substrate detection, verify-gate enforcement, and bug-TDD onset in `evals/*.json` (gap #22).

---

## License + credits

License: see `LICENSE` in the repository root.
Built by Sudipta Dhara. Sources cited inline (Google SRE, DORA, OWASP, Fowler, Thoughtworks). Compatible with the `superpowers` plugin and Sudipta's sibling Cowork plugins.
