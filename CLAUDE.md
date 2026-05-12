# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

A **Claude Code plugin marketplace** that ships one plugin: `develop-like-sudipta`. The repo contains no application code in the traditional sense — every artifact is a `.md` (skill / command / agent / reference), a `.sh` script, a `.json` config, or a template asset. There is nothing to compile, no package manager, no test runner at the repo root. "Building" means editing markdown/scripts and validating them by running the scripts directly or installing the plugin into a real Claude Code session.

## Repo layout (only the pieces that matter)

- `.claude-plugin/marketplace.json` — marketplace entry point. Points at the single plugin in `develop-like-sudipta/`.
- `develop-like-sudipta/` — the plugin itself. Everything Claude Code loads at install time lives under here.
  - `.claude-plugin/plugin.json` — plugin manifest. **The `version` field here is the source of truth** (currently `5.0.3`; bump on every release). The `description` is intentionally a long changelog — older versions live there.
  - `agents/*.md` — 9 isolated-context subagents (`test-writer`, `implementer`, `code-reviewer`, `security-reviewer`, `dep-researcher`, `env-sync-checker`, `audit-agent`, `bug-triage-agent`, `playwright-spec-reviewer`).
  - `commands/*.md` — 23 slash commands (`/plan`, `/implement`, `/audit`, `/secure`, `/hack`, `/review`, `/deploy`, `/fix`, `/refactor`, `/research-deps`, `/cc-drive`, `/cc-resume`, `/cc-send`, `/browser-test`, `/e2e-suite`, `/cc-audit`, `/reproduce-bug`, `/ccbridge-init`, `/ccbridge-status`, plus the 4 `/autoresearch-*`).
  - `hooks/` — `hooks.json` plus 4 `.sh` scripts (`tdd-gate`, `post-edit-check`, `completion-gate`, `state-saver`) + `scripts/` with the 2 opt-in git pre-commit hooks. `setup.sh` wires everything into `~/.claude/settings.json`.
  - `skills/` — four bundled skills, each with its own `SKILL.md` + `references/` + `evals/` (+ usually `scripts/` and `autoresearch/`):
    - `develop-like-sudipta/` — routing hub for the 11 pillars.
    - `code-hacker/` — 23-category red-team auditor invoked via `/hack`. Has its own `agents/` (one per attack category) and parallel-runnable `scripts/NN_*.sh`.
    - `sd-claude-code-access/` — drives Claude Code from Cowork; ships the **ccbridge** runtime (scripts that get copied to `~/.cache/ccbridge/` at install).
    - `autoresearch/` — Karpathy-style self-improvement meta-skill.
  - `assets/scheduled-tasks/` — six bundled Cowork scheduled-task SKILLs (`ccbridge-aggregate-learnings`, `ccbridge-distill-and-propose`, `ccbridge-propose-fix-pr`, `cc-orchestrator`, `cc-coordinator-keepalive`, `ccbridge-sync-learnings`) that `/ccbridge-init` copies into `~/Documents/Claude/Scheduled/`.

## Two install / bootstrap paths (don't confuse them)

The repo has two completely separate install scripts. Read this section before touching either.

1. **Plugin hooks** → `bash develop-like-sudipta/hooks/setup.sh`. One-time per machine. Makes the hook scripts executable, rewrites the `~/.claude/skills/...` paths inside `hooks.json` to the actual install location, then prints instructions for merging `hooks.json` into the user's `~/.claude/settings.json`. **Does NOT auto-merge** — it tells the user to merge manually if a settings file already exists. Do not change that behavior without good reason; clobbering a user's settings.json is the worst failure mode.

2. **ccbridge runtime** → `bash develop-like-sudipta/skills/sd-claude-code-access/scripts/install.sh`. Copies the `send/read/watchdog/audit/state/lock/diagnose/...` shell scripts into `~/.cache/ccbridge/` (canonical, persistent across reboots — `/tmp/ccbridge` is kept as a back-compat symlink only). Also copies `aggregate_learnings.sh` + `distill_learnings.sh` from `skills/autoresearch/scripts/` into the same dir — these have a STABLE per-machine path the bundled scheduled-task SKILLs reference. The full bootstrap (install.sh + scheduled-task SKILL copy + Cowork task registration) is wrapped by the `/ccbridge-init` slash command and the `setup_ccbridge.sh` script.

If a hook/install script change appears to be silently swallowed, suspect `set -euo pipefail` + SIGPIPE — v4.3.4 fixed two real instances of that in `install.sh` and `setup_ccbridge.sh`. The pattern is: capture stdout to a `mktemp` tmpfile, then process the file (no pipeline). Don't pipe through `sed`/`head` under `set -e`.

## Validating changes (the closest thing to a test suite)

There is no central `make test`. Validation is per-component:

