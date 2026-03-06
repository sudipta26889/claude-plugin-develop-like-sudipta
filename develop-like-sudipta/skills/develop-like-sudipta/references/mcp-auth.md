# MCP Server Authentication — OAuth 2.0 with 2.1 Enhancements Pattern

**Standard:** All MCP servers MUST use OAuth 2.0 with 2.1 enhancements (PKCE mandatory, implicit flow removed) for authentication.
No API keys. No basic auth. No custom token schemes.

Based on production implementation: Slack-Agent MCP Server.

---

## Architecture Overview

```
Client                    MCP Server                     Auth Server (same app)
  │                           │                                │
  ├── GET /.well-known/oauth-authorization-server ────────────►│  (1) Discovery
  │◄──────────────── metadata (endpoints, scopes) ────────────┤
  │                           │                                │
  ├── POST /mcp/oauth/register ───────────────────────────────►│  (2) Dynamic Registration
  │◄──────────────── client_id (+secret if confidential) ─────┤
  │                           │                                │
  ├── GET /mcp/oauth/authorize?code_challenge=...&state=... ──►│  (3) Authorization + PKCE
  │◄──────────────── 302 → consent screen ────────────────────┤
  │── user approves ──►       │                                │
  │◄──────────────── 302 → redirect_uri?code=...&state=... ──┤
  │                           │                                │
  ├── POST /mcp/oauth/token (code + code_verifier) ──────────►│  (4) Token Exchange
  │◄──────────────── access_token + refresh_token ────────────┤
  │                           │                                │
  ├── POST /mcp (Bearer token) ──►│                            │  (5) Use MCP
  │◄──────────────── JSON-RPC response ──┤                     │
  │                           │                                │
  ├── POST /mcp/oauth/token (refresh_token) ──────────────────►│  (6) Token Rotation
  │◄──────────────── new access_token + new refresh_token ────┤
  │                           │                                │
  ├── POST /mcp/oauth/revoke ─────────────────────────────────►│  (7) Revocation
  │◄──────────────── 200 (always) ────────────────────────────┤
```

---

## Required Endpoints (7 total)

### 1. Discovery — RFC 8414 + RFC 9728

> **HTTPS REQUIRED:** All OAuth endpoints (authorization, token, discovery) MUST use HTTPS in production. HTTP is acceptable only in local development with explicit `--insecure` flag.

```python
# /.well-known/oauth-authorization-server
{
    "issuer": BASE_URL,
    "authorization_endpoint": f"{BASE_URL}/mcp/oauth/authorize",
    "token_endpoint": f"{BASE_URL}/mcp/oauth/token",
    "registration_endpoint": f"{BASE_URL}/mcp/oauth/register",
    "revocation_endpoint": f"{BASE_URL}/mcp/oauth/revoke",
    "response_types_supported": ["code"],
    "grant_types_supported": ["authorization_code", "refresh_token"],
    "code_challenge_methods_supported": ["S256"],  # ONLY S256
    "token_endpoint_auth_methods_supported": ["none", "client_secret_post"],
    "scopes_supported": ["<service>:read", "<service>:write"],
}

# /.well-known/oauth-protected-resource
{
    "resource": RESOURCE_URL,
    "authorization_servers": [ISSUER_URL],
    "scopes_supported": ["<service>:read", "<service>:write"],
    "bearer_methods_supported": ["header"],
}
```

### 2. Dynamic Client Registration — RFC 7591

```python
@router.post("/mcp/oauth/register")
async def register_client(request: ClientRegistrationRequest):
    # Public client (CLI, desktop app): token_endpoint_auth_method = "none"
    # Confidential client (server-side): gets client_secret
    #
    # client_id strategy:
    #   - Production: use origin URL (e.g., "https://example.com")
    #   - Localhost/dev: generate random ID (secrets.token_urlsafe(16))
    #
    # Returns: client_id, client_id_issued_at, redirect_uris, grant_types
```

**Request model:**
```python
class ClientRegistrationRequest(BaseModel):
    redirect_uris: list[str]       # Allowed callback URLs
    client_name: str                # Human-readable name
    grant_types: list[str] = ["authorization_code", "refresh_token"]
    token_endpoint_auth_method: str = "none"  # "none" for public clients
```

### 3. Authorization Endpoint — PKCE Mandatory

```python
@router.get("/mcp/oauth/authorize")
async def authorize(
    response_type: str,        # MUST be "code"
    client_id: str,
    redirect_uri: str,
    scope: str,
    state: Optional[str],      # CSRF protection
    code_challenge: str,       # REQUIRED per OAuth 2.1
    code_challenge_method: str = "S256",  # ONLY S256
):
    # Validate: response_type == "code"
    # Validate: code_challenge present (reject if missing)
    # Validate: code_challenge_method == "S256" (reject "plain")
    # Encode params → redirect to consent screen
    # After user approves → redirect to redirect_uri?code=...&state=...
```

**Hard rules:**
- PKCE is MANDATORY. No code_challenge = reject with `invalid_request`.
- Only S256 method. "plain" is explicitly disallowed per OAuth 2.1.
- Only "code" response_type. No implicit flow.

