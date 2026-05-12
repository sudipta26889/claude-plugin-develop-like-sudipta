#!/usr/bin/env bash
# Eval: scan every bridge script + hook script for bash 4+ features.
# macOS ships /bin/bash 3.2 as default — bridge scripts MUST run there or
# they'll break on every machine that hasn't manually installed bash 5.x.
#
# Patterns detected:
#   declare -A           assoc arrays           (bash 4.0+)
#   ${var,,} / ${var^^}  case transformation    (bash 4.0+)
#   mapfile / readarray  built-in array reader  (bash 4.0+)
#   coproc               coprocess              (bash 4.0+)
#   ${var@Q} / ${var@a}  variable transforms    (bash 4.4+)
#   wait -t              timeout on wait        (bash 5.1+)
#
# Filtering:
#   - Pure-comment lines (^\s*#) are skipped — comments documenting bash 4
#     features as caveats (e.g. `# bash 3.2 compatible — no mapfile.`)
#     wouldn't trigger a real incompatibility.
#   - Heredoc bodies are skipped — strings inside `<<'EOF' … EOF` blocks
#     usually carry data, not executed bash. The state machine tracks
#     a single open heredoc per file; nested heredocs aren't supported
#     in shell anyway.
#   - Symlinks are not followed (defends against bind-mount surprises).
set -uo pipefail

# From evals/, go up to develop-like-sudipta/:
#   evals/ → sd-claude-code-access/ → skills/ → develop-like-sudipta/
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
SCRIPTS_DIR="$ROOT/skills/sd-claude-code-access/scripts"
HOOKS_DIR="$ROOT/hooks/scripts"

# Build the file list — non-symlink *.sh under both dirs.
FILES=$(for d in "$SCRIPTS_DIR" "$HOOKS_DIR"; do
  find "$d" -maxdepth 1 -type f -name '*.sh' 2>/dev/null
done | sort)

if [ -z "$FILES" ]; then
  echo "FAIL: no scripts found to scan (SCRIPTS_DIR=$SCRIPTS_DIR HOOKS_DIR=$HOOKS_DIR)"
  exit 1
fi

python3 - "$FILES" <<'PY'
import os, re, sys

files = sys.argv[1].splitlines()

# Patterns — (regex, friendly-name). Each is anchored against the bash 4+
# feature set documented in the eval header.
patterns = [
    (re.compile(r'\bdeclare\s+-[A-Za-z]*A\b'),       'declare -A'),
    (re.compile(r'\$\{[^}]*,,\}'),                   '${var,,}'),
    (re.compile(r'\$\{[^}]*\^\^\}'),                 '${var^^}'),
    (re.compile(r'(?:^|[^A-Za-z_0-9])mapfile(?:[^A-Za-z_0-9]|$)'),   'mapfile'),
    (re.compile(r'(?:^|[^A-Za-z_0-9])readarray(?:[^A-Za-z_0-9]|$)'), 'readarray'),
    (re.compile(r'(?:^|[^A-Za-z_0-9])coproc(?:[^A-Za-z_0-9]|$)'),    'coproc'),
    (re.compile(r'\$\{[^}]*@Q\}'),                   '${var@Q}'),
    (re.compile(r'\$\{[^}]*@a\}'),                   '${var@a}'),
    # `wait` followed by a short-flag bundle containing `t`. Matches
    # `wait -t`, `wait -tn`, `wait -nt`, etc. Doesn't false-alarm on
    # `wait` alone or `wait $pid`.
    (re.compile(r'\bwait\s+-[a-z]*t\b'),             'wait -t'),
]

COMMENT_RE = re.compile(r'^\s*#')
# Heredoc opener: matches `<<EOF`, `<< 'EOF'`, `<<-EOF`, `<<"EOF"` etc.
# Captures the delimiter token and whether the `<<-` form (tab-stripping)
# was used. Doesn't try to handle multiple heredocs opened on one line —
# none of our scripts do that.
HEREDOC_RE = re.compile(r'<<(-?)\s*[\'"]?(\w+)[\'"]?')

findings = []
for fname in files:
    if not fname:
        continue
    heredoc_delim = None
    heredoc_dash = False
    try:
        with open(fname) as fp:
            for lineno, raw in enumerate(fp, 1):
                line = raw.rstrip('\n')
                if heredoc_delim is not None:
                    check = line.lstrip('\t') if heredoc_dash else line
                    if check == heredoc_delim:
                        heredoc_delim = None
                        heredoc_dash = False
                    continue  # entire heredoc body is opaque to the scan
                if COMMENT_RE.match(line):
                    continue
                # Pattern scan — note we still scan the heredoc-opener line
                # itself, since e.g. `cmd "${var,,}" <<EOF` carries a bash 4
                # feature in the opener even though the body is heredoc data.
                for rx, name in patterns:
                    if rx.search(line):
                        findings.append((fname, lineno, name, line))
                m = HEREDOC_RE.search(line)
                if m:
                    heredoc_delim = m.group(2)
                    heredoc_dash = (m.group(1) == '-')
    except OSError as e:
        print(f"WARN: could not read {fname}: {e}", file=sys.stderr)

if findings:
    print(f"FAIL: {len(findings)} bash 4+ feature usage(s) found:")
    for fname, n, name, line in findings:
        rel = os.path.relpath(fname)
        print(f"  {rel}:{n}: [{name}] {line.strip()[:120]}")
    sys.exit(1)

print(f"PASS  ({len(files)} script(s) scanned, 0 bash 4+ features detected)")
PY
