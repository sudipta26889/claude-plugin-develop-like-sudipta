# Git Workflow Reference

Detailed guidance for Pillar 8. Read this when setting up Git conventions, branching strategy, commit hooks, or code ownership.

## Conventional Commits — Full Specification

### Format

```
<type>[optional scope]: <description>

[optional body]

[optional footer(s)]
```

### Types

| Type | When | SemVer Impact | Example |
|------|------|---------------|---------|
| `feat` | New feature for user | MINOR | `feat(auth): add OAuth2 Google login` |
| `fix` | Bug fix for user | PATCH | `fix(cart): prevent negative quantities` |
| `docs` | Documentation only | None | `docs(api): add cursor pagination examples` |
| `refactor` | Code change, no behavior change | None | `refactor(user): extract email validation` |
| `test` | Adding/fixing tests | None | `test(auth): add token expiry edge cases` |
| `chore` | Build, tooling, deps | None | `chore(deps): bump fastapi to 0.115.6` |
| `perf` | Performance improvement | PATCH | `perf(search): add composite index for queries` |
| `ci` | CI/CD changes | None | `ci: add Trivy security scanning step` |
| `style` | Formatting, no logic change | None | `style: apply ruff formatting` |
| `build` | Build system changes | None | `build: switch to multi-stage Dockerfile` |

### Breaking Changes

Append `!` after type or add `BREAKING CHANGE:` footer:

```
feat(api)!: change pagination from offset to cursor

BREAKING CHANGE: The `page` and `per_page` query parameters are removed.
Use `cursor` and `limit` instead. See migration guide at /docs/pagination-v2.
```

### Scope Conventions (Project-Specific)

Define scopes matching your project structure:

```
auth, user, workspace, bot, chat, rag, admin, api, db, config, docker, ci
```

### Good vs Bad Commit Messages

```
✅ GOOD
feat(auth): add JWT refresh token rotation
fix(chat): handle empty message body without crashing
refactor(user): extract email validation to shared utility
test(auth): add tests for expired token rejection
chore(deps): update pydantic from 2.9 to 2.10

❌ BAD
fixed stuff                          # No type, vague
update                               # No type, no description
feat: changes                        # Non-descriptive
WIP                                  # Don't commit WIP to main
feat(auth): Add JWT refresh token    # Capital letter (convention: lowercase)
```

## Commit Authorship — No AI Attribution

**Hard rule:** Never add AI tools as commit co-authors or signers.

```
❌ NEVER include these in commits:
Co-authored-by: Claude <claude@anthropic.com>
Co-authored-by: GitHub Copilot <copilot@github.com>
Co-authored-by: Cursor <cursor@cursor.sh>
Signed-off-by: Anthropic Claude
# Or any variation with AI tool/company names

✅ ALL commits authored by:
Sudipta Dhara <sudipta@...>
# AI is a tool like an IDE — you don't credit VS Code in commits
```

**Why:** AI assisted the work but did not author it. The human reviewed, validated, and
takes responsibility for every line. Crediting AI tools pollutes git history, confuses
`git log --author`, and misrepresents authorship in open-source contributions.

## Trunk-Based Development

### Why (DORA Evidence)

Google's DORA research (2014-2024, 39,000+ professionals) shows trunk-based development strongly correlates with:
- Higher deployment frequency
- Lower lead time for changes
- Lower change failure rate
- Faster mean time to recovery

### Branch Lifecycle

```
main ─────────────────────────────────────────────────→
       ↑         ↑          ↑         ↑
       │ feat/   │ fix/     │ feat/   │ fix/
       │ auth    │ cart     │ search  │ typo
       │ (1 day) │ (2 hrs)  │ (2 days)│ (10 min)
       └─────────┘          └─────────┘
       Short-lived branches    Ship directly if trivial
```

### Rules

1. **Branches live <1-2 days.** Longer = higher merge conflict risk.
2. **Feature flags** for incomplete work — merge to main behind a flag, not a long-lived branch.
3. **No release branches** unless regulated industry. Tag releases on main.
4. **Rebase before merge** to maintain linear history when possible.
5. **Delete branch after merge** — no stale branches lingering.

### When to Use GitFlow Instead

