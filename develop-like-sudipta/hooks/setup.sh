#!/usr/bin/env bash
# Setup script for develop-like-sudipta hooks
# Run once: bash ~/.claude/skills/develop-like-sudipta/hooks/setup.sh

set -euo pipefail

HOOKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(dirname "$HOOKS_DIR")"

echo "=== develop-like-sudipta Hook Setup ==="

# 1. Make all hook scripts executable
chmod +x "$HOOKS_DIR"/*.sh
echo "✅ Hook scripts made executable"

# 2. Check if superpowers is installed
if [ -d "$HOME/.claude/plugins" ]; then
  SP_INSTALLED=$(find "$HOME/.claude/plugins" -name "superpowers" -type d 2>/dev/null | head -1)
  if [ -n "$SP_INSTALLED" ]; then
    echo "✅ Superpowers plugin detected at: $SP_INSTALLED"
    echo "   Hooks will complement superpowers (not duplicate)"
  else
    echo "⚠️  Superpowers plugin not found."
    echo "   Install: /plugin marketplace add obra/superpowers-marketplace"
    echo "   Then:    /plugin install superpowers@superpowers-marketplace"
  fi
fi

# 3. Merge hooks into user's settings
SETTINGS_FILE="$HOME/.claude/settings.json"
if [ -f "$SETTINGS_FILE" ]; then
  echo ""
  echo "⚠️  Found existing $SETTINGS_FILE"
  echo "   Manually merge hooks from: $HOOKS_DIR/hooks.json"
  echo "   into your settings.json under the 'hooks' key."
  echo ""
  echo "   Or for project-level: copy hooks.json content to"
  echo "   <project>/.claude/settings.json or settings.local.json"
else
  echo ""
  echo "📋 To activate hooks, add to your Claude Code settings:"
  echo "   Copy $HOOKS_DIR/hooks.json content into:"
  echo "   - Global: ~/.claude/settings.json"
  echo "   - Project: <project>/.claude/settings.json"
  echo "   - Local: <project>/.claude/settings.local.json"
fi

# 4. Check dependencies
echo ""
echo "=== Dependency Check ==="
for cmd in python3 git; do
  if command -v "$cmd" &>/dev/null; then
    echo "✅ $cmd found"
  else
    echo "❌ $cmd NOT found (required)"
  fi
done
for cmd in ruff pytest coverage; do
  if command -v "$cmd" &>/dev/null; then
    echo "✅ $cmd found"
  else
    echo "⚠️  $cmd not found (optional — install for full enforcement)"
  fi
done

echo ""
echo "=== Setup Complete ==="
echo "Skill: $SKILL_DIR/SKILL.md"
echo "Hooks: $HOOKS_DIR/"
echo "Refs:  $SKILL_DIR/references/"
