# ✅ INPUT — Input Validation & Output Encoding

## Mission
Find every place user input is trusted without validation or encoding.

## Checklist
- [ ] Input length limits enforced server-side
- [ ] Type validation (expecting int, getting string)
- [ ] Range validation (negative numbers, overflow values)
- [ ] Whitelist vs blacklist approach (whitelist preferred)
- [ ] Null byte injection (%00 in filenames/paths)
- [ ] Unicode normalization attacks (homoglyph, RTL override)
- [ ] Output encoding appropriate for context (HTML, JS, URL, SQL, LDAP)
- [ ] Content-Type validation (is uploaded file really an image?)
- [ ] JSON schema validation on API inputs
- [ ] Array/object where scalar expected (PHP type juggling, NoSQL injection)

```bash
rg -n "request\.(args|form|json|data|files|params|body|query)" --type py
rg -n "req\.(body|query|params|cookies|headers)" --type js --type ts
rg -n "@RequestParam|@PathVariable|@RequestBody" --type java
rg -n "params\[:|request\.parameters" --type rb
```
