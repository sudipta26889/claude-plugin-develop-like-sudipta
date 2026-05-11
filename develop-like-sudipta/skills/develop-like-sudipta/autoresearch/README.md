# Autoresearch for develop-like-sudipta

Opts this skill into Karpathy-style autoresearch (see `skills/autoresearch/SKILL.md`).

## Invocation

```
/autoresearch develop-like-sudipta
```

Or one cycle manually:
```bash
bash skills/autoresearch/scripts/run_autoresearch.sh \
  skills/develop-like-sudipta \
  --single-cycle /tmp/proposed_skill_md.txt
```

## What's being optimized

`SKILL.md`'s `description:` field — Claude's skill-routing magnet. We're maximizing accuracy on a curated mix of dev queries (must match) and non-dev queries (must NOT match).

## Proxy scorer (v4.1)

Lexical term-overlap between query and description. Honest limitations same as sd-claude-code-access — see that skill's autoresearch/README.md for details.

## Future work
- v4.2: replace proxy with real-LLM trigger scoring (call Claude with the description and each query, ask "does this skill apply?", measure agreement with ground truth)
- v4.2: extend eval set to 50+ positives and 50+ negatives (currently 15+10)
- v4.2: cover edge cases — borderline queries that might or might not match
