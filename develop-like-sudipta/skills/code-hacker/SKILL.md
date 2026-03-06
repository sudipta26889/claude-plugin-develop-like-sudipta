---
name: code-hacker
description: >
  Elite red-team codebase auditor — attacks your codebase like a real hacker and files a
  breach report. USE THIS SKILL whenever anyone says: "audit", "review my code", "security
  scan", "find vulnerabilities", "hack my codebase", "what's wrong with my code", "code review",
  "pentest", "red team", "security check", "find bugs", "break my code", "attack surface".
  Deploys parallel scripts + mandatory agent fallback audits — NOTHING is skipped even if
  scripts fail. Output: structured hacker's findings report with CWE mappings, CVSS scores,
  and exploit chain narratives. ALWAYS use this skill for any codebase review or security request.
---

# ☠️ CODE HACKER — World-Class Ethical Red Team Auditor

> **ETHICAL USE ONLY**: This skill is designed exclusively for auditing codebases owned by
> the operator. It is a defensive tool for finding and fixing vulnerabilities before real
> attackers do. Never use against systems you don't own or have explicit authorization to test.

## REQUIREMENTS
- Python 3.8+
- `ripgrep` (rg) — scripts auto-fallback to grep if missing
- Optional: `pip-audit`, `npm audit`, `safety`, `semgrep` (auto-installed by setup)

---

## ⚡ WHAT MAKES THIS SKILL — THE HACKER'S EDGE

It thinks like a real attacker with *both* code access (white-box) and dynamic live execution (black-box). It doesn't just grep for patterns — it actively fuzzes live endpoints, validates Proof of Concepts (PoC) in a safe sandbox, traces data flows, constructs `<exploit_chain>` narratives, maps every finding to CWE/CVSS, and reasons about business logic that no scanner can catch.

**23 Attack Categories** aligned with:
- OWASP Top 10 (2025)
- OWASP API Security Top 10
- OWASP LLM Top 10
- CWE Top 25 Most Dangerous Software Weaknesses
- MITRE ATT&CK Techniques

---

## 🎯 PRIME DIRECTIVE

**Every single category MUST be audited. No exceptions. No skips.**

Scripts are the primary mechanism — fast, deterministic, parallel. But scripts can fail,
timeout, or miss semantic patterns. That is WHY you — the agent — are the mandatory second layer.

**THE RULE:**
> After scripts run, you verify every category is covered. If any category has zero
> findings OR if any script failed/timed out/errored — you MUST manually audit that
> category yourself using the instructions in `agents/`. The user must NEVER receive
> a report where a category was simply skipped.

**SCRIPTS FAIL → AGENTS COVER. ALWAYS.**

---

## 📋 THE 22 ATTACK CATEGORIES

| # | ID | Category | OWASP Alignment | Script |
|---|-----|----------|-----------------|--------|
| 1 | RECON | Reconnaissance & Attack Surface Mapping | — | 01_recon.sh |
| 2 | INJECTION | SQL/NoSQL/OS/LDAP/Template Injection | A05:2025 | 02_injection.sh |
| 3 | AUTH | Authentication & Session Failures | A07:2025 | 03_auth.sh |
| 4 | AUTHZ | Authorization & Access Control (BOLA/BFLA/IDOR) | A01:2025 | 04_authz.sh |
| 5 | SECRETS | Hardcoded Secrets & Credential Exposure | A02:2025 | 05_secrets.sh |
| 6 | CRYPTO | Cryptographic Failures & Misuse | A04:2025 | 06_crypto.sh |
| 7 | INPUT | Input Validation & Output Encoding | A05:2025 | 07_input.sh |
| 8 | API | API Security (REST/GraphQL/gRPC) | API Top 10 | 08_api.sh |
| 9 | DESER | Insecure Deserialization & Object Injection | A08:2025 | 09_deser.sh |
| 10 | SUPPLY | Supply Chain & Dependency Vulnerabilities | A03:2025 | 10_supply.sh |
| 11 | CONFIG | Security Misconfiguration & Insecure Defaults | A02:2025 | 11_config.sh |
| 12 | SSRF | Server-Side Request Forgery | A10:2021 | 12_ssrf.sh |
| 13 | FILE | File Upload & Path Traversal Attacks | A01:2025 | 13_file.sh |
| 14 | XSS | Cross-Site Scripting & DOM Attacks | A05:2025 | 14_xss.sh |
| 15 | ARCH | Architecture & Insecure Design Flaws | A06:2025 | 15_arch.sh |
| 16 | CONCUR | Race Conditions & Concurrency Flaws | A04:2025 | 16_concur.sh |
| 17 | LOGGING | Security Logging & Alerting Failures | A09:2025 | 17_logging.sh |
| 18 | CONTAINER | Container & Infrastructure Security | Infra Top 10 | 18_container.sh |
| 19 | AI | LLM/AI-Specific Vulnerabilities | LLM Top 10 | 19_ai.sh |
| 20 | PERF | DoS & Resource Exhaustion Attacks | A10:2025 | 20_perf.sh |
| 21 | PROTO | Prototype Pollution, Cache Poisoning, WebSockets | Novel Attacks | 21_proto.sh |
| 22 | QUALITY | Error Handling & Exceptional Conditions | A10:2025 | 22_quality.sh |
| 23 | DAST | Active Dynamic Fuzzing & Payload Injection | Live Targets | 23_dast_fuzz.sh |

