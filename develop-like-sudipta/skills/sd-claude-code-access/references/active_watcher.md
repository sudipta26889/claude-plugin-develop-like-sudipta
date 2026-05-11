# Active watcher — manager-decides model

## Why the shift

The v4.x watchdog was a regex auto-approver: it identified a prompt frame, ran the
visible buffer through a danger deny-list, and pressed Enter if no danger pattern
matched. It never read the prompt's *meaning*. The deny-list was a fail-safe, not a
decision-maker, and the manager (Cowork / human) was a passive observer.

That model was the wrong shape. Quoting the user critique that triggered this
architectural pivot:

> *"Currently you are not watching, a static script is blindly approving all claude
> code requests without actually checking what claude code is going to do. I want
> Claude Cowork to keep watching, keep deciding, take the right call, select the
> right option (with revise prompt if and when applicable)."*

The v4.9+ model inverts the responsibilities:

| Concern | v4.x (old) | v4.9+ (new) |
|---|---|---|
| Primary approver | `watchdog.sh` (heuristic) | Manager — Cowork or human (reasoning) |
| Watchdog's job | Decide every prompt | Detect prompts; refuse danger patterns only |
| Manager's job | Poll occasionally, rubber-stamp checkpoints | Read every `prompt_pending` event, decide, act |
| Failure mode | Watchdog auto-approves something it shouldn't | Manager misreads context — but a reasoning miss is recoverable in a way a heuristic miss isn't |
| When to opt out | n/a — watchdog was always on | Set `WATCHDOG_AUTO_APPROVE=1` for unattended scheduled-task runs |

## Manager polling cadence

Within a Cowork turn, the manager polls aggressively:

1. Read `~/.cache/ccbridge/watchdog.log` (or `<workspace>/.cc/state.json`) every
   ~5s via `read.sh` in a loop.
2. Continue until either (a) a `prompt_pending` event appears, (b) CC produces a
   commit (`git log --oneline` changed), or (c) the user sends new input.
3. On a `prompt_pending` hit, fall into the per-prompt decision tree (next section).
4. After acting (approve / deny / revise), return to polling.

Between turns the manager is dormant. CC pauses at its prompt and waits for the
manager's keystroke; this is fine — the verify-gate and bug-driven TDD discipline
make stalling at a prompt strictly better than auto-approving the wrong action.

## Per-prompt decision tree

Each time the manager sees a `prompt_pending` event:

1. **Read the FULL visible buffer** via `read.sh`. Don't trust the 200-char
   snippet from the state event alone — it's a grep hook, not the decision input.
   You need to see what CC is about to do, including the context that produced
   the prompt (the last directive, the recent diff, the menu options).

2. **Classify the intent:**
   - *Right thing* — CC is about to do what the directive asked. Identify the
     menu option (1/2/3, or arrow position) and send it via `keys.sh`:
     ```bash
     ~/.cache/ccbridge/keys.sh 1            # numbered menu
     ~/.cache/ccbridge/keys.sh down && ~/.cache/ccbridge/keys.sh return  # arrow menu
     ```
   - *Wrong thing* — CC is about to do something the directive didn't ask for, or
     misinterpreted the previous step. Interrupt with `keys.sh esc`, then write a
     revised directive to `.cc/revise-<ts>.md` and send via `send.sh`:
     ```bash
     ~/.cache/ccbridge/keys.sh esc
     echo "Read .cc/revise-2026-05-12-T13-22.md and proceed." \
       | ~/.cache/ccbridge/send.sh
     ```
   - *Ambiguous* — escalate to the human reviewer. Don't guess. A wrong approval
     can cost an hour of cleanup; a question to the human costs 30 seconds.

3. **Log the decision** so future autoresearch runs can learn from manager
   reasoning patterns:
   ```bash
   ~/.cache/ccbridge/state.sh "$WORKSPACE" manager_decision \
     "action=approve" "fp=$FP" "reason=matches phase-3 task 2 acceptance"
   ```
   The `action` values are canonical: `approve`, `deny`, `revise`, `escalate`.

## The watchdog's reduced role

