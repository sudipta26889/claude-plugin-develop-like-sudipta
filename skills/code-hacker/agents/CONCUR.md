# ⚡ CONCUR — Race Conditions & Concurrency Flaws

## Mission
Find every TOCTOU, double-spend, and atomicity failure.

## Detection
```bash
rg -n "lock|mutex|synchronized|atomic|semaphore" -i
rg -n "SELECT.*FOR UPDATE|LOCK IN SHARE MODE|advisory_lock"
rg -n "threading\.|Thread\(|goroutine|async.*await|Promise\.all"
```

## Checklist
- [ ] Check-then-act without locking (TOCTOU)
- [ ] Double-spend: payment/inventory not atomic
- [ ] Rate limiting in memory (bypassed across instances)
- [ ] File-based locks in distributed system (useless)
- [ ] Database optimistic locking without version column
- [ ] Redis operations without MULTI/EXEC or Lua scripts
- [ ] Coupon/voucher/promo code redemption without atomic claim
- [ ] Account balance check-then-debit without SELECT FOR UPDATE
- [ ] Go: shared map without sync.RWMutex
- [ ] Python: shared state across threads without Lock
- [ ] Signup flow: duplicate account creation race
