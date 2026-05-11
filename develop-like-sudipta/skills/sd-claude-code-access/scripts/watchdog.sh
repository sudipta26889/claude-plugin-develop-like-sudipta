#!/usr/bin/env bash
# Auto-approve CC permission prompts UNLESS the prompt mentions a danger pattern.
# Polls the active Terminal tab every ~4s. On detecting a known prompt:
#   - If the visible buffer also matches any danger_patterns.txt regex,
#     log LOUDLY, refuse to press Enter, wait for human.
#   - Otherwise press Enter (default-highlighted = "Yes").
# Idempotent per fingerprint - won't re-press for the same on-screen prompt.
# If $WORKSPACE is set, also logs structured state events to <workspace>/.cc/state.json.
DEST="${CCBRIDGE_DIR:-$HOME/.cache/ccbridge}"
LOG="$DEST/watchdog.log"
DANGER="$DEST/danger_patterns.txt"
# Optional per-project deny-list path. Resolved here, but existence is
# checked *inside* the poll loop so a file created after watchdog start
# is picked up on the next poll — no restart needed.
EXTRA_PATH=""
if [ -n "${WORKSPACE:-}" ]; then
  EXTRA_PATH="$WORKSPACE/.cc/danger_patterns_extra.txt"
fi
# Hard-require mktemp. Predictable /tmp paths are a symlink-attack risk.
# macOS and every supported Linux ship mktemp at /usr/bin/mktemp.
if ! command -v mktemp >/dev/null 2>&1 ; then
  echo "fatal: mktemp not available on PATH — refusing to start watchdog" >&2
  exit 1
