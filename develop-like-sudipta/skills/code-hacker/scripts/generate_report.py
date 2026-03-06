#!/usr/bin/env python3
"""
☠️ CODE HACKER — Report Generator
Generates a structured Markdown breach report from scan results.
"""
import json
import os
import sys
from datetime import datetime
from pathlib import Path
from collections import defaultdict

sys.path.insert(0, str(Path(__file__).parent))
from constants import SEVERITY_LEVELS as SEVERITY_ORDER_TUPLE, SEVERITY_ICONS, CATEGORIES
SEVERITY_ORDER = list(SEVERITY_ORDER_TUPLE)

def generate_report(results_path: str, output_path: str = "report.md"):
    try:
        with open(results_path) as f:
            data = json.load(f)
    except Exception as e:
        print(f"Error loading results: {e}")
        sys.exit(1)

    # Validate output path
    out_dir = os.path.dirname(os.path.abspath(output_path))
    if not os.path.isdir(out_dir):
        print(f"Error: output directory does not exist: {out_dir}", file=sys.stderr)
        sys.exit(1)

    summary = data.get("summary", {})
    by_cat = data.get("by_category", {})
    total = data.get("total_findings", 0)
    target = data.get("target", "unknown")
    duration = data.get("total_duration_ms", 0)
    gaps = [g["category"] for g in data.get("gaps_requiring_agent_audit", [])]

    lines = []
    w = lines.append

    w(f"# ☠️ CODE HACKER — Security Audit Report")
    w(f"")
    w(f"**Target:** `{target}`")
    w(f"**Date:** {datetime.utcnow().strftime('%Y-%m-%d %H:%M UTC')}")
    w(f"**Scan Duration:** {duration}ms")
    w(f"**Total Findings:** {total}")
    w(f"")

    # Executive Summary
    w(f"## Executive Summary")
    w(f"")
    crit = summary.get("critical", 0)
    high = summary.get("high", 0)
    med = summary.get("medium", 0)
    if crit > 0:
        w(f"🚨 **{crit} CRITICAL** vulnerabilities found requiring immediate remediation.")
    if high > 0:
        w(f"🔴 **{high} HIGH** severity issues with realistic exploit paths.")
    if crit == 0 and high == 0:
        w(f"✅ No critical or high severity findings from automated scan.")
    w(f"")
    w(f"| Severity | Count |")
    w(f"|----------|-------|")
    for sev in SEVERITY_ORDER:
        count = summary.get(sev.lower(), 0)
        icon = SEVERITY_ICONS.get(sev, "")
        w(f"| {icon} {sev} | {count} |")
    w(f"")

    if gaps:
        w(f"## ⚠️ Categories Requiring Agent Audit")
        w(f"")
        w(f"The following categories had no script findings or script errors:")
        for g in gaps:
            w(f"- **{g}** — Agent must manually audit using `agents/{g}.md`")
        w(f"")

    # Findings by Category
    w(f"## Findings by Category")
    w(f"")
    for cat in CATEGORIES:
        findings = by_cat.get(cat, [])
        w(f"### {cat}")
        w(f"")
        if not findings:
            if cat in gaps:
                w(f"⚠️ **Pending agent manual audit** — script did not cover this category.")
            else:
                w(f"✅ No issues found by automated scan.")
        else:
            # Sort by severity
            sev_rank = {s: i for i, s in enumerate(SEVERITY_ORDER)}
            findings.sort(key=lambda f: sev_rank.get(f.get("severity", "INFO").upper(), 99))
            for f in findings:
                sev = f.get("severity", "INFO").upper()
                icon = SEVERITY_ICONS.get(sev, "🔵")
                title = f.get("title", "Finding")
                cwe = f.get("cwe", "")
                file_ = f.get("file", "")
                line_ = f.get("line", "")
                desc = f.get("description", "")

                loc = f"`{file_}:{line_}`" if file_ and line_ else (f"`{file_}`" if file_ else "")
                cwe_str = f" ({cwe})" if cwe else ""

                w(f"- {icon} **{sev}**{cwe_str}: {title}")
                if loc:
                    w(f"  - Location: {loc}")
                if desc:
                    w(f"  - {desc}")
        w(f"")

    # Attack Chains placeholder
    w(f"## 🔗 Attack Chain Analysis")
    w(f"")
    w(f"*Agent must construct attack chains by connecting related findings.*")
    w(f"*See `references/semantic-audit-guide.md` Section 9 for methodology.*")
    w(f"")

    # Hacker's Verdict placeholder
    w(f"## ☠️ Hacker's Verdict")
    w(f"")
    w(f"*Agent must score each dimension 1-5 after completing full audit:*")
    w(f"")
    w(f"| Dimension | Score | Notes |")
    w(f"|-----------|-------|-------|")
    for dim in ["Injection Resistance", "Auth/AuthZ Strength", "Secrets Management",
                "Supply Chain Hygiene", "API Security", "Code Craftsmanship",
                "Operational Readiness"]:
        w(f"| {dim} | _/5 | |")
    w(f"| **TOTAL** | **_/35** | |")
    w(f"")

    # Remediation Roadmap
    w(f"## 🗺️ Remediation Roadmap")
    w(f"")
    w(f"### Immediate (0-48 hours)")
    w(f"- Fix all CRITICAL findings")
    w(f"- Rotate any exposed secrets")
    w(f"")
    w(f"### Short-term (1-2 weeks)")
    w(f"- Fix all HIGH findings")
    w(f"- Implement missing auth checks")
    w(f"")
    w(f"### Medium-term (1-3 months)")
    w(f"- Fix MEDIUM findings")
    w(f"- Add security headers, CSP, rate limiting")
    w(f"")
    w(f"### Long-term (3-6 months)")
    w(f"- Address LOW/INFO findings")
    w(f"- Implement security monitoring and alerting")
    w(f"- Regular dependency updates and security scanning")

    report = "\n".join(lines)
    with open(output_path, "w") as f:
        f.write(report)

    print(f"📄 Report generated: {output_path}")
    return report

if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument("results", help="Path to scan results JSON")
    parser.add_argument("--output", "-o", default="report.md")
    parser.add_argument("--format", default="full", choices=["full", "summary"])
    args = parser.parse_args()
    generate_report(args.results, args.output)
