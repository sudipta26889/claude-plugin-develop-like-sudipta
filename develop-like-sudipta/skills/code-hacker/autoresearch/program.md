# Autoresearch program for code-hacker

## Goal
Maximize F1 on `autoresearch/trigger_corpus.json` — the description should fire on red-team /
audit / security-scan / vulnerability / pentest prompts but NOT on routine code review or
feature work. The skill is the elite ethical red-team auditor; its description must pull in
attack-surface / breach / OWASP / CWE / CVSS / vulnerability prompts and ignore generic
"review this PR for style" / "refactor" / "add a feature" requests (those belong to
develop-like-sudipta or a code-reviewer agent).

## Metric
F1 on `autoresearch/trigger_corpus.json` (positive + negative cases). Higher is better.
Range 0.0 to 1.0.
- Positive cases: should_trigger=true — description should match
- Negative cases: should_trigger=false — description should NOT match
- Match proxy: lexical overlap between query content-words and description content-words
  (>= 0.60 of query content words present in description counts as a "match")
- F1 = 2 * P * R / (P + R)
- Baseline: whatever the current SKILL.md description scores at first invocation.

## Constraints (locked)
- **Editable target:** `SKILL.md` (the YAML frontmatter `description` field ONLY — body
  text is locked even though it lives in the same file)
- **Scoring command:** `bash autoresearch/score.sh` (emits F1 to stdout)
- **Time budget per experiment:** 300 sec
- **Max experiments per run:** 50
- **Locked files:** everything else in the skill dir, in particular:
  - `scripts/*.sh` and `scripts/*.py` (the 23 audit fixtures — must not drift)
  - `agents/*.md` (the per-category security focus areas)
  - `references/*` (semantic-audit-guide, language-patterns)
  - `assets/*`
  - `autoresearch/trigger_corpus.json` (the scoring contract)
  - `autoresearch/score.sh`, `autoresearch/program.md`, `autoresearch/target.txt`

## Hypothesis seeds
1. Add explicit red-team / attack / pentest / breach / exploit trigger phrases.
2. Include CWE / CVE / OWASP / CVSS / MITRE ATT&CK terms (the report-format vocabulary).
3. Differentiate from develop-like-sudipta with explicit "security audit" / "red team"
   framing rather than the generic "code review" surface (which the other skill owns).
4. Add anti-triggers for routine PR review: "NOT for routine code review — use the
   code-reviewer agent instead" / "NOT for refactors or feature work".
5. Surface the 23 attack categories the skill covers (SQLi, SSRF, XSS, IDOR, BOLA, BFLA,
   deserialization, prototype pollution, ReDoS, SSTI, prompt injection, etc.) so the
   description has lexical hooks for category-specific user prompts.
6. Group triggers by user intent: "audit X", "find vulns in X", "red-team X", "pentest X",
   "what's the attack surface of X", "scan for X", "is X exploitable" — each intent class
   needs at least one keyword in the description.

## Out of scope
- Don't change SKILL.md body (only the description field in YAML frontmatter is editable)
- Don't touch `scripts/*.sh` or `scripts/*.py` (the audit fixtures)
- Don't touch `agents/*.md` (the per-category security focus areas)
- Don't touch `references/*` or `assets/*`
- Don't modify `trigger_corpus.json` after baselining (it IS the scoring contract)
- Don't introduce new dependencies
- Don't break SKILL.md YAML frontmatter syntax
- Don't rename the skill
