#!/usr/bin/env bash
# v5.0.7 H2 regression — state.sh must emit VALID JSON for hostile values.
#
# The old escaper handled `"` only. Any value containing a backslash (regex
# text, danger patterns, Windows paths — exactly what buffer snippets carry)
# produced invalid escape sequences mid-string and corrupted the JSONL line.
# state_salvage.sh existed largely to clean up after this.
#
# Contract: every emitted line must parse with python json.loads AND
# round-trip the value's meaningful content.
set -uo pipefail
SRC="$(cd "$(dirname "$0")/../scripts" && pwd)"
WS=$(mktemp -d)
trap 'rm -rf "$WS"' EXIT

FAIL=0
emit_and_check() {
  local desc="$1"; shift
  mkdir -p "$WS/.cc"
  : > "$WS/.cc/state.json"
  bash "$SRC/state.sh" "$WS" test_event "$@" || { echo "FAIL $desc: state.sh exited non-zero"; FAIL=1; return; }
  if python3 -c '
import json, sys
with open(sys.argv[1]) as f:
    for ln in f:
        ln = ln.strip()
        if ln: json.loads(ln)
' "$WS/.cc/state.json" 2>/dev/null; then
    echo "PASS $desc"
  else
    echo "FAIL $desc: invalid JSON emitted:"
    sed "s/^/    /" "$WS/.cc/state.json"
    FAIL=1
  fi
}

emit_and_check "plain value"            "k=simple"
emit_and_check "double quotes"          'k=say "hello" twice'
emit_and_check "single backslash"       'k=C:\Users\path'
emit_and_check "regex with backslashes" 'pattern=\brm[[:space:]]+-rf\b'
emit_and_check "backslash before quote" 'k=end with \"escaped\"'
emit_and_check "mixed hostile"          'snippet=grep -qE "\bDROP\b" && rm -rf "$TMP"'
emit_and_check "tab in value"           "k=col1$(printf '\t')col2"

# Round-trip: the regex value must come back with its backslashes intact.
: > "$WS/.cc/state.json"
bash "$SRC/state.sh" "$WS" test_event 'pattern=\brm\b'
RT=$(python3 -c '
import json,sys
print(json.loads(open(sys.argv[1]).read().strip())["pattern"])
' "$WS/.cc/state.json" 2>/dev/null || echo "PARSE_FAIL")
if [ "$RT" = '\brm\b' ]; then
  echo "PASS round-trip: backslashes preserved"
else
  echo "FAIL round-trip: expected '\\brm\\b', got '$RT'"
  FAIL=1
fi

[ "$FAIL" -eq 0 ] && { echo "ALL PASS — state.sh emits valid JSON for hostile values"; exit 0; }
exit 1
