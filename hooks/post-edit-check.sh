#!/usr/bin/env bash
# Post-Edit Check — PostToolUse hook for Write/Edit/MultiEdit
# Runs a pipeline of checks on edited files:
# 1. Env var detection (Pillar 3)
# 2. Secret scanning (Pillar 4)
# 3. Dead code detection (Pillar 9)
# 4. Dockerfile standards (Pillar 11)

set -euo pipefail

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | python3 -c "
import json, sys
data = json.load(sys.stdin)
print(data.get('file_path', data.get('path', '')))
" 2>/dev/null || echo "")

[ -z "$FILE_PATH" ] && exit 0
[ ! -f "$FILE_PATH" ] && exit 0

WARNINGS=""

# --- 1. ENV VAR DETECTION (Pillar 3) ---
if grep -qE '(os\.environ|os\.getenv|process\.env\.|settings\.[A-Z_]+|Field\(.*env=)' "$FILE_PATH" 2>/dev/null; then
  WARNINGS="${WARNINGS}[ENV SYNC] New env var usage detected in ${FILE_PATH}. Pillar 3: update ALL surfaces (.env.example, docker-compose, stack, config model, CI, docs). "
fi

# --- 2. SECRET SCANNING (Pillar 4) ---
# Patterns that suggest hardcoded secrets
SECRET_PATTERNS='(password\s*=\s*["\x27][^"\x27]+|api_key\s*=\s*["\x27][^"\x27]+|secret\s*=\s*["\x27][^"\x27]+|token\s*=\s*["\x27](?!{)[^"\x27]+|AWS_SECRET|PRIVATE_KEY\s*=\s*["\x27])'
if grep -qPi "$SECRET_PATTERNS" "$FILE_PATH" 2>/dev/null; then
  # Exclude test files and .env.example (which may have placeholder values)
  case "$FILE_PATH" in
    *test*|*.env.example|*.env.sample) ;;
    *)
      WARNINGS="${WARNINGS}[SECURITY] ⚠️ Possible hardcoded secret in ${FILE_PATH}. Pillar 4: move to vault/env var, add to .gitignore. "
      ;;
  esac
fi

# --- 3. DEAD CODE DETECTION (Pillar 9) — Python only ---
EXTENSION="${FILE_PATH##*.}"
if [ "$EXTENSION" = "py" ]; then
  if command -v ruff &>/dev/null; then
    LINT_OUTPUT=$(ruff check --select F401,F841 --no-fix "$FILE_PATH" 2>/dev/null || true)
    if [ -n "$LINT_OUTPUT" ]; then
      WARNINGS="${WARNINGS}[CLEAN CODE] Dead code detected: ${LINT_OUTPUT}. Pillar 9: remove unused imports/variables. "
    fi
  fi
fi

# --- 4. DOCKERFILE STANDARDS (Pillar 11) ---
BASENAME=$(basename "$FILE_PATH")
if [[ "$BASENAME" == Dockerfile* ]]; then
  # Check for non-root user
  if ! grep -q "^USER " "$FILE_PATH" 2>/dev/null; then
    WARNINGS="${WARNINGS}[DOCKERFILE] No USER directive found. Pillar 11: add non-root user (adduser/useradd). "
  fi
  # Check for secret in ENV
  if grep -qiE "^ENV.*(PASSWORD|SECRET|TOKEN|API_KEY)" "$FILE_PATH" 2>/dev/null; then
    WARNINGS="${WARNINGS}[DOCKERFILE] ⚠️ Secret in ENV directive. Pillar 11: use runtime env vars or secrets, never bake into image. "
  fi
  # Check for latest tag in FROM
  if grep -qE "^FROM .+:latest" "$FILE_PATH" 2>/dev/null; then
    WARNINGS="${WARNINGS}[DOCKERFILE] Using :latest tag in FROM. Pillar 11: pin specific version for reproducibility. "
  fi
fi

# --- 5. .env.example SYNC WARNING ---
if [[ "$BASENAME" == ".env.example" ]] || [[ "$BASENAME" == ".env" ]]; then
  WARNINGS="${WARNINGS}[ENV SYNC] ${BASENAME} was modified. Pillar 3: ensure ALL config surfaces are updated in the same operation. "
fi

# Output warnings as additionalContext if any found
if [ -n "$WARNINGS" ]; then
  # Escape for JSON
  ESCAPED=$(echo "$WARNINGS" | python3 -c "import json,sys; print(json.dumps(sys.stdin.read().strip()))" 2>/dev/null || echo "\"$WARNINGS\"")
  echo "{\"additionalContext\": ${ESCAPED}}"
fi