The watchdog is now a **safety net**, not a decision-maker. It still:

- **Detects prompt frames** via `PROMPT_PATTERN` so the manager has a fingerprint
  to grep on (`prompt_pending` carries `fp=<sha256-12>`).
- **Refuses danger patterns** from `danger_patterns.txt` (and `<ws>/.cc/danger_patterns_extra.txt`)
  via the existing danger-deny branch — logs `danger_blocked`, fires `escalate.sh`,
  emits the central learning event.
- **Logs every prompt** for autoresearch via `learning.sh permission_pattern
  outcome=pending|approved|danger_blocked`.

What it **no longer does** in the default mode (`WATCHDOG_AUTO_APPROVE=0`):

- Press Enter on non-danger prompts. The manager decides every one.
- Make any policy decision beyond "is this in the danger list?".

`WATCHDOG_AUTO_APPROVE=1` restores v4.7 auto-approve behavior — the right call for
unattended scheduled-task runs (`ccbridge-propose-fix-pr` at 09:00 Monday, the
nightly aggregator, etc.) where no manager is online to poll. Set it explicitly in
the scheduled-task SKILL.md frontmatter so the intent is grep-able.

## Trade-offs

Honest accounting:

- **Slower than auto-approve.** CC pauses between manager pings. If the manager
  polls every 5s and acts in the next turn, each prompt costs 5-10s of CC
  wall-time. v4.x's watchdog handled it in <1s.
- **Manager turn budget grows.** Each prompt is now a Cowork-turn decision, not a
  no-op. For a 20-prompt phase, expect 20 cycles of "read state.json → read buffer
  → decide → keys.sh / send.sh". This is paid for by the next bullet.
- **Correctness is bought, not assumed.** Every approval is now a deliberate,
  contextual decision. The user's critique was that auto-approve is a lie —
  pretending to watch while actually rubber-stamping. The new model trades speed
  for honesty.
- **The escape hatch matters.** Don't refuse to set `WATCHDOG_AUTO_APPROVE=1` for
  the scenarios that genuinely warrant it. Unattended runs at 03:30 on a Sunday
  have no manager to decide for them. Auto-approve is the right answer there;
  the danger list is still the safety net.

## Anti-patterns

Don't:

- **Promote `prompt_pending` events to user-facing notifications.** The user
  already knows — CC's tab shows the prompt. A push notification on top of an
  already-visible prompt is noise. The state event is for the manager, not the
  user.
- **Add a third layer between manager and CC.** No "smart watchdog" daemon, no
  prompt-classifier service, no LLM-in-the-watchdog. The manager IS the watcher
  now. Three layers means three places to debug a wrong decision.
- **Try to make the watchdog "smart" again.** The whole point of moving the
  decision up to the manager is that LLM-grade reasoning belongs at the manager
  layer, not in a bash regex. Don't reinvent the heuristic.
- **Silently switch existing tests' expectations from `prompt_approved` to
  `prompt_pending`.** If a regression test fires on the wrong event after this
  flip, decide deliberately whether the test should run in auto-approve mode
  (`WATCHDOG_AUTO_APPROVE=1`) or assert the new event. Document the choice.
- **Keep polling `prompt_pending` after acting on it.** The fingerprint dedupe
  is per-fp; once you press a key, CC moves on, new fp on the next prompt. If
  you see the same fp twice, your action didn't take — investigate, don't
  re-fire.

## Job spec (v5.0)

The manager-decides model from the preceding sections is the *protocol*. The
**job spec** is the *trigger* — a single file at `<workspace>/.cc/active-job.json`
that switches a workspace from "dormant" to "the cc-orchestrator should attend
this every minute." When the file is absent, the orchestrator's per-fire Step 1
early-exits and no quota is spent.

### Schema

See [`assets/active-job.example.json`](../assets/active-job.example.json) for the
canonical template. Required fields:

