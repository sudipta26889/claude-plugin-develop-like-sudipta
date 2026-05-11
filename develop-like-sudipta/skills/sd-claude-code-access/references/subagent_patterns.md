# Subagent patterns for Cowork driving CC

When Cowork has subagent-spawn capability (the `Task` tool), parallelize the parts of driving CC that are independent. The main thread stays small and decisive; subagents do the bulky reading.

## Pattern A: Parallel audit-during-execute

While CC is busy on Phase N+1, dispatch a subagent to audit Phase N's commits against the directive. The subagent reads `.cc/phase-N.md` + `git log --stat`, runs `audit.sh`, and returns a 200-word summary. Saves the main thread from having to read 50KB of diff itself.

```text
Spawn subagent (Explore type), prompt:
  "Audit Phase 7 of project at /path/to/workspace. Read
  .cc/phase-7.md and the last N commits. Cross-reference:
  - Commit messages match § Commit pattern in directive
  - All files mentioned in directive appear in git log --name-only
  - Test count grew (compare to STATUS.md)
  - No TODO/HACK/FIXME comments slipped in
  Report: pass/fail per item, plus any deviations to flag.
  Under 200 words."
```

Run this *while* CC is on Phase 8. By the time CC checkpoints Phase 8, you have Phase 7's audit ready in 5 seconds — main thread spent zero context on it.

## Pattern B: Long-poll subagent

Dispatch a subagent to poll the terminal every 30s for 10 minutes and report back when something interesting happens (checkpoint, error, or no progress). Main thread does not poll at all — it just waits for the subagent's return message.

```text
Spawn subagent (general-purpose), prompt:
  "Watch /path/to/workspace via the bridge. Every 30s:
  1. /tmp/ccbridge/read.sh | tail -10
  2. cd <workspace> && git log --oneline -3
  3. tail -3 /tmp/ccbridge/watchdog.log
  Continue until ANY of:
  - 'Pausing for checkpoint review' appears in buffer
  - error/Error/FAIL appears in buffer
  - 10 minutes elapsed
  - 'Do you want to' prompt detected and watchdog log shows DANGER
  Return the buffer state at exit + the trigger reason. Under 100 words."
```

Useful for handing off long phases to subagents while main thread does other work (researching the next directive, drafting a STATUS.md update, etc.).

## Pattern C: Parallel directive-write

When you've finished Phase N's checkpoint review and need to write Phase N+1's directive, dispatch a subagent to draft it from the implementation plan. Main thread reviews the draft and either accepts or revises.

```text
Spawn subagent (Plan type), prompt:
  "Read /path/to/workspace/docs/plans/<plan>.md, focus on Phase 8
  (Reopen edge cases). Read .cc/phase-7.md to see directive style.
  Draft .cc/phase-8.md following the same shape. Capture: scope,
  per-task why/where/how/failure-modes/tests, acceptance gate,
  commit pattern, out-of-scope. Be specific — name file paths and
  function names. Under 600 words."
```

Saves ~15 minutes of main-thread time per phase.

## Pattern D: Parallel diagnose

When something feels off (paste failed, watchdog quiet, hang suspected), dispatch a subagent to run `diagnose.sh` + read recent state.json + grep for known error patterns, returning a compact report.

```text
Spawn subagent (Explore type), prompt:
  "Run health check on the CC bridge for /path/to/workspace.
  1. Run /tmp/ccbridge/diagnose.sh /path/to/workspace
  2. Tail last 50 lines of /tmp/ccbridge/watchdog.log
  3. Tail last 20 events from <workspace>/.cc/state.json
  4. Run /tmp/ccbridge/audit.sh <workspace> <last_phase_number>
  Return: what's healthy, what's sus, recommended next action.
  Under 250 words."
```

Single subagent return ≈ 3-4 main-thread tool calls' worth of context.

## Pattern E: Independent verifier

For high-stakes phases (security-related, infra changes), spawn a subagent to independently verify CC's checkpoint summary by reading the actual diffs. The subagent doesn't see CC's summary first — it reaches its own conclusion. If they disagree, surface the discrepancy.

```text
Spawn subagent (code-reviewer or general-purpose), prompt:
  "I'll give you a project workspace and a phase number. Without
  reading any directive or summary, do a code review of the commits
  in that phase. Use git log + git show. Tell me:
  - What did this phase actually accomplish?
  - Any concerns about correctness, security, or maintainability?
  - Test coverage adequate?
  Project: /path/to/workspace, Phase: 11.
  Under 400 words."
```

Then compare the subagent's review to CC's checkpoint summary. Divergence is a signal worth investigating.

## Anti-patterns

- **Don't spawn a subagent for a 5-second probe.** The Task-tool overhead is ~10s; small jobs are cheaper inline.
- **Don't spawn nested subagents that all need the same files.** Have ONE subagent fan out to do its own subagent work; main thread shouldn't orchestrate at depth >1.
- **Don't put credentials in subagent prompts.** Subagents see the full prompt; treat it as you would a paste.

## Cost ratio

A subagent dispatch costs roughly: (1) main-thread tokens for the prompt, (2) main-thread tokens for the return. Mid-sized prompt + 200-word return ≈ 1500 tokens. A naive inline read+process can easily burn 3000 tokens because you have to load the raw data into your own context. So subagents are net token-cheaper any time you're working with files >2KB or doing repeat-pattern work.

## When subagents are NOT available

In Cowork without the Task tool, fall back to:
- Tighter polling with cheap probes (`git log --oneline | head -1`, watchdog log tail)
- Pre-written directives so Phase N+1's directive is ready before Phase N completes
- Aggressive use of `audit.sh` and `diagnose.sh` so each tool call returns dense, structured info
