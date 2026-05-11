# Watchdog prompt classification eval

**Files:**
- `watchdog_prompt_evals.json` — 20 hand-labeled rows: 8 should-approve + 7 should-refuse + 5 should-ignore. Each row is a realistic terminal-scrollback excerpt paired with the action the watchdog SHOULD take.
- `test_watchdog_prompts.sh` — scorer. Shells out to actual `grep -qiE` so semantics exactly mirror `watchdog.sh`. Emits `ACCURACY=<float>` on the last line. Exits 0 when accuracy ≥ 0.90.

**Why this exists:** Per the autoresearch SKILL.md, autoresearch refuses skills whose value is subjective. Watchdog regex tuning *looked* subjective — but it isn't. With a fixture of `(scrollback_excerpt, expected_action)` rows, watchdog quality becomes a single number. This eval makes the value objective.

## Running

```bash
bash develop-like-sudipta/skills/sd-claude-code-access/evals/test_watchdog_prompts.sh
# Output:
#   correct=20 total=20
#   ACCURACY=1.0000
#   PASS
```

Last line is parseable: `tail -2 | head -1 | cut -d= -f2` → accuracy float.

## Baseline history

| Version | Accuracy | Notes |
|---|---|---|
| v4.6.0 (before this eval existed) | 0.55 — 0.85 | First measured. Gaps surfaced: numbered-menu form not recognized, "create" verb missing, AWS S3 cloud-deletion patterns missing. |
| v4.7.0 (this eval lands) | **1.0000** | PROMPT_PATTERN extended with verb list (create/write/edit/delete/run) + numbered-menu fallback. danger_patterns.txt gained 5 cloud-deletion regexes (aws/gcloud/azure). |

The starting score is reported here for honesty: when this eval was first run against v4.6.0's patterns, it was 0.85 — 3 of 20 rows failed. The eval *worked*; it identified real gaps, which were then fixed in the same v4.7.0 commit.

## Wiring into autoresearch (future work)

For autoresearch to mutate `scripts/watchdog.sh` against this fixture:

1. Create `autoresearch/watchdog_prompt_classification/` dir
2. Add `program.md`:
   ```
   Goal: maximize ACCURACY from test_watchdog_prompts.sh
   Editable target: scripts/watchdog.sh (just the PROMPT_PATTERN line)
   Metric: bash evals/test_watchdog_prompts.sh | tail -2 | head -1 | cut -d= -f2
   Locked: everything except PROMPT_PATTERN line in scripts/watchdog.sh
   ```
3. Add `target.txt` containing the path to the editable file/line
4. `bash develop-like-sudipta/skills/autoresearch/scripts/run_autoresearch.sh sd-claude-code-access/watchdog_prompt_classification`

Currently the autoresearch sub-loop is wired only for `trigger_evals.json` (SKILL.md description tuning). Adding the watchdog one is a v4.8 task — fixture and scorer are ready.

## Extending

Add new rows to `watchdog_prompt_evals.json` whenever a real-world CC scrollback exposes a watchdog miss or false-positive. The eval grows organically; autoresearch will re-score and adjust.