- **Bridge scripts**: run them directly. `bash develop-like-sudipta/skills/sd-claude-code-access/scripts/diagnose.sh <workspace>` is the canonical health check. Many scripts have a no-op detect mode: `launch_cc.sh <workspace> --detect-only` exits 4 if no CC is running (safe to invoke anytime).
- **Hook scripts**: pipe a JSON payload to stdin per the format in `develop-like-sudipta/hooks/HOOKS-README.md` and check stdout. Example: `echo '{"tool_name":"Write","file_path":"/tmp/x.py","path":"/tmp/x.py"}' | bash develop-like-sudipta/hooks/tdd-gate.sh`.
- **Skill evals**: each skill has an `evals/` dir. The `sd-claude-code-access` skill is the heaviest user (25 executable `test_*.sh` scripts covering watchdog prompt classification, danger-pattern coverage, BUG-1 bare-name regex, sync dry-run, etc.); `autoresearch` has 4, `develop-like-sudipta` and `code-hacker` have 1 each. Run any of them directly with `bash <path-to-test>.sh`. The autoresearch-driven scorers live at `develop-like-sudipta/skills/<skill>/autoresearch/score.sh` and emit a single number on stdout (F1 or accuracy).
- **End-to-end**: install the plugin into a real Claude Code session (`/plugin marketplace add /Users/sudipta/Workspace/personal/claude-plugin-develop-like-sudipta` then `/plugin install develop-like-sudipta`) and invoke a slash command. There is no faster way to validate slash-command frontmatter or `allowed-tools` lists.

## Architectural conventions to preserve

- **SKILL.md files are routing hubs, not knowledge dumps.** Deep content lives in `references/*.md` and is loaded only when a sub-topic triggers. When adding new content, decide first: is this a trigger/contract (→ SKILL.md) or a deep-dive (→ references)? The pattern repeats in all four bundled skills.
- **Agents are isolated-context contracts.** An agent's `.md` is the only thing it sees on invocation. Never assume an agent can read main-context state — pass it explicitly. The `test-writer` agent in particular is contractually forbidden from seeing implementation code.
- **Hooks fire deterministically; skills/agents don't.** If a check MUST run on every edit/commit/stop, it belongs in `hooks/`, not in a skill instruction. Hook scripts read JSON on stdin (Write/Edit/MultiEdit events) and write JSON on stdout with an optional `additionalContext` field.
- **The autoresearch 3-file contract:** every skill that opts into self-improvement carries `autoresearch/{program.md, score.sh, target.txt, .baselines.json}`. `program.md` is the locked goal, `score.sh` prints one number, `target.txt` names the ONE file the loop is allowed to mutate. Don't break this triple — the `autoresearch` meta-skill and the four `/autoresearch-*` commands assume it.
- **Frontmatter `description` fields are routing signal**, not human prose. The plugin's `plugin.json` and every `SKILL.md`/agent `.md`/command `.md` description is loaded into the model's context as a trigger. Edits there directly affect when the skill/agent/command fires.
- **The plugin runs WITH `obra/superpowers` when present.** Several commands and the routing skill delegate to `superpowers:brainstorming`, `superpowers:writing-plans`, `superpowers:test-driven-development`, etc. Don't duplicate that logic; gate the delegation on presence.

## ccbridge runtime invariants (sd-claude-code-access)

If you're modifying anything under `skills/sd-claude-code-access/scripts/`:

- **WORKSPACE resolution must be three-layer** (`start_watchdog.sh`): (1) honor env, (2) auto-detect from a running terminal-mode `claude` process's cwd via `lsof -a -p <pid> -d cwd` filtering out anything under `Claude.app/Contents/`, (3) fail-fast loudly. Silent learning-loss is the failure mode this guards against.
- **Filter Cowork-embedded Claudes out of process scans.** `awk '$2 ~ /^claude$|\/claude$/ && $2 !~ /Claude\.app\//'` is the canonical filter (v5.0+ — the leading `^claude$` alternation was added by BUG-1's bug-driven TDD to match user-shell-launched CCs whose `ps` shows a bare `claude` argv[0], not just full-path Cowork-embedded ones). Apply it anywhere you `ps -axo` for `claude`.
- **Bundled scheduled-task SKILLs reference `~/.cache/ccbridge/<script>.sh`, NOT plugin-relative paths.** That's why `install.sh` copies `aggregate_learnings.sh` + `distill_learnings.sh` out of the autoresearch dir into the canonical bridge dir. Don't break that — v4.3.3 fixed the portability bug.
- **Runtime-learning events dual-write** to `<workspace>/.cc/learnings.jsonl` (debuggable, local) AND `~/.cache/ccbridge/learnings/<id>.jsonl` (central tail, swept nightly). `learning.sh` does both; per-workspace `.cc/` must be gitignored.

## Versioning

Update three places per release: (1) `develop-like-sudipta/.claude-plugin/plugin.json` `version`, (2) the changelog narrative in that same `description` field, (3) the `## Versioning` section of `develop-like-sudipta/README.md`. The `marketplace.json` does NOT carry a version. Commits use Conventional Commits (`feat(...)`, `fix(...)`, `docs(...)`, etc.) per the project's git history.

## Platform / scope

- macOS-only for the CC-driving features (`/cc-drive`, watchdog, browser-test). They depend on `osascript`, Terminal.app/iTerm2, and Desktop_Commander or computer-use MCPs.
- The other pillars (planning, code review, security, dep research, hooks) are platform-agnostic.
- `python3` and `git` are required for hook scripts to work. `ruff`, `pytest`, `coverage` are optional but unlock the post-edit / completion-gate checks.
