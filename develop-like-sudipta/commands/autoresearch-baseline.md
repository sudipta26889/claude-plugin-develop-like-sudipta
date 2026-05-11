---
description: Establish or reset the baseline score for an autoresearch-wired skill
argument-hint: <target-skill-name> [--reset]
---

Set the score-to-beat for autoresearch runs on this skill.

## Procedure
1. Verify `<plugin>/skills/<$1>/autoresearch/` has wiring.
2. Run `bash <plugin>/skills/<$1>/autoresearch/score.sh` against the CURRENT target file.
3. Read the emitted score (last line of stdout, parse as float).
4. If `--reset`: archive existing .baselines.json to .baselines.json.bak.<timestamp>, write a fresh `[]`.
5. Append a new baseline entry to .baselines.json:
   ```json
   {"ts": "<ISO-8601>", "target_hash": "<sha256>", "score": <FLOAT>, "accepted": true, "kind": "baseline"}
   ```
6. Report to user: target file, score, where the baseline is recorded.

## Don't
- Don't run any experiments — this command only establishes the score-to-beat.
- Don't reset without --reset (preserves history by default).
