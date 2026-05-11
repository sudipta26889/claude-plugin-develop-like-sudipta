# Danger-pattern governance — how the watchdog deny-list stays honest

The deny-list is the single fall-back that keeps the watchdog from auto-approving a destructive Claude Code action. Every other safeguard (phase plans, verify gates, audit logs) assumes the watchdog won't press Enter on `rm -rf /`. That assumption only holds if `scripts/danger_patterns.txt` is curated, evaluated, and extensible per project.

## Pattern format

The file lives at `scripts/danger_patterns.txt` and is consumed by `scripts/watchdog.sh`. Format rules:

- One **extended regex** (ERE) per line, suitable for `grep -E`.
- Blank lines and lines whose first non-space character is `#` are ignored. Use `#` lines to group patterns by category.
- Patterns are matched with `grep -iE` — **always case-insensitive** at the consumer. Don't try to encode case sensitivity inside the regex; design patterns assuming `-i` is on. (Practical consequence: `git branch -D` and `git branch -d` both match the same rule. That's accepted collateral — the false-positive cost is one human keypress.)
- Patterns are applied to the **visible buffer** (last ~50 lines of the Terminal contents around the CC permission prompt), not just the command. That means the regex can see context like the surrounding "Do you want to proceed?" wording.

Anchors:

- Use `\b...\b` word boundaries (e.g. `\bmkfs\b`) so substrings inside identifiers, paths, or documentation don't fire.
- Use `[[:space:]]+` between tokens that may be separated by tabs or multiple spaces — the buffer is rendered text, not a clean argv array.
- **Do NOT use** `^` / `$` line anchors. The prompt and the command often span lines, and the visible buffer is multi-line. A `^rm` anchor would miss every real-world prompt.

## Evaluation rules — what is a "good" pattern

A pattern is well-formed when it satisfies all three:

1. **Destructive coverage.** It matches at least one fixture in `scripts/audit_danger_patterns.sh::DESTRUCTIVE`.
2. **Routine quiet.** It matches zero fixtures in `scripts/audit_danger_patterns.sh::ROUTINE`.
3. **Documented intent.** A `#` comment above the pattern (or above its category block) names the threat class.

The audit script labels every pattern healthy / loose / dead:

- **Healthy** — covers ≥1 destructive, 0 routine.
- **Loose** — covers ≥1 destructive AND ≥1 routine. A loose pattern annoys the human into disabling the watchdog. Tighten or split it.
- **Dead** — covers 0 destructive. Either the fixture set is missing a case, or the pattern is stale and should be deleted.

## Required process to add a pattern

Adding a pattern without a fixture pair is forbidden — the test goes stale and we have no idea whether the rule still does anything.

1. **Add a destructive fixture** to both `evals/test_danger_patterns.sh::DESTRUCTIVE` and `scripts/audit_danger_patterns.sh::DESTRUCTIVE`. Use a realistic CC-style prompt — what the operator would actually see.
2. **Add a routine counter-example** to both `ROUTINE` arrays. The counter-example should be something a careless regex would catch but a careful one wouldn't (e.g., `rm` inside documentation, `delete` as a noun).
3. **Run `evals/test_danger_patterns.sh`.** It must FAIL with the destructive fixture in the "false negatives" list. If it doesn't fail, your fixture isn't actually destructive — pick a better one.
4. **Write the pattern.** Group it with the relevant `#` category in `scripts/danger_patterns.txt`. Test again — both lists should pass.
5. **Run `scripts/audit_danger_patterns.sh`.** Confirm the new pattern shows up as `healthy`. If it's `loose`, tighten the regex (more specific tokens, narrower character classes) until routine hits drop to 0.
6. **Commit the patterns file and both scripts in the same change.** A pattern change without a fixture update is an unreviewable diff.

## Per-project extensions — `<workspace>/.cc/danger_patterns_extra.txt`

Some teams have project-specific destructive verbs the global list shouldn't carry (`prodctl nuke`, `dbtool wipe-tenant`, internal aliases). Drop additional patterns into the workspace at:

```
<workspace>/.cc/danger_patterns_extra.txt
```

The watchdog reads this file at every check and unions it with the base list. Format is identical to `danger_patterns.txt` (ERE, one per line, `#` comments). Edits take effect on the next poll — no watchdog restart needed.

Recommendations:

- Keep the per-project file under version control (commit it inside `.cc/`).
- Each pattern needs the same fixture discipline as the base list. Add the destructive example and the routine counter-example to your project's own deny-test if you maintain one, otherwise note them in a comment inside the file.
- If a project pattern starts to be useful generally, promote it to `scripts/danger_patterns.txt` and remove the per-project entry.

The extras path is opt-in: if the file is absent, the watchdog behaves exactly as before.

## Dryrun mode — `WATCHDOG_DRYRUN=1`

Before adopting a new pattern (especially a per-project one), you can run the watchdog in dryrun:

```bash
WATCHDOG_DRYRUN=1 ./start_watchdog.sh
```

In dryrun, when a pattern matches:

1. The watchdog logs `[date] would-deny fp=<X> matched=<pattern> (DRYRUN — not acting)` plus the buffer head, exactly like a real block.
2. It writes a `danger_dryrun` state event so the audit timeline shows the would-have-blocked moments.
3. It then **falls through to the approve branch** and presses Enter as if the pattern hadn't matched.

Dryrun is for vetting new patterns against real CC traffic without locking yourself out. Treat it as an evaluation mode, not a default — production runs should have `WATCHDOG_DRYRUN` unset (or `=0`).

## Quarterly review checklist

The deny-list ages. New CC verbs appear, old commands fall out of use, regex assumptions drift. Run this checklist on the first work-day of each quarter:

1. **Run `evals/test_danger_patterns.sh`.** It MUST pass. If not, fix before anything else.
2. **Run `scripts/audit_danger_patterns.sh`.** Inspect the table:
   - Dead patterns → either add a fixture that justifies them, or delete them.
   - Loose patterns → tighten the regex; if you can't, split into a positive rule + an exemption note.
3. **Diff the destructive fixture list against the last quarter's** (`git log -p -- evals/test_danger_patterns.sh`). Did any new CC capability ship that we haven't covered? Scan `cloud destruction` and `database` categories first — those evolve fastest.
4. **Review per-project extras.** Walk through any workspace `.cc/danger_patterns_extra.txt` files you maintain. Promote anything reusable; delete anything stale.
5. **Replay one week of watchdog logs.** Grep `DANGER fp=` in `$DEST/watchdog.log`. For every block, verify a human did the right follow-up. Patterns that fire often but never lead to a manual reject are candidates for tightening (the human is becoming desensitized).
6. **Replay would-deny events from any dryrun runs.** If a candidate pattern matched only routine traffic during dryrun, don't promote it.
7. **Commit findings** as a small `chore(safety): quarterly danger-pattern review` commit even if nothing changes — that's the audit trail.

## Don't

- **Don't disable the watchdog** because one pattern is loose. Fix the pattern.
- **Don't add a pattern without a fixture.** It will silently become dead the next time someone tweaks the regex.
- **Don't anchor patterns with `^` or `$`.** The buffer is multi-line; you'll get zero matches.
- **Don't catch a destructive *concept* with the global list.** Project-specific verbs go in the per-project extras file. The global list stays universal.
- **Don't leave dryrun on in production.** Dryrun is for evaluating patterns; running in dryrun means the watchdog approves everything.
