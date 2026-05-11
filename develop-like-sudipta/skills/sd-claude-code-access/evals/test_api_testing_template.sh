#!/usr/bin/env bash
# test_api_testing_template.sh — smoke test for assets/api_test_template.md.
#
# Background: <workspace>/docs/api-testing/phase-N-<slug>.md is generated
# from assets/api_test_template.md when a phase is backend-only (no UI).
# A future runner will parse the file by H2 heading; missing or reordered
# sections must fail loudly. This test validates the *template's* shape so
# we catch breakage as soon as the template drifts from its contract.
#
# What this test does NOT do:
#   - Run an actual API or curl anything (no runner exists yet; deferred).
#   - Validate JSON Schema references — the template is a contract, not
#     an executable.
#
# What it DOES check:
#   1. The template file exists where SKILL.md expects it.
#   2. All 10 required H2 sections are present, in the exact order from
#      the methodology doc.
#   3. Field markers within sections (table headers, idempotency labels,
#      bullet keywords) are present.
#   4. Cross-link to references/api_testing.md is present somewhere in
#      the body so users can find the methodology from the template.
#   5. The companion reference file (references/api_testing.md) exists
#      and mentions BACKEND_ONLY=1 (the routing keyword).
#
# Bash 3.2 compatible. No `mapfile`, `wait -n`, associative arrays.
#
# Usage: ./test_api_testing_template.sh
# Exit 0 on PASS, non-zero on any failed assertion.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TEMPLATE="$SCRIPT_DIR/../assets/api_test_template.md"
REFERENCE="$SCRIPT_DIR/../references/api_testing.md"

fails=0
fail() { fails=$((fails + 1)); echo "  FAIL: $*"; }
pass() { echo "  PASS: $*"; }

# ---------------------------------------------------------------------------
# Case 1 — template file exists
# ---------------------------------------------------------------------------
echo "-- Case 1: template file exists --"
if [ -f "$TEMPLATE" ]; then
  pass "found at $TEMPLATE"
else
  fail "missing at $TEMPLATE"
  echo "$fails assertion(s) FAILED"
  exit 1
fi

if [ -f "$REFERENCE" ]; then
  pass "reference found at $REFERENCE"
else
  fail "reference missing at $REFERENCE"
fi

# ---------------------------------------------------------------------------
# Case 2 — all 10 required H2 sections present, in order
# ---------------------------------------------------------------------------
# Per references/api_testing.md and the task spec, the required order is:
#   1. Test ID
#   2. Objective
#   3. Preconditions
#   4. Setup
#   5. Endpoints under test
#   6. Test cases
#   7. Schema assertions
#   8. Error-path assertions
#   9. Result
#  10. Notes
#
# Extract H2 headings (lines starting with "## ") in document order, then
# check that the canonical sequence appears as a contiguous prefix-subsequence
# at the start. Allow additional H2s (e.g. "## Re-run YYYY-MM-DD HH:MM")
# AFTER the canonical 10 so the re-run pattern stays compatible.
echo "-- Case 2: 10 required H2 sections in order --"

REQUIRED_ORDER="Test ID
Objective
Preconditions
Setup
Endpoints under test
Test cases
Schema assertions
Error-path assertions
Result
Notes"

# Pull only the first-level (## ) headings, strip the "## " prefix.
HEADINGS_FILE="$(mktemp -t api-tmpl-headings.XXXXXX)"
trap 'rm -f "$HEADINGS_FILE"' EXIT INT TERM

grep -E '^## ' "$TEMPLATE" | sed -E 's/^## //' > "$HEADINGS_FILE"

# Read first 10 actual headings (line-by-line, bash 3.2 friendly).
i=0
all_ok=1
while IFS= read -r expected; do
  i=$((i + 1))
  actual="$(sed -n "${i}p" "$HEADINGS_FILE")"
  if [ "$actual" = "$expected" ]; then
    pass "H2 #$i: \"$expected\""
  else
    fail "H2 #$i: expected \"$expected\", got \"$actual\""
    all_ok=0
  fi
done <<EOF
$REQUIRED_ORDER
EOF

if [ $all_ok -eq 1 ]; then
  pass "all 10 canonical sections in order"
fi

# ---------------------------------------------------------------------------
# Case 3 — field markers within sections are present
# ---------------------------------------------------------------------------
echo "-- Case 3: required field markers --"

# 3a. Endpoints under test should have a table header with Method/URL/Purpose.
if grep -q "| Method | URL | Purpose |" "$TEMPLATE"; then
  pass "endpoints table header present"
else
  fail "expected '| Method | URL | Purpose |' table header in template"
fi

# 3b. Test cases should have at least one '### tc1:' (the example).
if grep -qE '^### tc1:' "$TEMPLATE"; then
  pass "tc1 example case present"
else
  fail "expected '### tc1:' example in template"
fi

# 3c. Each example case must mention Idempotency as a labeled field.
if grep -q "Idempotency:" "$TEMPLATE"; then
  pass "Idempotency field marker present"
else
  fail "expected 'Idempotency:' field marker in template"
fi

# 3d. Schema assertions should have its own table.
if grep -q "| Endpoint | Schema source | Operation / message | Notes |" "$TEMPLATE"; then
  pass "schema-assertions table header present"
else
  fail "expected schema-assertions table header"
fi

# 3e. Error-path assertions should mention 401 and 4xx style assertions.
if grep -q "Missing auth" "$TEMPLATE" && grep -q "401" "$TEMPLATE"; then
  pass "error-path: missing-auth + 401 row present"
else
  fail "expected 'Missing auth' row with 401 in error-path table"
fi

# 3f. Result section must have Status, Timestamp, Runner, and Schema-asserted.
for marker in "Status:" "Timestamp:" "Runner:" "Schema-asserted:"; do
  if grep -q "$marker" "$TEMPLATE"; then
    pass "Result field marker '$marker' present"
  else
    fail "expected Result field marker '$marker'"
  fi
done

# ---------------------------------------------------------------------------
# Case 4 — cross-link to api_testing.md present in template
# ---------------------------------------------------------------------------
echo "-- Case 4: cross-link to references/api_testing.md --"
if grep -q "references/api_testing.md" "$TEMPLATE"; then
  pass "cross-link to references/api_testing.md present"
else
  fail "template must cross-link to references/api_testing.md"
fi

# ---------------------------------------------------------------------------
# Case 5 — reference doc mentions BACKEND_ONLY=1 (routing keyword)
# ---------------------------------------------------------------------------
echo "-- Case 5: reference doc covers BACKEND_ONLY routing --"
if [ -f "$REFERENCE" ]; then
  if grep -q "BACKEND_ONLY=1" "$REFERENCE"; then
    pass "BACKEND_ONLY=1 routing keyword present in reference"
  else
    fail "expected 'BACKEND_ONLY=1' in references/api_testing.md"
  fi
  if grep -q "openapi" "$REFERENCE"; then
    pass "reference mentions openapi (schema-source detection)"
  else
    fail "expected 'openapi' mention in references/api_testing.md"
  fi
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo
if [ $fails -eq 0 ]; then
  echo "ALL PASS"
  exit 0
else
  echo "$fails assertion(s) FAILED"
  exit 1
fi
