#!/usr/bin/env bash
# verify.sh — Programmatic claim verification and quality scoring
# Usage: verify.sh <doc-path> [project-dir]
# Verifies factual claims in generated documentation against the actual codebase.

set -euo pipefail

DOC_PATH="${1:?Usage: verify.sh <doc-path> [project-dir]}"
PROJECT_DIR="${2:-.}"

cd "$PROJECT_DIR"

if [[ ! -f "$DOC_PATH" ]]; then
  echo "=== VERIFICATION ==="
  echo "ERROR: Document not found: $DOC_PATH"
  echo "===================="
  exit 1
fi

DOC_CONTENT=$(cat "$DOC_PATH")

CHECKS=0
PASSED=0
FAILED=0
FAILURES=()

# ─── Check 1: File path references ──────────────────────────────────────────

check_file_refs() {
  local paths
  paths=$(echo "$DOC_CONTENT" | grep -oE '(src|lib|app|cmd|pkg|internal|tests?|scripts?)/[a-zA-Z0-9_./-]+\.[a-zA-Z]{1,5}' | sort -u || true)

  while IFS= read -r path; do
    [[ -z "$path" ]] && continue
    CHECKS=$((CHECKS + 1))

    if [[ -f "$path" ]]; then
      PASSED=$((PASSED + 1))
    else
      FAILED=$((FAILED + 1))
      FAILURES+=("file_exists: \"$path\" referenced but does not exist")
    fi
  done <<< "$paths"
}

# ─── Check 2: livindocs ref anchors ─────────────────────────────────────────

check_ref_anchors() {
  local refs
  refs=$(echo "$DOC_CONTENT" | sed -n 's/.*<!-- livindocs:refs:\([^>]*\) -->.*/\1/p' || true)

  while IFS= read -r ref_line; do
    [[ -z "$ref_line" ]] && continue

    IFS=',' read -ra ref_parts <<< "$ref_line"
    for ref in "${ref_parts[@]}"; do
      local file_path
      file_path=$(echo "$ref" | sed 's/:[0-9].*$//' | tr -d ' ')
      [[ -z "$file_path" ]] && continue

      CHECKS=$((CHECKS + 1))
      if [[ -f "$file_path" ]] || [[ -d "$file_path" ]]; then
        PASSED=$((PASSED + 1))
      else
        FAILED=$((FAILED + 1))
        FAILURES+=("ref_anchor: \"$file_path\" in livindocs:refs but does not exist")
      fi
    done
  done <<< "$refs"
}

# ─── Check 3: Endpoint/route count claims ───────────────────────────────────

check_endpoint_counts() {
  local claims
  claims=$(echo "$DOC_CONTENT" | grep -oiE '[0-9]+ (api )?(endpoints?|routes?|apis?)' || true)

  while IFS= read -r claim; do
    [[ -z "$claim" ]] && continue
    local claimed_count
    claimed_count=$(echo "$claim" | grep -oE '^[0-9]+')
    [[ -z "$claimed_count" ]] && continue

    CHECKS=$((CHECKS + 1))

    local actual_count=0

    # Express/Fastify style
    local js_routes
    js_routes=$({ grep -rE '\.(get|post|put|delete|patch|options|head)[[:space:]]*\(' src/ lib/ app/ routes/ 2>/dev/null | grep -vE '(test|spec|mock|\.min\.)' || true; } | wc -l)
    js_routes=$(echo "$js_routes" | tr -d ' \n')

    # Python Flask/FastAPI
    local py_routes
    py_routes=$({ grep -rE '@(app|router)\.(route|get|post|put|delete|patch)' src/ lib/ app/ 2>/dev/null || true; } | wc -l)
    py_routes=$(echo "$py_routes" | tr -d ' \n')

    # Go
    local go_routes
    go_routes=$({ grep -rE '(HandleFunc|\.GET|\.POST|\.PUT|\.DELETE|\.PATCH)\(' cmd/ pkg/ internal/ 2>/dev/null || true; } | wc -l)
    go_routes=$(echo "$go_routes" | tr -d ' \n')

    actual_count=$((js_routes + py_routes + go_routes))

    if [[ $actual_count -eq 0 ]]; then
      PASSED=$((PASSED + 1))
    elif [[ $claimed_count -eq $actual_count ]]; then
      PASSED=$((PASSED + 1))
    elif [[ $((claimed_count - actual_count)) -le 2 && $((actual_count - claimed_count)) -le 2 ]]; then
      PASSED=$((PASSED + 1))
    else
      FAILED=$((FAILED + 1))
      FAILURES+=("endpoint_count: claimed=$claimed_count actual=$actual_count")
    fi
  done <<< "$claims"
}

# ─── Check 4: Dependency version claims ──────────────────────────────────────