Only when ALL of these apply:
- Multiple production versions maintained simultaneously
- Regulated industry requiring release sign-off gates
- Large team (>20 devs) with formal release management
- Scheduled releases (not continuous delivery)

## Pre-Commit Hook Setup

### Python Projects (pre-commit framework)

```yaml
# .pre-commit-config.yaml
repos:
  # Formatting + linting (Ruff replaces black, isort, flake8)
  - repo: https://github.com/astral-sh/ruff-pre-commit
    rev: v0.8.0
    hooks:
      - id: ruff
        args: [--fix]
      - id: ruff-format

  # Type checking
  - repo: https://github.com/pre-commit/mirrors-mypy
    rev: v1.13.0
    hooks:
      - id: mypy
        additional_dependencies: [pydantic, types-redis]

  # Secret detection
  - repo: https://github.com/gitleaks/gitleaks
    rev: v8.21.0
    hooks:
      - id: gitleaks

  # Conventional commits
  - repo: https://github.com/compilerla/conventional-pre-commit
    rev: v3.6.0
    hooks:
      - id: conventional-pre-commit
        stages: [commit-msg]
```

### TypeScript/JavaScript Projects (husky + lint-staged)

```json
// package.json
{
  "scripts": {
    "prepare": "husky"
  },
  "lint-staged": {
    "*.{ts,tsx}": ["eslint --fix", "prettier --write"],
    "*.{json,md,yaml}": ["prettier --write"]
  }
}
```

```bash
# .husky/pre-commit
npx lint-staged

# .husky/commit-msg
npx commitlint --edit "$1"
```

```javascript
// commitlint.config.js
export default {
  extends: ["@commitlint/config-conventional"],
  rules: {
    "scope-enum": [2, "always", ["auth", "ui", "api", "config", "deps"]],
  },
};
```

## Branch Protection Rules

### GitHub Configuration

```yaml
# Required for main branch:
required_pull_request_reviews:
  required_approving_review_count: 1
  dismiss_stale_reviews: true
  require_code_owner_reviews: true

required_status_checks:
  strict: true  # Branch must be up-to-date
  contexts:
    - "lint"
    - "test"
    - "security-scan"
    - "type-check"

restrictions:
  enforce_admins: true  # Even admins can't bypass

allow_force_pushes: false
allow_deletions: false
require_linear_history: true  # No merge commits
```

## CODEOWNERS

```
# .github/CODEOWNERS

# Default — catches everything
* @team-leads

# Backend ownership
/backend/app/api/         @backend-team
/backend/app/services/    @backend-team
/backend/app/models/      @backend-team @db-team

# Frontend ownership
/frontend/src/            @frontend-team

# Infrastructure — requires DevOps review
docker-compose*.yml       @devops-team
Dockerfile*               @devops-team
.github/workflows/        @devops-team

# Security-sensitive — requires security review
/backend/app/core/auth*   @security-team @backend-team
/backend/app/core/config* @backend-team @devops-team

# Docs — anyone can approve
/docs/                    @team-leads
*.md                      @team-leads
```

## Semantic Release Automation

```yaml
# .github/workflows/release.yml
name: Release
on:
  push:
    branches: [main]

jobs:
  release:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0

      - name: Semantic Release
        uses: cycjimmy/semantic-release-action@v4
        with:
          extra_plugins: |
            @semantic-release/changelog
            @semantic-release/git
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```

This auto-generates:
- Version bumps based on commit types (feat → minor, fix → patch, `!` → major)
- CHANGELOG.md entries
- Git tags
- GitHub releases

## PR Size Guidelines

| Size | Lines Changed | Review Strategy |
|------|--------------|-----------------|
| XS | <50 | Quick review, merge fast |
| S | 50-200 | Standard review |
| M | 200-400 | Thorough review (optimal max) |
| L | 400-800 | Consider splitting; require 2 reviewers |
| XL | >800 | Must split into stacked PRs |

**Stacked PRs pattern:** Break large features into sequential, reviewable chunks:
```
PR 1: Add data model + migration (base)
PR 2: Add service layer (stacked on PR 1)
PR 3: Add API endpoints (stacked on PR 2)
PR 4: Add frontend integration (stacked on PR 3)
```

Each PR is independently reviewable and mergeable.
