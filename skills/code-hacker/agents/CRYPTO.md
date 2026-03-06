# 🔒 CRYPTO — Cryptographic Failures & Misuse

## Mission
Find every weak, misused, or broken cryptographic implementation.

## Checklist

### 1. Weak Algorithms
```bash
rg -n "md5|sha1[^0-9]|des[^c]|rc4|blowfish" -i --type py --type js --type go --type java
rg -n "ECB|arc4|RC2|DES\b" -i
```
- [ ] MD5/SHA1 for security purposes (only acceptable for checksums)
- [ ] DES/3DES/RC4/Blowfish for encryption
- [ ] ECB mode (reveals patterns in ciphertext)
- [ ] CBC without authentication (padding oracle)

### 2. Password Hashing
- [ ] Must be: bcrypt, argon2, or scrypt
- [ ] NOT: SHA-256, SHA-512, MD5, even with salt
- [ ] Sufficient iterations/cost factor (bcrypt ≥12, argon2 with proper params)

### 3. Key Management
- [ ] Hardcoded encryption keys
- [ ] Key derived from password without proper KDF
- [ ] IV/nonce reuse in AES-GCM or ChaCha20
- [ ] Same key for encryption and MAC

### 4. Random Number Generation
```bash
rg -n "math\.random|Math\.random\(\)|rand\(\)|random\(\)" 
rg -n "srand\(time|seed.*time" 
```
- [ ] Non-cryptographic PRNG for security (tokens, keys, nonces)
- [ ] Predictable seeds (time-based, PID-based)

### 5. TLS/SSL
- [ ] verify=False, InsecureRequestWarning suppressed
- [ ] Self-signed certificates accepted in production
- [ ] Weak TLS versions (SSLv3, TLS 1.0, TLS 1.1)
- [ ] Weak cipher suites
```bash
rg -n "verify.*=.*False|CERT_NONE|InsecureRequestWarning|ssl.*verify" -i
```

### 6. Comparison
- [ ] Token/HMAC comparison using `==` (timing attack) — must use constant-time compare
```bash
rg -n "==.*hmac|==.*token|==.*signature|!=.*hash" 
```
