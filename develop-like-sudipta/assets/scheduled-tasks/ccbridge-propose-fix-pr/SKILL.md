---
name: ccbridge-propose-fix-pr
description: Weekly — convert cross-project plugin signatures from the latest distillation priors into draft PRs on the plugin repo (subscription, no ANTHROPIC_API_KEY)
---

Weekly (Mondays 09:00 local — after Sunday's distill): walk the latest cross-project signatures, route each through the dispatch table, spawn a Claude Code (CC) session against the plugin repo clone, drive bug-driven TDD to produce a fix, and open a **draft** PR via `gh pr create --draft`. Maintainer reviews and merges. Never auto-merge.

## Substrate

`mcp__Desktop_Commander__*` only. Subscription Claude — DO NOT call `api.anthropic.com`. Cowork's sandbox bash cannot reach `~/.cache/ccbridge/` or run `gh`, so every shell step goes through Desktop_Commander.

## Pre-conditions

1. `gh auth status` must return 0. If it doesn't → log `gh_unauthenticated` and exit cleanly (don't half-open PRs that lose context).
2. `~/.cache/ccbridge/propose_fix_pr.sh` must be present. If missing → plugin is pre-v4.8 or `install.sh` didn't complete → tell user to run `/ccbridge-init` and exit.
3. `~/.cache/ccbridge/dispatch_signature.sh` must be present (same condition).
4. The latest priors file under `~/.cache/ccbridge/distillation/priors-*.md` must exist and be non-empty. If no priors → log `no_priors_this_week` and exit.

## Dispatch table