### 4. PKCE Implementation — RFC 7636

```python
# auth/pkce.py — Three functions, that's it.

import base64, hashlib, secrets

def generate_code_verifier(length: int = 43) -> str:
    """43-128 chars, cryptographically random, URL-safe."""
    if not 43 <= length <= 128:
        raise ValueError("Code verifier length must be between 43 and 128")
    random_bytes = secrets.token_bytes((length * 3 // 4) + 3)
    return base64.urlsafe_b64encode(random_bytes).decode().rstrip("=")[:length]

def generate_code_challenge(verifier: str, method: str = "S256") -> str:
    """SHA-256 hash of verifier, base64url encoded, no padding."""
    if method != "S256":
        raise ValueError(f"Only S256 supported per OAuth 2.1, got: {method}")
    digest = hashlib.sha256(verifier.encode("ascii")).digest()
    return base64.urlsafe_b64encode(digest).decode().rstrip("=")

def verify_code_challenge(verifier: str, challenge: str, method: str = "S256") -> bool:
    """Timing-safe comparison to prevent timing attacks."""
    if method != "S256":
        return False
    expected = generate_code_challenge(verifier, method)
    return secrets.compare_digest(expected, challenge)  # MUST be timing-safe
```

**PKCE rejection logic:**
If `code_verifier` is missing or `SHA256(code_verifier) != code_challenge`:
- Return HTTP 400 with `{"error": "invalid_grant", "error_description": "PKCE verification failed"}`
- Log the attempt with client_id and timestamp
- Do NOT reveal whether the code_challenge was found or not (prevents enumeration)

### 5. Token Endpoint — Exchange + Rotation

Two grant types:

**authorization_code grant:**
```python
# POST /mcp/oauth/token (application/x-www-form-urlencoded)
# grant_type=authorization_code
# code=<auth_code>
# redirect_uri=<must match original>
# client_id=<client_id>
# code_verifier=<PKCE verifier>

# Server validates:
# 1. Auth code exists + not used + not expired
# 2. client_id matches original request
# 3. redirect_uri matches original request
# 4. PKCE: verify_code_challenge(code_verifier, stored_challenge, "S256")
# 5. Mark code as used (single-use)
# 6. Issue tokens

# Response:
{
    "access_token": secrets.token_urlsafe(32),
    "token_type": "Bearer",
    "expires_in": 3600,           # Configurable TTL
    "refresh_token": secrets.token_urlsafe(32),
    "scope": "service:read"
}
```

**refresh_token grant (with rotation):**
```python
# grant_type=refresh_token
# refresh_token=<old_refresh_token>
# client_id=<client_id>

# Server:
# 1. Find old token, validate not expired
# 2. Validate client_id matches
# 3. DELETE old token (rotation — old refresh token invalidated)
# 4. Issue NEW access_token + NEW refresh_token
# 5. Return new token pair
```

**Token rotation is mandatory.** Old refresh tokens are deleted on use.

### 6. Token Revocation — RFC 7009

```python
@router.post("/mcp/oauth/revoke")
async def revoke(token: str, token_type_hint: Optional[str] = None):
    # Try delete by hint first, then try both columns
    # ALWAYS return 200 (even for unknown/already-revoked tokens)
    return {}
```

### 7. Bearer Token Authentication

```python
# auth/bearer.py — FastAPI dependency injection pattern

class MCPUser(BaseModel):
    user_id: str
    user_email: Optional[str] = None
    scope: str                    # Space-separated scopes
    client_id: str

security = HTTPBearer(auto_error=False)

async def get_current_user(
    credentials: Optional[HTTPAuthorizationCredentials] = Depends(security),
) -> MCPUser:
    """Validate bearer token → return MCPUser or 401."""
    if not credentials:
        raise HTTPException(401, "Missing authorization header",
                           headers={"WWW-Authenticate": "Bearer"})
    # Lookup token in DB, check expiration, return MCPUser

def require_scope(required_scope: str):
    """Dependency factory for scope-based authorization."""
    async def checker(user: MCPUser = Depends(get_current_user)) -> MCPUser:
        if required_scope not in user.scope.split():
            raise HTTPException(403, f"Required scope: {required_scope}")
        return user
    return checker
```

**Usage in endpoints:**
```python
@router.post("/mcp")
async def mcp_endpoint(user: MCPUser = Depends(get_current_user)):
    # user is authenticated, check scope for tool access
    pass

@router.post("/write-endpoint")
async def write_endpoint(user: MCPUser = Depends(require_scope("service:write"))):
    # user is authenticated AND has write scope
    pass
```

---

## MCP Transport Layer

### HTTP Transport (Simple)

```
POST /mcp (Bearer token in Authorization header)
Body: JSON-RPC 2.0 request
Response: JSON-RPC 2.0 response
```

### SSE Transport (Streaming)

```
1. GET  /mcp/sse (Bearer token) → SSE stream opens
   ← event: endpoint, data: http://server/mcp/messages?session_id=xxx
2. POST /mcp/messages?session_id=xxx → JSON-RPC request
   ← Response sent via SSE stream as event: message
3. Server sends keepalive pings every 30s
```