check_dependency_versions() {
  if [[ ! -f "package.json" ]]; then
    return
  fi

  local version_claims
  version_claims=$(echo "$DOC_CONTENT" | grep -oiE '(express|react|next|vue|angular|fastify|nestjs|django|flask|fastapi|gin|actix|axum)[[:space:]]+v?[0-9]+' || true)

  while IFS= read -r claim; do
    [[ -z "$claim" ]] && continue
    local dep_name claimed_version
    dep_name=$(echo "$claim" | awk '{print tolower($1)}')
    claimed_version=$(echo "$claim" | grep -oE '[0-9]+')
    [[ -z "$claimed_version" ]] && continue

    CHECKS=$((CHECKS + 1))

    local actual_version
    actual_version=$(sed -n 's/.*"'"${dep_name}"'"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' package.json 2>/dev/null | grep -oE '[0-9]+' | head -1 || true)

    if [[ -z "$actual_version" ]]; then
      PASSED=$((PASSED + 1))
    elif [[ "$claimed_version" == "$actual_version" ]]; then
      PASSED=$((PASSED + 1))
    else
      FAILED=$((FAILED + 1))
      FAILURES+=("dep_version: ${dep_name} claimed=v${claimed_version} actual=v${actual_version}")
    fi
  done <<< "$version_claims"
}

# ─── Check 5: Section coverage ──────────────────────────────────────────────

SECTIONS_PRESENT=0
SECTIONS_EXPECTED=0
COVERAGE_GAPS=()

check_coverage() {
  # Each entry: "canonical_name|alias1|alias2|..."
  # Matches against both ## headings and livindocs:start markers
  local expected_sections=(
    "description|overview|about|introduction|header"
    "installation|install|setup|quickstart|quick-start|getting-started"
    "usage|api|endpoints|commands|examples"
    "features|highlights|capabilities"
  )

  if [[ -f "package.json" ]] || [[ -f "requirements.txt" ]] || [[ -f "go.mod" ]]; then
    expected_sections+=("architecture|structure|design|project-structure")
  fi

  if [[ -f "LICENSE" ]] || [[ -f "LICENSE.md" ]]; then
    expected_sections+=("license")
  fi

  SECTIONS_EXPECTED=${#expected_sections[@]}

  for entry in "${expected_sections[@]}"; do
    local canonical="${entry%%|*}"
    local found=false

    IFS='|' read -ra aliases <<< "$entry"
    for alias in "${aliases[@]}"; do
      if echo "$DOC_CONTENT" | grep -qi "## .*${alias}\|<!-- livindocs:start:${alias}"; then
        found=true
        break
      fi
    done

    if $found; then
      SECTIONS_PRESENT=$((SECTIONS_PRESENT + 1))
    else
      COVERAGE_GAPS+=("$canonical")
    fi
  done
}

# ─── Check 6: Reference anchor count ────────────────────────────────────────

REF_COUNT=0

count_refs() {
  REF_COUNT=$(echo "$DOC_CONTENT" | grep -c '<!-- livindocs:refs:' || echo "0")
}

# ─── Run all checks ─────────────────────────────────────────────────────────

check_file_refs
check_ref_anchors
check_endpoint_counts
check_dependency_versions
check_coverage
count_refs

# ─── Compute scores ─────────────────────────────────────────────────────────

if [[ $CHECKS -gt 0 ]]; then
  ACCURACY_SCORE=$(echo "scale=2; $PASSED / $CHECKS" | bc 2>/dev/null || echo "1.00")
else
  ACCURACY_SCORE="1.00"
fi

if [[ $SECTIONS_EXPECTED -gt 0 ]]; then
  COVERAGE_SCORE=$(echo "scale=2; $SECTIONS_PRESENT / $SECTIONS_EXPECTED" | bc 2>/dev/null || echo "1.00")
else
  COVERAGE_SCORE="1.00"
fi

FRESHNESS_SCORE="1.00"

OVERALL=$(echo "scale=2; ($ACCURACY_SCORE * 50 + $COVERAGE_SCORE * 35 + $FRESHNESS_SCORE * 15)" | bc 2>/dev/null | sed 's/\..*//' || echo "85")
# Ensure OVERALL is never empty (bc can output ".50" for values < 1)
OVERALL=${OVERALL:-0}

# ─── Output ──────────────────────────────────────────────────────────────────

echo "=== VERIFICATION ==="
echo "CHECKS: $CHECKS"
echo "PASSED: $PASSED"
echo "FAILED: $FAILED"

if [[ ${#FAILURES[@]} -gt 0 ]]; then
  echo "FAILURES:"
  for f in "${FAILURES[@]}"; do
    echo "  $f"
  done
fi

if [[ ${#COVERAGE_GAPS[@]} -gt 0 ]]; then
  echo "COVERAGE_GAPS: ${COVERAGE_GAPS[*]}"
fi

echo "ACCURACY_SCORE: $ACCURACY_SCORE"
echo "COVERAGE_SCORE: $COVERAGE_SCORE"
echo "FRESHNESS_SCORE: $FRESHNESS_SCORE"
echo "OVERALL: $OVERALL"
echo "REFS: $REF_COUNT"
echo "===================="
