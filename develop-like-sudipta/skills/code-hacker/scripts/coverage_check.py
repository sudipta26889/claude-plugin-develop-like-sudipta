#!/usr/bin/env python3
"""
☠️ CODE HACKER — Coverage Checker
Verifies all 22 categories were audited. Reports gaps for agent fallback.
"""
import json
import sys

REQUIRED_CATEGORIES = {
    'RECON', 'INJECTION', 'AUTH', 'AUTHZ', 'SECRETS', 'CRYPTO', 'INPUT',
    'API', 'DESER', 'SUPPLY', 'CONFIG', 'SSRF', 'FILE', 'XSS', 'ARCH',
    'CONCUR', 'LOGGING', 'CONTAINER', 'AI', 'PERF', 'PROTO', 'QUALITY'
}

def check_coverage(results_path: str):
    try:
        with open(results_path) as f:
            data = json.load(f)
    except (FileNotFoundError, json.JSONDecodeError) as e:
        print(f"❌ Cannot read results: {e}")
        print(f"ALL {len(REQUIRED_CATEGORIES)} categories need agent audit")
        return REQUIRED_CATEGORIES

    covered = set()
    by_cat = data.get("by_category", {})
    scripts = data.get("script_results", [])

    # Category is covered only if script ran OK AND produced findings
    for sr in scripts:
        cat = sr.get("category", "")
        if sr.get("status") == "OK" and len(sr.get("findings", [])) > 0:
            covered.add(cat)

    gaps = REQUIRED_CATEGORIES - covered
    errored = []
    for sr in scripts:
        if sr.get("status") in ("ERROR", "TIMEOUT", "EXCEPTION", "MISSING"):
            errored.append(f"  {sr['category']}: {sr['status']} - {sr.get('error', 'unknown')[:80]}")

    # Report
    print(f"\n☠️ CODE HACKER — Coverage Report")
    print(f"{'='*50}")
    print(f"✅ Covered categories: {len(covered)}/{len(REQUIRED_CATEGORIES)}")
    print(f"⚠️  Gap categories:    {len(gaps)}/{len(REQUIRED_CATEGORIES)}")

    if covered:
        print(f"\n✅ COVERED: {', '.join(sorted(covered))}")
    if gaps:
        print(f"\n⚠️  GAPS REQUIRING AGENT FALLBACK AUDIT:")
        for g in sorted(gaps):
            print(f"   → {g} (read agents/{g}.md)")
    if errored:
        print(f"\n❌ SCRIPT ERRORS:")
        for e in errored:
            print(e)

    print(f"\n{'='*50}")
    if gaps:
        print(f"🔴 ACTION: Agent must manually audit {len(gaps)} categories")
        print(f"   Read each agents/CATEGORY.md and execute ALL checks")
    else:
        print(f"🟢 All categories have script findings. Agent should still verify quality.")

    return gaps

if __name__ == "__main__":
    results_path = sys.argv[1] if len(sys.argv) > 1 else "/tmp/hack_results.json"
    gaps = check_coverage(results_path)
    sys.exit(0 if not gaps else 1)
