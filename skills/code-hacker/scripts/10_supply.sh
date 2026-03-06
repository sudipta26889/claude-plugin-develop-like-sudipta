#!/usr/bin/env bash
# ☠️ SUPPLY — Supply Chain & Dependency Vulnerabilities
CATEGORY="SUPPLY" source "$(dirname "$0")/_utils.sh"

# Check for lockfiles
for lockfile in package-lock.json yarn.lock pnpm-lock.yaml Pipfile.lock poetry.lock go.sum Gemfile.lock Cargo.lock composer.lock; do
    if [ ! -f "$TARGET/$lockfile" ]; then
        manifest=""
        case "$lockfile" in
            package-lock*) manifest="$TARGET/package.json" ;;
            Pipfile.lock) manifest="$TARGET/Pipfile" ;;
            poetry.lock) manifest="$TARGET/pyproject.toml" ;;
            go.sum) manifest="$TARGET/go.mod" ;;
            Gemfile.lock) manifest="$TARGET/Gemfile" ;;
            Cargo.lock) manifest="$TARGET/Cargo.toml" ;;
            composer.lock) manifest="$TARGET/composer.json" ;;
        esac
        if [ -n "$manifest" ] && [ -f "$manifest" ]; then
            emit_finding "HIGH" "Missing lockfile: $lockfile (manifest exists)" "$manifest" "0" "CWE-1104" "Dependency versions not pinned"
        fi
    fi
done

# npm audit
if [ -f "$TARGET/package.json" ]; then
    cd "$TARGET" && npm audit --json 2>/dev/null | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    vulns = data.get('vulnerabilities', {})
    for name, info in vulns.items():
        sev = info.get('severity', 'info').upper()
        if sev == 'MODERATE': sev = 'MEDIUM'
        via = ', '.join(str(v) if isinstance(v,str) else v.get('title','') for v in info.get('via',[])[:3])
        print(json.dumps({
            'category': 'SUPPLY', 'severity': sev,
            'title': f'npm: {name} - {via}',
            'cwe': 'CWE-1104',
        }))
except: pass
" 2>/dev/null || true
fi

# pip-audit
if [ -f "$TARGET/requirements.txt" ]; then
    pip-audit -r "$TARGET/requirements.txt" --format json 2>/dev/null | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    for vuln in data.get('dependencies', []):
        for v in vuln.get('vulns', []):
            print(json.dumps({
                'category': 'SUPPLY', 'severity': 'HIGH',
                'title': f'pip: {vuln[\"name\"]} {v[\"id\"]}',
                'cwe': 'CWE-1104',
                'description': v.get('description', '')[:200],
            }))
except: pass
" 2>/dev/null || true
fi

# Version ranges (not pinned)
if [ -f "$TARGET/package.json" ]; then
    unpinned=$(python3 -c "
import json
data = json.load(open('$TARGET/package.json'))
for section in ['dependencies', 'devDependencies']:
    for pkg, ver in data.get(section, {}).items():
        if ver.startswith('^') or ver.startswith('~') or ver == '*' or ver == 'latest':
            print(f'{pkg}: {ver}')
" 2>/dev/null | wc -l)
    [ "$unpinned" -gt 0 ] && emit_finding "MEDIUM" "npm: ${unpinned} dependencies with version ranges (not pinned)" "$TARGET/package.json" "0" "CWE-1104"
fi
