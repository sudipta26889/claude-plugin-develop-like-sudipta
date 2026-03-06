# 🕸️ CATEGORY 23: DAST (Dynamic Application Security Testing)

## 📌 OVERVIEW
DAST shifts the focus from static code analysis (SAST) to active network interaction. As the elite red-team agent, you must evaluate the live application (if a `--live-url` is provided or if you can stand up a local instance) by sending crafted payloads and analyzing the HTTP responses. This actively proves whether a theoretical SAST finding is genuinely exploitable.

## 🕵️ WHAT TO LOOK FOR (AGENT FALLBACK)
If `23_dast_fuzz.sh` finds anomalies (or fails/skips), review the codebase manually to deduce API schemas and then actively test:

1.  **Reflected & DOM XSS:** Send payloads like `<img src=x onerror=alert(1)>` into search parameters or input fields. Verify if they are reflected unescaped in the raw HTML response.
2.  **Blind SQL Injection:** Inject time-blocking payloads like `1' WAITFOR DELAY '0:0:5'--` and observe response delay.
3.  **Authentication Bypasses:** Attempt forced browsing to administrative endpoints (e.g., `/admin`, `/api/v1/users`) without valid tokens.
4.  **SSRF Probing:** Inject `http://localhost`, `http://169.254.169.254`, or `http://127.0.0.1:22` into any parameter that fetches remote resources.

## 💣 HOW TO EXPLOIT (PROOF OF CONCEPT)
To definitively prove a DAST vulnerability and avoid false positives, you MUST:
1.  Read the SAST findings to identify the exact expected parameter structure.
2.  Write a simple `requests` Python script aiming at the target.
3.  Run it using `scripts/poc_validator.py` to ensure it executes safely and successfully prints the exploit success verification.

## 🛡️ FALSE POSITIVE CHECKLIST
- Did the server respond with a `200 OK`, but actually return a custom error page (Soft 404)?
- Did the XSS payload reflect, but inside a secure context (like a JSON string payload where `Content-Type: application/json` nullifies HTML execution)?
- Was the SQL sleep delay caused by network latency rather than actual database processing? (Always re-verify!).
