#!/usr/bin/env bash
# test_emit_ci_workflow.sh — smoke test for scripts/emit_ci_workflow.sh.
#
# Cases:
#   1. npm + default URL
#   2. pnpm + custom URL (.cc/config.json)
#   3. yarn + custom Node (engines.node)
#   4. Idempotency: second run prints "unchanged" and doesn't touch the file
#   5. Custom Playwright config path (tests/e2e/)
#
# Usage: ./test_emit_ci_workflow.sh
# Exit 0 on PASS, non-zero on any failed assertion.
#
# Bash 3.2 compatible.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
EMITTER="$SCRIPT_DIR/../scripts/emit_ci_workflow.sh"

if [ ! -x "$EMITTER" ] && [ ! -f "$EMITTER" ]; then
  echo "FAIL: emitter not found at $EMITTER"
  exit 2
fi

TMP_ROOT="$(mktemp -d 2>/dev/null || mktemp -d -t emit_ci_test)"
trap 'rm -rf "$TMP_ROOT"' EXIT

failures=0
fail_msgs=()

assert_contains() {
  # $1=file $2=substring $3=label
  if ! grep -qF -- "$2" "$1" ; then
    failures=$((failures + 1))
    fail_msgs+=("$3: expected file '$1' to contain '$2'")
    return 1
  fi
  return 0
}

assert_not_contains() {
  if grep -qF -- "$2" "$1" 2>/dev/null ; then
    failures=$((failures + 1))
    fail_msgs+=("$3: file '$1' unexpectedly contained '$2'")
    return 1
  fi
  return 0
}

assert_file_exists() {
  if [ ! -f "$1" ]; then
    failures=$((failures + 1))
    fail_msgs+=("$2: expected file '$1' to exist")
    return 1
  fi
  return 0
}

echo "── emit_ci_workflow smoke test ──"

# ── Case 1: npm + default URL ──────────────────────────────────────────────
WS1="$TMP_ROOT/case1-npm"
mkdir -p "$WS1"
cat > "$WS1/package.json" <<'JSON'
{
  "name": "case1",
  "version": "0.0.0"
}
JSON
mkdir -p "$WS1/docs/e2e-testing/specs"
touch "$WS1/docs/e2e-testing/specs/playwright.config.ts"

out1="$("$EMITTER" "$WS1" 2>&1)"
WF1="$WS1/.github/workflows/e2e.yml"
assert_file_exists "$WF1" "case1"
if [ -f "$WF1" ]; then
  assert_contains "$WF1" "npm ci" "case1-npm-install"
  assert_contains "$WF1" "http://localhost:5173" "case1-default-url"
  assert_contains "$WF1" "chromium" "case1-chromium"
  assert_contains "$WF1" "node-version: '20'" "case1-default-node"
  assert_contains "$WF1" "docs/e2e-testing/specs/playwright.config.ts" "case1-playwright-config"
fi

# ── Case 2: pnpm + custom URL via .cc/config.json ──────────────────────────
WS2="$TMP_ROOT/case2-pnpm"
mkdir -p "$WS2/.cc"
cat > "$WS2/package.json" <<'JSON'
{
  "name": "case2",
  "version": "0.0.0"
}
JSON
touch "$WS2/pnpm-lock.yaml"
cat > "$WS2/.cc/config.json" <<'JSON'
{
  "dev_server_url": "http://localhost:4321"
}
JSON
mkdir -p "$WS2/docs/e2e-testing/specs"
touch "$WS2/docs/e2e-testing/specs/playwright.config.ts"

out2="$("$EMITTER" "$WS2" 2>&1)"
WF2="$WS2/.github/workflows/e2e.yml"
assert_file_exists "$WF2" "case2"
if [ -f "$WF2" ]; then
  assert_contains "$WF2" "pnpm" "case2-pnpm-pkg-manager"
  assert_contains "$WF2" "http://localhost:4321" "case2-custom-url"
  assert_not_contains "$WF2" "http://localhost:5173" "case2-no-default-url"
fi

