#!/bin/bash
# 23_dast_fuzz.sh — Active DAST Fuzzing Wrapper
# Usage: ./23_dast_fuzz.sh <TARGET_DIR> <TARGET_URL>

TARGET_DIR="$1"
TARGET_URL="$2"

if [ -z "$TARGET_URL" ]; then
    echo "⚠️ No TARGET_URL provided. DAST requires a live target argument. Skipping active fuzzing."
    exit 0
fi

echo "🔫 Initiating basic DAST reconnaissance against $TARGET_URL..."

# Arrays of common sensitive paths to probe
SENSITIVE_PATHS=(
    ".env"
    ".git/config"
    "admin"
    "api/swagger.json"
    "server-status"
    "phpinfo.php"
    "actuator/env"
)

FOUND=0
for path in "${SENSITIVE_PATHS[@]}"; do
    # 3 second timeout, silently fetch HTTP status code
    STATUS=$(curl -s -k -o /dev/null -w "%{http_code}" "$TARGET_URL/$path" --max-time 3)
    if [ "$STATUS" = "200" ]; then
        echo "🚨 DAST ALERT: Potentially sensitive endpoint exposed -> $TARGET_URL/$path (HTTP 200)"
        FOUND=1
    fi
done

if [ "$FOUND" -eq 0 ]; then
    echo "✅ No obvious sensitive endpoints exposed dynamically during basic scan."
fi
exit 0
