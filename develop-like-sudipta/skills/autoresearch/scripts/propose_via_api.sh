#!/usr/bin/env bash
# propose_via_api.sh — curl-based proposer (uses ANTHROPIC_API_KEY).
#
# Reads program.md + current target + recent baselines, POSTs a structured
# prompt to https://api.anthropic.com/v1/messages, parses the response, and
# emits the proposed new target content on stdout.
#
# Usage: propose_via_api.sh <skill-dir>
#
# Exit codes:
#   0  success — proposed content emitted to stdout
#   1  generic error (bad args, missing files, parse failure)
#   2  ANTHROPIC_API_KEY missing or 401 auth failure
#   3  429 rate-limit
#   4  5xx server error
#
# Environment:
#   ANTHROPIC_API_KEY      required
#   ANTHROPIC_MODEL        defaults to claude-sonnet-4-6
#   ANTHROPIC_API_URL      defaults to https://api.anthropic.com/v1/messages
#   ANTHROPIC_MAX_TOKENS   defaults to 4096
#
# Bash 3.2 + curl + python3.

set -u
set -o pipefail

SKILL_DIR="${1:-}"
if [ -z "$SKILL_DIR" ]; then
  echo "Usage: propose_via_api.sh <skill-dir>" >&2
  exit 1
fi
[ -d "$SKILL_DIR" ] || { echo "skill-dir not a directory: $SKILL_DIR" >&2; exit 1; }
SKILL_DIR="$(cd "$SKILL_DIR" && pwd)"

if [ -z "${ANTHROPIC_API_KEY:-}" ]; then
  echo "ERROR: ANTHROPIC_API_KEY not set" >&2
  exit 2
fi

AR_DIR="$SKILL_DIR/autoresearch"
PROGRAM_MD="$AR_DIR/program.md"
TARGET_TXT="$AR_DIR/target.txt"
BASELINES="$AR_DIR/.baselines.json"

for required in "$PROGRAM_MD" "$TARGET_TXT"; do
  if [ ! -f "$required" ]; then
    echo "ERROR: missing $required" >&2
    exit 1
  fi
done

TARGET_REL="$(head -1 "$TARGET_TXT" | tr -d '[:space:]')"
[ -n "$TARGET_REL" ] || { echo "ERROR: target.txt is empty" >&2; exit 1; }
TARGET_FILE="$SKILL_DIR/$TARGET_REL"
[ -f "$TARGET_FILE" ] || { echo "ERROR: target file not found: $TARGET_FILE" >&2; exit 1; }

MODEL="${ANTHROPIC_MODEL:-claude-sonnet-4-6}"
API_URL="${ANTHROPIC_API_URL:-https://api.anthropic.com/v1/messages}"
MAX_TOKENS="${ANTHROPIC_MAX_TOKENS:-4096}"

# ---- read inputs ----
PROGRAM_CONTENT="$(cat "$PROGRAM_MD")"
TARGET_CONTENT="$(cat "$TARGET_FILE")"
if [ -f "$BASELINES" ]; then
  HISTORY_CONTENT="$(tail -5 "$BASELINES")"
else
  HISTORY_CONTENT="(no history yet — this is the first proposal)"
fi

# ---- build messages JSON (python3 for safe JSON encoding) ----
REQUEST_BODY="$(
  PROG="$PROGRAM_CONTENT" \
  TARG_REL="$TARGET_REL" \
  TARG="$TARGET_CONTENT" \
  HIST="$HISTORY_CONTENT" \
  MODEL_ENV="$MODEL" \
  MAX_TOK="$MAX_TOKENS" \
  python3 - <<'PY'
import json, os

system = (
    "You are an autoresearch agent. Given a skill's program.md "
    "(goal + constraints), its current editable target, and recent "
    "experiment history, propose the next mutation to the target. "
    "Output ONLY the new content of the target file — no explanation, "
    "no preamble, no markdown fences."
)

user = (
    "## Goal + constraints (program.md)\n\n"
    f"{os.environ['PROG']}\n\n"
    f"## Current target content ({os.environ['TARG_REL']})\n\n"
    "```\n"
    f"{os.environ['TARG']}\n"
    "```\n\n"
    "## Recent experiment history (last 5 baselines)\n\n"
    f"{os.environ['HIST']}\n\n"
    "## Your task\n\n"
    "Propose the next mutation. Output ONLY the full new contents of "
    f"{os.environ['TARG_REL']} — no diff, no preamble, no markdown fences."
)

body = {
    "model": os.environ["MODEL_ENV"],
    "max_tokens": int(os.environ["MAX_TOK"]),
    "system": system,
    "messages": [{"role": "user", "content": user}],
}
print(json.dumps(body))
PY
)" || { echo "ERROR: failed to build request body" >&2; exit 1; }

# ---- POST to Anthropic ----
RESP_FILE="$(mktemp -t propose_api_resp.XXXXXX)" || { echo "ERROR: mktemp" >&2; exit 1; }
HTTP_STATUS="$(
  curl -sS -o "$RESP_FILE" -w '%{http_code}' \
    -X POST "$API_URL" \
    -H "x-api-key: $ANTHROPIC_API_KEY" \
    -H "anthropic-version: 2023-06-01" \
    -H "content-type: application/json" \
    --data "$REQUEST_BODY" 2>/dev/null || echo "000"
)"

# ---- classify the HTTP status ----
case "$HTTP_STATUS" in
  2*)
    : # success
    ;;
  401|403)
    echo "ERROR: auth failure ($HTTP_STATUS) from $API_URL" >&2
    sed -n '1,40p' "$RESP_FILE" >&2 || true
    rm -f "$RESP_FILE"
    exit 2
    ;;
  429)
    echo "ERROR: rate-limited (429) by $API_URL" >&2
    sed -n '1,40p' "$RESP_FILE" >&2 || true
    rm -f "$RESP_FILE"
    exit 3
    ;;
  5*)
    echo "ERROR: server error ($HTTP_STATUS) from $API_URL" >&2
    sed -n '1,40p' "$RESP_FILE" >&2 || true
    rm -f "$RESP_FILE"
    exit 4
    ;;
  000)
    echo "ERROR: curl failed to reach $API_URL" >&2
    rm -f "$RESP_FILE"
    exit 4
    ;;
  *)
    echo "ERROR: unexpected HTTP $HTTP_STATUS from $API_URL" >&2
    sed -n '1,40p' "$RESP_FILE" >&2 || true
    rm -f "$RESP_FILE"
    exit 1
    ;;
esac

# ---- parse content[0].text ----
PARSED="$(
  python3 - "$RESP_FILE" <<'PY'
import json, sys
try:
    with open(sys.argv[1], "r") as f:
        obj = json.load(f)
except Exception as e:
    sys.stderr.write(f"parse error: {e}\n")
    sys.exit(1)
content = obj.get("content")
if not isinstance(content, list) or not content:
    sys.stderr.write("no content array in response\n")
    sys.exit(1)
first = content[0]
text = first.get("text") if isinstance(first, dict) else None
if not isinstance(text, str):
    sys.stderr.write("content[0].text not a string\n")
    sys.exit(1)
sys.stdout.write(text)
PY
)" || { echo "ERROR: failed to parse response" >&2; sed -n '1,40p' "$RESP_FILE" >&2 || true; rm -f "$RESP_FILE"; exit 1; }

rm -f "$RESP_FILE"
printf '%s\n' "$PARSED"
exit 0
