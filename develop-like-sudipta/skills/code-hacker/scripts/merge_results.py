#!/usr/bin/env python3
"""Merge multiple scan result JSON files into one."""
import json
import os
import sys
from collections import defaultdict

REQUIRED_KEYS = {"by_category", "script_results", "summary", "total_findings"}


def merge_results(paths):
    merged = {
        "version": "4.0",
        "by_category": {},
        "by_severity": defaultdict(list),
        "script_results": [],
        "total_findings": 0,
        "summary": {"critical": 0, "high": 0, "medium": 0, "low": 0, "info": 0},
    }

    for path in paths:
        if not os.path.isfile(path):
            print(f"Warning: file not found: {path}", file=sys.stderr)
            continue
        try:
            with open(path) as f:
                data = json.load(f)

            if not isinstance(data, dict):
                print(f"Warning: {path}: expected JSON object, got {type(data).__name__}", file=sys.stderr)
                continue

            for cat, findings in data.get("by_category", {}).items():
                merged["by_category"].setdefault(cat, []).extend(findings)
            for sr in data.get("script_results", []):
                merged["script_results"].append(sr)
            for sev in ("critical", "high", "medium", "low", "info"):
                merged["summary"][sev] += data.get("summary", {}).get(sev, 0)
            merged["total_findings"] += data.get("total_findings", 0)
        except json.JSONDecodeError as e:
            print(f"Warning: {path}: invalid JSON: {e}", file=sys.stderr)
        except Exception as e:
            print(f"Warning: {path}: {e}", file=sys.stderr)

    return merged


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: merge_results.py <results1.json> [results2.json ...]", file=sys.stderr)
        sys.exit(1)
    result = merge_results(sys.argv[1:])
    json.dump(result, sys.stdout, indent=2, default=str)
