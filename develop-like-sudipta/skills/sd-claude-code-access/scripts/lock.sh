#!/usr/bin/env bash
# lock.sh — driver-session semaphore. Prevents two Cowork sessions
# from driving the same CC simultaneously.
#
# Usage:
#   lock.sh acquire <workspace>   → prints lock holder; exits 0 if acquired,
#                                    exits 2 if already held by another driver
#   lock.sh release <workspace>   → release if we own it
#   lock.sh status  <workspace>   → print holder info, exit 0 always
set -euo pipefail
CMD="${1:?usage: lock.sh acquire|release|status <workspace>}"
WS="${2:?usage: lock.sh acquire|release|status <workspace>}"
mkdir -p "$WS/.cc"
LOCK="$WS/.cc/.driver.lock"
ME="$(hostname):$$:$(date -u +%s)"

case "$CMD" in
  acquire)
    if [ -f "$LOCK" ]; then
      OWNER=$(cat "$LOCK")
      OWNER_HOST="${OWNER%%:*}"
      OWNER_REST="${OWNER#*:}"
      OWNER_PID="${OWNER_REST%%:*}"
      OWNER_TS="${OWNER_REST#*:}"
      OWNER_TS="${OWNER_TS%%:*}"
      # Same-host stale lock? Check if pid is still alive.
      if [ "$OWNER_HOST" = "$(hostname)" ] && ! kill -0 "$OWNER_PID" 2>/dev/null; then
        echo "[lock] stale lock from dead pid $OWNER_PID on this host — taking it"
        echo "$ME" > "$LOCK"
        exit 0
      fi
      # v5.0.7 L3 — PID-reuse guard. After a reboot (or plain PID wraparound)
      # kill -0 can succeed against an UNRELATED process that recycled the
      # pid, faking a held lock forever. If the current process with that pid
      # started AFTER the lock was written, it cannot be the original owner.
      # `ps -o lstart=` epoch conversion via date -j is macOS-specific; guard
      # with a parse check and fall back to the conservative HELD verdict.
      if [ "$OWNER_HOST" = "$(hostname)" ] && kill -0 "$OWNER_PID" 2>/dev/null; then
        P_LSTART=$(ps -p "$OWNER_PID" -o lstart= 2>/dev/null | sed 's/^ *//')
        if [ -n "$P_LSTART" ]; then
          P_EPOCH=$(date -j -f "%a %b %d %T %Y" "$P_LSTART" +%s 2>/dev/null || echo "")
          case "$OWNER_TS" in *[!0-9]*|'') OWNER_TS="" ;; esac
          if [ -n "$P_EPOCH" ] && [ -n "$OWNER_TS" ] && [ "$P_EPOCH" -gt "$((OWNER_TS + 5))" ]; then
            echo "[lock] stale lock — pid $OWNER_PID was recycled (proc started after lock ts) — taking it"
            echo "$ME" > "$LOCK"
            exit 0
          fi
        fi
      fi
      echo "[lock] HELD by: $OWNER"
      exit 2
    fi
    echo "$ME" > "$LOCK"
    echo "[lock] acquired: $ME"
    ;;
  release)
    if [ -f "$LOCK" ]; then
      OWNER=$(cat "$LOCK")
      OWNER_REST="${OWNER#*:}"
      OWNER_PID="${OWNER_REST%%:*}"
      if [ "$OWNER_PID" = "$$" ] || [ "$OWNER_PID" = "${PPID}" ]; then
        rm -f "$LOCK"
        echo "[lock] released"
      else
        echo "[lock] not ours — owner=$OWNER, me=$ME (refusing to release)"
        exit 3
      fi
    else
      echo "[lock] no lock to release"
    fi
    ;;
  status)
    if [ -f "$LOCK" ]; then
      echo "[lock] holder: $(cat "$LOCK")"
    else
      echo "[lock] free"
    fi
    ;;
  *)
    echo "usage: lock.sh acquire|release|status <workspace>" >&2
    exit 1
    ;;
esac
