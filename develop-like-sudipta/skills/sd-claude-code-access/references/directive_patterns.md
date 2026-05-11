# Directive patterns

How to write `.cc/phase-N.md` files that CC executes well.

## Why file-based, not paste

See `bridge_mechanics.md` and the SKILL.md "Failure modes" section. Short version: long markdown pastes are unreliable and the conversation transcript can lie about what landed. Files are durable, version-controlled, and CC reads them via its own Read tool with no paste mechanics.

## Anatomy of a good directive

```markdown
# Phase N — <one-line title>

## Scope
2-4 sentences explaining why this phase exists. What gap does it close?
What invariant does it preserve? Set the model's frame BEFORE the tasks.

## Tasks (M commits)

### N.1 <Short imperative title>
**Why:** One sentence — the load-bearing reason this task exists.

**Where:** Exact file paths, function names, line numbers if you have them.

**How:**
- Bullet list of the actual changes
- Include code snippets for non-obvious bits
- Name specific patterns ("use `asyncio.gather(..., return_exceptions=True)`")

**Failure modes to plan for:**
- Things that have bitten in similar code
- What to do when each one happens

**Tests:**
- Test names you expect to see
- Edge cases (empty, error path, concurrency)

### N.2 ...

## Acceptance
The gate that has to clear before checkpoint.
- pytest clean (cumulative count: NNN)
- ruff + mypy clean
- (if applicable) integration test against ...

## Commit pattern
- `feat(area): X` — what
- `feat(area): Y` — what
- `chore: Z` — what

## Out-of-scope
What you EXPLICITLY don't want CC to expand into.
```

## Why "why" matters

LLMs follow rules better when they understand the rule. "Use `clock_timestamp()`" is brittle; "Use `clock_timestamp()` because `now()` returns transaction-start time and clumps round-robin assignments under bursts" is robust — the model can apply the principle to similar future cases. Ruthlessly include the reasoning.

## A real worked example

This was Phase 7's directive (multimodal attachments). Note the structure:

```markdown
# Phase 7 — Multimodal attachments

## Scope
Attach Gemini's multimodal capabilities to the triage pipeline so screenshots/
videos/PDFs/logs influence both classification and the eventual Jira draft.

## Pipeline
[ASCII diagram]

## Hard limits (T4 mitigation from pre-mortem)
- 5 attachments processed per report
- 10 MB per file
- Hard budget kill at €60/mo
- Per-day Gemini call cap

## PII scrub
Before persisting `ai_extraction.ocr_text`: run `pii.scrub_pii_text` (extends
`logging.scrub_pii` with phone patterns: Indian +91 / UK / Australian / generic).

## Tests
- 1 attachment, 1 image → process → ai_extraction populated
- 5 attachments → all processed; 6th attachment → skipped with warning
- 11MB file → skipped with warning
- PII scrub: image with "+91 9876543210" in OCR → stored as "[redacted-phone]"

## Commit pattern
- `feat(attachments): Slack file fetch + GCS cache + bot-token auth`
- `feat(attachments): Gemini multimodal extraction with structured JSON output`
- `feat(attachments): PII scrub on OCR'd text + 5/report cap + 10MB filter`
- `feat(cost): budget enforcement with auto-kill-switch at 100%`
```

CC executed all 4 commits cleanly. The hard-limits table flagged invariants by reference to a previous deliverable (the pre-mortem), giving CC a vocabulary that mapped to its own task tracker.

## Bad directive shapes

Things that tend to misfire:

- **"Build the dashboard"** — too vague. CC will sprawl and pull in 20 sub-decisions you didn't make.
- **"Add status field to Report model"** — too narrow. CC will add the column without thinking about the migration, the ORM model, the seed update, the test fixture, the API serializer, the frontend type. Either fully spec the dependents or use a phase-level directive.
- **"Be careful about X"** — without "why" or "how to detect X is happening", a careful directive becomes anxious-but-not-actionable.
- **"Fix all the lint issues"** — open-ended; CC will spend an hour. Better: "Fix the 3 SIM103 violations in `availability.py:60-90`."
- **"Use the same pattern as Phase 5"** — only if the model can read both files. If you're directing via `.cc/phase-N.md` it won't have Phase 5's directive in context. Quote the relevant snippet inline.

## Pre-writing all phase directives

For multi-hour autonomous runs, pre-write `.cc/phase-1.md` through `.cc/phase-N.md` BEFORE you start the run. Benefits:

- Saves Cowork's context — each per-phase trigger is a 1-line message.
- Forces Cowork to think about the whole arc upfront, catching dependency errors earlier.
- Lets CC self-look-ahead; if a phase mentions something deferred to a later phase, CC can choose its own task ordering.

Cost: ~30 min upfront. Pays back in the first two phases.

## Backfill directives

When you realize you forgot something in an earlier phase, don't wait — write `.cc/phase-N.4.md` (where N is the phase that just shipped) with `## Add now` items. Send a tiny trigger:

```
Phase N.4 backfill: read `.cc/phase-N.4.md` and apply the items in `§ Add now`,
commit them as `feat(...): [scope] (Phase N.4 backfill)`, then proceed to
Phase N+1 via `.cc/phase-{N+1}.md`.
```

CC handles backfills well — they're scoped, additive, and have a single clean commit boundary.
