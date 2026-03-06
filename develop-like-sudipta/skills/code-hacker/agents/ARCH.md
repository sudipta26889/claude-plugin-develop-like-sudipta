# 🏗️ ARCH — Architecture & Insecure Design Flaws

## Mission
Find design-level flaws that can't be fixed with a patch — they need redesign.

## Checklist
- [ ] Trust boundaries: where does trusted code meet untrusted input?
- [ ] Confused deputy: Service A trusts Service B without verifying the request origin
- [ ] Fail-open vs fail-close: what happens when auth service is down?
- [ ] Security as opt-in vs opt-out (new routes should require auth by default)
- [ ] Shared secrets across services (one compromise = all compromised)
- [ ] Monolithic auth: single point of failure
- [ ] Missing rate limiting on expensive operations (search, export, report generation)
- [ ] No idempotency on payment/financial operations
- [ ] Client-side security only (validation, routing, access control in frontend)
- [ ] Shared database across trust levels without row-level security
- [ ] Missing circuit breaker on external service calls
- [ ] No audit trail for sensitive operations (who changed what when)
- [ ] Webhook endpoints without signature verification
- [ ] Cron jobs running with elevated privileges unnecessarily