SSE session management:
```python
@dataclass
class SSESession:
    session_id: str        # UUID
    user_id: str           # From bearer token
    scope: str             # From bearer token
    client_id: str         # From bearer token
    message_queue: asyncio.Queue  # Responses queued here
```

---

## Database Models (3 tables)

```python
class MCPClient(Base):        # Registered OAuth clients
    client_id: str            # PK — origin URL or random ID
    client_secret_hash: str   # Null for public clients
    client_name: str
    redirect_uris: str        # JSON array
    grant_types: str          # JSON array
    token_endpoint_auth_method: str

class MCPAuthCode(Base):      # Authorization codes (short-lived)
    code: str                 # PK — secrets.token_urlsafe(32)
    client_id: str            # FK → MCPClient
    redirect_uri: str
    scope: str
    user_id: str
    user_email: str
    code_challenge: str       # PKCE challenge
    code_challenge_method: str  # Always "S256"
    used: bool = False        # Single-use enforcement
    expires_at: datetime      # Short TTL (10 min)

class MCPToken(Base):         # Access + refresh tokens
    access_token: str         # PK — secrets.token_urlsafe(32)
    refresh_token: str        # secrets.token_urlsafe(32)
    client_id: str            # FK → MCPClient
    user_id: str
    user_email: str
    scope: str
    access_token_expires_at: datetime   # Configurable (default 1h)
    refresh_token_expires_at: datetime  # Configurable (default 30d)
```

---

## File Structure (Reference)

```
services/mcp-server/
├── mcp_server/
│   ├── main.py                    # FastAPI app + lifespan
│   ├── auth/
│   │   ├── __init__.py            # Exports: PKCE + Bearer
│   │   ├── pkce.py                # generate/verify code challenge
│   │   └── bearer.py              # MCPUser, get_current_user, require_scope
│   ├── routes/
│   │   ├── metadata.py            # .well-known endpoints
│   │   ├── oauth.py               # register, authorize, token, revoke
│   │   └── mcp.py                 # HTTP + SSE transport, JSON-RPC dispatch
│   ├── transports/
│   │   ├── http.py                # JSONRPCRequest/Response models
│   │   └── sse.py                 # SSESession, SSESessionManager
│   └── tools/
│       ├── definitions.py         # Tool schemas, scope filtering
│       └── handlers.py            # Tool implementations
└── tests/
    ├── test_oauth.py              # OAuth endpoint tests
    ├── test_pkce.py               # PKCE unit tests
    ├── test_mcp_transport.py      # Transport tests
    └── test_mcp_oauth_flow.py     # Integration tests
```

---

## Security Checklist

| Requirement | Implementation |
|---|---|
| PKCE mandatory | Reject authorize without code_challenge |
| S256 only | Reject "plain" method |
| No implicit flow | Only response_type="code" |
| Single-use auth codes | Mark `used=True` after exchange |
| Auth code expiration | Short TTL (10 min) |
| Token rotation | Delete old refresh token on use |
| Timing-safe comparison | `secrets.compare_digest()` for PKCE verify |
| Bearer token in header only | HTTPBearer scheme, no query params |
| Scope-based access | Tools filtered by user's OAuth scope |
| Revocation always 200 | Per RFC 7009, no information leak |
| Token hashing | Store hashed tokens, not plaintext (production) |
| CORS | Configured per deployment |

---

## RFCs Referenced

| RFC | What | Where Used |
|---|---|---|
| OAuth 2.1 (draft) | Core framework | Entire flow |
| RFC 7636 | PKCE | `auth/pkce.py` |
| RFC 7591 | Dynamic Client Registration | `POST /mcp/oauth/register` |
| RFC 8414 | Authorization Server Metadata | `/.well-known/oauth-authorization-server` |
| RFC 9728 | Protected Resource Metadata | `/.well-known/oauth-protected-resource` |
| RFC 6750 | Bearer Token Usage | `auth/bearer.py` |
| RFC 7009 | Token Revocation | `POST /mcp/oauth/revoke` |
| JSON-RPC 2.0 | Message format | `transports/http.py` |

---

## Anti-Patterns (NEVER do these)

| Anti-Pattern | Why | Correct |
|---|---|---|
| API key in header | No rotation, no scoping, no revocation | OAuth 2.1 bearer token |
| Basic auth | Credentials sent every request | Authorization code + PKCE |
| Token in query string | Logged in server logs, browser history | Authorization header only |
| "plain" PKCE method | No security benefit over no PKCE | S256 only |
| Reusable auth codes | Replay attacks | Single-use, mark used=True |
| No token rotation | Stolen refresh token = permanent access | Delete old on refresh |
| Timing-unsafe compare | Side-channel attack on PKCE verify | `secrets.compare_digest()` |
| Hardcoded client_id | Can't revoke, no registration flow | Dynamic client registration |
| Skip .well-known | Clients can't discover endpoints | RFC 8414 + RFC 9728 |
