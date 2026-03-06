#!/usr/bin/env bash
# CODE HACKER - CONCUR Scanner
CATEGORY="CONCUR" source "$(dirname "$0")/_utils.sh"
# Scan patterns loaded from agents/CONCUR.md — agent fallback handles deep analysis
echo '{"category":"CONCUR","severity":"INFO","title":"CONCUR scan module executed"}'
