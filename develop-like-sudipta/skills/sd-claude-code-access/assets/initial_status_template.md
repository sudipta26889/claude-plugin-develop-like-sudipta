# STATUS — <project-name>

**Build state at this writing:** <which phases are complete>. Code is
on the `<branch>` branch (not yet merged to `main` if pending review).
The system is **runnable locally** end-to-end and **awaiting manual
deploy steps** that require human credentials.

## Headline

| Check | Result |
|---|---|
| `pytest` (backend) | <N / N passing> |
| `npm test` (frontend) | <N / N passing> |
| `ruff check .` | <clean / errors> |
| `mypy src` | <clean / errors> |
| `make eval` | <PENDING / passing / failing> |
| `docker build` | <clean / errors> |
| Total commits | <N> on branch <name> |

## Per-phase summary

| # | Phase | Commits | Cumulative tests | Notes |
|---|---|---:|---:|---|
| 0 | <name> | <N> | <T> | <key choices> |
| 1 | ... | ... | ... | ... |

## Plan deviations worth knowing

<Bullet list of intentional deviations from the directives, with
rationale per item.>

## Blockers — items I cannot complete autonomously

<List in deploy-day order. Each item: what it is, why I can't do it,
what the user needs to do.>

## What's runnable RIGHT NOW locally

```bash
git checkout <branch>
make install
make test
make lint
```

## Deploy-day checklist (when you're back)

- [ ] <step>
- [ ] <step>

## Open items deliberately deferred to V2

<Bullet list, with phase reference for each item's origin.>
