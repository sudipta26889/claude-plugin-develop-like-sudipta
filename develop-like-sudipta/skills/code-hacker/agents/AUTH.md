# 🔐 AUTH — Authentication & Session Failures

## Mission
Break every login, session, token, and identity mechanism.

## Checklist

### 1. Password Security
- [ ] Passwords stored in plaintext or reversible encryption
- [ ] Weak hashing (MD5, SHA1, SHA256 without salt) — must be bcrypt/argon2/scrypt
- [ ] No minimum password length/complexity enforcement
- [ ] No rate limiting on login attempts (brute force)
- [ ] No account lockout after failed attempts
- [ ] Password reset token: predictable, no expiry, reusable

### 2. Session Management
- [ ] Session ID in URL (leaks via Referer header)
- [ ] Session not invalidated on logout
- [ ] Session not rotated after login (session fixation)
- [ ] Session timeout too long or absent
- [ ] Missing Secure/HttpOnly/SameSite flags on session cookies

### 3. JWT Vulnerabilities
```bash
rg -n "jwt\.|jsonwebtoken|jose\.|PyJWT" 
rg -n "algorithm.*none|alg.*none|HS256.*RS256" -i
rg -n "verify.*false|verify.*False|algorithms=\[" 
```
- [ ] `none` algorithm accepted (signature bypass)
- [ ] Algorithm confusion (RS256 key used as HS256 secret)
- [ ] Secret key hardcoded or weak (crackable)
- [ ] Token not validated (expiry, issuer, audience)
- [ ] Token stored in localStorage (XSS → token theft)
- [ ] No token revocation mechanism (can't invalidate on logout)
- [ ] Sensitive data in JWT payload (visible to anyone with base64)

### 4. OAuth/OIDC
- [ ] Redirect URI validation: open redirect → token theft
- [ ] State parameter missing (CSRF on OAuth flow)
- [ ] Client secret exposed in frontend code
- [ ] Token exchange without PKCE

### 5. MFA
- [ ] MFA bypass via direct API calls (skip MFA step)
- [ ] MFA code not rate-limited (brute force 6-digit code)
- [ ] MFA code reusable (replay attack)
- [ ] Recovery codes: predictable, not hashed, unlimited use

### 6. Username Enumeration
- [ ] Different error messages for valid vs invalid username
- [ ] Timing differences in login response
- [ ] Registration: "email already taken" reveals accounts
- [ ] Password reset: different behavior for existing vs non-existing emails
