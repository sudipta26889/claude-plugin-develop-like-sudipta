#!/usr/bin/env bash
# Reliable paste-to-Terminal-then-Enter with verification.
# Reads message from stdin. Clears any existing input via Cmd+A + Delete first
# (so it doesn't append to text the user already typed). Then pastes + Returns.
# After submit, polls Terminal scrollback for a unique fragment of the message
# to confirm it actually landed. Exits non-zero on verification failure.
# Respects $TERMINAL_APP env var.
# If $WORKSPACE is set, logs to <workspace>/.cc/state.json.
set -euo pipefail
APP="${TERMINAL_APP:-Terminal}"
DEST="${CCBRIDGE_DIR:-$HOME/.cache/ccbridge}"

# v5.0.6 BUG-1 — never exit non-zero silently. The BUG-1 failure mode cost
# real debugging time precisely because `set -e` killed the script mid-pipe
# with zero output: no stdout, no stderr, no log line, no state event, and
# the manager believed the send had landed. This trap guarantees that any
# abort announces itself on stderr AND in the bridge log.
_send_abort_trap() {
  rc=$?
  [ "$rc" -eq 0 ] && exit 0
  # v5.0.7 L5 — exit 2 is the VERIFY-FAIL path, which already printed its
  # own [send] FAIL line; shouting ABORT over it was misleading (the paste
  # itself succeeded). ABORT is reserved for unexpected deaths (set -e).
  if [ "$rc" -ne 2 ]; then
    echo "[send] ABORT rc=$rc at line ${BASH_LINENO[0]:-?} — message NOT sent" >&2
  fi
  echo "[$(date)] [send] exit rc=$rc line=${BASH_LINENO[0]:-?}" >>"${DEST}/send.log" 2>/dev/null || true
  exit "$rc"
}
trap _send_abort_trap EXIT

MSG="$(cat)"
LEN=${#MSG}

# v4.5.1 — pick verification fragment from ASCII-only runs.
# Why: pbcopy ⇄ osascript paste ⇄ Terminal scrollback can re-encode some
# Unicode (em-dashes U+2014, smart quotes U+2018-201F, ellipsis U+2026, any
# char above U+007E). Literal byte-level grep then false-negatives even
# though the paste landed correctly. The fix is to pick the verification
# fragment from a printable-ASCII-only stretch (chars in [!-~ ]).
#
# Algorithm: extract all maximal ASCII-printable runs of ≥15 chars, take
# the longest one, slice up to 30 chars from its middle. Fall back to the
# old "middle 30 of first 80" if no ASCII-only run of usable length exists.
# v5.0.6 BUG-1: the `grep` must not be allowed to fail the pipeline. Under
# `set -euo pipefail`, a no-match grep exits 1 and kills the ENTIRE script
# before pbcopy/osascript run — silently, with no log line and no state
# event. Any message without a printable-ASCII run of >=15 chars hits this:
# `/clear`, `/compact`, `yes`, `2`. The `|| true` lets a no-match yield
# empty output so the `[ -z "$FRAG" ]` fallback below becomes reachable in
# exactly the case it was written for.
FRAG=$(printf '%s' "$MSG" \
  | { LC_ALL=C grep -oE '[!-~ ]{15,200}' 2>/dev/null || true; } \
  | awk '{ print length, $0 }' \
  | sort -rn \
  | head -1 \
  | cut -d' ' -f2- \
  | awk '{
      n = length($0)
      if (n <= 30) print $0
      else print substr($0, int((n-30)/2) + 1, 30)
    }' \
  | head -c 30)
if [ -z "$FRAG" ]; then
  # Fallback: legacy slice. Rarely reached — only if message is purely non-ASCII.
  FRAG="$(printf '%s' "$MSG" | head -c 80 | tail -c 30)"
fi
# v5.0.7 H4/M3 — capture the pre-paste buffer hash. Two verifiers need it:
#   - short frags (<5 chars): grepping the buffer for "2" matches any digit
#     anywhere → false OK. Verify by buffer-CHANGE instead.
#   - screen-mutating commands: "message still at prompt" can false-fail on
#     an autocomplete ghost suggestion of the just-submitted command. Hash
#     comparison is ghost-immune: a ghost implies the buffer changed.
PRE_HASH=$("$DEST/read.sh" 2>/dev/null | shasum -a 256 | cut -c1-12 || echo "prehash_unavailable")

printf '%s' "$MSG" | pbcopy
/usr/bin/osascript <<APPLESCRIPT >/dev/null
tell application "$APP" to activate
delay 0.5
tell application "System Events"
  keystroke "a" using {command down}
  delay 0.3
  key code 51
  delay 0.3
  keystroke "v" using {command down}
  delay 0.6
  key code 36
end tell
APPLESCRIPT
echo "[send] $LEN chars, frag='$FRAG'"

# v5.0.7 L1 — the message_sent event used to be logged HERE, before
# verification. A later verify-fail then left BOTH message_sent and
# message_send_failed for the same send; consumers reading only the first
# were misled. The event now fires only on the verified-OK paths below.

sleep 4

# v5.0.6 BUG-1b — screen-mutating slash commands destroy the very evidence
# verify-by-fragment looks for. `/clear` wipes the scrollback; `/compact`
# replaces it with a summary. The paste + Return DID land, but the fragment
# is gone by the time we poll, so the old code reported FAIL (exit 2) on a
# successful send. For this known set, verify by "the buffer changed and no
# longer contains our command echoed at the prompt" instead.
POST_HASH=$("$DEST/read.sh" 2>/dev/null | shasum -a 256 | cut -c1-12 || echo "posthash_unavailable")

case "$MSG" in
  /clear|/compact|/compact\ *|/clear\ *|/rc|/resume|/exit|/quit)
    # v5.0.7 M3 — verify by buffer-CHANGE, not by "message still at prompt".
    # The old grep false-failed when terminal autocomplete GHOSTED the
    # just-submitted command back onto the empty prompt (BUG-3's ghost-text
    # problem applied to our own verifier). Hash comparison is ghost-immune:
    # if the Return didn't take, the buffer is unchanged; anything else
    # (clear, compact summary, even a ghost suggestion) changes it.
    if [ "$POST_HASH" = "$PRE_HASH" ] && [ "$PRE_HASH" != "prehash_unavailable" ]; then
      echo "[send] FAIL: screen-mutating command '$MSG' — buffer unchanged (not submitted)"
      if [ -n "${WORKSPACE:-}" ] && [ -x "$DEST/state.sh" ]; then
        "$DEST/state.sh" "$WORKSPACE" message_send_failed "frag=$FRAG" "reason=buffer_unchanged" >/dev/null 2>&1 || true
      fi
      exit 2
    fi
    echo "[send] OK (screen-mutating command '$MSG' submitted; buffer-change verified)"
    if [ -n "${WORKSPACE:-}" ] && [ -x "$DEST/state.sh" ]; then
      "$DEST/state.sh" "$WORKSPACE" message_sent "len=$LEN" "frag=$FRAG" "verify=screen_mutating" >/dev/null 2>&1 || true
    fi
    exit 0
    ;;
