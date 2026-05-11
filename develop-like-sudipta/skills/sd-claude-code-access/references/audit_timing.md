# Audit timing — why the audit needs retry, and how to budget it

`audit.sh` cross-references the phase directive against `git log` and the working tree. The naive single-shot version runs the moment Cowork sees CC's checkpoint message. That message can render BEFORE the commit it describes has actually landed on disk. When that happens the audit reports drift — a missing file, a missing commit message — and Cowork treats a healthy phase as broken.

The fix is small and behavioural: when audit sees the laggy kind of drift (a directive-mentioned file that didn't land, or an expected commit message that isn't in `git log` yet), give it a chance to recheck before screaming. Two flags do that:

```bash
audit.sh <workspace> <phase> --retry 3 --retry-interval 2
```

Default (no flags) is single-shot, identical to the v3.2 behaviour. The per-phase loop in `SKILL.md` invokes audit with `--retry 3 --retry-interval 2`, which is a sane baseline for most projects.

## Why commit-hook lag is real

Several common pieces of dev infrastructure add seconds — sometimes tens of seconds — between "Claude Code finished writing the commit message" and "the SHA is in `git log`":

- **Python pre-commit framework** (`pre-commit`). Runs ruff / mypy / black / isort / bandit / etc. on the staged hunks before the commit is finalised. Cold cache on a first run can be 10–30 s; warm cache is usually 2–5 s.
- **Node hook runners** — husky + lint-staged, lefthook, simple-git-hooks. Same shape as pre-commit. Eslint + prettier + tsc on a large monorepo regularly takes 8–15 s. Vitest run on changed files adds 3–10 s more.
- **GPG signing** (`commit.gpgsign=true`). Adds a `gpg --sign` call. If the agent is unlocked, ~200 ms. If the agent prompts for a passphrase, the commit blocks until the operator types — that's not "lag", that's "waiting for a human", and no retry budget will save it.
- **Large-file scanning**. Hooks like `trufflehog`, `gitleaks`, `talisman` walk staged content for secrets. Time scales with hunk size; 1–5 s typical, more on a doc-heavy commit.
- **Security or compliance scanners** wired into the repo (SAST, license check). Usually 5–20 s.
- **Native OS quirks** — Spotlight reindexing in `.git/`, antivirus on Windows hosts, slow networked filesystems (NFS, SMB). Adds variance, not a fixed cost.

The naive audit fires the moment CC's TUI prints the checkpoint summary, which is BEFORE most of those pipelines start. By the time the audit reads `git log`, the commit is in flight but not committed. Drift reported. Phase rejected for no reason.

## Recommended retry budgets

Pick the budget by what's installed in the project's `.pre-commit-config.yaml` / `package.json` (`husky`, `lint-staged`, `lefthook`) / equivalent. Numbers are starting points — measure your project's p95 hook latency once and adjust.

| Stack | `--retry` | `--retry-interval` | Total budget | Notes |
|---|---:|---:|---:|---|
| Small Python project (ruff + mypy) | 3 | 2 | 6 s | The default. Most CC sessions live here. |
| Node project with husky + lint-staged + tsc | 5 | 3 | 15 s | tsc on a 30k-LOC TS repo + eslint dominate. |
| Large monorepo (turborepo / nx, full-repo type-check) | 6 | 5 | 30 s | Cache-cold runs can blow past this; if you hit "budget exhausted" repeatedly, raise to `--retry 8 --retry-interval 5`. |
| GPG-signed commits (agent unlocked) | 4 | 3 | 12 s | The extra slack covers TTY-prompt variance. |
| GPG-signed commits (agent locked — passphrase prompt) | n/a | n/a | n/a | Retry doesn't help; the commit is paused for a human. Approve in the terminal, then re-run audit by hand. |
| Backend-only phase, no new files expected | 0 | — | 0 s | See "When NOT to use retry" below. |

The cost of being too generous is wall time during a green phase. The cost of being too stingy is a false-positive drift report that triggers a bug-driven-TDD loop on a phase that's actually fine. Err generous.

## Per-project defaults (documented, not yet wired)

The plan is to let projects opt into a default budget via `<workspace>/.cc/config.json`:

```json
{
  "audit_retries": 5,
  "audit_retry_interval": 3
}
```

When the per-project loop runs `audit.sh`, it would read these keys and pass them through, so the SKILL.md baseline doesn't have to be tweaked per repo. **This config-reading is NOT implemented yet** — at the moment the loop hard-codes `--retry 3 --retry-interval 2`. The config keys are reserved so a later task can plumb them through without renaming.

If you want different per-project defaults today, override at the call site:

```bash
# In .cc/audit.sh or a project-level wrapper:
exec ~/.cache/ccbridge/audit.sh "$@" --retry 6 --retry-interval 4
```

## When NOT to use retry

Retry budgets are pure cost when applied to phases where the laggy-drift signal is meaningful as-is:

- **Pure-refactor phases.** Directive intentionally mentions no new files — only existing ones. If audit reports "no files mentioned but not changed", retry can't help, and exit 2 is the correct signal that the directive is too vague.
- **Plan / docs phases.** A phase whose only artifact is `docs/plans/N-implementation.md`. Same logic: if the doc didn't land, retrying for 30 s won't change that.
- **Investigation phases.** Bug-reproduction work where the directive itself says "no commits expected, just write evidence into `.cc/bugs/`". Pass `--retry 0` to skip; treat any drift report as instant feedback.

Skip retries by passing `--retry 0` explicitly:

```bash
audit.sh "$WORKSPACE" 7 --retry 0
```

This restores the old single-shot semantics. It's also what the script does when neither flag is passed — back-compat for any caller that hasn't been updated.

## What exit code 2 means now

`audit.sh` previously exited 0 even when drift was found (the text report was the signal). With retry plumbing, the exit code carries information:

- **0** — clean. Every expected commit-pattern entry resolved, every directive-mentioned file changed in the range.
- **1** — hard error. Missing directive file, bad CLI args, can't `cd` to the workspace.
- **2** — missing-file-or-commit (retryable drift). Returned when the only finding is files or commits that haven't landed yet. With `--retry N`, you only ever see this once the budget is fully spent.

The per-phase driver should treat exit 2 (post-retry) as a real drift event and route to the bug-found / fix-directive flow. Treat exit 1 as a tooling problem to fix in the driver, not the project under test.

## Anti-patterns

- **Don't disable retry "to make audit faster"**. A 6 s budget on a green phase is invisible. A false-positive drift report costs you a 5-minute bug-TDD detour.
- **Don't keep raising `--retry` to mask a slow hook**. If a project's pre-commit pipeline regularly takes 45 s, the right fix is to profile and prune the hook, not to bump the retry budget to 60 s. Long hooks make every commit feel laggy to humans too.
- **Don't run retries during interactive debugging**. When you're staring at the audit output trying to understand a drift, the sleeps are noise. Pass `--retry 0` for ad-hoc diagnostic runs.
- **Don't rely on retry to paper over a GPG passphrase prompt**. That's not lag, it's a blocked commit. Approve, then run audit once.
