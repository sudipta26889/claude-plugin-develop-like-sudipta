# 🏷️ QUALITY — Error Handling & Exceptional Conditions

## Mission
Find error handling that leaks information, fails open, or crashes the system.

## Checklist

### Fail-Open Patterns
```bash
rg -n "except:|catch\s*\(|rescue\b" --type py --type js --type rb
rg -n "except:\s*$|except Exception:|catch\s*{|catch\s*\(\s*\)" 
```
- [ ] Bare except/catch that swallows all errors (masks security failures)
- [ ] Auth/authz that defaults to "allow" on exception
- [ ] Transaction rollback missing on error (partial state = corruption)
- [ ] Error recovery that skips security checks

### Information Leakage
- [ ] Stack traces in production responses
- [ ] Database error messages to users (reveals schema)
- [ ] File paths in error messages (reveals server structure)
- [ ] Version numbers in headers/responses (aids targeted attacks)
- [ ] Different error format for different error types (info leak)

### Exception Safety
- [ ] Resources not cleaned up in error paths (file handles, DB connections, locks)
- [ ] Partial writes without rollback
- [ ] Background jobs that fail silently
- [ ] Async operations without error handlers
- [ ] Missing finally/defer/ensure blocks

### Panic/Crash Safety
- [ ] Unhandled exceptions crashing the process (DoS)
- [ ] Go: goroutine panic without recovery
- [ ] Rust: unwrap() on None/Err in request handlers
- [ ] Node.js: unhandledRejection without global handler
