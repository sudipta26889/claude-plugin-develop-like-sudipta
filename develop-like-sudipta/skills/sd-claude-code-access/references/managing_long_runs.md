# Managing long autonomous runs

For runs > 30 min where the user is partly or fully away. Optimized for context budget and recoverability.

## Pre-run setup (do BEFORE the user steps away)

1. **Pre-write all phase directives.** Each one in `<workspace>/.cc/phase-N.md`. Verify they reference each other consistently (Phase N's "deferred to later" matches what Phase N+1 actually picks up).
2. **Confirm `.cc/` is gitignored.** First commit of the session if not.
3. **Start the watchdog and confirm it works** by triggering a small test (the next normal phase trigger will do).
4. **Establish polling cadence.** 60-180s during phases. Faster polling burns Cowork's context for no benefit — the watchdog handles routine prompts.
5. **Tell the user what to expect.** "I'll handle phases 6-16 autonomously. Watchdog auto-approves dev commands. I'll surface checkpoints + design questions only. STATUS.md will be the entry point when you're back."

## During the run — the discipline

### Polling

Use longer intervals than feels comfortable. 60s is the floor; 180s for stable phases. Cheap probes:

```bash
git log --oneline -1                              # last commit
git log --since="N minutes ago" --oneline | wc -l # phase progress count
/tmp/ccbridge/read.sh | tail -10                  # last 10 lines of TUI
tail -5 /tmp/ccbridge/watchdog.log                # watchdog activity
```

Only read the full TUI buffer when the cheap probes suggest something interesting (phase done, error visible, no progress).

### Per-checkpoint discipline

When CC pauses for review:

1. Read git log for new commits.
2. For 1-2 headline commits, `git show --stat` and `git show` to skim the diff.
3. Read CC's checkpoint summary.
4. Run `audit.sh <workspace> <N>` for the structured cross-check.
5. Decide: approve / nudge for fix / ask design question.
6. Trigger next phase via tiny "Read .cc/phase-<N+1>.md and proceed." message.

Allocate ~5-10 min of Cowork context per checkpoint. Long phases compound; keep this lean.

### Mid-phase intervention

Avoid it. The watchdog handles routine approvals. Only intervene if:

- A design question surfaces (CC asks "do you want X or Y?")
- An error surfaces that CC isn't recovering from (lint persists across two commit attempts)
- A hang is detected by `nudge_if_stuck.sh` or by your own probe

Each intervention costs context. Most phases don't need any.

### Status hygiene

Every phase's checkpoint summary should land into `STATUS.md` cumulatively. CC usually does this in the final commit of a phase (`docs(status,runbook): Phase N — ...`). Verify.

If STATUS.md is 3 phases stale, you've lost track. Send a tiny "Bring STATUS.md current with the last 3 phases — same row format as existing rows." directive.

## Context budget management

Cowork's context is finite. A 16-phase run with naive polling burns 100k+ tokens in just terminal reads. Defenses:

- **Use `git log --oneline` over `read.sh`** when you only need to know "did anything happen?"
- **Tail watchdog log** instead of reading the buffer to confirm prompts are being approved
- **Pre-write directives** so per-phase triggers are 1-line messages, not 3KB markdown
- **Refuse to approve without reading** — don't substitute a long re-read of CC's checkpoint summary for a 30-second `git show <sha> | head -50` glance at the actual diff

## Hang detection & recovery — automated

Run `nudge_if_stuck.sh` as a background companion to the watchdog:

```bash
# In addition to the watchdog
nohup /tmp/ccbridge/nudge_if_stuck.sh 600 30 >/dev/null 2>&1 &
disown
```

Args: 600 = "stuck if buffer unchanged for 10 min", 30 = "poll every 30s".

It logs to `/tmp/ccbridge/nudge.log`. After it presses Esc, your queued message (if any) gets processed. If there's no queued message, CC just shows the cancel prompt and waits — you can then send the right next message.

## Final phase / wrap-up

The final phase should always include:

- Run full test suite
- Run all linters / type checkers
- Build the Docker image
- Generate a `STATUS.md` that captures: phase summary, deferred items, blockers, deploy-day checklist
- Commit a `chore: V1 implementation complete; awaiting <list>` marker commit

Use this directive shape for the final phase:

```markdown
# Phase N — Final acceptance

## Standard checks
- pytest
- ruff check
- mypy src
- docker build
- (eval gate if dataset present)
- git log --oneline | wc -l

## Items I CANNOT complete autonomously (document, don't pretend)
- <list things that need user creds / human review / external services>

## Deliverable: STATUS.md at repo root
- All commits + per-phase test counts
- Pass/fail matrix per phase
- Blockers list
- "What's runnable RIGHT NOW locally" section
- "Deploy when you're back" ordered checklist
```

This is the most important deliverable of an autonomous run. Without it, the user can't pick up where you left off.

## Human checkpoint cadence

For long autonomous runs where the user is away, Cowork should pause for user OK at meaningful checkpoints — not every phase (noisy), not never (loses oversight). The right cadence is: pause at events that materially change risk or scope, summary-update everything else.

### Default cadence (events that trigger a pause)

Configurable via `<workspace>/.cc/config.json` → `pause_at` (array of state-event names):

| State event | Default in pause_at? | Why |
|---|---|---|
| `substrate_chosen` | yes | First time touching the Mac — user should see which path |
| `phase_start` | no | Pre-flight done, user told plan upfront; no new info |
| `phase_complete` | no | Routine — STATUS.md update is enough |
| `phase_verify_passed` | no | Routine |
| `phase_browser_test_passed` | no | Routine |
| `phase_browser_test_failed` | yes | Real bug — user needs to see it before fix loop continues |
| `phase_verify_step_failed` | yes | Test went red — fix loop incoming |
| `bug_resolved` | yes | Three failed attempts before this is a different event (escalation) |
| `bug_escalated` | yes | After 3 fix attempts on same bug — definitely need user |
| `danger_blocked` | yes | Watchdog blocked something — user should review |
| `auth_refresh_required` | yes | Cred-dependent step, user might need to enter creds |
| `dev_server_start_failed` | yes | Infrastructure problem, not code |
| `final_e2e_suite_emitted` | yes | End-of-run — user should review umbrella |

### Behavior on pause

When Cowork hits a paused event:
1. Write a one-paragraph summary of WHAT just happened to chat (not the full transcript — the user is skimming).
2. Show the relevant diff / artifact / log snippet (3-5 lines max).
3. Wait for user OK before continuing. Don't auto-advance.

### Behavior on non-paused events
Update `STATUS.md` cumulatively. Don't ping the user in chat unless something surprising happened.

### Overrides

- `pause_at: []` — fully autonomous, only pause if the user @-mentions Cowork
- `pause_at: ["*"]` — pause on every state event (verbose; use for debugging)
- `pause_at: [<specific events>]` — custom list

### Patterns I've seen

- **First overnight run on a new project:** pause at all defaults — get used to the rhythm
- **Familiar project, low-risk refactor:** drop `bug_resolved` and `dev_server_start_failed` to reduce interruptions
- **Demo / live coding:** pause on every event so the audience sees the steps

See also: `references/state_and_resume.md` for the full list of state events Cowork emits.

## When to stop

Stop the autonomous run if:

- Three consecutive phases fail acceptance and CC keeps "fixing forward"
- The directive structure breaks down (you can't write a useful directive for the next phase without more user input)
- A real design question surfaces that needs user judgment
- The user pings you for something else and you can't manage both

Restarting later is fine — STATUS.md captures the resumption point.
