# ⚙️ CONFIG — Security Misconfiguration & Insecure Defaults

## Mission
Find every dangerous default, exposed debug interface, and missing security header.

## Checklist

### 1. Debug/Development Mode
```bash
rg -n "DEBUG\s*=\s*True|debug:\s*true|NODE_ENV.*dev" -i
rg -n "FLASK_DEBUG|DJANGO_DEBUG|app\.debug" 
```
- [ ] Debug mode enabled in production configs
- [ ] Stack traces exposed to users
- [ ] Debug endpoints accessible (/debug, /__debug__, /actuator)

### 2. CORS
```bash
rg -n "Access-Control-Allow-Origin.*\*|cors\(.*origin.*\*|CORS_ALLOW_ALL"
rg -n "Access-Control-Allow-Credentials.*true" 
```
- [ ] CORS Allow-Origin: * with credentials
- [ ] Overly permissive CORS (reflects Origin header)

### 3. Security Headers
- [ ] Content-Security-Policy missing
- [ ] X-Content-Type-Options: nosniff missing
- [ ] X-Frame-Options missing (clickjacking)
- [ ] Strict-Transport-Security missing
- [ ] Referrer-Policy missing
- [ ] Permissions-Policy missing

### 4. Default Credentials
```bash
rg -n "admin:admin|root:root|test:test|password:password|default.*password" -i
rg -n "changeme|p@ssw0rd|123456|qwerty" -i
```

### 5. Exposed Services
- [ ] Database ports in docker-compose without bind to localhost
- [ ] Redis/Memcached exposed without auth
- [ ] Admin panels without IP restriction
- [ ] Swagger/OpenAPI docs in production
- [ ] Health check endpoints leaking sensitive info

### 6. TLS Configuration
- [ ] HTTP endpoints without redirect to HTTPS
- [ ] Mixed content (HTTPS page loading HTTP resources)
- [ ] Certificate validation disabled
