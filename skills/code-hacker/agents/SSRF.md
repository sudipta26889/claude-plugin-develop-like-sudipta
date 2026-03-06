# 🌍 SSRF — Server-Side Request Forgery

## Mission
Find every place the server makes requests to user-controlled URLs.

## Detection
```bash
rg -n "requests\.get\(|requests\.post\(|urllib\.request|httpx\.(get|post)" --type py
rg -n "fetch\(|axios\.(get|post)|http\.get\(|https\.get\(" --type js --type ts
rg -n "HttpClient|WebClient|RestTemplate|URL\(" --type java
rg -n "curl_exec|file_get_contents\(.*\$|fopen\(.*\$" --type php
rg -n "Net::HTTP|open-uri|HTTParty|Faraday" --type rb
```

## Checklist
- [ ] Any URL/URI parameter from user input used in server-side HTTP request
- [ ] URL validation bypass: `http://127.0.0.1`, `http://0x7f000001`, `http://[::1]`
- [ ] DNS rebinding: first resolution safe, second hits internal
- [ ] Protocol smuggling: `gopher://`, `file://`, `dict://`, `ftp://`
- [ ] Redirect following: safe URL → 302 → internal target
- [ ] Cloud metadata: `http://169.254.169.254/latest/meta-data/`
- [ ] PDF/image generators fetching URLs (wkhtmltopdf, puppeteer, imgproxy)
- [ ] Webhook URLs pointing to internal services
- [ ] SVG/XML files with external entity references
- [ ] Import/feed URLs (RSS, OPML, iCal) fetched server-side
