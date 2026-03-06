# Security Reference

Detailed security guidance for Pillar 4. Read this when implementing auth, handling user input, configuring headers, or setting up security scanning.

## OWASP Top 10 (2021) — Mitigation Checklist

| # | Risk | Mitigation | Enforcement |
|---|------|------------|-------------|
| A01 | Broken Access Control | Deny by default; server-side RBAC; invalidate JWT on logout; re-validate on every request | ArchUnit/access control tests |
| A02 | Cryptographic Failures | TLS 1.2+; bcrypt/argon2 for passwords (never MD5/SHA1); rotate keys | SSL config audit; CI check for weak hashing |
| A03 | Injection (incl. XSS) | Parameterized queries; escape output; CSP headers; sanitize HTML | SAST rules; Zod/Pydantic input validation |
| A04 | Insecure Design | Threat model during planning; abuse case tests; rate limit auth endpoints | Threat model in plan file; rate limit middleware |
| A05 | Security Misconfiguration | Automate hardening; remove default creds; disable unused features; error messages don't leak internals | IaC config scans; checklist in deploy pipeline |
| A06 | Vulnerable Components | Dependabot/Renovate; Snyk/Trivy in CI; patch CRITICAL in 24h, HIGH in 7d | CI gate blocking on severity thresholds |
| A07 | Auth Failures | MFA where possible; rate limit login (5 attempts/15min); NIST 800-63B passwords | Rate limit middleware; auth integration tests |
| A08 | Integrity Failures | Verify artifact signatures; secure CI/CD pipeline; generate SBOM | Cosign/Sigstore; SLSA Level 2 target |
| A09 | Logging Failures | Log all auth events; SIEM integration; alerting on anomalies; tamper-proof log storage | Structured logging middleware; alert rules |
| A10 | SSRF | Validate/allowlist URLs; block internal IPs; network segmentation | URL validation middleware; firewall rules |

## Input Validation Patterns

### Python (FastAPI + Pydantic)

```python
from pydantic import BaseModel, Field, EmailStr, field_validator
from typing import Annotated

class CreateUserRequest(BaseModel):
    """Validates user creation input at API boundary."""
    email: EmailStr
    name: str = Field(min_length=2, max_length=100, pattern=r"^[a-zA-Z\s\-']+$")
    age: int = Field(ge=13, le=150)

    @field_validator("name")
    @classmethod
    def sanitize_name(cls, v: str) -> str:
        # WHY: Strip control characters that could exploit downstream rendering
        return "".join(c for c in v if c.isprintable())

# In route — Pydantic validates automatically
@router.post("/users", response_model=UserResponse, status_code=201)
async def create_user(
    request: CreateUserRequest,  # Validated before handler executes
    service: UserService = Depends(get_user_service),
) -> UserResponse:
    return await service.create(request)
```

### TypeScript (Zod)

```typescript
import { z } from "zod";

const CreateUserSchema = z.object({
  email: z.string().email(),
  name: z.string().min(2).max(100).regex(/^[a-zA-Z\s\-']+$/),
  age: z.number().int().min(13).max(150),
});

type CreateUserInput = z.infer<typeof CreateUserSchema>;

// In handler — validate before processing
const parsed = CreateUserSchema.safeParse(req.body);
if (!parsed.success) {
  return res.status(422).json({ errors: parsed.error.flatten() });
}
```

## JWT Implementation Standards

```python
# Access token — short-lived
ACCESS_TOKEN_CONFIG = {
    "algorithm": "RS256",        # Asymmetric — public key verifies, private key signs
    "expiry": timedelta(minutes=15),
    "issuer": "api.yourapp.com",
    "audience": "yourapp-client",
}

# Refresh token — longer-lived, rotated on use
REFRESH_TOKEN_CONFIG = {
    "algorithm": "RS256",
    "expiry": timedelta(days=7),
    "rotation": True,            # Issue new refresh token on each use
    "family_tracking": True,     # Detect token reuse (compromise signal)
}

# Cookie settings (preferred over localStorage)
COOKIE_CONFIG = {
    "httponly": True,    # JavaScript cannot access
    "secure": True,      # HTTPS only
    "samesite": "Lax",  # CSRF protection
    "path": "/api",      # Scope to API routes only
}
```

**Validation on every request:**
```python
async def validate_token(token: str) -> TokenPayload:
    """
    WHY: Every request must re-validate to catch revoked tokens,
    expired sessions, and tampered payloads.
    """
    payload = jwt.decode(
        token,
        public_key,
        algorithms=["RS256"],
        issuer="api.yourapp.com",
        audience="yourapp-client",
        options={"require": ["exp", "iss", "aud", "sub"]},
    )
    # Check token not in revocation list (logout, password change)
    if await is_revoked(payload["jti"]):
        raise HTTPException(401, "Token revoked")
    return TokenPayload(**payload)
```

## Security Headers Configuration

