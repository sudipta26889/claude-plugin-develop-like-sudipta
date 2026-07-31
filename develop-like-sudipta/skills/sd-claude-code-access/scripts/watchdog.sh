#!/usr/bin/env bash
# Watch CC permission prompts. Safety-net mode by default (v4.9+): detect
# prompts, refuse danger patterns, log everything else as prompt_pending for
# the manager to decide. WATCHDOG_AUTO_APPROVE=1 opt-in presses Enter on
# non-danger prompts (unattended runs) — v5.0.7: cursor-aware (C1).
# Idempotent per fingerprint - won't re-act on the same on-screen prompt.
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
# v4.9 — default to safety-net-only. The watchdog only refuses danger
# patterns; the manager (Cowork or human) decides every other prompt by
# reading state.json's prompt_pending events. Set WATCHDOG_AUTO_APPROVE=1
# for unattended autonomous runs (scheduled tasks, batch jobs) where no
# manager is polling. See references/active_watcher.md for the model shift.
AUTO_APPROVE="${WATCHDOG_AUTO_APPROVE:-0}"
# Track the deny-source temp file at the script scope so the EXIT trap
# can clean it up on SIGTERM/SIGINT or normal exit. Empty when no
# temp file exists.
DENY_SRC=""
cleanup() {
  [ -n "$DENY_SRC" ] && rm -f "$DENY_SRC" 2>/dev/null
}
# v5.0.1 BUG-2 fix — split traps: EXIT runs cleanup only; INT/TERM run
# cleanup AND exit explicitly (rc 128+15=143) so the while-true loop
# actually terminates on SIGTERM instead of ignoring it.
on_signal() {
  cleanup
  exit 143
}
trap cleanup EXIT
trap on_signal INT TERM

# ─────────────────────────────────────────────────────────────────────────
# v5.0.7 H1 — bounded logging. state.sh / learning.sh / escalate.sh can hang
# on flock contention (BUG-5/6 class). `|| true` catches a non-zero exit but
# NOT a hang; one wedged call froze the entire poll loop → prompts unattended,
# silently. Every event emission now runs in a background subshell with a 3s
# kill. Losing one audit event is strictly cheaper than losing the watchdog.
_bounded_log() {
  ( "$@" >/dev/null 2>&1 ) &
  local _blpid=$!
  local _w=0
  while kill -0 "$_blpid" 2>/dev/null && [ "$_w" -lt 3 ]; do
    sleep 1; _w=$((_w + 1))
  done
  if kill -0 "$_blpid" 2>/dev/null; then
    kill -KILL "$_blpid" 2>/dev/null
    echo "[$(date)] WARN: bounded log call timed out (3s): $1" >>"$LOG"
  fi
}
# Same guarantee for escalate.sh, which takes its payload on stdin.
_bounded_escalate() {
  local _payload="$1" _ws="$2"
  ( printf '%s\n' "$_payload" | "$DEST/escalate.sh" "$_ws" >>"$LOG" 2>&1 ) &
  local _bepid=$!
  local _w=0
  while kill -0 "$_bepid" 2>/dev/null && [ "$_w" -lt 3 ]; do
    sleep 1; _w=$((_w + 1))
  done
  kill -KILL "$_bepid" 2>/dev/null || true
}

