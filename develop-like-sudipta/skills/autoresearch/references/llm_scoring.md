# LLM-based scoring (opt-in)

Per-skill autoresearch ships two scorers side-by-side:

| Mode | File | Mechanism | Cost | Latency | Determinism |
| --- | --- | --- | --- | --- | --- |
| `wordlap` (default) | `autoresearch/score.sh` | Content-word overlap between query and SKILL.md description (threshold 0.60 in develop-like-sudipta / code-hacker, 0.30 in sd-claude-code-access — see in-file rationale) | $0 | ~1 s for ~50 queries | Fully deterministic |
| `llm` (opt-in) | `autoresearch/score-llm.sh` | Asks Claude Haiku 4.5 for a YES/NO judgment per query, given the SKILL.md `description` | ~$0.01 per 100-query fixture | ~150 ms/query (100 ms throttle + ~50 ms inference) | Cached, but model-bound |

## When to use which

**Use `wordlap` for fast iteration.** Every proposed-vs-current comparison costs 0¢ and runs in under a second, so the hypothesis loop can sustain 50+ experiments per `/autoresearch` invocation without manual approval gates.

**Switch to `llm` for the final hill-climb.** Word-overlap saturates once the description has all the trigger keywords lexically present — but it can't distinguish "audit X for SQL injection" (positive) from "audit my expense report" (negative) if the description happens to use the word "audit" generically. Claude Haiku does. Run wordlap to ~F1 ≥ 0.85, then re-baseline under `llm` and squeeze the remaining points by tightening anti-trigger phrasing.

## Cost estimate

Haiku 4.5 pricing as of 2026-05: ~$1/MTok input, ~$5/MTok output. A typical scoring prompt is ~500 input tokens (description + query + instructions) and ~5 output tokens (just "YES" or "NO"). Per query: 500 * 1e-6 + 5 * 5e-6 ≈ $0.00053. A 50-query fixture costs about $0.026; a 100-query fixture costs about $0.05. Verify with current pricing before running.

**Cost guard.** `score-llm.sh` refuses fixtures with more than 100 entries (exit 3) to prevent accidental $5+ runs when someone points the LLM scorer at a 10k-row eval set by mistake. If you intentionally need to score a larger fixture, use `score.sh` (free), or batch the fixture and run multiple invocations with separate cache files.

## Caching strategy

Each scorer maintains a per-skill `autoresearch/.llm_cache.json` (gitignored). Keys are `sha256(description)[:16] :: <query>`; values are `"YES"` or `"NO"`.

- A repeated run on the **same description** is fully cache-hit → no API calls, no cost, no rate limits.
- Changing the description (the autoresearch loop's whole point) invalidates every cache entry under the old hash but keeps the new ones. Old entries linger until the cache file is hand-pruned — acceptable; they consume KBs.
- Each unique `(description, query)` is judged exactly once per cache lifetime.

To force a fresh judgment after a model change, delete `.llm_cache.json`.

## Selecting the mode

Mode is configured per skill in `<skill-dir>/autoresearch/config.json`:

```json
{ "scorer_mode": "llm" }
```

Default (file missing, or `scorer_mode` unset) is `"wordlap"`. The dispatcher (`skills/autoresearch/scripts/score.sh`) reads this file when invoked by `run_autoresearch.sh` and routes to the right scorer.

You can also bypass the dispatcher and call either scorer directly:

```bash
bash develop-like-sudipta/skills/<skill>/autoresearch/score.sh         # wordlap
ANTHROPIC_API_KEY=sk-... bash develop-like-sudipta/skills/<skill>/autoresearch/score-llm.sh
```

Both emit a single F1 float on the last line of stdout.

## Failure modes

- **No API key** (`ANTHROPIC_API_KEY` unset) → exit 2 with clear stderr message. The autoresearch loop should fall back to wordlap or abort the run.
- **401 from API** (bad key) → exit 2.
- **429 rate-limit** → 5 s backoff, up to 3 retries, then exit 3.
- **5xx server error** → 2 s backoff, up to 3 retries, then exit 4.
- **Malformed response** (no leading YES/NO) → logged to stderr, treated as NO (conservative — prefer false negatives over false positives, since over-eager scorers lock in bad descriptions).

## Out of scope

- Other scoring modes (BLEU, embedding cosine, BERTScore, etc.) — defer until wordlap + llm both saturate.
- Cross-skill scoring (e.g., "this query should pick skill X over skill Y") — current scorers only judge their own skill's description in isolation.
