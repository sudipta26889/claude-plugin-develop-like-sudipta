#!/usr/bin/env bash
# emit_ci_workflow.sh — generate .github/workflows/e2e.yml for a workspace.
#
# Detects:
#   - Package manager: pnpm-lock.yaml → pnpm, yarn.lock → yarn, default npm
#   - Node version: package.json engines.node (digits-only prefix), default 20
#   - Dev URL: env DEV_SERVER_URL > .cc/config.json dev_server_url > http://localhost:5173
#   - Playwright config: docs/e2e-testing/specs/playwright.config.ts → use,
#                        else tests/e2e/playwright.config.ts → use,
#                        else default docs/e2e-testing/specs/playwright.config.ts
#
# Idempotent: writes a `# source-hash:` line as the first line of the file.
# Re-running with the same inputs is a no-op (prints "unchanged").
#
# Usage: emit_ci_workflow.sh <workspace>
#
# Bash 3.2 compatible.

set -euo pipefail

if [ "$#" -lt 1 ]; then
  echo "usage: emit_ci_workflow.sh <workspace>" >&2
  exit 2
fi

WORKSPACE="$1"
if [ ! -d "$WORKSPACE" ]; then
  echo "emit_ci_workflow: workspace not a directory: $WORKSPACE" >&2
  exit 2
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TEMPLATE="$SCRIPT_DIR/../assets/github_actions_e2e_template.yml"
if [ ! -f "$TEMPLATE" ]; then
  echo "emit_ci_workflow: template missing at $TEMPLATE" >&2
  exit 2
fi

# ── Detect package manager ──────────────────────────────────────────────────
PKG_MANAGER="npm"
if [ -f "$WORKSPACE/pnpm-lock.yaml" ]; then
  PKG_MANAGER="pnpm"
elif [ -f "$WORKSPACE/yarn.lock" ]; then
  PKG_MANAGER="yarn"
fi

case "$PKG_MANAGER" in
  npm)  INSTALL_CMD="npm ci || npm install" ;;
  pnpm) INSTALL_CMD="pnpm install --frozen-lockfile || pnpm install" ;;
  yarn) INSTALL_CMD="yarn install --frozen-lockfile || yarn install" ;;
esac

DEV_SERVER_START_CMD="$PKG_MANAGER run dev"

# ── Detect Node version ─────────────────────────────────────────────────────
# Reads package.json engines.node. Strips leading non-digits (^, ~, >=) and
# takes only the major-version digits. Falls back to 20.
NODE_VERSION="20"
PKG_JSON="$WORKSPACE/package.json"
if [ -f "$PKG_JSON" ]; then
  # Grab the line containing "node" inside an engines block. Simple grep —
  # avoids a JSON parser dep. False positives are tolerable because the
  # regex below only keeps the major-version digits.
  node_line=$(grep -E '"node"[[:space:]]*:' "$PKG_JSON" 2>/dev/null | head -n 1 || true)
  if [ -n "$node_line" ]; then
    # Extract the quoted value: "node": "18.19.0"  →  18.19.0
    raw=$(printf '%s' "$node_line" | sed -E 's/.*"node"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/')
    # Strip range prefixes, keep leading digits.
    major=$(printf '%s' "$raw" | sed -E 's/^[^0-9]*([0-9]+).*/\1/')
    if [ -n "$major" ] && printf '%s' "$major" | grep -qE '^[0-9]+$' ; then
      NODE_VERSION="$major"
    fi
  fi
fi

# ── Detect dev URL ──────────────────────────────────────────────────────────
DEV_SERVER_URL="${DEV_SERVER_URL:-}"
if [ -z "$DEV_SERVER_URL" ] && [ -f "$WORKSPACE/.cc/config.json" ]; then
  url_line=$(grep -E '"dev_server_url"[[:space:]]*:' "$WORKSPACE/.cc/config.json" 2>/dev/null | head -n 1 || true)
  if [ -n "$url_line" ]; then
    DEV_SERVER_URL=$(printf '%s' "$url_line" | sed -E 's/.*"dev_server_url"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/')
  fi
fi
if [ -z "${DEV_SERVER_URL:-}" ]; then
  DEV_SERVER_URL="http://localhost:5173"
fi

# ── Detect Playwright config ────────────────────────────────────────────────
PLAYWRIGHT_CONFIG="docs/e2e-testing/specs/playwright.config.ts"
if [ -f "$WORKSPACE/docs/e2e-testing/specs/playwright.config.ts" ]; then
  PLAYWRIGHT_CONFIG="docs/e2e-testing/specs/playwright.config.ts"
