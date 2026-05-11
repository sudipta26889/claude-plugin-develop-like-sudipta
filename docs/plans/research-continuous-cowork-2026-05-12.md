# Continuous Cowork-driven Claude Code — research report (2026-05-12)

Source: deep-research subagent dispatched during Phase 3 of v5.0 plan execution. Plugin baseline at the time: v4.8.0 + Phase 1-3 of v5.0 in flight (active-watcher arch landing now).

## TL;DR

1. **No "always-on" Cowork exists by design.** Cowork conversations are turn-based; no background loop. The official long-running pattern is a **desktop scheduled task on a 1-minute cron** that re-spawns a fresh agent each tick, sharing state via files.
2. **For intelligent (non-regex) approval review, two real options:**
   - **CC `--auto` mode** (Anthropic, April 2026 GA) — Sonnet 4.6 classifier reviews every tool call server-side. Replaces `--dangerously-skip-permissions`. No extra subscription cost.
   - **Cowork scheduled task** as active watcher — reads pending state, decides, writes verdict every minute.
3. **Recommended: hybrid.** L1 = CC `--auto` (per-tool-call review), L2 = `cc-orchestrator` scheduled task (`* * * * *`, strategic decisions), L3 = `cc-coordinator-keepalive` (`*/5 * * * *`, watchdog over watchdog).

## What works today (cited)

