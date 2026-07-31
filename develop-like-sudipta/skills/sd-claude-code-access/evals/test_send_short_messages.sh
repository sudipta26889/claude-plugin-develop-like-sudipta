#!/usr/bin/env bash
# v5.0.6 BUG-1 regression — send.sh must handle messages of ANY length.
#
# Field report (2026-07-31, Django multi-tenant run):
#   printf '/clear' | send.sh  →  EXIT=1, zero output, nothing pasted,
#   no log line, no state event. The manager believed the send landed.
#
# Root cause: `set -euo pipefail` + the FRAG picker's
#   LC_ALL=C grep -oE '[!-~ ]{15,200}'
# For any message WITHOUT a printable-ASCII run of >=15 chars, grep exits 1,
# pipefail propagates, and the script dies BEFORE pbcopy/osascript ever run.
# The `[ -z "$FRAG" ]` fallback at the next line is unreachable in exactly
# the case it was written for.
#
# This eval tests the FRAG-selection logic in isolation (pure text pipeline,
# no Terminal needed) by extracting it from the real send.sh and running it
# under the same `set -euo pipefail` the script uses.
#
# Contracts:
#   1. Every message in the fixture list yields a NON-EMPTY frag.
#   2. The pipeline exits 0 for all of them (no pipefail abort).
#   3. Long-message frags are unchanged (non-regression on the v4.5.1 C3 fix).
set -uo pipefail

SCRIPT="$(cd "$(dirname "$0")/../scripts" && pwd)/send.sh"
test -f "$SCRIPT" || { echo "FAIL: send.sh missing at $SCRIPT"; exit 1; }

# Extract the FRAG picker from the real send.sh so the eval can't drift from
# the implementation. We grab the contiguous block from the `FRAG=$(printf`
# line through the fallback assignment.
FRAG_BLOCK=$(awk '/^FRAG=\$\(printf/,/^fi$/' "$SCRIPT")
if [ -z "$FRAG_BLOCK" ]; then
  echo "FAIL: could not extract FRAG picker block from send.sh"
  echo "      (send.sh structure changed — update this eval's awk range)"
  exit 1
fi

frag_of() (
  # Same shell options the real script runs under. This is what makes the
  # bug reproducible: without pipefail the grep-no-match is harmless.
  set -euo pipefail
  MSG="$1"
  eval "$FRAG_BLOCK"
  printf '%s' "$FRAG"
)

FAIL=0

# Contract 1+2 — short messages must produce a frag and exit 0.
for m in "/clear" "/compact" "/rc" "yes" "no" "2" "y"; do
  if out=$(frag_of "$m" 2>/dev/null) && [ -n "$out" ]; then
    echo "PASS  short '$m' -> frag '$out'"
  else
    echo "FAIL  short '$m' -> empty frag or non-zero exit (BUG-1)"
    FAIL=1
  fi
done

# Contract 3 — long-message behavior unchanged (middle-slice of longest run).
LONG='Read `.cc/phase-1.md` and proceed.'
if out=$(frag_of "$LONG" 2>/dev/null) && [ -n "$out" ]; then
  case "$out" in
    *"phase-1.md"*)
      echo "PASS  long message -> frag '$out' (middle-slice preserved)" ;;
    *)
      echo "FAIL  long message frag lost its middle-slice property: '$out'"
      FAIL=1 ;;
  esac
else
  echo "FAIL  long message produced no frag (regression on v4.5.1 C3 fix)"
  FAIL=1
fi

# Contract 4 — unicode-heavy short message (em-dash) still gets a frag via
# the fallback path, since the ASCII-only run is under 15 chars.
UNI="ok — go"
if out=$(frag_of "$UNI" 2>/dev/null) && [ -n "$out" ]; then
  echo "PASS  unicode-short '$UNI' -> frag '$out'"
else
  echo "FAIL  unicode-short '$UNI' -> empty frag or non-zero exit (BUG-1)"
  FAIL=1
fi

[ "$FAIL" -eq 0 ] && { echo "ALL PASS — send.sh FRAG picker handles any message length"; exit 0; }
echo "FAIL — BUG-1 present: send.sh cannot frag short messages"
exit 1
