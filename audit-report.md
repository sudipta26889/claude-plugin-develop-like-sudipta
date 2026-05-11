# 💀 CODE HACKER — Red Team Audit Report
## Plugin: `develop-like-sudipta` v2.0.0

**Audit Date:** 2026-03-06
**Target:** 90 files, 492K total
**Auditor:** Claude Code Hacker (23-category automated + agent fallback)
**Methodology:** Script scan → Coverage verification → Agent fallback → Semantic audit

---

## Executive Summary

| Severity | Count |
|----------|-------|
| 💣 CRITICAL | 6 |
| 🔴 HIGH | 14 |
| 🟠 MEDIUM | 18 |
| 🟡 LOW | 8 |
| 🔵 INFO | 4 |
| **TOTAL** | **50** |

**Verdict:** The plugin is architecturally sound with strong separation of concerns and comprehensive OWASP alignment. However, it has **shell injection vulnerabilities in hooks**, **missing input validation in Python scripts**, **JSON encoding flaws**, and **hardcoded non-portable paths** that must be fixed before production use.

**Risk Level:** 🟠 MEDIUM (→ LOW after fixing CRITICAL/HIGH items)
**Estimated Remediation:** 2-3 weeks

---

## 💣 CRITICAL Findings (6)

### C1. JSON Injection via Unsafe Fallback Encoding
**Files:** `hooks/completion-gate.sh`, `hooks/post-edit-check.sh`
**Issue:** The fallback `echo "\"$WARNINGS\""` does NOT escape JSON. If `$WARNINGS` contains quotes/newlines, JSON is malformed and injectable.
**Fix:** Remove the fallback — always require Python JSON encoding or fail hard.

### C2. Hardcoded Non-Portable Paths in hooks.json
**File:** `hooks/hooks.json` (lines 9, 20, 30, 40)
**Issue:** All hooks reference `~/.claude/skills/develop-like-sudipta/hooks/...`. Tilde may not expand in all execution contexts. If skill installs elsewhere, hooks fail silently.
**Fix:** Use environment variables or relative paths from `$SKILL_DIR`.

### C3. No Input Validation on master_hack.py CLI Args
**File:** `skills/code-hacker/scripts/master_hack.py` (lines 43-50)
**Issue:** `--live-url` accepts any string (SSRF risk to internal services), `--parallel` unbounded (resource exhaustion), `--timeout` can be negative. Target can be symlink to `/`.
**Fix:** Validate URL scheme/host, bound parallel to 1-64, bound timeout to 10-3600, reject symlinks.

### C4. Unsafe Shell→Python Variable Interpolation
**File:** `skills/code-hacker/scripts/_utils.sh` (lines 12-13, 20-27)
**Issue:** `${CATEGORY}` and `${severity}` injected directly into Python heredoc strings. A category like `'; import os; os.system('rm -rf /')` breaks out.
**Fix:** Pass values via `sys.argv` or `os.environ`, never string interpolation into Python code.

### C5. Unvalidated Context Isolation for test-writer Agent
**File:** `agents/test-writer.md`
**Issue:** Claims "NEVER sees implementation code" but this is honor-system only — no enforcement mechanism prevents callers from including implementation context.
**Fix:** Add system-level file-access restrictions or structured input schema that explicitly excludes implementation files.

### C6. Single Point of Failure in Audit Workflow
**File:** `skills/code-hacker/SKILL.md`
**Issue:** If `master_hack.py` fails AND individual scripts also fail, there's no structured tool to identify what was missed. The agent could declare audit complete without actually checking all categories.
**Fix:** Add a mandatory pre-completion checklist with explicit verification steps.

---

## 🔴 HIGH Findings (14)

| ID | File | Issue |
|----|------|-------|
| H1 | hooks/completion-gate.sh:33 | `$GIT_ROOT` unquoted in Python string — shell injection risk |
| H2 | hooks/state-saver.sh:10 | No error check on `mkdir -p` — silent failure if permissions denied |
| H3 | hooks/post-edit-check.sh:31 | `grep -P` flag not portable (fails on macOS default grep) |
| H4 | hooks/tdd-gate.sh:44,53 | `git rev-parse` called multiple times in loop — race condition |
| H5 | _utils.sh:30-40 | `TARGET` used in rg without validation — potential glob expansion |
| H6 | _utils.sh:30-45 | Silent error suppression via `|| true` masks scan failures |
| H7 | master_hack.py:67-70 | Non-atomic file writes — crash mid-write = corrupted JSON |
| H8 | master_hack.py:50-65 | Weak JSON schema validation — malformed lines accepted as findings |
| H9 | coverage_check.py:20-28 | "Zero findings" confused with "successfully audited" — false negatives |
| H10 | All Python scripts | No structured logging — print statements only, no timestamps |
| H11 | agents/implementer.md | No explicit error path when prerequisites missing (tests, plans) |
| H12 | commands/hack.md | Skill path referenced without checksum/integrity verification |
| H13 | cicd-deployment.md | CI/CD template missing secret scanning (Gitleaks/Trivy) |
| H14 | security.md | No key rotation implementation guidance despite mentioning it |

---

## 🟠 MEDIUM Findings (18)

