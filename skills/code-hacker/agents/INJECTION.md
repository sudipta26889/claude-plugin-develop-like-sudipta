# 💉 INJECTION — SQL/NoSQL/OS/LDAP/Template/Expression Language

## Mission
Find every path where user input reaches an interpreter without sanitization.

## Attack Vectors

### 1. SQL Injection
```bash
rg -n "execute\(.*f['\"]|execute\(.*%|execute\(.*\+|execute\(.*\.format" --type py
rg -n "query\(.*\+|query\(.*\`|\.raw\(.*\+" --type js --type ts
rg -n "executeQuery\(.*\+|createQuery\(.*\+" --type java
rg -n "\$_(GET|POST|REQUEST|COOKIE)\[.*\].*mysql_query|\$.*=.*\".*SELECT" --type php
```
- [ ] String concatenation in SQL queries (f-strings, format, +, %)
- [ ] ORM raw/extra methods with user input
- [ ] Stored procedures with dynamic SQL inside
- [ ] ORDER BY / LIMIT injection (often overlooked)
- [ ] LIKE clause injection (wildcards as DoS)

### 2. NoSQL Injection
```bash
rg -n "\$where|\$regex|\$gt|\$ne|\$exists" --type js --type py
rg -n "find\(.*req\.(body|query|params)" --type js --type ts
```
- [ ] MongoDB query operators in user input (`{"$gt": ""}`)
- [ ] Aggregation pipeline injection

### 3. OS Command Injection
```bash
rg -n "os\.system|os\.popen|subprocess.*shell=True|exec\(|system\(" 
rg -n "child_process\.exec[^F]|spawn.*shell:" --type js --type ts
rg -n "Runtime\.getRuntime\(\)\.exec|ProcessBuilder" --type java
```
- [ ] Shell=True with user input
- [ ] Backtick execution with user data
- [ ] Arguments not properly escaped

### 4. LDAP Injection
```bash
rg -n "ldap.*search|ldap.*filter|ldap.*bind" -i
```
- [ ] User input in LDAP filter strings without escaping

### 5. Server-Side Template Injection (SSTI)
```bash
rg -n "render_template_string|Template\(.*request|Jinja2.*from_string" --type py
rg -n "ERB\.new\(.*params" --type rb
rg -n "new Velocity|VelocityEngine|freemarker" --type java
rg -n "Handlebars\.compile\(.*req\.|ejs\.render\(.*req\." --type js
```
- [ ] User input directly in template content (not just template variables)
- [ ] Template engine with unsafe options enabled

### 6. Expression Language Injection
```bash
rg -n "SpEL|@Value.*\$\{|ExpressionParser|#\{.*\}" --type java
rg -n "OGNL|ActionSupport|ValueStack" --type java
```

### 7. Header/CRLF Injection
```bash
rg -n "set_header|add_header|response\.headers\[" 
rg -n "redirect\(.*request\.|Location.*req\." 
```
- [ ] User input in HTTP response headers (CRLF → response splitting)
- [ ] Email headers with user-controlled To/CC/Subject (newline injection)
