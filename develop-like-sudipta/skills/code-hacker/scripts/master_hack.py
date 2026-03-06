#!/usr/bin/env python3
"""
☠️ CODE HACKER — Master Orchestrator
Runs all 23 scan modules in parallel, collects results, outputs JSON.
"""
import json
import logging
import os
import subprocess
import sys
import tempfile
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime, timezone
from pathlib import Path
from urllib.parse import urlparse

SCRIPT_DIR = Path(__file__).parent
sys.path.insert(0, str(SCRIPT_DIR))
from constants import SCRIPT_MAP as CATEGORIES, SEVERITY_LEVELS, BLOCKED_HOSTS, MAX_PARALLEL, MIN_PARALLEL, MAX_TIMEOUT, MIN_TIMEOUT, MAX_FINDINGS

logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")
logger = logging.getLogger("code-hacker")


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
                # Only accept lines that look like structured findings
                line_stripped = line.strip()
                if line_stripped and not line_stripped.startswith(("#", "//", "[", "=")):
                    logger.warning("Non-JSON output from %s: %s", category, line_stripped[:100])
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

    # --- Input Validation ---
    target = os.path.realpath(args.target)
    if not os.path.exists(target):
        logger.error("Target not found: %s", target)
        sys.exit(1)
    if not os.path.isdir(target):
        logger.error("Target must be a directory: %s", target)
        sys.exit(1)
    if os.path.islink(args.target):
        logger.error("Target cannot be a symlink (resolved to: %s)", target)
        sys.exit(1)

    # Validate --parallel and --timeout bounds
    if not (MIN_PARALLEL <= args.parallel <= MAX_PARALLEL):
        logger.error("--parallel must be %d-%d (got %d)", MIN_PARALLEL, MAX_PARALLEL, args.parallel)
        sys.exit(1)
    if not (MIN_TIMEOUT <= args.timeout <= MAX_TIMEOUT):
        logger.error("--timeout must be %d-%d seconds (got %d)", MIN_TIMEOUT, MAX_TIMEOUT, args.timeout)
        sys.exit(1)

    # Validate --live-url (SSRF prevention)
    live_url = args.live_url
    if live_url:
        try:
            parsed = urlparse(live_url)
            if parsed.scheme not in ("http", "https"):
                logger.error("--live-url must use http/https scheme")
                sys.exit(1)
            if parsed.hostname and parsed.hostname.lower() in BLOCKED_HOSTS:
                logger.error("--live-url points to blocked internal address: %s", parsed.hostname)
                sys.exit(1)
        except Exception as e:
            logger.error("Invalid --live-url: %s", e)
            sys.exit(1)

    logger.info("☠️ CODE HACKER — Scanning %s", target)
    logger.info("⚙️ Parallel: %d | Timeout: %ds | Categories: %d", args.parallel, args.timeout, len(CATEGORIES))

    all_results = []
    start_time = time.monotonic()
    completed = 0
    total = len(CATEGORIES)

    with ThreadPoolExecutor(max_workers=args.parallel) as executor:
        futures = {
            executor.submit(run_script, script, cat, target, args.live_url, args.timeout): cat
            for script, cat in CATEGORIES
        }
        for future in as_completed(futures):
            completed += 1
            cat = futures[future]
            result = future.result()
            status_icon = {"OK": "✅", "ERROR": "❌", "TIMEOUT": "⏱️",
                          "MISSING": "⚠️", "EXCEPTION": "💥"}.get(result["status"], "❓")
            count = len(result["findings"])
            logger.info("  [%d/%d] %s %s — %d findings (%dms)", completed, total, status_icon, cat, count, result['duration_ms'])
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
        "scan_metadata": {
            "python_version": sys.version,
            "platform": sys.platform,
            "arguments": vars(args),
            "script_dir": str(SCRIPT_DIR),
        },
        "timestamp": datetime.now(timezone.utc).isoformat(),
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

    # Atomic write — write to temp file then rename
    out_dir = os.path.dirname(args.output) or "."
    os.makedirs(out_dir, exist_ok=True)
    try:
        fd, tmp_path = tempfile.mkstemp(dir=out_dir, suffix=".json.tmp")
        with os.fdopen(fd, "w") as f:
            json.dump(output, f, indent=2, default=str)
        os.replace(tmp_path, args.output)
    except Exception as e:
        logger.error("Failed to write results: %s", e)
        if os.path.exists(tmp_path):
            os.unlink(tmp_path)
        sys.exit(1)

    logger.info("\n☠️ SCAN COMPLETE in %dms", total_time)
    logger.info("📊 Findings: %s", output['summary'])
    logger.info("⚠️ Gaps requiring agent audit: %d", len(gaps))
    logger.info("📄 Results: %s", args.output)

if __name__ == "__main__":
    main()
