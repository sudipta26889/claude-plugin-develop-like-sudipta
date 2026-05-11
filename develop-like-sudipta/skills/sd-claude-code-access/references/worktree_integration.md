# Worktree integration — running CC in a git worktree

The `sd-claude-code-access` skill assumes `WORKSPACE` points at the directory CC is operating on. When you use `superpowers:using-git-worktrees` to isolate a feature branch, CC runs in the WORKTREE subdirectory, not the main repo. This doc covers the resulting setup.

## What changes when CC runs in a worktree

A git worktree (`git worktree add .worktrees/<branch-name> -b <branch-name>`) creates a sibling working tree that shares the main repo's `.git/` (mostly). CC can run there just fine — but several things shift:

| What | Without worktree | With worktree |
|---|---|---|
| CC's `cwd` | `<repo>/` | `<repo>/.worktrees/<branch>/` (or wherever the worktree was created) |
| `WORKSPACE` env | `<repo>` | `<repo>/.worktrees/<branch>` |
| `.cc/` directory | `<repo>/.cc/` | `<repo>/.worktrees/<branch>/.cc/` |
| Browser tests | `<repo>/docs/e2e-testing/` | `<repo>/.worktrees/<branch>/docs/e2e-testing/` |
| Driver lock | `<repo>/.cc/.driver.lock` | `<repo>/.worktrees/<branch>/.cc/.driver.lock` |
| state.json | per-worktree | per-worktree |
| watchdog | one per worktree (multi-watchdog OK) | one per worktree |
| Audit | reads worktree's `git log` (same as main repo's, but `--since` honors worktree HEAD) | same |

## Pre-flight changes when using a worktree

When starting a CC-driving session in a worktree:

1. **Set `WORKSPACE` to the worktree path**, not the main repo:
   ```bash
   export WORKSPACE=/path/to/repo/.worktrees/feat-foo
   ```
2. **Verify worktree is the active git tree:**
   ```bash
   cd "$WORKSPACE" && git rev-parse --show-toplevel
   ```
   Should print the worktree path. If it prints the MAIN repo path, you're in the wrong dir.
3. **Install scripts as usual** — they go to `~/.cache/ccbridge/` (machine-global). One install per machine, regardless of how many worktrees you'll drive.
4. **Run the watchdog inside the worktree** — `WORKSPACE` is the only knob that determines which `.cc/` it writes to.

## Multiple parallel worktrees

It's safe to drive multiple worktrees simultaneously — each Cowork session sets `WORKSPACE` to a different worktree. The driver lock (`.cc/.driver.lock`) is per-worktree, so no two sessions clash on the same one.

```
Cowork session A -> WORKSPACE=<repo>/.worktrees/feat-auth     -> CC instance A
Cowork session B -> WORKSPACE=<repo>/.worktrees/feat-payments -> CC instance B
```

Two CC terminals, two separate watchdogs, two separate test banks under each worktree's `docs/e2e-testing/`. They share `.git/objects` so refs are visible to each other, but state events and bugs are isolated.

## Browser tests inside worktrees

`docs/e2e-testing/` lives INSIDE the worktree. Each worktree's test bank is its own — no cross-contamination. When the worktree is merged into main, `docs/e2e-testing/` lands in main as part of the merge; commit history is preserved.

If you want a shared test bank across worktrees, symlink:
```bash
ln -s <repo>/docs/e2e-testing <repo>/.worktrees/<branch>/docs/e2e-testing
```
(But this is rare — usually you want per-branch tests because the feature is what's being tested.)

## Audit behavior

`audit.sh --retry 3 --retry-interval 2` reads the worktree's `git log`. Since worktrees share `.git/`, the log shows the worktree's branch tip + ancestors. `--since` and `HEAD~N` work as expected. The drift detection is per-worktree.

## Resume after crash

`state_salvage.sh <WORKSPACE>` reads the worktree's `.cc/state.json`. If you crashed mid-run, set `WORKSPACE` to the same worktree and resume; the state is local.

## Driver lock semantics

The driver lock is held by a Cowork session for a worktree. If Cowork crashes:
- Lock detection: `lock.sh status "$WORKSPACE"` reports "stale" if the holder PID is dead
- Salvage: another Cowork session can take the lock if it's stale

## Finishing the development branch

After CC finishes in the worktree:

1. Run `/e2e-suite` — stitches the worktree's per-phase tests into `docs/e2e-testing/E2E-SUITE.md`
2. Run `cleanup_test_artifacts.sh` to archive old screenshots (optional)
3. Use `superpowers:finishing-a-development-branch` to merge / PR
4. Remove the worktree: `git worktree remove .worktrees/<branch>`
   - `.cc/`, screenshots, and test artifacts go with the worktree dir UNLESS you specifically moved them to the main repo first
   - The committed `docs/e2e-testing/*.md` and `specs/*.ts` are PRESERVED via the merge

## Don't

- **Don't run two Cowork sessions on the same worktree.** Driver lock blocks it, but only if `WORKSPACE` is set correctly. Belt-and-braces: one Cowork chat per worktree.
- **Don't symlink `.cc/` across worktrees.** State events get tangled — phases overlap, bugs get cross-attributed.
- **Don't commit `.cc/` to git.** The plugin's `install_precommit.sh` adds a hook that prevents this — install it per worktree.
- **Don't assume the main repo's `STATUS.md` covers the worktree.** Each worktree has its own — but the user reads the main repo's by default, so keep them in sync at merge time.

## See also

- `superpowers:using-git-worktrees` — the canonical worktree setup pattern
- `superpowers:finishing-a-development-branch` — merge / PR options after CC completes
- `references/state_and_resume.md` — what `.cc/state.json` contains
- `references/managing_long_runs.md` — orchestrating long CC runs (which can include multi-worktree)
