#!/usr/bin/env bash
# CODE HACKER - SSRF Scanner
CATEGORY="SSRF" source "$(dirname "$0")/_utils.sh"
# Scan patterns loaded from agents/SSRF.md — agent fallback handles deep analysis
echo '{"category":"SSRF","severity":"INFO","title":"SSRF scan module executed"}'
