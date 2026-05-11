#!/usr/bin/env bash
# sync_learnings.sh — pull a peer Mac's learning tails into local namespace.
#
# Usage: sync_learnings.sh <peer-host> [--dry-run]
#        sync_learnings.sh --dry-run        (sweep all peers in peers.json)
#        sync_learnings.sh                  (sweep all peers in peers.json)
#
# Reads ~/.cache/ccbridge/peers.json for the default peer list:
#   {"version": 1, "peers": ["m1-max.local", "old-mini.local"]}
#
# Pulls peer's ~/.cache/ccbridge/learnings/*.jsonl into
# ~/.cache/ccbridge/learnings/remote-<peer-host>/<ws_id>.jsonl
#
# Idempotent: rsync with --update so only newer remote files transfer.
# Safe:       --dry-run flag prints the plan without transferring.
# Privacy:    skips peer's distillation/ and aggregated/ dirs (local-only by
#             design — those contain derived priors the autoresearch loop
#             computes locally; only the raw learning tails travel).
#
# Bash 3.2 compatible. Requires ssh + rsync (both ship with macOS).

set -euo pipefail

DRY_RUN=0
HOST=""
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    -*) echo "unknown flag: $arg" >&2; exit 2 ;;
    *) HOST="$arg" ;;
  esac
done

CCBRIDGE="${CCBRIDGE_HOME:-$HOME/.cache/ccbridge}"
PEERS_JSON="$CCBRIDGE/peers.json"

# Sweep mode — no host arg → walk every peer in peers.json.
if [ -z "$HOST" ]; then
  [ -f "$PEERS_JSON" ] || { echo "no peer specified and no $PEERS_JSON"; exit 1; }
  PEERS=$(python3 -c 'import json,sys; print("\n".join(json.load(open(sys.argv[1])).get("peers",[])))' "$PEERS_JSON")
  if [ -z "$PEERS" ]; then echo "$PEERS_JSON has no peers entries"; exit 1; fi
  rc=0
  while IFS= read -r peer; do
    [ -z "$peer" ] && continue
    echo "=== syncing $peer ==="
    # Recurse on self per peer. Use `|| rc=$?` so one peer's failure doesn't
    # abort the whole sweep — best-effort semantics across the peer set.
    if [ "$DRY_RUN" = "1" ]; then
      "$0" "$peer" --dry-run || rc=$?
    else
      "$0" "$peer" || rc=$?
    fi
  done <<< "$PEERS"
  exit "$rc"
fi

REMOTE_DIR="$CCBRIDGE/learnings/remote-$HOST"
mkdir -p "$REMOTE_DIR"

RSYNC_FLAGS="-az --update"
[ "$DRY_RUN" = "1" ] && RSYNC_FLAGS="$RSYNC_FLAGS --dry-run --verbose"

echo "[sync] $HOST:~/.cache/ccbridge/learnings/*.jsonl -> $REMOTE_DIR/"

# Capture the remote file list to a tmpfile rather than piping into a while
# loop. Reason: under `set -e` + `pipefail`, an ssh failure (DNS, refused
# connection, etc.) propagates up the pipe and aborts the script before
# the sweep mode's accumulator can record the per-peer failure. Capturing
# first lets us treat a missing/empty remote list as "no files to sync"
# rather than a hard error.
REMOTE_LIST=$(mktemp)
trap 'rm -f "$REMOTE_LIST"' EXIT
ssh -o ConnectTimeout=5 -o BatchMode=yes "$HOST" \
  'ls ~/.cache/ccbridge/learnings/*.jsonl 2>/dev/null' \
  >"$REMOTE_LIST" 2>/dev/null || true

if [ ! -s "$REMOTE_LIST" ]; then
  echo "[sync] no learning tails on $HOST (or peer unreachable)"
  exit 0
fi

COUNT=0
while IFS= read -r remote_file; do
  [ -z "$remote_file" ] && continue
  fname=$(basename "$remote_file")
  rsync $RSYNC_FLAGS "$HOST:$remote_file" "$REMOTE_DIR/$fname" 2>&1 \
    | sed 's/^/  /' || echo "  [sync] WARN: rsync failed for $remote_file"
  COUNT=$((COUNT + 1))
done <"$REMOTE_LIST"

echo "[sync] done: $HOST ($COUNT file(s))"