```python
# FastAPI middleware
from starlette.middleware import Middleware
from starlette.responses import Response

@app.middleware("http")
async def security_headers(request: Request, call_next):
    response = await call_next(request)
    response.headers["Content-Security-Policy"] = (
        "default-src 'self'; "
        "script-src 'self'; "
        "style-src 'self' 'unsafe-inline'; "
        "img-src 'self' data: https:; "
        "frame-ancestors 'none'"
    )
    response.headers["Strict-Transport-Security"] = "max-age=63072000; includeSubDomains; preload"
    response.headers["X-Frame-Options"] = "DENY"
    response.headers["X-Content-Type-Options"] = "nosniff"
    response.headers["Referrer-Policy"] = "strict-origin-when-cross-origin"
    response.headers["Permissions-Policy"] = "camera=(), microphone=(), geolocation=()"
    return response
```

## SAST/DAST Pipeline Integration

```yaml
# GitHub Actions example
security-scan:
  runs-on: ubuntu-latest
  steps:
    - uses: actions/checkout@v4

    # SAST — Static Analysis
    - name: Run Semgrep
      uses: semgrep/semgrep-action@v1
      with:
        config: p/owasp-top-ten p/python p/typescript

    # Dependency scanning
    - name: Run Trivy
      uses: aquasecurity/trivy-action@master
      with:
        scan-type: fs
        severity: HIGH,CRITICAL
        exit-code: 1  # Fail pipeline on findings

    # Secret detection
    - name: Run Gitleaks
      uses: gitleaks/gitleaks-action@v2

    # DAST — Dynamic Analysis (on staging only)
    - name: Run OWASP ZAP (staging)
      if: github.ref == 'refs/heads/staging'
      uses: zaproxy/action-full-scan@v0.10
      with:
        target: https://staging.yourapp.com
```

## Remediation SLAs

| Severity | Deadline | Action |
|----------|----------|--------|
| CRITICAL | 24 hours | Hotfix, emergency deploy |
| HIGH | 7 days | Next sprint priority |
| MEDIUM | 30 days | Backlog, planned sprint |
| LOW | 90 days | Best-effort cleanup |

## Secret Management Hierarchy

```
Development:  .env file (gitignored) + .env.example (committed, empty values)
CI/CD:        GitHub Secrets / GitLab CI Variables (encrypted at rest)
Staging:      Cloud Secret Manager (versioned, audited)
Production:   Cloud Secret Manager + automatic rotation where supported
```

**Pre-commit hook (git-secrets):**
```bash
# .pre-commit-config.yaml
- repo: https://github.com/awslabs/git-secrets
  hooks:
    - id: git-secrets
      stages: [pre-commit]
```

## Key Rotation Implementation

Every secret must have a rotation plan:

| Secret Type | Rotation Interval | Method |
|------------|-------------------|--------|
| API keys | 90 days | Automated via vault policy |
| JWT signing keys | 180 days | Dual-key overlap (old key valid 24h after rotation) |
| Database passwords | 90 days | Automated via cloud provider |
| TLS certificates | Auto (Let's Encrypt) | certbot auto-renew |
| Service account tokens | 60 days | Kubernetes secret rotation |

**Rotation procedure:**
1. Generate new secret
2. Deploy new secret alongside old (dual-active window)
3. Verify all services use new secret
4. Revoke old secret after grace period (24h minimum)
5. Audit log: record rotation timestamp, rotator identity, affected services

## CORS Configuration

```python
# FastAPI example
from fastapi.middleware.cors import CORSMiddleware

app.add_middleware(
    CORSMiddleware,
    allow_origins=["https://app.example.com"],  # NEVER use ["*"] in production
    allow_credentials=True,
    allow_methods=["GET", "POST", "PUT", "DELETE"],
    allow_headers=["Authorization", "Content-Type"],
    max_age=3600,
)
```

**Rules:**
- Never `allow_origins=["*"]` with `allow_credentials=True`
- Whitelist specific origins, not wildcards
- Restrict methods to what's actually needed

## Webhook Signature Verification

Always verify webhook signatures before processing:

```python
import hmac
import hashlib

def verify_webhook(payload: bytes, signature: str, secret: str) -> bool:
    expected = hmac.new(secret.encode(), payload, hashlib.sha256).hexdigest()
    return hmac.compare_digest(f"sha256={expected}", signature)
```

**Rules:**
- Use `hmac.compare_digest()` (constant-time comparison) — never `==`
- Verify BEFORE parsing the payload
- Reject requests with missing or invalid signatures with HTTP 401
- Log all verification failures

## Password Reset Security

1. **Token generation:** cryptographically random, ≥32 bytes, single-use
2. **Token expiry:** 15 minutes maximum
3. **Rate limiting:** max 3 reset requests per email per hour
4. **Response:** always return "If an account exists, a reset email has been sent" (prevent enumeration)
5. **Invalidation:** invalidate all existing tokens when a new one is generated
6. **Notification:** email user on successful password change
