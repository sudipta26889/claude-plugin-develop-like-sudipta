# ⚡ PERF — DoS & Resource Exhaustion Attacks

## Mission
Find every way to crash, slow, or exhaust the application.

## Checklist

### ReDoS (Regular Expression DoS)
```bash
rg -n "re\.compile|re\.(match|search|sub)\(|new RegExp\(|/.*[+*].*[+*].*/" 
```
- [ ] Regex with catastrophic backtracking (nested quantifiers: `(a+)+$`)
- [ ] User-controlled regex patterns (ReDoS via crafted input)

### Algorithmic Complexity
- [ ] Unbounded loops with user-controlled iteration count
- [ ] Sorting/searching user data without size limits
- [ ] Hash collision attacks (hash table DoS)
- [ ] XML bomb (billion laughs attack)
- [ ] JSON parsing without depth/size limits
- [ ] Zip bomb (small file, huge decompressed size)

### Resource Exhaustion
```bash
rg -n "limit.*=.*None|no.*limit|unlimited|max.*=.*0" -i
rg -n "while True|while 1|for.*in range\(" --type py
```
- [ ] No pagination limits (fetch all records)
- [ ] No file upload size limits
- [ ] No request body size limits
- [ ] No timeout on external service calls
- [ ] No connection pool limits
- [ ] Memory-heavy operations without streaming (loading entire file into memory)
- [ ] GraphQL: no query depth/complexity limits
- [ ] Bulk operations without batch size limits
