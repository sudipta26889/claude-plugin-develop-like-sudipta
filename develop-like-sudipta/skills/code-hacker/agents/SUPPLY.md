# 📦 SUPPLY — Supply Chain & Dependency Vulnerabilities

## Mission
Find vulnerable, malicious, or compromised dependencies.

## Automated Scans
```bash
# Python
pip-audit 2>/dev/null || safety check --json 2>/dev/null
pip list --outdated --format=json 2>/dev/null

# Node.js
npm audit --json 2>/dev/null
npx audit-ci --config audit-ci.json 2>/dev/null

# Go
go list -m -json all 2>/dev/null | grep -i "deprecated\|retracted"

# Ruby
bundle audit check 2>/dev/null

# Rust
cargo audit 2>/dev/null
```

## Checklist
- [ ] Known CVEs in direct dependencies
- [ ] Known CVEs in transitive dependencies
- [ ] Lockfile exists AND is committed (.lock, package-lock.json, go.sum)
- [ ] Lockfile integrity (hashes match)
- [ ] Version pinning (exact versions vs ranges like ^1.0.0)
- [ ] Dependency confusion risk (private package names on public registry?)
- [ ] Typosquatting risk (package names similar to popular packages?)
- [ ] Unused dependencies still installed (unnecessary attack surface)
- [ ] Post-install scripts in dependencies (npm lifecycle hooks)
- [ ] Dependency age and maintenance status (abandoned packages?)
- [ ] Number of transitive dependencies (>500 = high risk surface)
- [ ] Vendored dependencies up to date
- [ ] Container base image: official? minimal? recent? scanned?

```bash
# Check for lockfiles
ls -la package-lock.json yarn.lock pnpm-lock.yaml Pipfile.lock poetry.lock \
  go.sum Gemfile.lock Cargo.lock composer.lock 2>/dev/null

# Count dependencies depth
npm ls --all --json 2>/dev/null | python3 -c "
import json,sys
data=json.load(sys.stdin)
def count(d,depth=0):
    n=0
    for v in d.get('dependencies',{}).values():
        n+=1+count(v,depth+1)
    return n
print(f'Total deps: {count(data)}')" 2>/dev/null
```
