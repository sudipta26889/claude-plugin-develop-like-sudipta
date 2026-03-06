#!/usr/bin/env bash
# ☠️ SECRETS — Hardcoded Credentials & Secret Exposure
CATEGORY="SECRETS" source "$(dirname "$0")/_utils.sh"

# AWS Keys
search_and_emit 'AKIA[0-9A-Z]{16}' "CRITICAL" "AWS Access Key ID exposed" "CWE-798" "Hardcoded AWS credential"

# Generic API Keys
search_and_emit '(api[_-]?key|apikey)\s*[:=]\s*["\x27][a-zA-Z0-9_-]{20,}' "HIGH" "API Key hardcoded" "CWE-798" "Secret in source code"
search_and_emit '(secret[_-]?key|auth[_-]?token)\s*[:=]\s*["\x27][a-zA-Z0-9_-]{10,}' "HIGH" "Secret/Token hardcoded" "CWE-798" ""

# Passwords
search_and_emit '(password|passwd|pwd)\s*[:=]\s*["\x27][^"\x27]{3,}' "HIGH" "Password hardcoded" "CWE-798" "Credential in source code"

# Connection strings with credentials
search_and_emit '(mongodb|mysql|postgres|redis)://[^/\s]*:[^/\s]*@' "CRITICAL" "Database connection string with credentials" "CWE-798" ""

# Private keys
search_and_emit 'BEGIN (RSA |EC |DSA |OPENSSH )?PRIVATE KEY' "CRITICAL" "Private key in codebase" "CWE-321" ""

# Platform-specific tokens
search_and_emit 'ghp_[a-zA-Z0-9]{36}|github_pat_' "CRITICAL" "GitHub token exposed" "CWE-798" ""
search_and_emit 'sk[-_]live[-_][a-zA-Z0-9]+' "CRITICAL" "Stripe secret key exposed" "CWE-798" ""
search_and_emit 'xox[bpsa]-[a-zA-Z0-9-]+' "HIGH" "Slack token exposed" "CWE-798" ""
search_and_emit 'AIza[0-9A-Za-z_-]{35}' "HIGH" "Google API key exposed" "CWE-798" ""

# .env files
for envfile in $(find "$TARGET" -name ".env" -o -name ".env.local" -o -name ".env.production" 2>/dev/null | head -10); do
    emit_finding "HIGH" ".env file found in codebase" "$envfile" "0" "CWE-538" "Environment file may contain secrets"
done

# JWT secrets
search_and_emit '(jwt[_-]?secret|signing[_-]?key|token[_-]?secret)\s*[:=]\s*["\x27]' "HIGH" "JWT secret hardcoded" "CWE-798" ""