elif [ -f "$WORKSPACE/tests/e2e/playwright.config.ts" ]; then
  PLAYWRIGHT_CONFIG="tests/e2e/playwright.config.ts"
fi

# ── Compute source hash over the inputs that actually shape the output ──────
HASH_INPUT="pkg=$PKG_MANAGER|node=$NODE_VERSION|url=$DEV_SERVER_URL|cfg=$PLAYWRIGHT_CONFIG|start=$DEV_SERVER_START_CMD|install=$INSTALL_CMD"
if command -v shasum >/dev/null 2>&1 ; then
  SOURCE_HASH=$(printf '%s' "$HASH_INPUT" | shasum -a 256 | awk '{print $1}')
elif command -v sha256sum >/dev/null 2>&1 ; then
  SOURCE_HASH=$(printf '%s' "$HASH_INPUT" | sha256sum | awk '{print $1}')
else
  # Last-resort hash — not cryptographic, just stable.
  SOURCE_HASH=$(printf '%s' "$HASH_INPUT" | cksum | awk '{print $1}')
fi

OUT_DIR="$WORKSPACE/.github/workflows"
OUT_FILE="$OUT_DIR/e2e.yml"

# ── Idempotency check ───────────────────────────────────────────────────────
if [ -f "$OUT_FILE" ]; then
  existing=$(head -n 1 "$OUT_FILE" 2>/dev/null || true)
  expected_first_line="# source-hash: $SOURCE_HASH"
  if [ "$existing" = "$expected_first_line" ]; then
    echo "emit_ci_workflow: unchanged ($OUT_FILE, source-hash=$SOURCE_HASH)"
    echo "  pkg_manager:       $PKG_MANAGER"
    echo "  node_version:      $NODE_VERSION"
    echo "  dev_server_url:    $DEV_SERVER_URL"
    echo "  playwright_config: $PLAYWRIGHT_CONFIG"
    exit 0
  fi
fi

mkdir -p "$OUT_DIR"

# ── Substitute placeholders ─────────────────────────────────────────────────
# Use awk for substitution. Sed is brittle here because values can contain
# `|`, `/`, `&`, and other delimiter / replacement metacharacters (e.g.
# `npm ci || npm install`). awk's gsub with literal strings sidesteps that.
tmp_file="${OUT_FILE}.tmp.$$"
SOURCE_HASH_V="$SOURCE_HASH" \
NODE_VERSION_V="$NODE_VERSION" \
PKG_MANAGER_V="$PKG_MANAGER" \
INSTALL_CMD_V="$INSTALL_CMD" \
DEV_SERVER_START_CMD_V="$DEV_SERVER_START_CMD" \
DEV_SERVER_URL_V="$DEV_SERVER_URL" \
PLAYWRIGHT_CONFIG_V="$PLAYWRIGHT_CONFIG" \
awk '
BEGIN {
  src  = ENVIRON["SOURCE_HASH_V"];
  nv   = ENVIRON["NODE_VERSION_V"];
  pm   = ENVIRON["PKG_MANAGER_V"];
  inst = ENVIRON["INSTALL_CMD_V"];
  ds   = ENVIRON["DEV_SERVER_START_CMD_V"];
  url  = ENVIRON["DEV_SERVER_URL_V"];
  pc   = ENVIRON["PLAYWRIGHT_CONFIG_V"];
}
{
  line = $0;
  gsub(/__SOURCE_HASH__/,           src,  line);
  gsub(/__NODE_VERSION__/,          nv,   line);
  gsub(/__PKG_MANAGER__/,           pm,   line);
  gsub(/__INSTALL_CMD__/,           inst, line);
  gsub(/__DEV_SERVER_START_CMD__/,  ds,   line);
  gsub(/__DEV_SERVER_URL__/,        url,  line);
  gsub(/__PLAYWRIGHT_CONFIG__/,     pc,   line);
  print line;
}
' "$TEMPLATE" > "$tmp_file"
mv "$tmp_file" "$OUT_FILE"

echo "emit_ci_workflow: wrote $OUT_FILE"
echo "  pkg_manager:       $PKG_MANAGER"
echo "  node_version:      $NODE_VERSION"
echo "  dev_server_url:    $DEV_SERVER_URL"
echo "  playwright_config: $PLAYWRIGHT_CONFIG"
echo "  source_hash:       $SOURCE_HASH"
exit 0