---

## EXECUTION PROTOCOL

### PHASE 0 — SETUP & RECONNAISSANCE

```bash
TARGET="${1:-.}"
SKILL_DIR="/path/to/skill"  # Replace with actual skill path
RESULTS_DIR="/tmp/hack_results"
mkdir -p "$RESULTS_DIR"

echo "☠️ CODE HACKER — Initiating Red Team Audit"
echo "🎯 TARGET: $(realpath $TARGET)"
echo "📦 SIZE: $(du -sh $TARGET 2>/dev/null | cut -f1)"
echo "📄 FILES: $(find $TARGET -type f 2>/dev/null | wc -l)"
echo "🔤 LANGUAGES: $(find $TARGET -type f -name '*.py' -o -name '*.go' -o -name '*.js' \
  -o -name '*.ts' -o -name '*.java' -o -name '*.php' -o -name '*.rb' -o -name '*.rs' \
  -o -name '*.cs' | sed 's/.*\.//' | sort | uniq -c | sort -rn | head -5)"

# Install tools (non-blocking — scripts degrade gracefully)
which rg >/dev/null 2>&1 || apt-get install -y ripgrep 2>/dev/null || brew install ripgrep 2>/dev/null
pip install pip-audit safety --break-system-packages -q 2>/dev/null
chmod +x "$SKILL_DIR"/scripts/*.sh "$SKILL_DIR"/scripts/*.py 2>/dev/null
```

---

### PHASE 1 — AUTOMATED SCAN (ALL 23 SCRIPTS IN PARALLEL)

```bash
# If a live target is specified, DAST is actively triggered alongside SAST
python3 "$SKILL_DIR/scripts/master_hack.py" "$TARGET" \
  [--live-url "https://target-app.local"] \
  --output "$RESULTS_DIR/scan_results.json" \
  --parallel 8 \
  --timeout 300
```

If master fails, run each module manually:
```bash
for script in "$SKILL_DIR"/scripts/[0-2][0-9]_*.sh; do
    timeout 120 bash "$script" "$TARGET" 2>>"$RESULTS_DIR/errors.log"
done > "$RESULTS_DIR/scan_raw.json"
```

---

### PHASE 2 — COVERAGE VERIFICATION ← MANDATORY

```bash
python3 "$SKILL_DIR/scripts/coverage_check.py" "$RESULTS_DIR/scan_results.json"
```

**Manual fallback check:**
```python
required = {
    'RECON','INJECTION','AUTH','AUTHZ','SECRETS','CRYPTO','INPUT','API',
    'DESER','SUPPLY','CONFIG','SSRF','FILE','XSS','ARCH','CONCUR',
    'LOGGING','CONTAINER','AI','PERF','PROTO','QUALITY','DAST'
}
# Check which categories are missing or have zero findings
```

Also check script error log:
```bash
grep -iE "error|timeout|failed|killed|traceback" "$RESULTS_DIR/errors.log" | head -30
```

Any script that errored/timed out = its category is a gap even if some findings exist.

---

### PHASE 3 — AGENT FALLBACK AUDIT ← MANDATORY FOR ALL GAPS

**For every gap category, read and execute the corresponding agent file COMPLETELY.**

