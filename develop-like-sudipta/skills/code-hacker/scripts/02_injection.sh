#!/usr/bin/env bash
# ☠️ INJECTION — SQL/NoSQL/OS/LDAP/Template Injection
CATEGORY="INJECTION" source "$(dirname "$0")/_utils.sh"

# SQL Injection
search_and_emit 'execute\(.*f"|execute\(.*f'"'"'|execute\(.*%s.*%|execute\(.*\.format' "CRITICAL" "SQL Injection (string formatting)" "CWE-89" "User input in SQL via string formatting" "--type py"
search_and_emit 'execute\(.*\+.*req|query\(.*\+.*req' "CRITICAL" "SQL Injection (concatenation)" "CWE-89" "" "--type js --type ts"
search_and_emit 'executeQuery\(.*\+|createQuery\(.*\+' "CRITICAL" "SQL Injection (Java)" "CWE-89" "" "--type java"
search_and_emit '\.raw\(.*\+|\.extra\(' "HIGH" "Django raw/extra SQL" "CWE-89" "Potential SQL injection in ORM raw query" "--type py"

# NoSQL Injection
search_and_emit '\$where|\$regex|\$gt.*req\.|find\(.*req\.body' "HIGH" "NoSQL Injection" "CWE-943" "MongoDB operator injection" "--type js --type ts"

# OS Command Injection
search_and_emit 'os\.system\(|os\.popen\(' "CRITICAL" "OS Command Injection" "CWE-78" "" "--type py"
search_and_emit 'subprocess\.(call|run|Popen).*shell\s*=\s*True' "HIGH" "Shell=True subprocess" "CWE-78" "Command injection risk with shell=True" "--type py"
search_and_emit 'child_process\.exec[^F]\(' "CRITICAL" "OS Command Injection (Node.js)" "CWE-78" "" "--type js --type ts"
search_and_emit 'Runtime\.getRuntime\(\)\.exec' "CRITICAL" "OS Command Injection (Java)" "CWE-78" "" "--type java"

# Template Injection (SSTI)
search_and_emit 'render_template_string\(.*request|Template\(.*request' "CRITICAL" "Server-Side Template Injection" "CWE-1336" "User input in template content" "--type py"

# eval/exec
search_and_emit 'eval\(.*request|eval\(.*req\.|eval\(.*params' "CRITICAL" "Code injection via eval" "CWE-95" "" "--type py --type js --type ts --type rb"
search_and_emit 'exec\(.*request|exec\(.*input' "CRITICAL" "Code injection via exec" "CWE-95" "" "--type py"

# LDAP Injection
search_and_emit 'ldap.*search.*\+.*req|ldap.*filter.*%s' "HIGH" "LDAP Injection" "CWE-90" "" ""
