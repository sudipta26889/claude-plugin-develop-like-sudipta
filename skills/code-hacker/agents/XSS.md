# 🖥️ XSS — Cross-Site Scripting & DOM Attacks

## Mission
Find every place user input reaches HTML/JS output without encoding.

## Detection
```bash
# DOM XSS sinks
rg -n "innerHTML|outerHTML|document\.write|document\.writeln" --type js --type ts
rg -n "\.html\(|\.append\(.*\$|\.prepend\(.*\$" --type js  # jQuery
rg -n "dangerouslySetInnerHTML|v-html" --type js --type ts --type jsx --type vue
rg -n "bypassSecurityTrust|DomSanitizer" --type ts  # Angular bypass

# Server-side rendering without encoding
rg -n "\|safe|mark_safe|Markup\(|raw\(" --type py  # Jinja2/Django
rg -n "<%=.*params|<%-.*params" --type ejs  # EJS unescaped
rg -n "\.raw\(|html_safe" --type rb  # Rails

# Sources (user input reaching sinks)
rg -n "location\.(hash|search|href)|document\.cookie|document\.referrer" --type js
rg -n "window\.name|postMessage|URL\(.*search" --type js
```

## Checklist
- [ ] Reflected XSS: user input echoed in response without encoding
- [ ] Stored XSS: user input stored and rendered to other users
- [ ] DOM XSS: client-side JS puts user input in dangerous sinks
- [ ] XSS in admin panels (attackers target admin sessions)
- [ ] XSS via file upload (SVG, HTML, XML files)
- [ ] XSS in error messages, 404 pages, search results
- [ ] CSP header present and properly configured
- [ ] Template engine auto-escaping enabled
- [ ] React/Vue/Angular: raw HTML rendering bypasses