| Gap Category | Agent File | Focus Areas |
|---|---|---|
| RECON | `agents/RECON.md` | Attack surface, entry points, tech stack |
| INJECTION | `agents/INJECTION.md` | SQL/NoSQL/OS/LDAP/SSTI/Expression Language |
| AUTH | `agents/AUTH.md` | Login, session, MFA, password policy, JWT |
| AUTHZ | `agents/AUTHZ.md` | BOLA, BFLA, IDOR, RBAC, privilege escalation |
| SECRETS | `agents/SECRETS.md` | API keys, passwords, tokens, env files, git history |
| CRYPTO | `agents/CRYPTO.md` | Algorithm misuse, key management, KDF, RNG |
| INPUT | `agents/INPUT.md` | Validation, sanitization, encoding, type coercion |
| API | `agents/API.md` | REST/GraphQL/gRPC, mass assignment, rate limiting |
| DESER | `agents/DESER.md` | Pickle, YAML, JSON, XML, PHP object injection |
| SUPPLY | `agents/SUPPLY.md` | CVEs, typosquatting, dependency confusion, lockfiles |
| CONFIG | `agents/CONFIG.md` | Debug mode, CORS, headers, TLS, default creds |
| SSRF | `agents/SSRF.md` | Internal network access, cloud metadata, DNS rebinding |
| FILE | `agents/FILE.md` | Upload bypass, path traversal, symlink attacks |
| XSS | `agents/XSS.md` | Reflected/stored/DOM XSS, CSP bypass, dangerouslySetInnerHTML |
| ARCH | `agents/ARCH.md` | Design flaws, confused deputy, trust boundaries |
| CONCUR | `agents/CONCUR.md` | TOCTOU, distributed races, atomicity failures |
| LOGGING | `agents/LOGGING.md` | Missing audit trail, log injection, sensitive data in logs |
| CONTAINER | `agents/CONTAINER.md` | Dockerfile, K8s manifests, privileged mode, secrets |
| AI | `agents/AI.md` | Prompt injection, model extraction, training data leak |
| PERF | `agents/PERF.md` | ReDoS, algorithmic complexity, resource bombs |
| PROTO | `agents/PROTO.md` | Prototype pollution, cache deception, WebSocket hijacking |
| QUALITY | `agents/QUALITY.md` | Error handling, fail-open, information leakage |
| DAST | `agents/DAST.md` | Active payload injection, fuzzer output verification |

**IMPORTANT: Zero findings from a script ≠ category is clean.**
Zero could mean script missed something. Agent fallback is how you verify.

---

### PHASE 4 — DEEP SEMANTIC ANALYSIS ← ALWAYS REQUIRED

Scripts handle syntax-detectable issues. YOU handle semantic issues.
Read `references/semantic-audit-guide.md` and execute **every** item. Always. No exceptions.

This covers what no scanner can find:
- Business logic flaws (price manipulation, workflow bypass, state machine abuse)
- Second-order injection (stored payloads that trigger later)
- IDOR with complex ownership chains
- Auth logic that LOOKS correct but ISN'T
- Distributed race conditions across services
- Attack chain construction (chaining LOW findings into CRITICAL exploits)

---

### PHASE 5 — LANGUAGE-SPECIFIC DEEP DIVE ← ALWAYS REQUIRED

Read `references/language-patterns.md` for the detected language(s).
Each language has unique vulnerability patterns:
- **Python**: pickle deserialization, eval/exec, format string injection, __import__
- **Go**: goroutine races, defer misuse, unsafe pointer, integer overflow
- **JavaScript/TypeScript**: prototype pollution, ReDoS, type coercion, eval, innerHTML
- **Java**: XML external entity, reflection abuse, JNDI injection, deserialization gadgets
- **PHP**: type juggling, include/require, preg_e modifier, unserialize
- **Ruby**: ERB injection, mass assignment, send/public_send, YAML.load
- **Rust**: unsafe blocks, FFI boundary, integer overflow in release mode
- **C#**: ViewState deserialization, LINQ injection, directory traversal

---

### PHASE 5.5 — FALSE POSITIVE TRIAGE & POC VALIDATION

Use `python3 "$SKILL_DIR/scripts/poc_validator.py" <exploit_script.py>` to safely test any Python PoCs you write against the local environment. Prove the vulnerability is exploitable before claiming critical impact. Discard obvious false positives.

### PHASE 6 — GENERATE REPORT (WITH CoT MANDATE)

> **MANDATORY**: Before generating the final report, you MUST output a `<thinking>` block where you brainstorm `<exploit_chain>` narratives. Ask yourself: "How can I chain finding #3 (IDOR) with finding #12 (SSRF) to achieve critical impact?"