# ─────────────────────────────────────────────────────────────────────────
# v5.0.7 C2 — scope matching to the right buffer region.
#
# The deny-list used to scan the WHOLE visible buffer. When CC *displays*
# content containing `rm -rf` (editing danger_patterns.txt, showing an eval
# diff — exactly what happens when this plugin develops itself), the watchdog
# refused on file CONTENT, not a command. Danger scanning now targets the
# command block: lines from the last `⏺ Bash(` / `Bash command` marker to the
# end of the buffer. Fail-closed: if no marker is found, scan the whole
# buffer (over-refusal is safer than under-refusal).
_cmd_block() {
  printf '%s\n' "$1" | awk '
    /⏺ Bash\(|Bash command/ { i = NR }
    { l[NR] = $0 }
    END { if (!i) i = 1; for (j = i; j <= NR; j++) print l[j] }'
}
# v5.0.7 M1 — fingerprint the PROMPT BLOCK, not the whole buffer. CC's
# spinner/timer redraws above the prompt changed the whole-buffer hash every
# poll, defeating dedupe (136 duplicate events in one observed run). The
# block from the last "Do you want" line to the end is stable while the same
# physical prompt is on screen. Fallback: whole buffer.
_fp_block() {
  printf '%s\n' "$1" | awk '
    /Do you want/ { i = NR }
    { l[NR] = $0 }
    END { if (!i) i = 1; for (j = i; j <= NR; j++) print l[j] }'
}

echo "[$(date)] watchdog started, pid=$$, danger=$DANGER, extras_path=${EXTRA_PATH:-<none>}, dryrun=$DRYRUN, auto_approve=$AUTO_APPROVE, workspace=${WORKSPACE:-<unset>}" >>"$LOG"
last_seen=""
last_interrupt_line=""
PROMPT_PATTERN='Do you want to (proceed|make this edit|allow|continue|create|write|edit|delete|run)|^[[:space:]]*❯[[:space:]]*1\.[[:space:]]+(Yes|Continue|Allow|Proceed)'
# v5.0.5 FAILURE 4 — CC's "Interrupted · What should Claude do instead?" UI
# is NOT a permission prompt; it's a typed-response request → emit
# prompt_interrupted, never press keys.
# v5.0.7 C2/C3 hardening:
#   - Require the marker in the LAST 6 LINES of the buffer (the live UI
#     area). Scrollback echoes of the string — e.g. CC displaying this
#     plugin's own docs, which contain "Interrupted ·" — no longer trigger.
#   - Require "What should Claude do instead" somewhere in the buffer as
#     co-occurrence evidence of the real interrupt UI.
#   - Dedupe on the interrupt LINE text, not the whole-buffer hash. The old
#     buffer-hash dedupe re-emitted prompt_interrupted on every new output
#     line while a stale marker was still visible (event spam).
INTERRUPT_PATTERN='Interrupted ·'
INTERRUPT_CONFIRM='What should Claude do instead'
while true; do
  buf=$("$DEST/read.sh" 2>/dev/null | tail -50)
  tail6=$(printf '%s\n' "$buf" | tail -6)
  if printf '%s\n' "$tail6" | grep -qF "$INTERRUPT_PATTERN" \
     && printf '%s\n' "$buf" | grep -qF "$INTERRUPT_CONFIRM" ; then
    int_line=$(printf '%s\n' "$tail6" | grep -F "$INTERRUPT_PATTERN" | tail -1)
    if [ "$int_line" != "$last_interrupt_line" ]; then
      ifp=$(printf '%s' "$int_line" | shasum -a 256 | cut -c1-12)
      echo "[$(date)] INTERRUPT fp=$ifp - CC paused at typed-response UI, emitted prompt_interrupted (no keystroke)" >>"$LOG"
      if [ -n "${WORKSPACE:-}" ] && [ -x "$DEST/state.sh" ]; then
        snippet_int=$(echo "$buf" | tr '\n' ' ' | awk '{print substr($0,1,200)}' | iconv -c -t UTF-8//IGNORE 2>/dev/null || echo "")
        _bounded_log "$DEST/state.sh" "$WORKSPACE" prompt_interrupted "fp=$ifp" "snippet=$snippet_int"
      fi
      if [ -n "${WORKSPACE:-}" ] && [ -x "$DEST/learning.sh" ]; then
        _bounded_log "$DEST/learning.sh" "$WORKSPACE" watchdog_recovery \
          "outcome=interrupt_detected" "fp=$ifp"
      fi
      last_interrupt_line="$int_line"
    fi
    sleep 4
    continue
  fi
  # v5.0.7 C3 — marker gone from the live area → clear dedupe so a FUTURE
  # identical interrupt is still detected.
  last_interrupt_line=""
  if echo "$buf" | grep -qE "$PROMPT_PATTERN" ; then
    fpb=$(_fp_block "$buf")
    fp=$(printf '%s' "$fpb" | shasum -a 256 | cut -c1-12)
    if [ "$fp" != "$last_seen" ]; then
      blocked=""
      cmdb=$(_cmd_block "$buf")
      # v5.0.6 BUG-2 — project-scoped ALLOW-list, checked BEFORE the deny
      # scan. Contract: an allow entry must be NARROWER than the pattern it
      # exempts (`\bDROP\b` as an allow entry is a self-inflicted wound).
      # Every exemption is logged LOUDLY + emits danger_exempted. See
      # references/danger_pattern_governance.md.
      allowed=""
      ALLOW_PATH=""
      if [ -n "${WORKSPACE:-}" ]; then
        ALLOW_PATH="$WORKSPACE/.cc/danger_patterns_allow.txt"
      fi
      if [ -n "$ALLOW_PATH" ] && [ -f "$ALLOW_PATH" ]; then
        while IFS= read -r apat; do
          [ -z "$apat" ] && continue
          # v5.0.7 L2 — tolerate leading whitespace before '#', same as the
          # deny-list's comment handling.
          [[ "$apat" =~ ^[[:space:]]*# ]] && continue
          if echo "$cmdb" | grep -qiE "$apat" ; then
            allowed="$apat"
            break
          fi
        done < "$ALLOW_PATH"
      fi
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
      # v5.0.6 BUG-2 — allow-list wins: skip the deny scan entirely, log loudly.
      if [ -n "$allowed" ]; then
        echo "[$(date)] ALLOW fp=$fp matched=$allowed - exempted by project allow-list" >>"$LOG"
        if [ -n "${WORKSPACE:-}" ] && [ -x "$DEST/state.sh" ]; then
          _bounded_log "$DEST/state.sh" "$WORKSPACE" danger_exempted "fp=$fp" "pattern=$allowed"
        fi
        if [ -n "${WORKSPACE:-}" ] && [ -x "$DEST/learning.sh" ]; then
          _bounded_log "$DEST/learning.sh" "$WORKSPACE" permission_pattern \
            "outcome=danger_exempted" "pattern=$allowed" "fp=$fp"
        fi
        [ -n "$DENY_SRC" ] && { rm -f "$DENY_SRC" 2>/dev/null || true; DENY_SRC=""; }
      fi
      if [ -z "$allowed" ] && [ -n "$DENY_SRC" ] && [ -f "$DENY_SRC" ]; then
        while IFS= read -r pat; do
          [ -z "$pat" ] && continue
          [[ "$pat" =~ ^[[:space:]]*# ]] && continue
          # v5.0.7 C2 — scan the COMMAND BLOCK, not the whole buffer, so
          # displayed file content (diffs, docs, the deny-list itself) can't
          # trip a refusal. Fail-closed: _cmd_block returns the whole buffer
          # when no command marker is present.
          if echo "$cmdb" | grep -qiE "$pat" ; then
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
          _bounded_log "$DEST/state.sh" "$WORKSPACE" danger_dryrun "fp=$fp" "pattern=$blocked"
        fi
        blocked=""
      fi
      if [ -n "$blocked" ]; then
        echo "[$(date)] DANGER fp=$fp matched=$blocked - REFUSING to auto-approve" >>"$LOG"
        echo "[$(date)] buffer head:" >>"$LOG"
        echo "$buf" | head -20 >>"$LOG"
        if [ -n "${WORKSPACE:-}" ] && [ -x "$DEST/state.sh" ]; then
          _bounded_log "$DEST/state.sh" "$WORKSPACE" danger_blocked "fp=$fp" "pattern=$blocked"
        fi
        # v4.3: feed refusal pattern to cross-project learning capture so
        # autoresearch can spot novel/repeated refusal phrases globally.
        if [ -n "${WORKSPACE:-}" ] && [ -x "$DEST/learning.sh" ]; then
          _bounded_log "$DEST/learning.sh" "$WORKSPACE" permission_pattern \
            "outcome=danger_blocked" "pattern=$blocked" "fp=$fp"
        fi
        # ADDITIVE escalation: a silent refusal stalls the run with no
        # notification. escalate.sh appends to <ws>/.cc/escalations.log and
        # optionally fans out via ESCALATE_CMD. v5.0.7 H1: bounded (3s) so a
        # wedged escalate can no longer freeze the poll loop.
        if [ -n "${WORKSPACE:-}" ]; then
          if [ -x "$DEST/escalate.sh" ]; then
            snippet=$(echo "$buf" | tr '\n' ' ' | awk '{print substr($0,1,200)}' | iconv -c -t UTF-8//IGNORE)
            _bounded_escalate "fp=$fp
matched=$blocked
prompt=$snippet" "$WORKSPACE"
          else
            echo "[$(date)] escalate.sh missing at $DEST/escalate.sh — skipping escalation (fp=$fp)" >>"$LOG"
          fi
        fi
      else
        if [ "$AUTO_APPROVE" = "1" ]; then
          # Unattended path: approve non-danger prompts.
          #
          # v5.0.7 C1 — cursor-aware. CC's multi-option prompts often default
          # the cursor to the LAST option ("3. No"); a bare return REJECTED
          # the action the watchdog meant to approve (same bug class as BUG-4,
          # which was fixed for the orchestrator via unblock_cc.sh but never
          # here). Parse the `❯ N.` cursor line from the prompt block; press
          # `up` (N-1) times first when the cursor is not on option 1. Prompts
          # without a numbered cursor (plain y/n) keep the bare return.
          cursor_line=$(printf '%s\n' "$fpb" | grep -E '^[[:space:]]*❯[[:space:]]+[0-9]+\.' | tail -1)
          cursor_opt=""
          if [ -n "$cursor_line" ]; then
            cursor_opt=$(printf '%s' "$cursor_line" | sed -E 's/^[[:space:]]*❯[[:space:]]+([0-9]+)\..*/\1/')
            case "$cursor_opt" in ''|*[!0-9]*) cursor_opt="" ;; esac
          fi
          if [ -n "$cursor_opt" ] && [ "$cursor_opt" -gt 1 ]; then
            steps=$((cursor_opt - 1))
            echo "[$(date)] prompt fp=$fp - cursor on option $cursor_opt, pressing up x$steps then return (auto_approve=1)" >>"$LOG"
            i=0
            while [ "$i" -lt "$steps" ]; do
              "$DEST/keys.sh" up >>"$LOG" 2>&1
              sleep 0.3
              i=$((i + 1))
            done
            sleep 0.2
          else
            echo "[$(date)] prompt fp=$fp - pressing return (auto_approve=1)" >>"$LOG"
          fi
          "$DEST/keys.sh" return >>"$LOG" 2>&1
          if [ -n "${WORKSPACE:-}" ] && [ -x "$DEST/state.sh" ]; then
            _bounded_log "$DEST/state.sh" "$WORKSPACE" prompt_approved "fp=$fp" "cursor_was=${cursor_opt:-none}"
          fi
          # v4.3: surface the actual prompt buffer — useful for spotting
          # novel auto-approved phrases the autoresearch loop should learn.
          if [ -n "${WORKSPACE:-}" ] && [ -x "$DEST/learning.sh" ]; then
            snippet_appr=$(echo "$buf" | tr '\n' ' ' | awk '{print substr($0,1,160)}' | iconv -c -t UTF-8//IGNORE 2>/dev/null || echo "")
            _bounded_log "$DEST/learning.sh" "$WORKSPACE" permission_pattern \
              "outcome=approved" "snippet=$snippet_appr" "fp=$fp"
          fi
        else
          # v4.9 default: safety-net-only. DON'T press Enter. Emit a
          # prompt_pending state event so the manager (Cowork or human)
          # picks it up on the next state.json poll and decides what to do.
          # Manager-decides model — see references/active_watcher.md.
          snippet_pend=$(echo "$buf" | tr '\n' ' ' | awk '{print substr($0,1,200)}' | iconv -c -t UTF-8//IGNORE 2>/dev/null || echo "")
          echo "[$(date)] prompt fp=$fp - safety-net mode (auto_approve=0), NOT pressing return; emitted prompt_pending" >>"$LOG"
          if [ -n "${WORKSPACE:-}" ] && [ -x "$DEST/state.sh" ]; then
            _bounded_log "$DEST/state.sh" "$WORKSPACE" prompt_pending "fp=$fp" "snippet=$snippet_pend"
          fi
          if [ -n "${WORKSPACE:-}" ] && [ -x "$DEST/learning.sh" ]; then
            _bounded_log "$DEST/learning.sh" "$WORKSPACE" permission_pattern \
              "outcome=pending" "snippet=$snippet_pend" "fp=$fp"
          fi
        fi
      fi
      last_seen="$fp"
      sleep 3
    fi
  fi
  sleep 4
done
