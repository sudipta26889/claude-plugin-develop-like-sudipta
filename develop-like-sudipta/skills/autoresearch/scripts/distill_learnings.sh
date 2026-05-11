#!/usr/bin/env bash
# distill_learnings.sh — turn aggregated learnings into a candidate-mutations report.
#
# Why: aggregated jsonl is too low-level for the autoresearch proposer to read directly.
# This script collapses it into "top N patterns by frequency per category", flags
# cross-project signals (same pattern observed in >=2 distinct ws_ids → strong signal),
# and writes a markdown report that the autoresearch loop can consume as priors.
#
# Usage:
#   distill_learnings.sh                   # distill the current month
#   distill_learnings.sh --month 2026-04   # distill a specific month
#   distill_learnings.sh --last-days 14    # distill the last N days
#
# Output: ~/.cache/ccbridge/distillation/<YYYY-MM>.md  (or -last-<N>days.md)
# Stdout: same content (for piping into other tools).

set -euo pipefail

CCBRIDGE="${CCBRIDGE_HOME:-$HOME/.cache/ccbridge}"
AGG_DIR="$CCBRIDGE/aggregated"
DIST_DIR="$CCBRIDGE/distillation"
mkdir -p "$DIST_DIR"

MONTH=""
LAST_DAYS=""
while [ $# -gt 0 ]; do
  case "$1" in
    --month) MONTH="$2"; shift 2 ;;
    --last-days) LAST_DAYS="$2"; shift 2 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

if [ -z "$MONTH" ] && [ -z "$LAST_DAYS" ]; then
  MONTH=$(date -u +%Y-%m)
fi

python3 - "$AGG_DIR" "$DIST_DIR" "$MONTH" "$LAST_DAYS" <<'PY'
import json, os, sys, glob, datetime as dt
from collections import Counter, defaultdict
agg_dir, dist_dir, month, last_days = sys.argv[1:]

# Build list of jsonl files to read.
files = []
if month:
    pat = os.path.join(agg_dir, f"{month}-*.jsonl")
    files = sorted(glob.glob(pat))
    out_name = f"{month}.md"
else:
    n = int(last_days)
    today = dt.datetime.utcnow().date()
    for i in range(n):
        d = today - dt.timedelta(days=i)
        p = os.path.join(agg_dir, f"{d.isoformat()}.jsonl")
        if os.path.exists(p):
            files.append(p)
    files.sort()
    out_name = f"last-{n}days.md"

if not files:
    print("(no aggregated data in window)")
    sys.exit(0)

# Counters: per category, per (category, key_attr)
cat_count = Counter()
sig_count = defaultdict(Counter)        # category -> Counter(signature) -> n
sig_projects = defaultdict(lambda: defaultdict(set))  # category -> signature -> {ws_id...}
# v5.0 — cross-machine dimension. sync_learnings.sh + aggregate_learnings.sh
# stamp every record with source_host ("local" or a peer hostname). A
# signature observed on >=2 distinct source_host values in the window is a
# stronger universal signal than one that appears across many projects on
# a single machine — different hardware / installs / users converging on
# the same pattern.
sig_hosts = defaultdict(lambda: defaultdict(set))  # category -> signature -> {source_host...}
total = 0

# Choose a "signature" key per category — the field whose distribution is most
# informative for that category. These are the bits autoresearch cares about.
SIG_KEYS = {
    "permission_pattern":   ["pattern", "snippet"],
    "audit_finding":        ["outcome"],
    "bug_triage":           ["classification"],
    "verify_red":           ["tier", "assertion"],
    "substrate_choice":     ["path"],
    "browser_test_failure": ["outcome", "failing_step"],
    "bug_reproduction":     ["stage"],
    "watchdog_recovery":    ["reason"],
    "spec_drift":           ["state"],
    "resume_after_crash":   ["reason"],
}

def signature(rec):
    cat = rec.get("category", "?")
    keys = SIG_KEYS.get(cat, [])
    parts = []
    for k in keys:
        v = rec.get(k, "")
        if v:
            v_s = str(v)[:80]
            parts.append(f"{k}={v_s}")
    return " | ".join(parts) if parts else "(no signature)"

for f in files:
    with open(f) as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            try:
                rec = json.loads(line)
            except Exception:
                continue
            total += 1
            cat = rec.get("category", "?")
            cat_count[cat] += 1
            sig = signature(rec)
            sig_count[cat][sig] += 1
            ws = rec.get("ws_id", "?")
            sig_projects[cat][sig].add(ws)
            # v5.0 — track distinct source_hosts for cross-machine detection.
            # Default to "local" for legacy aggregated records that pre-date
            # the source_host tag (so old data doesn't get phantom NULL hosts).
            host = rec.get("source_host", "local")
            sig_hosts[cat][sig].add(host)

out_path = os.path.join(dist_dir, out_name)
lines = []
window = month or f"last {last_days} days"
lines.append(f"# Distilled learnings — {window}")
lines.append("")
lines.append(f"Total events: **{total}** across {len(files)} day(s)")
lines.append("")
lines.append("## Category frequencies")
lines.append("")
lines.append("| category | events |")
lines.append("|---|---|")
for cat, n in cat_count.most_common():
    lines.append(f"| `{cat}` | {n} |")
lines.append("")

lines.append("## Top signatures per category")
lines.append("")
for cat, _n in cat_count.most_common():
    lines.append(f"### {cat}")
    lines.append("")
    lines.append("| signature | events | distinct projects | distinct hosts | cross-project? | cross-machine? |")
    lines.append("|---|---|---|---|---|---|")
    for sig, n in sig_count[cat].most_common(8):
        proj_n = len(sig_projects[cat][sig])
        host_n = len(sig_hosts[cat][sig])
        cross_proj = "**YES**" if proj_n >= 2 else "no"
        cross_machine = "**YES**" if host_n >= 2 else "no"
        sig_safe = sig.replace("|", "\\|")
        lines.append(f"| {sig_safe} | {n} | {proj_n} | {host_n} | {cross_proj} | {cross_machine} |")
    lines.append("")

lines.append("## Candidate mutations (priors for autoresearch)")
lines.append("")
lines.append("Two strength tiers feed the proposer:")
lines.append("")
lines.append("1. **cross-machine: YES** — same signature observed on >=2 distinct")
lines.append("   `source_host` values in the window. This is the strongest universal")
lines.append("   signal: different hardware / installs / users converging on the same")
lines.append("   pattern means the issue is in the plugin, not the environment. Feed")
lines.append("   the top 3 cross-machine signatures per category to `propose_via_file.sh`")
lines.append("   FIRST.")
lines.append("")
lines.append("2. **cross-project: YES** (but single-machine) — same signature on >=2")
lines.append("   distinct `ws_id` values within one host. Strong evidence of a systemic")
lines.append("   gap; weaker than cross-machine because it could still be a")
lines.append("   per-machine setup quirk. Use these to round out the top-N if no")
lines.append("   cross-machine signatures exist for a category yet.")
lines.append("")
lines.append("Single-project, single-machine signatures are idiosyncrasies — log them")
lines.append("but don't promote them into priors. The autoresearch loop's quota is")
lines.append("better spent on signals that travel.")
lines.append("")

content = "\n".join(lines)
with open(out_path, "w") as f:
    f.write(content + "\n")
print(content)
print(f"\n[distill] wrote {out_path}", file=sys.stderr)
PY
