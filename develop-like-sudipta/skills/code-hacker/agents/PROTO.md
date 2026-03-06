# 🧪 PROTO — Prototype Pollution, Cache Poisoning, WebSocket Attacks

## Mission
Find novel attack vectors that traditional scanners miss.

## 1. Prototype Pollution (JavaScript)
```bash
rg -n "merge\(|extend\(|assign\(|deepCopy|lodash.*merge|_.merge" --type js --type ts
rg -n "\[.*\]\s*=|__proto__|constructor\[|prototype\[" --type js --type ts
```
- [ ] Deep merge/extend functions without __proto__ filtering
- [ ] Object property access with user-controlled keys
- [ ] JSON.parse of user input assigned to objects
- [ ] Lodash/underscore merge with user-controlled source

## 2. Web Cache Poisoning/Deception
- [ ] Cache key doesn't include all relevant headers (Host, X-Forwarded-Host)
- [ ] Unkeyed headers reflected in response (poisoning via X-Forwarded-For, etc.)
- [ ] Path confusion: `/api/user.css` cached differently from `/api/user`
- [ ] Cache-Control headers missing or overly permissive
- [ ] Sensitive responses cached (auth tokens, user data)

## 3. WebSocket Security
```bash
rg -n "WebSocket|socket\.io|ws\(|wss\(|@OnMessage|@SubscribeMessage" 
```
- [ ] No origin validation on WebSocket handshake (CSWSH)
- [ ] No authentication per message (only on connect)
- [ ] No rate limiting on WebSocket messages
- [ ] No input validation on WebSocket messages
- [ ] WebSocket used for sensitive operations without CSRF protection

## 4. Clickjacking
- [ ] X-Frame-Options missing
- [ ] CSP frame-ancestors not set
- [ ] Sensitive forms/actions frameable

## 5. Open Redirect
```bash
rg -n "redirect\(.*request|redirect\(.*params|Location.*req\." 
rg -n "window\.location\s*=.*req|document\.location.*\+" --type js
```
- [ ] Redirect URL from user input without validation
- [ ] OAuth callback URL manipulation
