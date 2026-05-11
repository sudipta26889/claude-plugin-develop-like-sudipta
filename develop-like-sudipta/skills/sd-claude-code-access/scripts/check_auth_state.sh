#!/usr/bin/env bash
# check_auth_state.sh — validate freshness of the persisted browser auth
# state before driving a browser-test step.
#
# Browser tests for auth-gated apps depend on
# <workspace>/.cc/auth/storage-state.json (a Playwright/Chrome MCP storage
# state file: cookies + origins). When that state goes stale mid-run the
# next browser test silently lands on a login form and asserts against
# the wrong page. This script classifies the state and exits with a code
# the caller can branch on:
#
#   exit 0  fresh                   storage state is recent + cookies
#                                   valid (+ optional 401 liveness OK)
#   exit 1  missing                 no storage-state.json on disk
#   exit 2  stale-by-age            mtime older than auth_max_age_minutes
#   exit 3  stale-by-cookie-expiry  critical session cookie expired
#   exit 4  stale-by-401            liveness check returned 401/403
#
# A single token is printed on stdout (the reason). Anything more goes to
# stderr so the caller can capture the reason cleanly:
#
#   reason="$(check_auth_state.sh "$WS")"; case "$reason" in fresh) ...
#
# Usage:
#   check_auth_state.sh <workspace> [--health-url URL]
#
# Config keys read from <workspace>/.cc/config.json (optional):
#   auth_max_age_minutes  integer  default 30
#   auth_health_url       string   optional; --health-url overrides
#
# Bash 3.2 compatible (macOS /bin/bash). Uses python3 for JSON parsing.
# Helper python is written to a temp file rather than passed via inline
# heredoc inside $(...) — bash 3.2's parser misreads that construct when
# the python body contains quote characters.
set -u

WS="${1:-}"
shift || true
HEALTH_URL_CLI=""
while [ "${1:-}" != "" ]; do
  case "$1" in
    --health-url)
      HEALTH_URL_CLI="${2:-}"
      shift 2
      ;;
    --health-url=*)
      HEALTH_URL_CLI="${1#--health-url=}"
      shift
      ;;
    *)
      echo "check_auth_state: unknown argument '$1'" >&2
      exit 2
      ;;
  esac
done

if [ -z "$WS" ]; then
  echo "usage: check_auth_state.sh <workspace> [--health-url URL]" >&2
  exit 2
fi

STORAGE="$WS/.cc/auth/storage-state.json"
CONFIG="$WS/.cc/config.json"

# --------------------------------------------------------------------------
# Hard dependency: python3 is used for JSON parsing. If it's missing every
# subsequent check would misclassify the file — fail loudly.
# --------------------------------------------------------------------------
command -v python3 >/dev/null 2>&1 || {
  echo "check_auth_state: python3 required but not found on PATH" >&2
  exit 2
}

# --------------------------------------------------------------------------
# 1. Missing file.
# --------------------------------------------------------------------------
if [ ! -e "$STORAGE" ]; then
  echo "missing"
  exit 1
fi

# --------------------------------------------------------------------------
# Safety bound: refuse to chew through a runaway file. 10MB cap.
# --------------------------------------------------------------------------
MAX_BYTES=$((10 * 1024 * 1024))
SIZE_BYTES="$(wc -c < "$STORAGE" | tr -d ' ')"
if [ "$SIZE_BYTES" -gt "$MAX_BYTES" ]; then
  echo "check_auth_state: refusing — $STORAGE is $SIZE_BYTES bytes (> 10MB cap). Inspect manually." >&2
  exit 2
fi

# --------------------------------------------------------------------------
# Stage the python helpers to a temp dir. Cleaned up on exit.
# --------------------------------------------------------------------------
HELPER_DIR="$(mktemp -d "${TMPDIR:-/tmp}/check-auth-helpers-XXXXXX")"
trap 'rm -rf "$HELPER_DIR"' EXIT INT TERM

CFG_PY="$HELPER_DIR/cfg.py"
COOKIE_PY="$HELPER_DIR/cookie.py"
HEADER_PY="$HELPER_DIR/header.py"
MTIME_PY="$HELPER_DIR/mtime.py"

cat > "$CFG_PY" <<'PY'
import json, sys
try:
    with open(sys.argv[1]) as f:
        cfg = json.load(f)
except Exception:
    cfg = {}
mx = cfg.get("auth_max_age_minutes", 30)
try:
    mx = int(mx)
except Exception:
    mx = 30
hu = cfg.get("auth_health_url", "") or ""
print("%d|%s" % (mx, hu))
PY

cat > "$MTIME_PY" <<'PY'
import os, sys, time
try:
    m = int(os.path.getmtime(sys.argv[1]))
except Exception:
    m = 0
print("%d %d" % (m, int(time.time())))
PY

