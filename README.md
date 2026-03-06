# develop-like-sudipta

Claude Code plugin enforcing 11 engineering pillars via skills, agents, hooks, and commands.

## Install

```bash
/plugin marketplace add git@github.com:sudipta26889/claude-plugin-develop-like-sudipta.git
/plugin install develop-like-sudipta
```

## What's Included

| Component | Count | Purpose |
|---|---|---|
| Skill | 1 | Routing hub — tells Claude which agent/command to use when |
| Agents | 6 | Specialized subagents with isolated contexts |
| Commands | 7 | Slash commands for explicit workflow triggers |
| Hooks | 5+1 | Mechanical enforcement scripts |
| References | 11 | Progressive disclosure knowledge base |

### Agents
- `test-writer` — TDD RED phase, never sees implementation
- `implementer` — GREEN phase, takes plan + failing tests
- `code-reviewer` — SOLID/DRY/KISS audit-fix cycles
- `security-reviewer` — OWASP Top 10 focused review
- `dep-researcher` — Package Selection Gate before any install
- `env-sync-checker` — Verifies all config surfaces in sync

### Commands
- `/plan` — Create a development plan from scratch
- `/implement` — Execute existing plan (SKIPS re-planning)
- `/audit` — Run code quality audit-fix cycle
- `/secure` — Run OWASP security review
- `/review` — Full review (quality + security + tests + git)
- `/deploy` — CI/CD pipeline execution
- `/research-deps` — Research packages before installing

### 11 Pillars
Plan First, Code Quality, Env Sync, Security First, Test-Driven, Resilience,
API Design, Git Discipline, Clean Codebase, Latest Deps, CI/CD.

## Architecture

```
Plugin
├── skills/         → SKILL.md routes to agents + references (258 lines)
├── agents/         → 6 isolated-context specialists
├── commands/       → 7 slash commands for workflow control
├── hooks/          → 5 mechanical enforcement scripts
└── references/     → 11 knowledge base files (loaded on-demand)
```

## Author
Sudipta Dhara — [github.com/sudipta26889](https://github.com/sudipta26889)
