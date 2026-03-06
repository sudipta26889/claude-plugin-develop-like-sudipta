#!/usr/bin/env bash
# ☠️ AUTHZ — Authorization, BOLA, BFLA, IDOR
CATEGORY="AUTHZ" source "$(dirname "$0")/_utils.sh"

# BOLA: Object access without ownership check
search_and_emit 'objects\.get\(pk=.*request|\.get\(id=.*request' "HIGH" "Potential BOLA - object fetch by user ID" "CWE-639" "Verify ownership check exists" "--type py"
search_and_emit 'findById\(req\.params|findOne\(.*req\.params' "HIGH" "Potential BOLA - findById with user param" "CWE-639" "" "--type js --type ts"

# BFLA: Admin endpoints without role check
search_and_emit 'admin|superuser|is_staff' "MEDIUM" "Admin role reference - verify authorization" "CWE-285" "Check if admin functions are properly protected" "--type py --type js --type ts"

# Missing auth decorators on routes
py_routes=$(search_pattern "@app\.(get|post|put|delete)" "--type py" 2>/dev/null | grep -v "login_required\|auth\|permission\|jwt\|public\|health" | head -20)
[ -n "$py_routes" ] && while IFS= read -r line; do
    file=$(echo "$line" | cut -d: -f1)
    lineno=$(echo "$line" | cut -d: -f2)
    emit_finding "HIGH" "Route possibly missing auth decorator" "$file" "$lineno" "CWE-862" "No auth decorator found on this route"
done <<< "$py_routes"

# Mass assignment
search_and_emit 'update\(\*\*request|from_dict\(request|\.update\(request\.json\)' "HIGH" "Mass Assignment" "CWE-915" "All request fields update model" "--type py"
search_and_emit 'Object\.assign\(.*req\.body|\.merge\(.*params|spread.*req\.body' "HIGH" "Mass Assignment (JS)" "CWE-915" "" "--type js --type ts"
search_and_emit "fields.*=.*__all__" "MEDIUM" "Django serializer exposes all fields" "CWE-915" "" "--type py"
