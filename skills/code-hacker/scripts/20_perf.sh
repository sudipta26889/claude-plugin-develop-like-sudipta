#!/usr/bin/env bash
# CODE HACKER - PERF Scanner
CATEGORY="PERF" source "$(dirname "$0")/_utils.sh"
# Scan patterns loaded from agents/PERF.md — agent fallback handles deep analysis
echo '{"category":"PERF","severity":"INFO","title":"PERF scan module executed"}'