# ── Case 3: yarn + custom Node engine ──────────────────────────────────────
WS3="$TMP_ROOT/case3-yarn"
mkdir -p "$WS3"
cat > "$WS3/package.json" <<'JSON'
{
  "name": "case3",
  "version": "0.0.0",
  "engines": {
    "node": "18"
  }
}
JSON
touch "$WS3/yarn.lock"
mkdir -p "$WS3/docs/e2e-testing/specs"
touch "$WS3/docs/e2e-testing/specs/playwright.config.ts"

out3="$("$EMITTER" "$WS3" 2>&1)"
WF3="$WS3/.github/workflows/e2e.yml"
assert_file_exists "$WF3" "case3"
if [ -f "$WF3" ]; then
  assert_contains "$WF3" "yarn" "case3-yarn-pkg-manager"
  assert_contains "$WF3" "node-version: '18'" "case3-node-18"
fi

# ── Case 4: idempotency ────────────────────────────────────────────────────
WS4="$TMP_ROOT/case4-idem"
mkdir -p "$WS4"
cat > "$WS4/package.json" <<'JSON'
{
  "name": "case4",
  "version": "0.0.0"
}
JSON
mkdir -p "$WS4/docs/e2e-testing/specs"
touch "$WS4/docs/e2e-testing/specs/playwright.config.ts"

"$EMITTER" "$WS4" >/dev/null 2>&1
WF4="$WS4/.github/workflows/e2e.yml"
assert_file_exists "$WF4" "case4-first"

# Capture mtime + content hash after first emit.
mtime_before=$(stat -f '%m' "$WF4" 2>/dev/null || stat -c '%Y' "$WF4" 2>/dev/null)
hash_before=$(shasum -a 256 "$WF4" 2>/dev/null | awk '{print $1}')

# Sleep 1s so a real rewrite would change mtime even on coarse filesystems.
sleep 1

out4="$("$EMITTER" "$WS4" 2>&1)"
mtime_after=$(stat -f '%m' "$WF4" 2>/dev/null || stat -c '%Y' "$WF4" 2>/dev/null)
hash_after=$(shasum -a 256 "$WF4" 2>/dev/null | awk '{print $1}')

if [ "$hash_before" != "$hash_after" ]; then
  failures=$((failures + 1))
  fail_msgs+=("case4-content: content hash changed across idempotent runs ($hash_before -> $hash_after)")
fi
if [ "$mtime_before" != "$mtime_after" ]; then
  failures=$((failures + 1))
  fail_msgs+=("case4-mtime: file mtime changed ($mtime_before -> $mtime_after) — second run wrote unnecessarily")
fi
case "$out4" in
  *unchanged*) : ;;
  *)
    failures=$((failures + 1))
    fail_msgs+=("case4-msg: expected 'unchanged' in second run output, got: $out4")
    ;;
esac

# ── Case 5: custom Playwright config path (tests/e2e) ──────────────────────
WS5="$TMP_ROOT/case5-customcfg"
mkdir -p "$WS5/tests/e2e"
cat > "$WS5/package.json" <<'JSON'
{
  "name": "case5",
  "version": "0.0.0"
}
JSON
touch "$WS5/tests/e2e/playwright.config.ts"
# Deliberately no docs/e2e-testing/ — emitter should fall through to tests/e2e.

out5="$("$EMITTER" "$WS5" 2>&1)"
WF5="$WS5/.github/workflows/e2e.yml"
assert_file_exists "$WF5" "case5"
if [ -f "$WF5" ]; then
  assert_contains "$WF5" "tests/e2e/playwright.config.ts" "case5-tests-e2e-path"
  assert_not_contains "$WF5" "docs/e2e-testing/specs/playwright.config.ts" "case5-no-default-path"
fi

# ── Report ─────────────────────────────────────────────────────────────────
echo
if [ "$failures" -eq 0 ]; then
  echo "PASS — 5 cases ok"
  exit 0
else
  echo "FAIL — $failures assertion(s):"
  for m in "${fail_msgs[@]}"; do
    echo "  - $m"
  done
  exit 1
fi
