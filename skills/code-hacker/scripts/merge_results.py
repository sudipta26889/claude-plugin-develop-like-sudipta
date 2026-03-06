#!/usr/bin/env python3
"""Merge multiple scan result JSON files into one."""
import json, sys
from collections import defaultdict

merged = {"version":"4.0","by_category":{},"by_severity":defaultdict(list),
          "script_results":[],"total_findings":0,
          "summary":{"critical":0,"high":0,"medium":0,"low":0,"info":0}}

for path in sys.argv[1:]:
    try:
        with open(path) as f:
            data = json.load(f)
        for cat, findings in data.get("by_category",{}).items():
            merged["by_category"].setdefault(cat,[]).extend(findings)
        for sr in data.get("script_results",[]):
            merged["script_results"].append(sr)
        for sev in ["critical","high","medium","low","info"]:
            merged["summary"][sev] += data.get("summary",{}).get(sev,0)
        merged["total_findings"] += data.get("total_findings",0)
    except Exception as e:
        print(f"Warning: {path}: {e}", file=sys.stderr)

json.dump(merged, sys.stdout, indent=2, default=str)
