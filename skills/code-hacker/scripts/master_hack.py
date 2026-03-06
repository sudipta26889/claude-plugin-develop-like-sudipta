#!/usr/bin/env python3
"""
☠️ CODE HACKER — Master Orchestrator
Runs all 22 scan modules in parallel, collects results, outputs JSON.
"""
import json
import os
import subprocess
import sys
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path
from datetime import datetime

SCRIPT_DIR = Path(__file__).parent
CATEGORIES = [
    ("01_recon.sh", "RECON"),
    ("02_injection.sh", "INJECTION"),
    ("03_auth.sh", "AUTH"),
    ("04_authz.sh", "AUTHZ"),
    ("05_secrets.sh", "SECRETS"),
    ("06_crypto.sh", "CRYPTO"),
    ("07_input.sh", "INPUT"),
    ("08_api.sh", "API"),
    ("09_deser.sh", "DESER"),
    ("10_supply.sh", "SUPPLY"),
    ("11_config.sh", "CONFIG"),
    ("12_ssrf.sh", "SSRF"),
    ("13_file.sh", "FILE"),
    ("14_xss.sh", "XSS"),
    ("15_arch.sh", "ARCH"),
    ("16_concur.sh", "CONCUR"),
    ("17_logging.sh", "LOGGING"),
    ("18_container.sh", "CONTAINER"),
    ("19_ai.sh", "AI"),
    ("20_perf.sh", "PERF"),
    ("21_proto.sh", "PROTO"),
    ("22_quality.sh", "QUALITY"),
    ("23_dast_fuzz.sh", "DAST"),
]

def run_script(script_name: str, category: str, target: str, live_url: str = None, timeout: int = 300) -> dict:
    """Run a single scan script and return results."""
    script_path = SCRIPT_DIR / script_name
    if not script_path.exists():
        return {
            "category": category,
            "status": "MISSING",
            "findings": [],
            "error": f"Script {script_name} not found",
            "duration_ms": 0,
        }
    start = time.monotonic()
    try:
        cmd = ["bash", str(script_path), target]
        if live_url:
            cmd.append(live_url)
        
        result = subprocess.run(
            cmd,
            capture_output=True, text=True, timeout=timeout,
            env={**os.environ, "TARGET": target, "LIVE_URL": live_url or "", "CATEGORY": category}
        )
        duration_ms = int((time.monotonic() - start) * 1000)
        findings = []
        for line in result.stdout.strip().split("\n"):
            line = line.strip()
            if not line:
                continue
            try:
                finding = json.loads(line)
                finding.setdefault("category", category)
                findings.append(finding)
            except json.JSONDecodeError:
                if ":" in line and any(sev in line.upper() for sev in
                    ["CRITICAL", "HIGH", "MEDIUM", "LOW", "INFO"]):
                    findings.append({
                        "category": category,
                        "severity": "INFO",
                        "title": line,
                        "raw": True,
                    })
        return {
            "category": category,
            "status": "OK" if result.returncode == 0 else "ERROR",
            "findings": findings,
            "error": result.stderr[:500] if result.returncode != 0 else None,
            "duration_ms": duration_ms,
        }
    except subprocess.TimeoutExpired:
        duration_ms = int((time.monotonic() - start) * 1000)
        return {
            "category": category,
            "status": "TIMEOUT",
            "findings": [],
            "error": f"Script timed out after {timeout}s",
            "duration_ms": duration_ms,
        }
    except Exception as e:
        duration_ms = int((time.monotonic() - start) * 1000)
        return {
            "category": category,
            "status": "EXCEPTION",
            "findings": [],
            "error": str(e)[:500],
            "duration_ms": duration_ms,
        }

def main():
    import argparse
    parser = argparse.ArgumentParser(description="☠️ CODE HACKER — Master Scanner")
    parser.add_argument("target", help="Path to codebase to audit")
    parser.add_argument("--live-url", "-l", help="Live target URL for active DAST fuzzing")
    parser.add_argument("--output", "-o", default="/tmp/hack_results.json", help="Output JSON path")
    parser.add_argument("--parallel", "-p", type=int, default=8, help="Max parallel scripts")
    parser.add_argument("--timeout", "-t", type=int, default=300, help="Per-script timeout (seconds)")
    args = parser.parse_args()

    target = os.path.realpath(args.target)
    if not os.path.exists(target):
        print(f"❌ Target not found: {target}", file=sys.stderr)
        sys.exit(1)

    print(f"☠️ CODE HACKER — Scanning {target}")
    print(f"⚙️ Parallel: {args.parallel} | Timeout: {args.timeout}s | Categories: {len(CATEGORIES)}")

    all_results = []
    start_time = time.monotonic()

    with ThreadPoolExecutor(max_workers=args.parallel) as executor:
        futures = {
            executor.submit(run_script, script, cat, target, args.live_url, args.timeout): cat
            for script, cat in CATEGORIES
        }
        for future in as_completed(futures):
            cat = futures[future]
            result = future.result()
            status_icon = {"OK": "✅", "ERROR": "❌", "TIMEOUT": "⏱️",
                          "MISSING": "⚠️", "EXCEPTION": "💥"}.get(result["status"], "❓")
            count = len(result["findings"])
            print(f"  {status_icon} {cat:12s} — {count} findings ({result['duration_ms']}ms)")
            all_results.append(result)

    total_time = int((time.monotonic() - start_time) * 1000)

    # Build output
    by_category = {}
    by_severity = {"CRITICAL": [], "HIGH": [], "MEDIUM": [], "LOW": [], "INFO": []}
    all_findings = []
    gaps = []

    for r in all_results:
        cat = r["category"]
        by_category[cat] = r["findings"]
        for f in r["findings"]:
            sev = f.get("severity", "INFO").upper()
            by_severity.setdefault(sev, []).append(f)
            all_findings.append(f)
        if r["status"] != "OK" or len(r["findings"]) == 0:
            gaps.append({"category": cat, "reason": r["status"],
                        "error": r.get("error")})

    output = {
        "timestamp": datetime.utcnow().isoformat() + "Z",
        "target": target,
        "total_findings": len(all_findings),
        "total_duration_ms": total_time,
        "summary": {
            "critical": len(by_severity.get("CRITICAL", [])),
            "high": len(by_severity.get("HIGH", [])),
            "medium": len(by_severity.get("MEDIUM", [])),
            "low": len(by_severity.get("LOW", [])),
            "info": len(by_severity.get("INFO", [])),
        },
        "gaps_requiring_agent_audit": gaps,
        "by_category": by_category,
        "by_severity": by_severity,
        "script_results": all_results,
    }

    os.makedirs(os.path.dirname(args.output) or ".", exist_ok=True)
    with open(args.output, "w") as f:
        json.dump(output, f, indent=2, default=str)

    print(f"\n☠️ SCAN COMPLETE in {total_time}ms")
    print(f"📊 Findings: {output['summary']}")
    print(f"⚠️ Gaps requiring agent audit: {len(gaps)}")
    print(f"📄 Results: {args.output}")

if __name__ == "__main__":
    main()
