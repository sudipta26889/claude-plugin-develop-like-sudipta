#!/usr/bin/env bash
# regenerate_phase_specs.sh — detect stale, missing, or orphan per-phase
# Playwright specs by comparing each spec's `// source-hash:` comment to
# the current SHA-256 of its source markdown's `## Steps` section.
#
# Problem: when phase 3 renames a button that phase 1 tested, the
# selector inside phase-1.spec.ts goes red. The spec generator already
# stamps every generated `*.spec.ts` with a `// source-hash:` comment
# (sha256 of the source markdown's `## Steps` section). This script
# reports which specs have drifted from their source markdowns and
# suggests the right regeneration command — but does not run it.
#
# Three drift classes:
#   STALE        — spec exists, hash mismatch       → /browser-test <N>
#   MISSING_SPEC — md exists, no spec.ts            → /browser-test <N>
#   ORPHAN_SPEC  — spec exists, no md               → cleanup_test_artifacts.sh
#
# Usage:
#   regenerate_phase_specs.sh <workspace> [--dry-run] [--apply]
#
# Modes:
#   default / --dry-run — REPORT mode (the only mode in v1)
#   --apply             — stub, exits 0 with a message; full auto-regen
#                         is deferred (would need to dispatch
#                         /browser-test runs).
#
# Resolution:
#   Test root: env BROWSER_TEST_ROOT > .cc/config.json browser_test_root
#              > default <workspace>/docs/e2e-testing.
#
# Exit codes:
#   0 — all fresh (or only --apply stub)
#   1 — at least one STALE/MISSING_SPEC/ORPHAN_SPEC detected
#   2 — misconfiguration (workspace missing, test root missing, etc.)
#
# Bash 3.2 compatible (macOS /bin/bash). Uses python3 for sha256 + Steps
# section extraction so the algorithm matches the spec generator exactly.
set -u

# --------------------------------------------------------------------------
# Argument parsing.
# --------------------------------------------------------------------------
WS=""
APPLY=0
# DRY_RUN tracked for symmetry / future use; default mode == --dry-run.
DRY_RUN=0

while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help)
      sed -n '2,40p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    --apply)
      APPLY=1
      shift
      ;;
    --)
      shift
      break
      ;;
    -*)
      echo "regenerate_phase_specs: unknown argument '$1'" >&2
      exit 2
      ;;
    *)
      if [ -z "$WS" ]; then
        WS="$1"
        shift
      else
        echo "regenerate_phase_specs: unexpected extra argument '$1'" >&2
        exit 2
      fi
      ;;
  esac
done

if [ -z "$WS" ]; then
  echo "usage: regenerate_phase_specs.sh <workspace> [--dry-run] [--apply]" >&2
  exit 2
fi

# --apply is a stub in v1. Print intent and exit 0 — the operator should
# still run --dry-run to see the report, then re-run /browser-test by hand.
if [ "$APPLY" -eq 1 ]; then
  echo "regenerate_phase_specs: --apply is not yet implemented in v1."
  echo "Run /browser-test <phase> manually for each stale/missing phase."
  echo "(Re-run this script without --apply to see the drift report.)"
  exit 0
fi

# --------------------------------------------------------------------------
# Hard dependency: python3 — used for SHA-256 + Steps section extraction.
# The algorithm must match the spec generator's. Failing loud beats
# silently misclassifying every spec as stale.
# --------------------------------------------------------------------------
command -v python3 >/dev/null 2>&1 || {
  echo "regenerate_phase_specs: python3 required but not found on PATH" >&2
  exit 2
}

CONFIG="$WS/.cc/config.json"

# --------------------------------------------------------------------------
# Resolve test root: env > config > default.
# --------------------------------------------------------------------------
CONFIG_TEST_ROOT=""
if [ -f "$CONFIG" ]; then
  CONFIG_TEST_ROOT="$(python3 - "$CONFIG" <<'PY' 2>/dev/null || true