| ID | Category | Issue |
|----|----------|-------|
| M1 | INPUT | Silent JSON parse failures in tdd-gate.sh (no feedback) |
| M2 | DEPS | All hooks call `python3` without checking it exists |
| M3 | QUALITY | Inconsistent error suppression patterns across hooks |
| M4 | QUALITY | Magic strings (categories, severities) duplicated in 3+ files |
| M5 | QUALITY | Inline Python in bash heredocs — hard to debug/maintain |
| M6 | ARCH | Inconsistent severity scales: P0-P3 (code-reviewer) vs CVSS (security-reviewer) |
| M7 | ARCH | Audit-fix cycle has no max iteration limit — potential infinite loop |
| M8 | ARCH | No resource limits on code-hacker parallel execution |
| M9 | API | dep-researcher has no rate limiting on web_search calls |
| M10 | CONFIG | OAuth discovery endpoint examples missing HTTPS enforcement note |
| M11 | CONFIG | JWT token lifetime contradictory between security.md and mcp-auth.md |
| M12 | INJECTION | generate_report.py output path not validated (path traversal) |
| M13 | INJECTION | merge_results.py loads arbitrary JSON files without schema validation |
| M14 | CRYPTO | mcp-auth.md: PKCE validation example missing explicit rejection logic |
| M15 | PERF | completion-gate.sh: sequential grep per changed file — slow for large changesets |
| M16 | PERF | master_hack.py: no progress reporting during long scans |
| M17 | OBS | No audit trail/reproducibility metadata in scan results |
| M18 | DOCS | Missing CORS, webhook signature, password reset security patterns |

---

## 🟡 LOW Findings (8)

| ID | Issue |
|----|-------|
| L1 | setup.sh: Non-symlink-safe path resolution |
| L2 | state-saver.sh: Redundant `&>/dev/null 2>&1` |
| L3 | All agents: "Use PROACTIVELY" undefined — no trigger specification |
| L4 | Multiple agents: Hardcoded model selection without fallback chain |
| L5 | distributed-patterns.md: Feature flag removal lacks verification guidance |
| L6 | performance-db.md: Pool size heuristic doesn't account for async connections |
| L7 | poc_validator.py: subprocess imported but results not properly logged |
| L8 | merge_results.py: Compressed one-liner style reduces auditability |

---

## 🔵 INFO Findings (4)

| ID | Issue |
|----|-------|
| I1 | No .gitignore in plugin root (detected by script scan) |
| I2 | Hook scripts lack input format documentation |
| I3 | Agent reference files not all verified for existence |
| I4 | OAuth 2.1 still draft — should clarify as "OAuth 2.0 + 2.1 enhancements" |

---

## 🔗 Attack Chain Analysis

### Chain 1: Hook Injection → Code Execution
```
hooks.json hardcoded path (C2)
  → attacker replaces skill at ~/.claude/skills/develop-like-sudipta/
  → malicious hook loaded
  → JSON injection via $WARNINGS (C1)
  → arbitrary context injected into Claude session
```
**Impact:** Full session compromise via hook manipulation.

### Chain 2: Audit False Negative → Undetected Vulnerability
```
master_hack.py runs (scripts fail silently — H6)
  → coverage_check treats "zero findings" as "covered" (H9)
  → agent skips manual audit for "covered" categories
  → real vulnerabilities in INJECTION/AUTH go unreported
  → code ships with undetected flaws
```
**Impact:** Security audit produces false confidence.

### Chain 3: SSRF via DAST Fuzzing
```
User runs /hack with --live-url=http://169.254.169.254 (C3)
  → master_hack.py passes URL to DAST scripts unvalidated
  → scripts hit AWS metadata endpoint
  → IAM credentials exposed in scan results
```
**Impact:** Cloud credential theft.

---

## ✅ Strengths

- **Strong separation of concerns** — dedicated agents for testing, implementation, review, security
- **Comprehensive OWASP alignment** — Top 10 + API Security + LLM Top 10 + CWE Top 25
- **Defense-in-depth** — multiple agents check same code
- **TDD enforcement** — hooks gate completion on test existence
- **Structured logging enforcement** — explicit ban on `print()` in implementation
- **Dependency governance** — legacy→modern replacement tables, research-before-install
- **13 reference docs** — covering API design, CI/CD, distributed patterns, resilience, security

---

## 🔧 Remediation Priority

### Immediate (Before Any Use)
1. Fix JSON encoding fallback in hooks (C1)
2. Make hooks.json paths portable (C2)
3. Add input validation to master_hack.py (C3)
4. Fix shell→Python variable interpolation (C4)

### Short-term (Next Release)
5. Add error handling to mkdir, git commands (H2, H4)
6. Log search failures instead of `|| true` (H6)
7. Implement atomic file writes (H7)
8. Fix coverage_check "zero = covered" logic (H9)
9. Unify severity scales across agents (M6)
10. Add Gitleaks to CI/CD template (H13)

### Medium-term (Framework Hardening)
11. Extract shared constants to single source of truth (M4)
12. Add JSON schema validation for findings (H8)
13. Define audit-fix loop termination conditions (M7)
14. Add resource limits to parallel execution (M8)
15. Add scan metadata for reproducibility (M17)

---

## 💀 Hacker's Verdict

> "The architecture is solid — you've built a disciplined engineering framework with real teeth.
> But the hooks are the soft underbelly. I'd compromise the session through JSON injection in
> completion-gate.sh, or I'd poison the audit itself by exploiting the false-negative bug in
> coverage_check.py. Fix the 6 CRITICALs and this plugin becomes genuinely hard to break."

---

*Report generated by Code Hacker skill — 23 automated scripts + 4 parallel agent audits + semantic analysis*