Signature prefixes (from `learning.sh`'s event categories) route to plugin files. The canonical mapping lives in `~/.cache/ccbridge/dispatch_signature.sh` and is the single source of truth — never copy it inline into prompts. The table covers:

```
watchdog_*               → develop-like-sudipta/skills/sd-claude-code-access/scripts/watchdog.sh
diagnose_*               → develop-like-sudipta/skills/sd-claude-code-access/scripts/diagnose.sh
send_*                   → develop-like-sudipta/skills/sd-claude-code-access/scripts/send.sh
launch_cc_*              → develop-like-sudipta/skills/sd-claude-code-access/scripts/launch_cc.sh
learning_*               → develop-like-sudipta/skills/sd-claude-code-access/scripts/learning.sh
state_*                  → develop-like-sudipta/skills/sd-claude-code-access/scripts/state.sh
audit_*                  → develop-like-sudipta/skills/sd-claude-code-access/scripts/audit.sh
scheduled_skill_*        → develop-like-sudipta/assets/scheduled-tasks/**/SKILL.md
cc_drive_*               → develop-like-sudipta/commands/cc-drive.md
directive_template_*     → develop-like-sudipta/skills/sd-claude-code-access/assets/directive_template.md
verify_gate_*            → develop-like-sudipta/skills/sd-claude-code-access/references/verify_gate.md
bug_driven_tdd_*         → develop-like-sudipta/skills/sd-claude-code-access/references/bug_driven_tdd.md
substrate_*              → develop-like-sudipta/skills/sd-claude-code-access/references/substrate_and_access.md
# anything else → skip + log "no_dispatch_target"
```

Anything not in the table is skipped (logged `no_dispatch_target`).

## Plugin-repo resolution

Prefer the dev clone at `$HOME/Workspace/personal/claude-plugin-develop-like-sudipta`. If absent, `git clone https://github.com/sudipta26889/claude-plugin-develop-like-sudipta` into a temp dir and use that for the working copy. Never push to `main` — only create draft PRs from a topic branch.

## Procedure

### Step 1 — pre-flight (Desktop_Commander shell)

```bash
gh auth status >/dev/null 2>&1 || { echo "gh_unauthenticated"; exit 0; }
test -x ~/.cache/ccbridge/propose_fix_pr.sh || { echo "missing_bridge_script"; exit 0; }
PRIORS=$(ls -t ~/.cache/ccbridge/distillation/priors-*.md 2>/dev/null | head -n1)
test -n "$PRIORS" && test -s "$PRIORS" || { echo "no_priors_this_week"; exit 0; }
echo "PRIORS=$PRIORS"
```

### Step 2 — dry-run preview (always first)

```bash
DRY_RUN=1 PRIORS_FILE="$PRIORS" bash ~/.cache/ccbridge/propose_fix_pr.sh
```

Read the output to enumerate planned actions: each `WOULD spawn` line names a signature + target file; each `batched_to_issue` line names overflow that goes to a single GitHub issue. If the dry-run finds zero `WOULD spawn` lines → exit (nothing to do).

### Step 3 — for each WOULD-spawn signature (max PR_CAP)

For each line of the form `[dry-run] WOULD spawn CC: signature=<sig> target=<rel-path>`:

1. Resolve `WORKSPACE` = the dev clone path (or temp clone if absent).
2. Create a topic branch:
   ```bash
   cd "$WORKSPACE"
   BR="auto-fix/${sig}-$(date -u +%Y%m%d-%H%M)"
   git checkout -b "$BR"
   ```
3. Write a directive file `$WORKSPACE/.cc/phase-autopr-${sig}.md` containing:
   - The exact priors line(s) that motivated this PR (copy from `$PRIORS`)
   - The dispatch-targeted file path
   - The bug-driven TDD contract: "write a failing eval FIRST in `skills/sd-claude-code-access/evals/`, then min fix in the target file, then four greens before commit"
   - The verify gate list (existing evals that must remain green)
4. Spawn CC via the bridge:
   ```bash
   bash ~/.cache/ccbridge/launch_cc.sh "$WORKSPACE"
   bash ~/.cache/ccbridge/send.sh "$WORKSPACE" "Read .cc/phase-autopr-${sig}.md and proceed per the bug-driven TDD protocol."
   ```
5. Poll for the `auto-fix:` commit landing on the branch (every 2 minutes, give up after 60 minutes). Use `git log --oneline -n 5 "$BR"` and look for the `auto-fix:` prefix.
6. Open a draft PR — body-file mode so no `$EDITOR` is needed:
   ```bash
   BODY=$(mktemp); cat > "$BODY" <<EOF
   ## Auto-fix proposal (from ccbridge-distill priors)

   - Signature: \`${sig}\`
   - Target: \`${target}\`
   - Priors evidence: see \`.cc/phase-autopr-${sig}.md\` in this branch.

   Bug-driven TDD trail:
   - Failing eval written FIRST
   - Min fix applied to target
   - Verify-gate green before commit

   Maintainer: review the failing-test → fix delta, then squash-merge if it looks right. **Do not** force-merge — this is a proposal, not an auto-merge.
   EOF
   gh pr create --draft --title "auto-fix: ${sig}" --body-file "$BODY"
   ```
7. Log to `~/.cache/ccbridge/distillation/.pr_log.jsonl` via `propose_fix_pr.sh` (it does this automatically when invoked WITHOUT `DRY_RUN=1`).

### Step 4 — overflow (over PR_CAP)

Collect every `batched_to_issue` row from the dry-run output into a single GitHub issue body. Open one issue (not N PRs):

```bash
BODY=$(mktemp); cat > "$BODY" <<EOF
## Cross-project signatures over the weekly PR cap

The auto-fix-PR task hit its $PR_CAP/week cap. The following signatures were observed in ≥2 workspaces this week but did NOT get an auto-PR — please pick them up manually or wait for next Monday's cycle.

$BATCH_LINES
EOF
gh issue create --title "auto-fix: $(date -u +%Y-%m-%d) over-cap batch" --body-file "$BODY" --label "auto-fix,batch"
```

### Step 5 — summary

Print one line per action and a final summary:

```
[propose-fix-pr] spawned=2 batched=1 skipped=0 prs_opened=2 issues_opened=1
```

## --dry-run flag

Running this whole SKILL with `DRY_RUN=1` env (set at the Cowork scheduled-task layer) MUST skip every CC spawn, every `gh pr create`, and every `.pr_log.jsonl` write. The dry-run pass in Step 2 is mandatory; Step 3+ is the only place that gets gated by `$DRY_RUN`.

## Don't

- Don't auto-push to plugin `main`. Only draft PRs from `auto-fix/*` topic branches.
- Don't open PRs for signatures whose distill row has `worked=true` — those are CONFIRMATIONS that an earlier fix held, not bugs.
- Don't spawn CC if `gh auth status` returns non-zero — a PR-less workflow leaks effort.
- Don't run on `CROSS_N=1` signatures even with `--force` — single-workspace = quirk, not pattern.
- Don't write tests that require a real GitHub API call. Mock `gh` via `GH_OVERRIDE=mock` env when running the evals.
- Don't exceed `PR_CAP` (default 3) PRs per call — overflow batches to one issue.
- Don't hardcode plugin-relative paths in this SKILL. All bridge calls go through `~/.cache/ccbridge/*.sh` (stable per-machine paths).