```bash
python3 "$SKILL_DIR/scripts/generate_report.py" \
  "$RESULTS_DIR/scan_results.json" \
  --output report.md \
  --format full
```

Append all agent fallback findings, semantic audit findings, and language-specific findings.

**The final report MUST contain:**
1. Executive Summary (1 paragraph — worst findings, overall risk)
2. Attack Surface Map (entry points, technologies, exposed services)
3. All 23 categories explicitly addressed (even if clean)
4. Each finding with: CWE ID, Severity, File:Line, Description, Exploit Scenario, Fix
5. Attack Chain Narratives (how multiple findings chain into critical exploits)
6. Hacker's Verdict (5-dimension score + overall rating)
7. Prioritized Remediation Roadmap (immediate/short/medium/long term)

---

## LARGE CODEBASE STRATEGY (>50k files)

Partition by module → spawn sub-agents → each runs FULL protocol:
```bash
# Each sub-agent handles a partition:
python3 master_hack.py "$TARGET/auth" --output "$RESULTS_DIR/hack_auth.json"
python3 master_hack.py "$TARGET/api" --output "$RESULTS_DIR/hack_api.json"
# Merge all results:
python3 scripts/merge_results.py "$RESULTS_DIR"/hack_*.json > "$RESULTS_DIR/final.json"
```

For monorepos: identify service boundaries first, audit each service independently,
then audit CROSS-SERVICE trust boundaries separately.

---

## COMPLETION CHECKLIST (Do NOT report until ALL checked)

- [ ] All 23 script modules attempted
- [ ] Coverage check run — all gaps identified
- [ ] Agent fallback completed for EVERY gap category
- [ ] Semantic audit completed (`references/semantic-audit-guide.md`)
- [ ] DAST executed (if `--live-url` provided) and verified via `poc_validator.py`
- [ ] Language-specific audit completed (`references/language-patterns.md`)
- [ ] False positive triage completed manually
- [ ] `<thinking>` and `<exploit_chain>` nodes generated successfully
- [ ] Every finding has CWE mapping
- [ ] Final report explicitly covers all 23 categories
- [ ] Hacker's Verdict and remediation roadmap delivered

---

## SEVERITY SCALE (CVSS-aligned)

| Level | Symbol | CVSS | Meaning | Example |
|-------|--------|------|---------|---------|
| CRITICAL | 💣 | 9.0-10.0 | Exploitable NOW, full system compromise | RCE, auth bypass, admin takeover |
| HIGH | 🔴 | 7.0-8.9 | Serious exploit, realistic attack path | SQLi, SSRF to internal, privilege escalation |
| MEDIUM | 🟠 | 4.0-6.9 | Exploitable with conditions or chaining | Stored XSS, IDOR, weak crypto |
| LOW | 🟡 | 0.1-3.9 | Minor risk, defense-in-depth concern | Missing headers, verbose errors |
| INFO | 🔵 | 0.0 | Observation, best practice suggestion | Code quality, documentation |

---

## FINDING TEMPLATE

```markdown
### [SEVERITY] [CATEGORY] — [Title]

**CWE:** CWE-XXX (Name)
**CVSS:** X.X (Vector String)
**Location:** `path/to/file.py:42`

**Description:** What the vulnerability is and why it matters.

**Vulnerable Code:**
[relevant code snippet]

**Exploit Scenario:**
Step-by-step how an attacker would exploit this.

**Remediation:**
Specific fix with code example.

**References:**
- OWASP link
- CWE link
```

---

## HACKER'S VERDICT — 7 DIMENSIONS (1-5 scale)

1. **Injection Resistance** — Parameterized queries, input validation, output encoding
2. **Auth/AuthZ Strength** — Proper auth, RBAC/ABAC, session management, MFA
3. **Secrets Management** — Env vars, vault integration, no hardcoded credentials
4. **Supply Chain Hygiene** — Dependency management, lockfiles, vulnerability scanning
5. **API Security** — Rate limiting, input validation, proper auth on every endpoint
6. **Code Craftsmanship** — Error handling, logging, test coverage, documentation
7. **Operational Readiness** — Health checks, metrics, graceful shutdown, incident response

**Overall Verdict:**
- 28-35: Fortress — solid security posture (keep monitoring)
- 21-27: Guarded — needs work but not critically dangerous
- 14-20: Exposed — multiple serious vulnerabilities, remediate before production
- 7-13: Breached — critical state, do not expose to internet
- 1-6: Compromised — complete security failure, rebuild with security in mind
