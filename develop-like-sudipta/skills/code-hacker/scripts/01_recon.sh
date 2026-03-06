#!/usr/bin/env bash
# ☠️ RECON — Attack Surface Mapping
CATEGORY="RECON" source "$(dirname "$0")/_utils.sh"

# Count files by type
for ext in py go js ts jsx tsx java php rb rs cs; do
    count=$(find "$TARGET" -name "*.${ext}" -not -path "*/node_modules/*" -not -path "*/.git/*" 2>/dev/null | wc -l)
    [ "$count" -gt 0 ] && emit_finding "INFO" "Language detected: .${ext} (${count} files)" "" "0" "" "Tech stack fingerprinting"
done

# Framework detection
search_and_emit "from django|from flask|from fastapi|from starlette" "INFO" "Python framework detected" "" "Framework fingerprinting" "--type py"
search_and_emit "express\(|from 'express'|require\('express'\)" "INFO" "Express.js detected" "" "" "--type js --type ts"
search_and_emit "import.*spring|@SpringBoot|@RestController" "INFO" "Spring framework detected" "" "" "--type java"

# Entry point counting
route_count=$(search_pattern "@app\.(get|post|put|delete|patch|route)|@router\." "--type py" | wc -l)
[ "$route_count" -gt 0 ] && emit_finding "INFO" "Found ${route_count} Python route definitions" "" "0"

route_count=$(search_pattern "app\.(get|post|put|delete|patch|use)\(" "--type js --type ts" | wc -l)
[ "$route_count" -gt 0 ] && emit_finding "INFO" "Found ${route_count} JS/TS route definitions" "" "0"

# Infrastructure files
for f in Dockerfile docker-compose.yml docker-compose.yaml .env .env.example; do
    found=$(find "$TARGET" -name "$f" -not -path "*/.git/*" 2>/dev/null | head -5)
    [ -n "$found" ] && emit_finding "INFO" "Infrastructure file: $f" "$found" "0"
done

# Sensitive file exposure
search_and_emit "\.(pem|key|p12|pfx|jks)$" "HIGH" "Private key/certificate file found" "CWE-321" "Cryptographic key in repository"
