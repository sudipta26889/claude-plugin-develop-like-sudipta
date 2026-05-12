#!/usr/bin/env bash
# BUG-3 regression — launch_cc.sh's resolved CC_LAUNCH_FLAGS must never contain
# a flag that the local `claude` binary doesn't recognize.
#
# Why this test exists:
# v5.0.0 shipped CC_LAUNCH_FLAGS="--continue --chrome --auto" based on a research
# claim that Anthropic's April-2026 GA flag was `--auto`. The flag is bogus on
# claude 2.1.139 — `claude --auto` exits with "error: unknown option '--auto'".
# Every fresh CC spawn since v5.0.0 errored on first attempt; the supposed L1
# reviewer never actually engaged.
#
# Contract this test guards (post-fix in v5.0.2):
#   - launch_cc.sh resolves CC_LAUNCH_FLAGS by probing `claude --help`:
#       * if `--permission-mode` is supported AND `auto` is a listed choice
#         → include `--permission-mode auto` (real L1 form)
#       * else → drop the L1 flag (graceful degradation)
#   - The resolved flags MUST be a subset of `claude --help` output.
#   - The resolved flags MUST NEVER contain a bare `--auto` token.
#
# Mechanics: invoke launch_cc.sh in --dry-run mode against a mktemp workspace,
# capture the "launch flags:" line from stderr, then validate every token
# against `claude --help`. macOS-friendly; no GNU-only commands.
set -uo pipefail

SCRIPT="$(dirname "$0")/../scripts/launch_cc.sh"
test -f "$SCRIPT" || { echo "FAIL: launch_cc.sh missing at $SCRIPT"; exit 1; }

WS=$(mktemp -d)
trap 'rm -rf "$WS"' EXIT

# Run launch_cc in dry-run mode. The flag log goes to stderr regardless of --dry-run;
# we don't care whether spawn happens (the script's poll loop will time out but the
# flag echo at line ~111 fires before any spawn). Capture stderr only.
FLAGS_LINE=$(bash "$SCRIPT" "$WS" --dry-run 2>&1 1>/dev/null | grep '^\[launch_cc\] launch flags:' | head -1)
if [ -z "$FLAGS_LINE" ]; then
  echo "FAIL: could not extract 'launch flags:' line from launch_cc.sh dry-run"
  echo "  full stderr:"
  bash "$SCRIPT" "$WS" --dry-run 2>&1 | head -30 | sed 's/^/    /'
  exit 1
fi

RESOLVED=$(echo "$FLAGS_LINE" | sed -E 's/^\[launch_cc\] launch flags:[[:space:]]*//')
echo "[test] resolved CC_LAUNCH_FLAGS: '$RESOLVED'"

# Negative assertion (the bug): bare --auto must NOT be present in resolved flags.
if echo " $RESOLVED " | grep -qE '[[:space:]]--auto[[:space:]]'; then
  echo "FAIL: BUG-3 regression — bare --auto in resolved CC_LAUNCH_FLAGS"
  echo "       claude 2.1.139+ uses '--permission-mode auto', not bare '--auto'"
  exit 1
fi

# Positive assertion: every --flag in resolved flags must appear in `claude --help`.
# Skip cleanly if claude not on PATH (CI / fresh machine without claude installed).
if ! command -v claude >/dev/null 2>&1; then
  echo "[test] claude not on PATH; skipping flag-validity check"
  echo "       (negative assertion above still enforces BUG-3 contract)"
  echo "PASS"
  exit 0
fi

HELP=$(claude --help 2>&1)
unknown=()
prev=""
for tok in $RESOLVED; do
  case "$prev" in
    --permission-mode|--add-dir|--agent|--agents|--allowedTools|--allowed-tools|--append-system-prompt|--betas|--debug|--debug-file|--disallowedTools|--disallowed-tools|--effort|--fallback-model|--file|--from-pr|--input-format|--json-schema|--max-budget-usd|--mcp-config|--model|-n|--name|--output-format|--plugin-dir|--plugin-url|--system-prompt|--remote-control-session-name-prefix)
      prev="$tok"; continue ;;
  esac
  case "$tok" in
    --*|-*)
      if ! echo "$HELP" | grep -qE "[[:space:]]$tok([[:space:]]|,|$)"; then
        unknown+=("$tok")
      fi
      ;;
  esac
  prev="$tok"
done

if [ ${#unknown[@]} -gt 0 ]; then
  echo "FAIL: launch_cc.sh resolved flags reference unknown claude flags: ${unknown[*]}"
  echo "       claude --version: $(claude --version 2>&1)"
  exit 1
fi

echo "PASS"
