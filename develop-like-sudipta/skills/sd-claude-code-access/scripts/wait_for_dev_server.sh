#!/usr/bin/env bash
# wait_for_dev_server.sh — bring up & wait for the workspace dev server.
#
# Browser-test directives need a live HTTP server before they can drive
# Chrome. Most projects either expect "npm run dev" or "docker compose up"
# to have been kicked off by the developer. CC can't assume that — we
# need an orchestrator that:
#
#   1. probes the configured URL,
#   2. starts the server in the background if it isn't already up,
#   3. polls until it answers, or times out,
#   4. surfaces a single-line status that the caller can branch on.
#
# Exit codes:
#   0  ready (already-running OR started-and-ready)
#   1  start attempted but timed out                  (start-failed)
#   2  server not running and no way to start it      (not-running-no-start-cmd)
#   3  misconfiguration (bad URL, missing required field)
#
# Usage:
#   wait_for_dev_server.sh <workspace> [--url URL] [--max-wait SEC] [--health-path PATH]
#
# Resolution order (URL):
#   --url flag > env DEV_SERVER_URL > .cc/config.json:dev_server_url > http://localhost:5173
#
# Resolution order (start cmd):
#   .cc/config.json:dev_server_start_cmd
#   docker-compose.yml / docker-compose.test.yml  -> `docker compose [-f F] up -d`
#   package.json scripts.dev                       -> `npm|pnpm|yarn run dev`
#   (else) no start cmd, assume already-running
#
# Bash 3.2 compatible (macOS /bin/bash). Uses python3 for JSON parsing
# only when a config file is present. curl is required.

set -u

WS="${1:-}"
shift || true

URL_CLI=""
MAX_WAIT_CLI=""
HEALTH_PATH_CLI=""

while [ "${1:-}" != "" ]; do
  case "$1" in
    --url)
      URL_CLI="${2:-}"
      shift 2
      ;;
    --url=*)
      URL_CLI="${1#--url=}"
      shift
      ;;
    --max-wait)
      MAX_WAIT_CLI="${2:-}"
      shift 2
      ;;
    --max-wait=*)
      MAX_WAIT_CLI="${1#--max-wait=}"
      shift
      ;;
    --health-path)
      HEALTH_PATH_CLI="${2:-}"
      shift 2
      ;;
    --health-path=*)
      HEALTH_PATH_CLI="${1#--health-path=}"
      shift
      ;;
    *)
      echo "wait_for_dev_server: unknown argument '$1'" >&2
      exit 3
      ;;
  esac
done

if [ -z "$WS" ]; then
  echo "usage: wait_for_dev_server.sh <workspace> [--url URL] [--max-wait SEC] [--health-path PATH]" >&2
  exit 3
fi
if [ ! -d "$WS" ]; then
  echo "wait_for_dev_server: workspace '$WS' is not a directory" >&2
  exit 3
fi

command -v curl >/dev/null 2>&1 || {
  echo "wait_for_dev_server: curl required but not found on PATH" >&2
  exit 3
}

CONFIG="$WS/.cc/config.json"
PID_FILE="$WS/.cc/dev-server.pid"
LOG_FILE="$WS/.cc/dev-server.log"

mkdir -p "$WS/.cc" 2>/dev/null || true

# ---------------------------------------------------------------------------
# Stage a tiny python JSON-reader helper (only used when config.json exists).
# Bash 3.2 + inline heredoc inside $(...) is fragile; helper file is robust.
# ---------------------------------------------------------------------------
HELPER_DIR=""
make_helper_dir() {
  if [ -z "$HELPER_DIR" ]; then
    HELPER_DIR="$(mktemp -d "${TMPDIR:-/tmp}/wait-devsvr-helpers-XXXXXX")"
  fi
}

cleanup_helpers() {
  if [ -n "$HELPER_DIR" ] && [ -d "$HELPER_DIR" ]; then
    rm -rf "$HELPER_DIR"
  fi
}
trap cleanup_helpers EXIT INT TERM

# Read a string key from a JSON object file. Prints the value (or empty
# string), exit 0. Missing file / missing key / parse error -> empty.
json_get() {
  local file="$1"; local key="$2"
  [ -f "$file" ] || { printf ''; return 0; }
  command -v python3 >/dev/null 2>&1 || { printf ''; return 0; }
  make_helper_dir
  local h="$HELPER_DIR/json_get.py"
  if [ ! -f "$h" ]; then
    cat > "$h" <<'PY'
import json, sys
try:
    with open(sys.argv[1]) as f:
        d = json.load(f)
except Exception:
    print("")
    sys.exit(0)
v = d.get(sys.argv[2])
if v is None:
    print("")
else:
    print(v)
PY
  fi
  python3 "$h" "$file" "$key" 2>/dev/null || printf ''
}