- **Desktop scheduled tasks** — 1-min cron minimum; full local FS + MCP + plugin access; runs on user's Claude subscription (no API key); fires while Cowork app open + Mac awake; sleep = skipped fires resumed on wake with notification. [support.claude.com/13854387](https://support.claude.com/en/articles/13854387-schedule-recurring-tasks-in-cowork)
- **Cloud Routines** — 1-hour minimum, explicitly NOT for minute-by-minute polling. [code.claude.com/docs/en/web-scheduled-tasks](https://code.claude.com/docs/en/web-scheduled-tasks)
- **Each scheduled-task fire** — spawns a fresh agent inheriting MCP + skills + plugins. Coordinate via shared FS state. Our existing `ccbridge-aggregate-learnings` + `ccbridge-distill-and-propose` already demonstrate this.
- **CC `/loop`** — runs prompts on schedule INSIDE an open CC session. 1-min floor, 50-call ceiling, 7-day TTL, dies when terminal closes. [code.claude.com/docs/en/scheduled-tasks](https://code.claude.com/docs/en/scheduled-tasks)
- **CC background subagents** — `run_in_background`, monitored via `/tasks`, Ctrl-B to background. Persists across `claude --resume`. User-scope memory at `~/.claude/agent-memory/`. [code.claude.com/docs/en/sub-agents](https://code.claude.com/docs/en/sub-agents)
- **Auto mode** — Sonnet 4.6 classifier reviewing every tool call: scope escalation / untrusted infra / prompt injection. Server-side, no extra cost. [anthropic.com/engineering/claude-code-auto-mode](https://www.anthropic.com/engineering/claude-code-auto-mode)
- **Anthropic's long-horizon agent pattern** — write progress to `claude-progress.txt`, let fresh agent on each tick rebuild context from git + the file. We already do this via `<workspace>/.cc/state.json`. [anthropic.com/engineering/effective-harnesses-for-long-running-agents](https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents)

## What doesn't work (hard limits)

| Want | Reality | Workaround |
|---|---|---|
| Cowork keeps thinking between messages | Impossible by design | Re-spawn via scheduled task; share state on disk |
| Sub-minute cadence | 1-min cron floor | None recommended (sleep tricks burn quota) |
| Cloud routine fast monitoring | 1-hour minimum | Desktop scheduled tasks only |
| Task subagents persisting across turns | Single turn only | Use within one fired tick for parallel observe |
| Scheduled task spawning scheduled task | Possible once; no documented recursion cap | Use sparingly |
| Per-fire token cost transparency | Not published | 1440 fires/day on Sonnet 4.6 saturates Pro; Max 5× recommended for 24/7 |
| First-party Cowork push notifications | Not exposed | Call Slack MCP / send_email from scheduled task |

## Recommended architecture

```
┌─────────────────────────────────────────────────────────────────┐
│ L1 — Per-tool-call review (instant, Anthropic-hosted)           │
│ launch_cc.sh: claude --continue --chrome --auto                 │
│   → Sonnet 4.6 classifier blocks dangerous actions per call     │
│   → Replaces the dumb static auto-approver                      │
└─────────────────────────────────────────────────────────────────┘
                              ▲
                              │ writes verdicts to .cc/state.json
                              │
┌─────────────────────────────────────────────────────────────────┐
│ L2 — cc-orchestrator (Cowork scheduled task, * * * * *)         │
│ Each fire (≤30s of work):                                       │
│  1. Exit IMMEDIATELY if .cc/active-job.json absent (quota saver)│
│  2. Read state.json + journal tail                              │
│  3. If phase complete → write next phase directive              │
│  4. If CC stuck >5min on same step → escalate (revise prompt)   │
│  5. If awaiting browser-test → dispatch Chrome-MCP subagent     │
│  6. If anomaly → write .cc/bug-<id>.md + ping CC                │
│  7. Update .cc/orchestrator-heartbeat                           │
│  8. Exit                                                        │
└─────────────────────────────────────────────────────────────────┘
                              ▲
                              │ heartbeat watched by
                              │
┌─────────────────────────────────────────────────────────────────┐
│ L3 — cc-coordinator-keepalive (*/5 * * * *)                     │
│ If heartbeat > 7 min stale: Slack + send_email to user          │
│ If job.done === true: update_scheduled_task enabled=false (both)│
└─────────────────────────────────────────────────────────────────┘
```

### Concrete artifacts

| Task ID | Cron | Purpose |
|---|---|---|
| `cc-orchestrator` | `* * * * *` | Active reasoning watcher — decide/escalate/advance |
| `cc-coordinator-keepalive` | `*/5 * * * *` | Watches the watcher; pings user on stall |

| File | Schema |
|---|---|
| `<workspace>/.cc/active-job.json` | `{job_id, started_at, plan_path, max_duration_hours, max_cycles}` — exists ⇔ job in progress |
| `<workspace>/.cc/job-status.json` | `{phase, verified, blocked_on, last_action, done, done_evidence}` |
| `<workspace>/.cc/orchestrator-heartbeat` | `<ts> <verdict>` one-liner, updated by L2 each fire |
| `develop-like-sudipta/assets/scheduled-tasks/cc-orchestrator/SKILL.md` | bundled, copied by `/ccbridge-init` |
| `develop-like-sudipta/assets/scheduled-tasks/cc-coordinator-keepalive/SKILL.md` | bundled |

### Done condition (mandatory)

`job-status.done === true` AND `<workspace>/.cc/browser-test-evidence/phase-<N>-screenshot.png` exists AND git HEAD has a `test:` commit referencing the phase. Only then orchestrator self-disables.

## Trade-offs and gotchas

- **Mac-awake requirement** — both tasks need Cowork open + Mac awake. `caffeinate -dimsu` while job active. Sleep = skipped fires resume on wake but real-time response lost.
- **Quota burn** — 1440 fires/day × ~5-10k tokens/fire on Sonnet 4.6 saturates Pro. Recommend **Max 5×** for sustained 24/7. Keep per-fire prompts <2k tokens via file references.
- **`--auto` is not a substitute for business-logic review** — it catches dangerous actions, not wrong code. Orchestrator still needed for strategic decisions.
- **State-file races** — orchestrator + CC both write `.cc/`. Use existing `lock.sh` or atomic `mv` writes.
- **Slack/email uses your identity** — gate behind `.cc/config.json` → `notify_user_email`.
- **Self-disable on done is critical** — otherwise tasks fire forever, burning quota.
- **No verified scheduled-task recursion chains** beyond 1 generation.

## Open questions (would need empirical testing)

1. Per-fire token budget under Pro/Max — Anthropic doesn't publish per-fire cost.
2. Concurrent scheduled-task fires (1-min + 5-min aligning on same minute).
3. Can scheduled task observe `/tasks` background-subagent state from a different CC session?
4. Auto-mode behavior under `claude --continue` reattach.
5. Sub-minute via internal sleeps (`act; sleep 20; act` × 3 per fire) — allowed? quota-amplifying?

## Sources

- support.claude.com/en/articles/13854387-schedule-recurring-tasks-in-cowork
- code.claude.com/docs/en/scheduled-tasks
- code.claude.com/docs/en/web-scheduled-tasks
- anthropic.com/engineering/claude-code-auto-mode
- claude.com/blog/auto-mode
- anthropic.com/engineering/effective-harnesses-for-long-running-agents
- code.claude.com/docs/en/sub-agents
- code.claude.com/docs/en/agent-teams
- anthropic.com/research/long-running-Claude
- support.claude.com/en/articles/12429409-manage-extra-usage-for-paid-claude-plans
- github.com/anthropics/claude-code#issues/6854 (non-blocking task notifications)
- github.com/anthropics/claude-code#issues/9905 (background agent async)
