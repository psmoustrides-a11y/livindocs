#!/usr/bin/env bash
# description: Counts Express route registrations by HTTP method
# file-filter: src/routes/**/*.js

PROJECT_DIR="${1:-.}"
cd "$PROJECT_DIR"

echo "=== CUSTOM FINDINGS ==="
echo "ANALYZER: route-counter"
echo "CONFIDENCE: 0.95"
echo ""

GET_COUNT=$(grep -r "\.get(" src/routes/ 2>/dev/null | wc -l | tr -d ' ')
POST_COUNT=$(grep -r "\.post(" src/routes/ 2>/dev/null | wc -l | tr -d ' ')
PUT_COUNT=$(grep -r "\.put(" src/routes/ 2>/dev/null | wc -l | tr -d ' ')
DELETE_COUNT=$(grep -r "\.delete(" src/routes/ 2>/dev/null | wc -l | tr -d ' ')
TOTAL=$((GET_COUNT + POST_COUNT + PUT_COUNT + DELETE_COUNT))

echo "FINDINGS:"
echo "  ROUTE_METHODS:"
echo "    GET: $GET_COUNT"
echo "    POST: $POST_COUNT"
echo "    PUT: $PUT_COUNT"
echo "    DELETE: $DELETE_COUNT"
echo "    TOTAL: $TOTAL"

echo "========================"
