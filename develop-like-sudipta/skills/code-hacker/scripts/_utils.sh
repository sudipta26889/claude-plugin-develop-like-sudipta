#!/usr/bin/env bash
# ☠️ CODE HACKER — Shared Utilities
# Source this in every scan script: source "$(dirname "$0")/_utils.sh"

set -euo pipefail

TARGET="${1:-.}"
CATEGORY="${CATEGORY:-UNKNOWN}"

# Validate target directory
if [ ! -d "$TARGET" ]; then
    echo "ERROR: TARGET '$TARGET' is not a valid directory" >&2
    exit 1
fi
TARGET="$(cd "$TARGET" && pwd)"  # Resolve to absolute path

# Color codes (for terminal output, stripped in JSON)
RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'
BLUE='\033[0;34m'; NC='\033[0m'

# Use ripgrep if available, else grep
if command -v rg &>/dev/null; then
    SEARCH="rg"
    SEARCH_OPTS="--no-heading --line-number --with-filename"
else
    SEARCH="grep"
    SEARCH_OPTS="-rn --include='*.py' --include='*.js' --include='*.ts' \
      --include='*.go' --include='*.java' --include='*.php' --include='*.rb' \
      --include='*.rs' --include='*.cs' --include='*.yaml' --include='*.yml' \
      --include='*.json' --include='*.xml' --include='*.html' --include='*.jsx' \
      --include='*.tsx' --include='*.vue'"
fi

# Directories to skip
SKIP_DIRS="node_modules|vendor|venv|\.venv|__pycache__|\.git|dist|build|\.next|\.nuxt|target|bin|obj"

emit_finding() {
    local severity="$1"
    local title="$2"
    local file="${3:-}"
    local line="${4:-0}"
    local cwe="${5:-}"
    local description="${6:-}"

    # JSON output — use Python with env vars (no shell interpolation into Python code)
    EMIT_SEVERITY="$severity" EMIT_CATEGORY="$CATEGORY" \
    python3 -c "
import json, os, sys
f = {
    'category': os.environ['EMIT_CATEGORY'],
    'severity': os.environ['EMIT_SEVERITY'],
    'title': sys.argv[1],
    'file': sys.argv[2] if sys.argv[2] else None,
    'line': int(sys.argv[3]) if sys.argv[3] != '0' else None,
    'cwe': sys.argv[4] if sys.argv[4] else None,
    'description': sys.argv[5] if sys.argv[5] else None,
}
f = {k:v for k,v in f.items() if v is not None}
print(json.dumps(f))
" "$title" "$file" "$line" "$cwe" "$description" 2>/dev/null || {
        echo "{\"category\":\"${CATEGORY}\",\"severity\":\"${severity}\",\"title\":\"finding\"}" >&2
        return 1
    }
}

search_pattern() {
    local pattern="$1"
    local file_types="${2:-}"
    local extra_opts="${3:-}"

    if [ "$SEARCH" = "rg" ]; then
        rg $SEARCH_OPTS $file_types $extra_opts \
            -g "!{${SKIP_DIRS}}" \
            "$pattern" "$TARGET" 2>/tmp/hack_search_err.log || {
            local exit_code=$?
            if [ $exit_code -ne 1 ]; then  # 1 = no matches (normal)
                echo "SEARCH_ERROR: rg exited $exit_code for pattern '$pattern'" >&2
            fi
        }
    else
        grep $SEARCH_OPTS $extra_opts \
            --exclude-dir="{${SKIP_DIRS}}" \
            -E "$pattern" "$TARGET" 2>/tmp/hack_search_err.log || {
            local exit_code=$?
            if [ $exit_code -ne 1 ]; then
                echo "SEARCH_ERROR: grep exited $exit_code for pattern '$pattern'" >&2
            fi
        }
    fi
}

count_matches() {
    local pattern="$1"
    local file_types="${2:-}"
    search_pattern "$pattern" "$file_types" | wc -l
}

# Parse search results into findings
# Usage: search_and_emit "pattern" "SEVERITY" "Title" "CWE-XXX" "Description" "--type py"
search_and_emit() {
    local pattern="$1"
    local severity="$2"
    local title="$3"
    local cwe="${4:-}"
    local description="${5:-}"
    local file_types="${6:-}"

    while IFS=: read -r file line_num rest; do
        [ -z "$file" ] && continue
        emit_finding "$severity" "$title: $rest" "$file" "$line_num" "$cwe" "$description"
    done < <(search_pattern "$pattern" "$file_types" | head -50)
}