# Detect whether package.json has scripts.dev. Prints "1" if yes, "" otherwise.
pkg_has_dev_script() {
  local pkg="$1"
  [ -f "$pkg" ] || { printf ''; return 0; }
  command -v python3 >/dev/null 2>&1 || { printf ''; return 0; }
  make_helper_dir
  local h="$HELPER_DIR/pkg_dev.py"
  if [ ! -f "$h" ]; then
    cat > "$h" <<'PY'
import json, sys
try:
    with open(sys.argv[1]) as f:
        d = json.load(f)
except Exception:
    print("")
    sys.exit(0)
scripts = d.get("scripts") or {}
print("1" if scripts.get("dev") else "")
PY
  fi
  python3 "$h" "$pkg" 2>/dev/null || printf ''
}

# Detect the package manager from lockfiles in the workspace root.
# Order: pnpm > yarn > npm (default).
detect_pkg_mgr() {
  if [ -f "$WS/pnpm-lock.yaml" ]; then
    printf 'pnpm'
  elif [ -f "$WS/yarn.lock" ]; then
    printf 'yarn'
  else
    printf 'npm'
  fi
}

# ---------------------------------------------------------------------------
# Resolve URL.
# ---------------------------------------------------------------------------
URL=""
if [ -n "$URL_CLI" ]; then
  URL="$URL_CLI"
elif [ -n "${DEV_SERVER_URL:-}" ]; then
  URL="$DEV_SERVER_URL"
else
  CFG_URL="$(json_get "$CONFIG" "dev_server_url")"
  if [ -n "$CFG_URL" ]; then
    URL="$CFG_URL"
  else
    URL="http://localhost:5173"
  fi
fi
# Strip trailing slash so we can append health-path cleanly.
case "$URL" in
  */) URL="${URL%/}" ;;
esac
case "$URL" in
  http://*|https://*) ;;
  *)
    echo "wait_for_dev_server: bad URL '$URL' (must start with http:// or https://)" >&2
    exit 3
    ;;
esac

# ---------------------------------------------------------------------------
# Resolve health-path.
# ---------------------------------------------------------------------------
HEALTH_PATH=""
if [ -n "$HEALTH_PATH_CLI" ]; then
  HEALTH_PATH="$HEALTH_PATH_CLI"
else
  CFG_HP="$(json_get "$CONFIG" "dev_server_health_path")"
  if [ -n "$CFG_HP" ]; then
    HEALTH_PATH="$CFG_HP"
  else
    HEALTH_PATH="/"
  fi