fi
DRYRUN="${WATCHDOG_DRYRUN:-0}"
# Track the deny-source temp file at the script scope so the EXIT trap
# can clean it up on SIGTERM/SIGINT or normal exit. Empty when no
# temp file exists.
DENY_SRC=""
cleanup() {
  [ -n "$DENY_SRC" ] && rm -f "$DENY_SRC" 2>/dev/null
}
trap cleanup EXIT INT TERM
echo "[$(date)] watchdog started, pid=$$, danger=$DANGER, extras_path=${EXTRA_PATH:-<none>}, dryrun=$DRYRUN, workspace=${WORKSPACE:-<unset>}" >>"$LOG"
last_seen=""
PROMPT_PATTERN='Do you want to (proceed|make this edit|allow|continue)'
while true; do
  buf=$("$DEST/read.sh" 2>/dev/null | tail -50)
  if echo "$buf" | grep -qE "$PROMPT_PATTERN" ; then
    fp=$(echo "$buf" | shasum -a 256 | cut -c1-12)
    if [ "$fp" != "$last_seen" ]; then
      blocked=""
      # Re-check extras file existence per cycle so files created
      # after the watchdog started are picked up automatically.
      EXTRA=""
      if [ -n "$EXTRA_PATH" ] && [ -f "$EXTRA_PATH" ]; then
        EXTRA="$EXTRA_PATH"
      fi
      # Build the effective deny-list: base + optional per-project extras.
      DENY_SRC=""
      if [ -f "$DANGER" ] || [ -n "$EXTRA" ]; then
        DENY_SRC=$(mktemp)
        : > "$DENY_SRC"
        [ -f "$DANGER" ] && cat "$DANGER" >> "$DENY_SRC"
        [ -n "$EXTRA" ] && { echo ""; cat "$EXTRA"; } >> "$DENY_SRC"
      fi
      if [ -n "$DENY_SRC" ] && [ -f "$DENY_SRC" ]; then
        while IFS= read -r pat; do
          [ -z "$pat" ] && continue
          [[ "$pat" =~ ^[[:space:]]*# ]] && continue
          if echo "$buf" | grep -qiE "$pat" ; then
            blocked="$pat"
            break
          fi
        done < "$DENY_SRC"
        rm -f "$DENY_SRC" 2>/dev/null || true
        DENY_SRC=""
      fi
      if [ -n "$blocked" ] && [ "$DRYRUN" = "1" ]; then
        # Dryrun: log intent, then fall through to the approve branch so
        # operators can vet new patterns without locking themselves out.
        echo "[$(date)] would-deny fp=$fp matched=$blocked (DRYRUN — not acting)" >>"$LOG"
        echo "[$(date)] buffer head:" >>"$LOG"
        echo "$buf" | head -20 >>"$LOG"
        if [ -n "${WORKSPACE:-}" ] && [ -x "$DEST/state.sh" ]; then
          "$DEST/state.sh" "$WORKSPACE" danger_dryrun "fp=$fp" "pattern=$blocked" >/dev/null 2>&1 || true
        fi
        blocked=""
      fi
      if [ -n "$blocked" ]; then
        echo "[$(date)] DANGER fp=$fp matched=$blocked - REFUSING to auto-approve" >>"$LOG"
        echo "[$(date)] buffer head:" >>"$LOG"
        echo "$buf" | head -20 >>"$LOG"
        if [ -n "${WORKSPACE:-}" ] && [ -x "$DEST/state.sh" ]; then
          "$DEST/state.sh" "$WORKSPACE" danger_blocked "fp=$fp" "pattern=$blocked" >/dev/null 2>&1 || true
        fi
        # v4.3: feed refusal pattern to cross-project learning capture so
        # autoresearch can spot novel/repeated refusal phrases globally.
        if [ -n "${WORKSPACE:-}" ] && [ -x "$DEST/learning.sh" ]; then
          "$DEST/learning.sh" "$WORKSPACE" permission_pattern \
            "outcome=danger_blocked" "pattern=$blocked" "fp=$fp" >/dev/null 2>&1 || true
        fi
        # ADDITIVE escalation: a silent refusal stalls the run with no
        # notification. Pipe a structured payload into escalate.sh so the
        # workspace gets <workspace>/.cc/escalations.log + (optionally) an
        # ESCALATE_CMD fan-out. Refusal itself is unchanged — escalation
        # is purely a notification side-effect. Back-compat: skip if
        # WORKSPACE is unset or escalate.sh is missing (post-install
        # bridge mismatch).
        if [ -n "${WORKSPACE:-}" ]; then
          if [ -x "$DEST/escalate.sh" ]; then
            # ~200-char snippet of the buffer so the log entry stays
            # grep-friendly without dumping the whole screen.
            # UTF-8-safe truncation: `cut -c` operates on BYTES on macOS
            # and most Linux builds, so cutting at byte 200 can land
            # mid-multibyte sequence and emit invalid UTF-8 trailing into
            # escalations.log (breaking jq, Slack webhooks, etc).
            # `awk substr` is also byte-based, so we follow with
            # `iconv -c -t UTF-8//IGNORE` to drop any trailing partial
            # bytes. iconv ships at /usr/bin/iconv on macOS + all
            # supported Linux distros.
            snippet=$(echo "$buf" | tr '\n' ' ' | awk '{print substr($0,1,200)}' | iconv -c -t UTF-8//IGNORE)
            {
              echo "fp=$fp"
              echo "matched=$blocked"
              echo "prompt=$snippet"
            } | "$DEST/escalate.sh" "$WORKSPACE" >>"$LOG" 2>&1 || \
              echo "[$(date)] escalate.sh failed (fp=$fp matched=$blocked) — continuing" >>"$LOG"
          else
            echo "[$(date)] escalate.sh missing at $DEST/escalate.sh — skipping escalation (fp=$fp)" >>"$LOG"
          fi
        fi
      else
        echo "[$(date)] prompt fp=$fp - pressing return" >>"$LOG"
        "$DEST/keys.sh" return >>"$LOG" 2>&1
        if [ -n "${WORKSPACE:-}" ] && [ -x "$DEST/state.sh" ]; then
          "$DEST/state.sh" "$WORKSPACE" prompt_approved "fp=$fp" >/dev/null 2>&1 || true
        fi
        # v4.3: surfaces of the actual prompt buffer — useful for spotting
        # novel auto-approved phrases the autoresearch loop should learn.
        if [ -n "${WORKSPACE:-}" ] && [ -x "$DEST/learning.sh" ]; then
          snippet_appr=$(echo "$buf" | tr '\n' ' ' | awk '{print substr($0,1,160)}' | iconv -c -t UTF-8//IGNORE 2>/dev/null || echo "")
          "$DEST/learning.sh" "$WORKSPACE" permission_pattern \
            "outcome=approved" "snippet=$snippet_appr" "fp=$fp" >/dev/null 2>&1 || true
        fi
      fi
      last_seen="$fp"
      sleep 3
    fi
  fi
  sleep 4
done
