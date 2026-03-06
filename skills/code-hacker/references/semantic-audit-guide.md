# 🧠 SEMANTIC AUDIT GUIDE
# What the AI Agent MUST Check That Scripts Cannot

Scripts handle ~60% of findings automatically. This guide covers the remaining 40%
that requires human/AI semantic reasoning. Execute AFTER scripts complete. ALWAYS.

---

## 1. BUSINESS LOGIC FLAWS (Highest Value, Script-Invisible)

### 1.1 Auth Logic That Looks Correct But Isn't
```python
# BUG — falsy bypass: None, 0, "", False all skip auth
if user_id and user.is_authenticated:
    pass  # None/0/False bypass this

# BUG — equality vs identity
if request.user != admin_user:  # Should be 'is not'
    raise PermissionDenied

# BUG — default True (should ALWAYS default False)
def is_authorized(user_id):
    try:
        user = User.objects.get(pk=user_id)
        return user.is_active  # Missing: banned, locked, suspended checks
    except User.DoesNotExist:
        return True  # CRITICAL: defaults to authorized on error!

# BUG — time-gap between check and use
user = authenticate(token)       # Check at time T
# ... 50 lines of code ...
perform_action(user)             # Use at time T+N (user might be revoked)
```

**Checklist:**
- [ ] Auth using falsy-value comparisons (`if user_id` vs `if user_id is not None`)
- [ ] `==` vs `is` for None comparisons in auth paths
- [ ] Auth functions that return True as default (MUST return False as default)
- [ ] Missing account disabled/locked/banned/suspended checks
- [ ] Race between checking auth and using the result
- [ ] Auth bypass via HTTP method switching (GET vs POST vs PUT)
- [ ] Auth bypass via parameter pollution (?admin=true&admin=false)
- [ ] Auth bypass via case sensitivity (Admin vs admin vs ADMIN)
- [ ] JWT none algorithm attack, key confusion (RS256 → HS256)
- [ ] Token not invalidated on password change/logout

### 1.2 IDOR (Insecure Direct Object Reference)
Scripts find `.get(id=req.id)` patterns. You MUST verify ownership semantics:

```python
# VULNERABLE — no ownership check
@app.get("/orders/{order_id}")
def get_order(order_id: int, user=Depends(get_current_user)):
    return Order.objects.get(pk=order_id)  # Returns ANY user's order

# VULNERABLE — nested IDOR (order belongs to user, but items not checked)
@app.get("/orders/{order_id}/items/{item_id}")
def get_item(order_id, item_id, user=Depends(get_current_user)):
    order = Order.objects.get(pk=order_id, user=user)  # Good
    return OrderItem.objects.get(pk=item_id)  # BAD: item not checked against order

# SAFE — ownership enforced at every level
    return OrderItem.objects.get(pk=item_id, order=order)
```

**Checklist:**
- [ ] Every API endpoint taking an ID verifies `obj.owner == request.user`
- [ ] Nested resources verify ownership at EVERY level of nesting
- [ ] Batch/bulk endpoints check ownership for ALL items
- [ ] UUID doesn't replace auth (UUIDs are guessable with enough entropy info)
- [ ] GraphQL nested queries don't leak cross-user data
- [ ] Websocket connections verify ownership per message, not just on connect

### 1.3 Price/Quantity/Discount Manipulation
```python
# VULNERABLE — client-controlled price
total = request.json['quantity'] * request.json['price']

# VULNERABLE — negative quantity for refund
if request.json['quantity'] > 0:  # Missing: also check max limits
    process_order(request.json['quantity'] * product.price)

# VULNERABLE — floating point abuse
# User sends quantity=0.0000001, gets rounded to 0 cost but item ships

# VULNERABLE — coupon stacking / replay
apply_coupon(order, coupon_code)  # No check if already applied
```

**Checklist:**
- [ ] All prices come from server-side, never from client
- [ ] Quantity validated: positive integer, reasonable max, no floating point abuse
- [ ] Discounts/coupons: single-use enforcement, expiry check, max discount cap
- [ ] Currency conversion: server-side only, no user-supplied rates
- [ ] Refund amounts don't exceed original payment
- [ ] Free trial abuse: account re-registration, email aliases

### 1.4 Workflow/State Machine Abuse
```python
# VULNERABLE — steps can be skipped
@app.post("/checkout/payment")  # User skips /checkout/verify-address
def process_payment(order_id):
    order = Order.objects.get(pk=order_id)
    charge(order)  # No check that address was verified first

# VULNERABLE — state transition not enforced
order.status = request.json['status']  # User can set any status
order.save()  # Should enforce: pending→confirmed→shipped→delivered
```

