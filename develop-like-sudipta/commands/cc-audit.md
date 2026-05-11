---
description: Cross-reference a Claude Code phase directive against git log + repo state — detect drift between what was directed and what got committed
argument-hint: <workspace-path> [days-back=7]
---

Audit a Claude Code phase: compare the directive against what actually landed in git, and surface drift.

**You MUST invoke the `sd-claude-code-access` skill first** — specifically the `audit.sh` script and `references/codebase_understanding.md`. Drift between directive and reality is silent and lethal.

## Inputs

- `$1` — workspace path (required)
- `$2` — days back to scan (optional, default 7)

## Procedure

1. **Read the skill's codebase-understanding reference.**
2. **Locate the latest directive** — `$1/.cc/phase-*.md` sorted by phase number, take the highest.
3. **Run the bundled audit script:**
   ```bash
   bash ~/.cache/ccbridge/audit.sh "$1" "${2:-7}"
   ```
   It reports:
   - Matched commit messages (directive task → commit subject)
   - Missing files (mentioned in directive but never committed)
   - Files committed but never mentioned (potential scope creep)
   - Expected commit messages still outstanding
4. **Read the diffs of the matched commits** — `git -C "$1" log --since="${2:-7} days ago" --oneline`, then `git show` on the headline ones. Don't trust subject lines alone.
5. **Cross-reference verify-gate state** — for every `phase_complete` event, is there a `phase_verify_passed` event before it? Phases that completed without a passing verify-gate are highly suspect — surface them.
6. **Cross-reference browser-test artifacts** — for every `phase_complete` event in `$1/.cc/state.json`, is there a corresponding `docs/e2e-testing/phase-N-*.md` with a green `## Result`? Flag any phase that completed without a browser test.
7. **Audit bug-driven TDD discipline** — for every `bug_resolved` event in `state.json`:
   - Verify a corresponding `$1/.cc/bugs/<bug-id>.md` exists.
   - Verify the new test file(s) that the bug report references actually exist in the project's test tree (`git ls-files | grep <bug-id>`).
   - Verify the fix commit references the bug-id in its message.
   - Verify the per-phase browser test md has a `## Re-run` section linking the bug.
   - Flag any bug-resolved event missing any of the above — the fix bypassed the protocol.
8. **Read STATUS.md** — `$1/STATUS.md`. Does it match git reality? Flag anything that says "done" without commits to back it up.
9. **Report to the user** in this order:
   - **Drift findings** — what the directive said vs what got committed.
   - **Verify-gate gaps** — phases marked complete without `phase_verify_passed`.
   - **Browser-test gaps** — phases marked complete without a corresponding green test.
   - **Bug-TDD discipline gaps** — fixes that landed without a failing test first.
   - **STATUS.md mismatches** — claims unsupported by git.
   - **Scope creep** — files committed that weren't directed.
   - **Recommended actions** — what to fix, what to re-run, what to send back to CC as a follow-up directive.

## Don't

- Don't pass an audit because the commit messages "look right". Read the diffs.
- Don't ignore verify-gate gaps. A phase without `phase_verify_passed` may have shipped on red unit tests.
- Don't ignore browser-test gaps. A phase without a passing test isn't done; it's untested.
- **Don't accept bug fixes that have no failing-test-first artifact.** Bug-driven TDD is the discipline. Fixes without a corresponding `.cc/bugs/<bug-id>.md` + new test file = audit fail.
- Don't auto-fix drift. Surface it, propose actions, let the user decide.
- Don't audit without `WORKSPACE` set if the previous run didn't log state events — fall back to git log + mtimes and say so.
