# 🌐 API — REST/GraphQL/gRPC Security

## Mission
Break every API endpoint — auth bypass, data leak, abuse.

## Checklist

### REST
- [ ] Authentication on every endpoint (not just frontend-facing)
- [ ] Rate limiting per user/IP/API key
- [ ] Input validation on all parameters
- [ ] Response doesn't include extra fields (excessive data exposure)
- [ ] Pagination limits enforced (no `?limit=999999`)
- [ ] HTTP methods restricted (no PUT/DELETE on read-only resources)
- [ ] CORS properly configured (not `*` in production)

### GraphQL
```bash
rg -n "introspection|__schema|__type" -g "*.graphql" -g "*.gql" -g "*.py" -g "*.js"
rg -n "depthLimit|queryComplexity|costAnalysis" -g "*.py" -g "*.js" -g "*.ts"
```
- [ ] Introspection disabled in production
- [ ] Query depth limit enforced
- [ ] Query complexity/cost analysis
- [ ] Field-level authorization (not just type-level)
- [ ] Batch query abuse (aliases to bypass rate limiting)
- [ ] Mutations require same auth as REST equivalents

### Mass Assignment
```bash
rg -n "update\(\*\*|\.update_attributes|fields.*=.*__all__|from_dict|from_json" 
rg -n "Object\.assign\(.*req\.|\.merge\(.*params|spread.*req\." --type js --type ts
```
- [ ] All model fields exposed via API (send `is_admin=true`)
- [ ] No DTO/serializer whitelist (accepting all fields from client)

### gRPC
- [ ] TLS enforced (not insecure channel)
- [ ] Auth interceptor on all RPCs
- [ ] Large message size limits
