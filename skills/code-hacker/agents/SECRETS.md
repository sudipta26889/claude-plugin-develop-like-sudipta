# 🔑 SECRETS — Hardcoded Credentials & Secret Exposure

## Mission
Find every secret that should never be in source code.

## Detection Patterns
```bash
# API Keys & Tokens
rg -n "(api[_-]?key|apikey|api[_-]?secret)\s*[:=]" -i
rg -n "(access[_-]?key|secret[_-]?key|auth[_-]?token)\s*[:=]" -i
rg -n "(AKIA[0-9A-Z]{16})" # AWS Access Key
rg -n "(ghp_[a-zA-Z0-9]{36}|github_pat_)" # GitHub token
rg -n "sk[-_]live[-_][a-zA-Z0-9]+" # Stripe secret key
rg -n "xox[bpsa]-[a-zA-Z0-9-]+" # Slack tokens
rg -n "AIza[0-9A-Za-z_-]{35}" # Google API key

# Passwords
rg -n "(password|passwd|pwd)\s*[:=]\s*['\"][^'\"]{3,}" -i
rg -n "DB_PASSWORD|DATABASE_URL.*:.*@" -i

# Private Keys
rg -n "BEGIN (RSA |EC |DSA |OPENSSH )?PRIVATE KEY"
rg -n "BEGIN CERTIFICATE"

# Connection Strings
rg -n "(mongodb|mysql|postgres|redis)://[^/\s]+" -i
rg -n "jdbc:[a-z]+://[^/\s]+"

# JWT Secrets
rg -n "(jwt[_-]?secret|signing[_-]?key|token[_-]?secret)\s*[:=]" -i
```

## Checklist
- [ ] Secrets in source code files (not just config)
- [ ] Secrets in config files committed to git
- [ ] .env files committed (check .gitignore)
- [ ] Secrets in docker-compose.yml, Dockerfile, k8s manifests
- [ ] Secrets in CI/CD configs (.github/workflows, .gitlab-ci.yml, Jenkinsfile)
- [ ] Secrets in test files (even "test" secrets may be real)
- [ ] Secrets in comments (old credentials commented out)
- [ ] Default credentials in config files
- [ ] Secrets in client-side code (JS bundles, mobile apps)
- [ ] Secrets in log output (logged tokens, passwords)
- [ ] Git history: secrets removed from HEAD but in old commits
```bash
git log --all --diff-filter=D -- "*.env" ".env*" "*.pem" "*.key"
git log -p --all -S "password" --source -- "*.py" "*.js" "*.go" | head -100
```
