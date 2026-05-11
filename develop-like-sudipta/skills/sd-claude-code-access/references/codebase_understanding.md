# Codebase understanding — staying in lockstep with CC

Cowork's understanding of the project is the most fragile part of this whole system. CC writes the code; Cowork only sees what CC summarizes plus what Cowork actively reads. Without effort, drift sets in fast.

This document is a protocol for maintaining a real mental model of the codebase as CC builds it.

## The 4-document floor

Before starting any session, read these in order:

1. **`STATUS.md`** (or equivalent) — the cumulative source of truth maintained across phases. If the project doesn't have one, ask CC to create one in Phase 1.
2. **`README.md`** — entry points, how to run locally, env vars.
3. **`CLAUDE.md`** — the project's load-bearing conventions (patterns the team has agreed on after iteration). Treat as authoritative.
4. **`docs/plans/*-implementation.md`** OR equivalent — the canonical multi-phase plan.

If any of these don't exist, that's an early-phase smell. Ask CC to create them.

## The git log probe

`git log --oneline -N` is the cheapest, most reliable progress probe. After every checkpoint:

```bash
cd <workspace>
git log --oneline -10
git log --stat -5  # files changed per commit
```

What to look for:

- **Commit count matches what the directive promised.** If the directive said "4 commits" and you see 2, ask why.
- **Commit messages match the pattern you specified.** Drift here usually means CC reordered tasks.
- **No "amend" or "fixup" commits without explanation.** Those mean CC re-shaped a commit after the fact; usually fine but worth noting.
- **No `git add -A` mass commits.** They sweep in scratch files (e.g. `.cc/phase-*.md` if not gitignored). The pre-mortem-flagged outcome.

## The directive-vs-reality diff

Before approving a phase, do this:

1. Re-read `.cc/phase-N.md` (the directive you sent).
2. For each task in the directive, ask:
   - Was it committed? (`git log --oneline | head -10`)
   - Did the commit touch the expected file? (`git log --name-only -5`)
   - Did the test count grow? (CC's checkpoint summary should have the number; verify via `pytest --collect-only -q | tail -3`)
3. Run `bash <skill-path>/scripts/audit.sh <workspace> <N>` for a structured cross-check.

If anything's missing, ask CC about it before approving. "I notice you didn't add the `is_escalation` test from §3 of the directive — was that intentional?"

## Reading actual diffs

CC's checkpoint summaries describe intent. Diffs describe reality.

For each new commit you care about:

```bash
git show --stat <sha>      # what changed
git show <sha>             # the actual code
```

What to look for in the diff:

- **Did CC use the patterns from the directive?** (`asyncio.gather(... return_exceptions=True)`, `clock_timestamp()`, etc.)
- **Are the new tests actually testing the thing?** It's easy to write a test that asserts a True is True. Glance at the `assert` lines.
- **Are there new TODO/HACK/FIXME comments?** Those are CC's way of flagging deferred items it didn't tell you about.
- **Are there commented-out blocks?** Usually scaffolding CC forgot to delete.
- **Did `pyproject.toml` / `package.json` grow new deps?** If yes and the directive didn't mention them, ask why.

## The deferred-item catalog

Things CC defers (legitimately or otherwise) accumulate fast in long runs. Track them in a file rather than relying on memory:

- `STATUS.md` should have a "Deferred to V2" section that grows each phase
- The phase checkpoint should explicitly list new deferrals
- When a phase uses `# TODO V2:` comments in code, surface those in the next checkpoint

In real runs, ~20-30 deferred items accumulate by the end of a 16-phase project. Some are fine to ship with; others (security, performance) need to come back for a follow-up phase.

## The "what changed since I last looked" probe

Mid-phase, when you want a quick read on progress without disrupting CC:

```bash
git log --oneline --since="30 minutes ago"
git diff --stat HEAD~5  # rough volume
```

Don't read the full buffer every time you check — that costs context. The git log is enough to know if CC is making progress.

## The codebase scan, when you join late

If you're picking up a session that another Cowork run started (or a human did some work between sessions):

```bash
# Where am I?
git status
git log --oneline -20
git branch -v

# What's the shape?
find <workspace> -type f -name '*.md' | xargs ls -la
ls -la <workspace>/.cc/  # any pending directives?

# What's tested?
.venv/bin/pytest --collect-only -q | tail -5
```

This 30-second scan tells you 80% of what you need to know without reading code.

## Anti-patterns

- **Approving a phase based on the checkpoint summary alone.** Always at least skim `git log` and one diff.
- **Letting `STATUS.md` go stale.** If 3 phases have shipped since the last STATUS update, the file is lying.
- **Trusting your memory.** This is a manager job; manager jobs require notes. Use STATUS.md.
- **Asking CC "did you do X?" instead of grepping the code.** Faster, more accurate to read the code.
