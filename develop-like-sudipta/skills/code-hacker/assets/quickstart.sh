#!/usr/bin/env bash
# CODE HACKER - Quick Start
set -euo pipefail
SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TARGET="${1:-.}"
echo "CODE HACKER - Quick Start"
which rg >/dev/null 2>&1 || { apt-get install -y ripgrep 2>/dev/null || brew install ripgrep 2>/dev/null || true; }
python3 "$SKILL_DIR/scripts/master_hack.py" "$TARGET" --output /tmp/hack_results.json --parallel 8 --timeout 120
python3 "$SKILL_DIR/scripts/coverage_check.py" /tmp/hack_results.json
python3 "$SKILL_DIR/scripts/generate_report.py" /tmp/hack_results.json --output /tmp/hack_report.md
echo "Report: /tmp/hack_report.md"