| Field | Type | Purpose |
|---|---|---|
| `job_id` | string | Stable id used in state events and the central learning tail. Convention: `<short-slug>-<YYYY-MM-DD>`. |
| `started_at` | RFC-3339 UTC | When the job began. The orchestrator uses this to evaluate `max_duration_hours`. |
| `plan_path` | repo-relative path | The implementation plan the orchestrator references when deciding next-phase directives. Manager-side, not consumed by CC directly. |
| `max_duration_hours` | int | Wall-clock cap. Orchestrator marks `done` when exceeded (regardless of phase progress). |
| `max_cycles` | int | Hard cap on orchestrator fires for this job (1 fire = 1 minute, so `1440` = 24h). Belt-and-suspenders for the duration cap. |
| `done_criteria.phase_complete_min` | int | The phase number that, once `phase_complete` fires, signals the job is done. |
| `done_criteria.browser_test_required` | bool | If `true`, the orchestrator requires a screenshot under `evidence_dir/phase-<N>-*.png` before flipping `done = true`. |
| `done_criteria.evidence_dir` | repo-relative path | Where browser-test artifacts live. Default `docs/e2e-testing`. |

Optional fields:

| Field | Purpose |
|---|---|
| `notify_user_email` | If set, the keepalive task (Phase 5) emails this address on stall escalations / `job_complete`. |
| `notify_slack_channel` | If set, the keepalive task posts to this channel on the same events. |

### How `cc-orchestrator` consumes the spec

Each fire (every minute via cron `* * * * *`):

1. **Step 1 — discover** active jobs by globbing `~/Workspace/*/.cc/active-job.json`
   (max depth 4). If none, exit. This is the only path that costs no quota.
2. **Step 2 — drive** one cycle per active job: read state, read CC buffer,
   decide (approve / deny / revise / advance / escalate / idle), keystroke
   via `keys.sh`, update `orchestrator-heartbeat` + `job-status.json`.
3. **Step 3 — done check** against `done_criteria`. Sets `job-status.done = true`
   on match. The keepalive task (Phase 5) is the only thing allowed to disable
   the orchestrator scheduled task itself.

Full step-by-step contract lives in the bundled
[`assets/scheduled-tasks/cc-orchestrator/SKILL.md`](../../../assets/scheduled-tasks/cc-orchestrator/SKILL.md)
(copied to `~/Documents/Claude/Scheduled/cc-orchestrator/` by `/ccbridge-init`).

### Starting a job

```bash
cp <plugin>/skills/sd-claude-code-access/assets/active-job.example.json \
   <workspace>/.cc/active-job.json
# edit job_id, started_at, plan_path, max_*, done_criteria
```

The next orchestrator fire (within ≤60 seconds) picks it up. No restart needed.

### Stopping a job

Two ways, both immediate:

```bash
rm <workspace>/.cc/active-job.json             # clean stop: orchestrator sees no job, exits Step 1
touch <workspace>/.cc/monitor.stop             # kill switch: orchestrator marks done=true, then exits
```

Use `monitor.stop` when you want the job-status.json to record the explicit stop
(so the keepalive task can fire a `job_aborted` notification). Use the `rm` when
you've already grabbed the keyboard and the orchestrator's heartbeat is just
noise.

### Quota notes (from `research-continuous-cowork-2026-05-12.md`)

- **Pro plan saturates** at sustained 1-minute cadence even with Step 1
  early-exit if multiple jobs run concurrently. The orchestrator's reasoning
  step (per-job, Step 2) is the cost driver — each fire is one Cowork turn.
- **Max 5× is the recommended tier for 24/7** operation. The math: 1440
  fires/day × ~1 turn each = 1440 turns/day; Max 5× absorbs that comfortably
  for a single active job, with headroom for the other three ccbridge tasks
  and the user's interactive sessions.
- **Idle workspaces are free.** Step 1 globs `find ~/Workspace -name
  active-job.json` (no Anthropic API call); when nothing is found, the agent
  writes a one-line `idle` log and exits. The cron tick itself doesn't bill.
- **Multiple active jobs are linear in cost.** If you have three workspaces
  with active jobs, each fire consumes ~3× the per-job reasoning budget. Cap
  the total active jobs to what your subscription can afford to keep healthy.