cat > "$COOKIE_PY" <<'PY'
import json, sys, time, fnmatch
CRITICAL = ("session", "auth", "token", "jsessionid", "sb-*")

def is_critical(name):
    n = name.lower()
    for pat in CRITICAL:
        if "*" in pat:
            if fnmatch.fnmatch(n, pat):
                return True
        elif n == pat:
            return True
    return False

try:
    with open(sys.argv[1]) as f:
        data = json.load(f)
except Exception:
    # Unparseable file is not a cookie-staleness signal; let upstream
    # tooling diagnose it. Return ok so we do not double-signal.
    print("ok")
    sys.exit(0)

cookies = data.get("cookies") or []
now = int(time.time())
critical_seen = 0
critical_expired = 0
expiring_seen = 0
expiring_expired = 0
for c in cookies:
    if not isinstance(c, dict):
        continue
    name = c.get("name", "")
    exp = c.get("expires")
    if exp is None:
        if is_critical(name):
            critical_seen += 1
        continue
    try:
        exp = int(exp)
    except Exception:
        continue
    if exp < 0:
        if is_critical(name):
            critical_seen += 1
        continue
    expiring_seen += 1
    expired = exp <= now
    if expired:
        expiring_expired += 1
    if is_critical(name):
        critical_seen += 1
        if expired:
            critical_expired += 1

if critical_seen > 0 and critical_expired > 0:
    print("stale")
    sys.exit(0)
if critical_seen == 0 and expiring_seen > 0 and expiring_expired == expiring_seen:
    print("stale")
    sys.exit(0)
print("ok")
PY

cat > "$HEADER_PY" <<'PY'
import json, sys
try:
    with open(sys.argv[1]) as f:
        data = json.load(f)
except Exception:
    print("")
    sys.exit(0)
parts = []
for c in (data.get("cookies") or []):
    if not isinstance(c, dict):
        continue
    n = c.get("name")
    v = c.get("value")
    if n is None or v is None:
        continue
    parts.append("%s=%s" % (n, v))
print("; ".join(parts))
PY

# --------------------------------------------------------------------------
# Read config (best-effort): auth_max_age_minutes, auth_health_url.
# --------------------------------------------------------------------------
MAX_AGE_MIN=30
HEALTH_URL_CFG=""
if [ -f "$CONFIG" ]; then
  CFG_OUT="$(python3 "$CFG_PY" "$CONFIG" 2>/dev/null || true)"
  if [ -n "$CFG_OUT" ]; then
    MAX_AGE_MIN="${CFG_OUT%%|*}"
    HEALTH_URL_CFG="${CFG_OUT#*|}"
  fi
fi
HEALTH_URL="${HEALTH_URL_CLI:-$HEALTH_URL_CFG}"

# --------------------------------------------------------------------------
# 2. File mtime check.
# --------------------------------------------------------------------------
MTIME_OUT="$(python3 "$MTIME_PY" "$STORAGE" 2>/dev/null || echo "0 0")"
FILE_MTIME="${MTIME_OUT%% *}"
NOW_TS="${MTIME_OUT##* }"
AGE_SEC=$((NOW_TS - FILE_MTIME))
MAX_AGE_SEC=$((MAX_AGE_MIN * 60))
if [ "$AGE_SEC" -gt "$MAX_AGE_SEC" ]; then
  echo "stale-by-age"
  exit 2
fi

# --------------------------------------------------------------------------
# 3. Cookie expiry check.
# --------------------------------------------------------------------------
COOKIE_VERDICT="$(python3 "$COOKIE_PY" "$STORAGE" 2>/dev/null || echo "ok")"
if [ "$COOKIE_VERDICT" = "stale" ]; then
  echo "stale-by-cookie-expiry"
  exit 3
fi

# --------------------------------------------------------------------------
# 4. Optional liveness check.
# --------------------------------------------------------------------------
if [ -n "$HEALTH_URL" ]; then
  COOKIE_HEADER="$(python3 "$HEADER_PY" "$STORAGE" 2>/dev/null || echo "")"
  if command -v curl >/dev/null 2>&1; then
    if [ -n "$COOKIE_HEADER" ]; then
      HTTP_CODE="$(curl -sS -o /dev/null -w '%{http_code}' -m 10 -b "$COOKIE_HEADER" "$HEALTH_URL" 2>/dev/null || echo "000")"
    else
      HTTP_CODE="$(curl -sS -o /dev/null -w '%{http_code}' -m 10 "$HEALTH_URL" 2>/dev/null || echo "000")"
    fi
    case "$HTTP_CODE" in
      401|403)
        echo "stale-by-401"
        exit 4
        ;;
    esac
  fi
fi

# --------------------------------------------------------------------------
# 5. All checks passed.
# --------------------------------------------------------------------------
echo "fresh"
exit 0
