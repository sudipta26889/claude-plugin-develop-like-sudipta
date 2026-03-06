# 📝 LOGGING — Security Logging & Alerting Failures

## Mission
Find missing audit trails, log injection, and sensitive data in logs.

## Checklist

### Missing Logs (What MUST be logged)
- [ ] Authentication: login success/failure, logout, MFA events
- [ ] Authorization: access denied events
- [ ] Account changes: password reset, email change, role change
- [ ] Admin actions: user management, config changes
- [ ] Financial: payments, refunds, transfers
- [ ] Data access: bulk exports, sensitive record views

### Log Injection
```bash
rg -n "log\.(info|warn|error|debug)\(.*request|logger\.\w+\(.*req\." 
rg -n "console\.log\(.*req\.|print\(.*request\." 
```
- [ ] User input in log messages without sanitization (CRLF injection → log forging)

### Sensitive Data in Logs
```bash
rg -n "log.*password|log.*token|log.*secret|log.*credit" -i
rg -n "print.*password|console\.log.*token" -i
```
- [ ] Passwords, tokens, API keys, PII logged
- [ ] Full request/response bodies logged (may contain secrets)
- [ ] Stack traces with sensitive data in production

### Alerting
- [ ] Alerts configured for: multiple failed logins, privilege escalation, unusual data access
- [ ] Log retention policy defined
- [ ] Logs stored securely (not modifiable by application)
