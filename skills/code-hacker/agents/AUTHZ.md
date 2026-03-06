# 🛡️ AUTHZ — Authorization, Access Control, BOLA/BFLA/IDOR

## Mission
Break every access control — prove users can access what they shouldn't.

## Attack Vectors

### 1. BOLA (Broken Object Level Authorization)
Every endpoint taking an ID parameter — verify ownership check exists:
```bash
rg -n "(get|find|fetch|load|read)\(.*id|objects\.get\(.*pk=|findById\(|findOne\(" 
rg -n "params\[:id\]|params\['id'\]|req\.params\.id|request\.args\.get" 
```
- [ ] User A can access User B's resources by changing ID
- [ ] Sequential IDs make enumeration trivial
- [ ] Nested resources: `/users/{uid}/orders/{oid}` — is oid checked against uid?
- [ ] Batch endpoints: bulk fetch doesn't verify ownership per item
- [ ] File/media access: `/files/{file_id}` without ownership check

### 2. BFLA (Broken Function Level Authorization)
- [ ] Regular user can call admin endpoints by guessing URL
- [ ] HTTP method switching: GET allowed but PUT/DELETE also works without extra auth
- [ ] Admin functions only hidden in UI but accessible via API
- [ ] Role checks only on frontend, not backend
```bash
rg -n "admin|superuser|is_staff|role.*=.*admin|permission" 
rg -n "@admin_required|@staff_member|@roles_required|authorize" 
```

### 3. IDOR Patterns
- [ ] Direct database ID in URL/params without authorization check
- [ ] File paths controllable by user (../../ other_user/data)
- [ ] Webhook/callback URLs with user-specific data accessible to others
- [ ] Export/download endpoints that don't verify ownership

### 4. Privilege Escalation
- [ ] Mass assignment of role/permission fields (send `{"role":"admin"}` in update)
- [ ] Self-registration with elevated roles
- [ ] Token/cookie manipulation to change user context
- [ ] Horizontal: User A → User B (same privilege level)
- [ ] Vertical: User → Admin (higher privilege level)

### 5. Multi-Tenancy Isolation
- [ ] Tenant ID from user input instead of auth context
- [ ] Cross-tenant data leakage via shared database without row-level security
- [ ] Shared cache keys without tenant prefix
- [ ] Background jobs processing data across tenants

### 6. Access Control Architecture
- [ ] Is auth middleware opt-in or opt-out? (Must be opt-out — deny by default)
- [ ] Are there routes/endpoints without any auth decorator/middleware?
- [ ] Is authorization checked at controller AND service layer?
```bash
# Find unprotected routes
rg -n "@app\.(get|post|put|delete)" --type py | grep -v "login_required\|auth\|permission\|jwt"
rg -n "router\.(get|post|put|delete)" --type js | grep -v "auth\|middleware\|protect\|guard"
```
