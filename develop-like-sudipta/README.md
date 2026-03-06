# develop-like-sudipta

Claude Code plugin enforcing 11 engineering pillars via skills, agents, hooks, and commands.
Includes the **code-hacker** red-team security auditor for full pen-test capability.

## Install

```bash
/plugin marketplace add sudipta26889/claude-plugin-develop-like-sudipta
/plugin install develop-like-sudipta
```

## What's Included

| Component | Count | Purpose |
|---|---|---|
| Skills | 2 | `develop-like-sudipta` (routing hub) + `code-hacker` (23-category red-team auditor) |
| Agents | 6 | Specialized subagents with isolated contexts |
| Commands | 8 | Slash commands for explicit workflow triggers |
| Hooks | 5+1 | Mechanical enforcement scripts |
| References | 13 | Progressive disclosure knowledge base (11 + 2 from code-hacker) |

### Agents
- `test-writer` — TDD RED phase, never sees implementation (context isolation)
- `implementer` — GREEN phase, takes plan + failing tests, writes minimum code
- `code-reviewer` — SOLID/DRY/KISS audit-fix cycles + 7-dimension Engineering Verdict
- `security-reviewer` — OWASP Top 10 with CWE/CVSS mapping + exploit chain analysis
- `dep-researcher` — Package Selection Gate before any install
- `env-sync-checker` — Verifies all config surfaces in sync

### Commands
- `/plan` — Create a development plan from scratch
- `/implement` — Execute existing plan (SKIPS re-planning)
- `/audit` — Run code quality audit-fix cycle
- `/secure` — Run OWASP security review (lightweight, per-change)
- `/hack` — Full 23-category red-team pen-test via code-hacker skill
- `/review` — Full review (quality + security + tests + git)
- `/deploy` — CI/CD pipeline execution
- `/research-deps` — Research packages before installing

### 11 Pillars
Plan First, Code Quality, Env Sync, Security First, Test-Driven, Resilience,
API Design, Git Discipline, Clean Codebase, Latest Deps, CI/CD.

## Architecture

```
Plugin
├── skills/
│   ├── develop-like-sudipta/  → Routing hub (260 lines) + 11 reference files
│   └── code-hacker/           → Red-team auditor (23 scripts + 23 agents)
├── agents/                    → 6 isolated-context specialists
├── commands/                  → 8 slash commands for workflow control
└── hooks/                     → 5 mechanical enforcement scripts
```

## Author
Sudipta Dhara — [github.com/sudipta26889](https://github.com/sudipta26889)

## Update

Plugin does NOT auto-update. Pull latest manually:

```bash
/plugin update develop-like-sudipta
```

Restart Claude Code after updating to load new commands, agents, and hooks.