**Checklist:**
- [ ] Multi-step workflows enforce step ordering
- [ ] State transitions follow valid paths only
- [ ] "Cancel" actions respect business rules (can't cancel shipped order)
- [ ] Time-based constraints enforced server-side (auction ending, etc.)
- [ ] Double-submit prevention (idempotency keys)

---

## 2. CRYPTOGRAPHIC MISUSE (Semantic, Not Syntactic)

### 2.1 Wrong Algorithm for the Job
- [ ] Password hashing: MUST be bcrypt/argon2/scrypt, NOT SHA-256/MD5
- [ ] Token generation: MUST use CSPRNG, NOT math.random/time-based
- [ ] Encryption for passwords (reversible = bad, should be hashing)
- [ ] ECB mode used (or CBC without authentication → padding oracle)
- [ ] Missing AEAD (encrypting without authenticating → bit-flip attacks)
- [ ] HMAC comparison using `==` instead of constant-time compare
- [ ] IV/nonce reuse in symmetric encryption
- [ ] RSA without proper padding (textbook RSA)

### 2.2 Key Management Failures
```python
# WRONG — password as key directly
key = password.encode()

# WRONG — deterministic derivation without salt
key = hashlib.sha256(password.encode()).digest()

# WRONG — weak KDF iterations
key = hashlib.pbkdf2_hmac('sha256', password, salt, iterations=1000)  # Need 600k+

# RIGHT
key = hashlib.scrypt(password.encode(), salt=os.urandom(16), n=2**14, r=8, p=1)
```

---

## 3. RACE CONDITIONS (Distributed, Script-Invisible)

### 3.1 Distributed TOCTOU
- [ ] Multiple app instances sharing state without locking
- [ ] Payment processing without idempotency keys across load-balanced servers
- [ ] Inventory: check-then-decrement without atomic operation (double-spend)
- [ ] Rate limiting stored in-memory (doesn't work across instances)
- [ ] Redis INCR as counter without atomic get-and-check
- [ ] File-based locks in distributed environment (useless)
- [ ] Database optimistic locking without version column
- [ ] Coupon/voucher redemption without atomic claim

### 3.2 Timing Attacks
- [ ] Password comparison not constant-time (leaks password length)
- [ ] Token validation timing varies with correctness (leaks valid tokens)
- [ ] Username enumeration via response time difference
- [ ] MFA code comparison not constant-time

---

## 4. INJECTION (SEMANTIC / SECOND-ORDER)

### 4.1 Second-Order Injection
```python
# Safe on write — sanitized input stored
username = sanitize(request.json['username'])
db.execute("INSERT INTO users (name) VALUES (%s)", (username,))

# VULNERABLE on read — stored value re-injected into new query
stored_name = db.execute("SELECT name FROM users WHERE id=%s", (uid,))
db.execute(f"SELECT * FROM logs WHERE username = '{stored_name}'")  # Second-order SQLi!
```

### 4.2 Template Injection (SSTI)
```python
# VULNERABLE — user input in template
return render_template_string(f"Hello {request.args.get('name')}")
# Payload: {{7*7}} or {{config.items()}}

# VULNERABLE — Jinja2 sandbox escape
# {{''.__class__.__mro__[2].__subclasses__()}}
```

### 4.3 Expression Language Injection
```java
// VULNERABLE — SpEL injection
@Value("#{${user.input}}")  // User controls Spring Expression Language
```

**Checklist:**
- [ ] Every place stored data is re-used in queries/templates/commands
- [ ] User-controlled format strings (`str.format`, f-strings with user data)
- [ ] Template engines with user-supplied template content
- [ ] Log injection (user input in log messages → log forging)
- [ ] Header injection (CRLF in user-controlled headers)
- [ ] Email header injection (newlines in To/CC/Subject fields)

---

## 5. API SECURITY (SEMANTIC)

### 5.1 Mass Assignment / Over-Posting
```python
# VULNERABLE — all fields from request update model
user.update(**request.json)  # User sends {"is_admin": true}

# VULNERABLE — Django/DRF
class UserSerializer(serializers.ModelSerializer):
    class Meta:
        model = User
        fields = '__all__'  # Exposes is_staff, is_superuser
```

### 5.2 GraphQL-Specific Attacks
- [ ] Introspection enabled in production (schema leak)
- [ ] No query depth/complexity limits (DoS via nested queries)
- [ ] Batched queries bypass rate limiting
- [ ] Field-level authorization missing (user queries admin-only fields)
- [ ] Aliases used to bypass rate limiting

### 5.3 Excessive Data Exposure
- [ ] API returns full database objects instead of DTOs
- [ ] Debug fields in production responses (stack traces, SQL queries)
- [ ] Verbose error messages revealing internal structure
- [ ] Auto-generated docs (Swagger/OpenAPI) exposed in production

---

## 6. ARCHITECTURE (SEMANTIC)

### 6.1 Confused Deputy Problem
```python
# Service B calls Service A with user_id
# Service A trusts user_id from Service B without re-verifying
# If Service B is compromised → attacker acts as any user
```

### 6.2 Insecure Defaults
- [ ] Default config is ALLOW_ALL (should be DENY_ALL)
- [ ] Feature flags default to ON (dangerous features active unless configured off)
- [ ] New routes/endpoints default to unprotected (auth is opt-in, not opt-out)
- [ ] Debug mode on by default, disabled only in production config
- [ ] Admin panel accessible without explicit enable

### 6.3 Trust Boundary Violations
- [ ] Internal services accessible from public network
- [ ] Client-side validation without server-side mirror
- [ ] Frontend routing as access control (API accepts any request)
- [ ] Shared database between services with different trust levels
- [ ] Internal API key shared across all microservices (lateral movement)

---

## 7. SUPPLY CHAIN (SEMANTIC)

- [ ] Lockfile exists and is committed (package-lock.json, Pipfile.lock, go.sum)
- [ ] Lockfile integrity: compare lockfile hashes with actual installations
- [ ] Private packages without scoped namespace (dependency confusion risk)
- [ ] Unused dependencies still installed (unnecessary attack surface)
- [ ] Transitive dependency depth (5+ levels = hard to audit)
- [ ] Post-install scripts in dependencies (npm lifecycle scripts)
- [ ] Pinned versions vs ranges (^1.0.0 allows untested updates)
- [ ] Container base image: is it official? Is it recent? Is it minimal?

---

## 8. SSRF DEEP ANALYSIS

- [ ] Any function that takes a URL/URI from user input
- [ ] URL validation: can it be bypassed with `http://127.0.0.1`, `http://0x7f000001`, `http://[::1]`
- [ ] DNS rebinding: first resolution points to valid host, second to internal
- [ ] Cloud metadata endpoints: `http://169.254.169.254/latest/meta-data/`
- [ ] Redirect following: safe URL → redirect to internal
- [ ] Protocol smuggling: `gopher://`, `file://`, `dict://`
- [ ] PDF/image generators that fetch URLs (wkhtmltopdf, puppeteer)

---

## 9. ATTACK CHAIN CONSTRUCTION ← MOST CRITICAL STEP

This is what separates a scanner from a hacker. Connect findings:

**Pattern: LOW + LOW = CRITICAL**
1. CORS misconfiguration + CSRF-like endpoint = account takeover
2. Path disclosure + Local File Inclusion = source code theft
3. Error message leak + SQL injection = database dump
4. Open redirect + OAuth callback = token theft
5. SSRF + cloud metadata = AWS key theft → full infrastructure compromise
6. XSS + CSRF token in DOM = arbitrary action as victim
7. IDOR + file upload = upload malware to other user's storage
8. Rate limit bypass + brute force = credential stuffing
9. Log injection + log viewer XSS = admin session theft
10. Mass assignment + role field = privilege escalation to admin

**For every MEDIUM+ finding, ask:**
- What other findings does this chain with?
- What's the maximum damage if this is the first step?
- What's the blast radius if the attacker gets this far?

---

## 10. FALSE POSITIVE REVIEW

Filter out findings that are:
- [ ] In test files with mock data (not real secrets)
- [ ] Example/placeholder code explicitly marked as such
- [ ] Commented-out code (but flag if it suggests past vulnerabilities)
- [ ] Well-known public defaults (127.0.0.1, example.com)
- [ ] Development-only code behind `if DEBUG` or `if ENV=test`
- [ ] Vendored/third-party code (note but deprioritize)

**IMPORTANT:** Commented-out credentials that were once live = still a finding (credential rotation needed).

---

## 11. SEVERITY CALIBRATION

Adjust severity based on context:
- [ ] Public API vs internal admin tool? (lower if internal-only)
- [ ] Is the "sensitive" data actually sensitive in this context?
- [ ] Are there compensating controls elsewhere (WAF, rate limiting)?
- [ ] Is the vulnerable code reachable from user input? (trace the data flow)
- [ ] What's the authentication requirement to reach the vulnerable code?
- [ ] Is the application internet-facing or behind VPN?