fi
# Normalize: must start with a slash.
case "$HEALTH_PATH" in
  /*) ;;
  *)  HEALTH_PATH="/$HEALTH_PATH" ;;
esac

PROBE_URL="${URL}${HEALTH_PATH}"

# ---------------------------------------------------------------------------
# Resolve max-wait.
# ---------------------------------------------------------------------------
MAX_WAIT=""
if [ -n "$MAX_WAIT_CLI" ]; then
  MAX_WAIT="$MAX_WAIT_CLI"
else
  CFG_MW="$(json_get "$CONFIG" "dev_server_max_wait")"
  if [ -n "$CFG_MW" ]; then
    MAX_WAIT="$CFG_MW"
  else
    MAX_WAIT="60"
  fi
fi
# Validate integer.
case "$MAX_WAIT" in
  ''|*[!0-9]*)
    echo "wait_for_dev_server: --max-wait must be a positive integer (got '$MAX_WAIT')" >&2
    exit 3
    ;;
esac
if [ "$MAX_WAIT" -le 0 ]; then
  echo "wait_for_dev_server: --max-wait must be > 0" >&2
  exit 3
fi

# ---------------------------------------------------------------------------
# Probe: is it already up?
# ---------------------------------------------------------------------------
probe() {
  curl -fsS -o /dev/null -m 5 "$PROBE_URL" 2>/dev/null
}

if probe; then
  echo "already-running url=$PROBE_URL"
  exit 0
fi

# ---------------------------------------------------------------------------
# Resolve start command.
# ---------------------------------------------------------------------------
START_CMD=""
START_SOURCE=""

CFG_CMD="$(json_get "$CONFIG" "dev_server_start_cmd")"
if [ -n "$CFG_CMD" ]; then
  START_CMD="$CFG_CMD"
  START_SOURCE="config"
elif [ -f "$WS/docker-compose.test.yml" ]; then
  START_CMD="docker compose -f docker-compose.test.yml up -d"
  START_SOURCE="docker-compose.test.yml"
elif [ -f "$WS/docker-compose.yml" ]; then
  START_CMD="docker compose up -d"
  START_SOURCE="docker-compose.yml"
elif [ -n "$(pkg_has_dev_script "$WS/package.json")" ]; then
  PM="$(detect_pkg_mgr)"
  case "$PM" in
    pnpm) START_CMD="pnpm dev" ;;
    yarn) START_CMD="yarn dev" ;;
    *)    START_CMD="npm run dev" ;;
  esac
  START_SOURCE="package.json:$PM"
fi

if [ -z "$START_CMD" ]; then
  echo "not-running-no-start-cmd url=$PROBE_URL"
  exit 2
fi

# ---------------------------------------------------------------------------
# Start the server in background. Persist PID + log path.
# ---------------------------------------------------------------------------
echo "[wait_for_dev_server] starting dev server: $START_CMD (source=$START_SOURCE)" >&2

# nohup + & so the child survives this script's foreground exit; redirect
# to dev-server.log so callers can grep on failure. Critically we must
# detach stdin/stdout/stderr from the script's own descriptors BEFORE
# backgrounding — otherwise a caller using $(wait_for_dev_server ...)
# will hang in the command-substitution pipe waiting for the long-lived
# server process to close its inherited fds.
( cd "$WS" && nohup sh -c "$START_CMD" >"$LOG_FILE" 2>&1 </dev/null ) >/dev/null 2>&1 </dev/null &
BG_PID=$!
echo "$BG_PID" > "$PID_FILE"

# For docker-compose, log container names once they're listed.
case "$START_SOURCE" in
  docker-compose.*)
    # Best-effort: wait briefly then dump container names. Detach from the
    # script's stdout (only stderr — diagnostics — passes through) so a
    # caller's $(wait_for_dev_server ...) does not hang on this subshell.
    ( sleep 2; (cd "$WS" && docker compose ps --format '{{.Name}}' 2>/dev/null || true) | while read -r cn; do
        [ -n "$cn" ] && echo "[wait_for_dev_server] container up: $cn" >&2
      done ) >/dev/null </dev/null &
    ;;
esac

# ---------------------------------------------------------------------------
# Poll the probe URL up to MAX_WAIT seconds.
# ---------------------------------------------------------------------------
start_ts="$(date +%s)"
i=0
while [ $i -lt "$MAX_WAIT" ]; do
  if probe; then
    elapsed=$(( $(date +%s) - start_ts ))
    echo "started-and-ready url=$PROBE_URL elapsed=${elapsed}s pid=$BG_PID source=$START_SOURCE"
    exit 0
  fi
  sleep 1
  i=$((i + 1))
done

# ---------------------------------------------------------------------------
# Polling exhausted — kill the started process and its descendants, then
# surface stderr.
# ---------------------------------------------------------------------------
elapsed=$(( $(date +%s) - start_ts ))

# Best-effort recursive kill: walk the pid tree with `ps -A -o pid,ppid`
# and SIGTERM, then SIGKILL, all descendants. macOS doesn't have
# `kill -- -PGID` without setsid (not portable in bash 3.2 + macOS).
kill_tree() {
  local root="$1"
  [ -z "$root" ] && return 0
  # Collect descendants breadth-first.
  local to_visit="$root"
  local all="$root"
  while [ -n "$to_visit" ]; do
    local next=""
    for p in $to_visit; do
      local kids
      kids="$(ps -A -o pid,ppid 2>/dev/null | awk -v pp="$p" '$2==pp{print $1}')"
      if [ -n "$kids" ]; then
        next="$next $kids"
        all="$all $kids"
      fi
    done
    to_visit="$next"
  done
  # SIGTERM in reverse order (kill children first so parents don't respawn).
  local rev=""
  for p in $all; do rev="$p $rev"; done
  for p in $rev; do kill "$p" 2>/dev/null || true; done
  sleep 1
  for p in $rev; do kill -9 "$p" 2>/dev/null || true; done
}

if [ -f "$PID_FILE" ]; then
  pid_to_kill="$(cat "$PID_FILE" 2>/dev/null || echo '')"
  kill_tree "$pid_to_kill"
  rm -f "$PID_FILE"
fi

LOG_TAIL=""
if [ -f "$LOG_FILE" ]; then
  # Last 20 lines for diagnostics.
  LOG_TAIL="$(tail -n 20 "$LOG_FILE" 2>/dev/null || true)"
fi
{
  echo "[wait_for_dev_server] start-failed: probe $PROBE_URL did not respond within ${MAX_WAIT}s"
  if [ -n "$LOG_TAIL" ]; then
    echo "[wait_for_dev_server] last 20 lines of $LOG_FILE:"
    echo "$LOG_TAIL"
  fi
} >&2

echo "start-failed url=$PROBE_URL elapsed=${elapsed}s source=$START_SOURCE"
exit 1
