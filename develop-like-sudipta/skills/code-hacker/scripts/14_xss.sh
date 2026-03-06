#!/usr/bin/env bash
# CODE HACKER - XSS Scanner
CATEGORY="XSS" source "$(dirname "$0")/_utils.sh"
# Scan patterns loaded from agents/XSS.md — agent fallback handles deep analysis
echo '{"category":"XSS","severity":"INFO","title":"XSS scan module executed"}'