esac

# v5.0.7 H4 — fragment-grep is meaningless for very short frags: grepping
# the buffer for "2" or "y" matches almost anything → false delivery
# confidence. Below 5 chars, verify by buffer-change instead (same
# ghost-immune hash logic as the screen-mutating path).
if [ "${#FRAG}" -lt 5 ]; then
  if [ "$POST_HASH" != "$PRE_HASH" ] && [ "$PRE_HASH" != "prehash_unavailable" ]; then
    echo "[send] OK (short message; buffer-change verified — frag too short for grep)"
    if [ -n "${WORKSPACE:-}" ] && [ -x "$DEST/state.sh" ]; then
      "$DEST/state.sh" "$WORKSPACE" message_sent "len=$LEN" "frag=$FRAG" "verify=buffer_change" >/dev/null 2>&1 || true
    fi
    exit 0
  fi
  echo "[send] FAIL: short message '$MSG' — buffer unchanged (not submitted)"
  if [ -n "${WORKSPACE:-}" ] && [ -x "$DEST/state.sh" ]; then
    "$DEST/state.sh" "$WORKSPACE" message_send_failed "frag=$FRAG" "reason=buffer_unchanged_short" >/dev/null 2>&1 || true
  fi
  exit 2
fi

HIST=$("$DEST/read.sh" 2>/dev/null)
if echo "$HIST" | grep -qF "$FRAG"; then
  echo "[send] OK (visible buffer)"
  if [ -n "${WORKSPACE:-}" ] && [ -x "$DEST/state.sh" ]; then
    "$DEST/state.sh" "$WORKSPACE" message_sent "len=$LEN" "frag=$FRAG" "verify=buffer" >/dev/null 2>&1 || true
  fi
  exit 0
fi
FULL=$("$DEST/read_history.sh" 2>/dev/null)
if echo "$FULL" | grep -qF "$FRAG"; then
  echo "[send] OK (scrollback)"
  if [ -n "${WORKSPACE:-}" ] && [ -x "$DEST/state.sh" ]; then
    "$DEST/state.sh" "$WORKSPACE" message_sent "len=$LEN" "frag=$FRAG" "verify=scrollback" >/dev/null 2>&1 || true
  fi
  exit 0
fi
echo "[send] FAIL: fragment '$FRAG' not found in buffer or scrollback"
if [ -n "${WORKSPACE:-}" ] && [ -x "$DEST/state.sh" ]; then
  "$DEST/state.sh" "$WORKSPACE" message_send_failed "frag=$FRAG" >/dev/null 2>&1 || true
fi
exit 2