import json, sys
try:
    with open(sys.argv[1]) as f:
        c = json.load(f)
except Exception:
    c = {}
print(c.get("browser_test_root", "") or "")
PY
)"
fi

if [ -n "${BROWSER_TEST_ROOT:-}" ]; then
  RAW_ROOT="$BROWSER_TEST_ROOT"
elif [ -n "$CONFIG_TEST_ROOT" ]; then
  RAW_ROOT="$CONFIG_TEST_ROOT"
else
  RAW_ROOT="docs/e2e-testing"
fi

case "$RAW_ROOT" in
  /*) TEST_ROOT="$RAW_ROOT" ;;
   *) TEST_ROOT="$WS/$RAW_ROOT" ;;
esac

if [ ! -d "$TEST_ROOT" ]; then
  echo "regenerate_phase_specs: test root not found at $TEST_ROOT" >&2
  exit 2
fi

SPECS_DIR="$TEST_ROOT/specs"

# --------------------------------------------------------------------------
# Helpers.
# --------------------------------------------------------------------------

# Print the SHA-256 of the `## Steps` section content of a markdown file.
# Section spans from the line AFTER `## Steps` to the line BEFORE the
# next `## ` heading (or EOF). Bytes are captured verbatim. This MUST
# match the generator's algorithm (referenced in
# assets/playwright_spec_template.ts and references/playwright_generation.md).
steps_hash_of() {
  python3 - "$1" <<'PY'
import hashlib, sys
try:
    with open(sys.argv[1], "rb") as f:
        raw = f.read()
except Exception:
    print("")
    sys.exit(0)
text = raw.decode("utf-8", errors="replace")
lines = text.splitlines(keepends=True)
out = []
in_steps = False
for ln in lines:
    stripped = ln.lstrip()
    if stripped.startswith("## "):
        if in_steps:
            break
        if stripped[3:].strip().lower() == "steps":
            in_steps = True
            continue
    if in_steps:
        out.append(ln)
body = "".join(out)
print(hashlib.sha256(body.encode("utf-8")).hexdigest())
PY
}

# Print the `// source-hash: <hex>` value from a spec.ts (first match
# wins). Empty string if absent or unreadable. Tolerant of any leading
# whitespace and any line position in the file.
source_hash_of() {
  python3 - "$1" <<'PY'
import re, sys
try:
    with open(sys.argv[1], "r", encoding="utf-8", errors="replace") as f:
        for line in f:
            m = re.search(r"//\s*source-hash:\s*([0-9a-fA-F]+)", line)
            if m:
                print(m.group(1).lower())
                break
        else:
            print("")
except Exception:
    print("")
PY
}

# Extract digit prefix from a `phase-N-foo.md` / `phase-N.spec.ts` path.
phase_num_from() {
  _pnf_base="$(basename "$1")"
  _pnf_rest="${_pnf_base#phase-}"
  _pnf_digits=""
  _pnf_i=0
  while [ "$_pnf_i" -lt ${#_pnf_rest} ]; do
    _pnf_ch="${_pnf_rest:$_pnf_i:1}"
    case "$_pnf_ch" in
      [0-9]) _pnf_digits="$_pnf_digits$_pnf_ch" ;;
      *) break ;;
    esac
    _pnf_i=$((_pnf_i + 1))
  done
  printf '%s' "$_pnf_digits"
}

# Find the markdown file for a given phase number. Prints the absolute
# path of the first match (deterministic via shell glob ordering), or
# empty string if none. `set -u` safe because we only read $1.
md_for_phase() {
  _mfp_n="$1"
  for _mfp_f in "$TEST_ROOT"/phase-"$_mfp_n"-*.md; do
    if [ -e "$_mfp_f" ]; then
      printf '%s' "$_mfp_f"
      return 0
    fi
  done
  printf ''
}

# --------------------------------------------------------------------------
# Walk all phase-N-*.md, classify each as FRESH / STALE / MISSING_SPEC.
# Then walk specs/phase-*.spec.ts and flag any without a corresponding md
# as ORPHAN_SPEC.
# --------------------------------------------------------------------------
FRESH=0
STALE=0
MISSING=0
ORPHANS=0
STALE_LIST=""
MISSING_LIST=""
ORPHAN_LIST=""

# Track which phase numbers we've already seen via markdown so we don't
# double-count if multiple `phase-N-*.md` files share an N (the first
# one wins; the generator behaves the same way).
SEEN_MD_PHASES=" "

for md in "$TEST_ROOT"/phase-*.md; do
  [ -e "$md" ] || continue
  pn="$(phase_num_from "$md")"
  [ -z "$pn" ] && continue
  case "$SEEN_MD_PHASES" in
    *" $pn "*) continue ;;
  esac
  SEEN_MD_PHASES="$SEEN_MD_PHASES$pn "

  spec="$SPECS_DIR/phase-$pn.spec.ts"
  if [ ! -f "$spec" ]; then
    MISSING=$((MISSING + 1))
    MISSING_LIST="$MISSING_LIST $pn"
    echo "MISSING_SPEC phase-$pn: would generate on next /browser-test"
    continue
  fi

  cur_hash="$(steps_hash_of "$md")"
  spec_hash="$(source_hash_of "$spec")"
  if [ -z "$cur_hash" ]; then
    # Markdown unreadable / has no `## Steps`. Treat as stale so the
    # operator notices; the generator would have caught this too.
    STALE=$((STALE + 1))
    STALE_LIST="$STALE_LIST $pn"
    echo "STALE phase-$pn (no ## Steps section found in $md)"
    continue
  fi
  if [ "$cur_hash" = "$spec_hash" ]; then
    FRESH=$((FRESH + 1))
    echo "FRESH phase-$pn"
  else
    STALE=$((STALE + 1))
    STALE_LIST="$STALE_LIST $pn"
    echo "STALE phase-$pn (source-hash ${spec_hash:-<missing>} != current $cur_hash)"
  fi
done

# Orphan specs: spec exists but no corresponding phase-N-*.md.
if [ -d "$SPECS_DIR" ]; then
  for spec in "$SPECS_DIR"/phase-*.spec.ts; do
    [ -e "$spec" ] || continue
    pn="$(phase_num_from "$spec")"
    [ -z "$pn" ] && continue
    md="$(md_for_phase "$pn")"
    if [ -z "$md" ]; then
      ORPHANS=$((ORPHANS + 1))
      ORPHAN_LIST="$ORPHAN_LIST $pn"
      echo "ORPHAN_SPEC phase-$pn: no markdown found"
    fi
  done
fi

# --------------------------------------------------------------------------
# Summary.
# --------------------------------------------------------------------------
echo
echo "Spec regeneration report:"
echo "  Fresh: $FRESH"
echo "  Stale: $STALE (run /browser-test for these phases to regenerate)"
echo "  Missing: $MISSING (run /browser-test for these phases to create)"
echo "  Orphans: $ORPHANS (run cleanup_test_artifacts.sh to quarantine)"
echo
# Trim leading space; if empty after trim, print "(none)" so the lines
# are always grep-able and pleasant to read.
_strip() { _s="${1# }"; [ -z "$_s" ] && _s="(none)"; printf '%s' "$_s"; }
echo "Stale phases: $(_strip "$STALE_LIST")"
echo "Missing phases: $(_strip "$MISSING_LIST")"
echo "Orphan phases: $(_strip "$ORPHAN_LIST")"

# Exit 1 if any drift, else 0. Misconfiguration (exit 2) is handled
# earlier.
if [ "$STALE" -gt 0 ] || [ "$MISSING" -gt 0 ] || [ "$ORPHANS" -gt 0 ]; then
  exit 1
fi
exit 0
