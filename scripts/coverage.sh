#!/usr/bin/env bash
# coverage.sh — Documentation coverage reporter
# Usage: coverage.sh [project-dir]
# Measures what percentage of the codebase's public API is documented.
# Counts endpoints, exported functions/classes, and checks which are
# referenced in docs via livindocs:refs anchors.

set -euo pipefail

PROJECT_DIR="${1:-.}"
cd "$PROJECT_DIR"

# ─── Config ────────────────────────────────────────────────────────────────────

DOCS_DIR="."
if [[ -f ".livindocs.yml" ]]; then
  configured_dir=$(sed -n 's/^docs_dir:[[:space:]]*\(.*\)/\1/p' .livindocs.yml 2>/dev/null | sed 's/^"//' | sed 's/"$//' | sed "s/^'//" | sed "s/'$//" | head -1 || true)
  if [[ -n "$configured_dir" ]]; then
    DOCS_DIR="$configured_dir"
  fi
fi

# ─── Count source entities ─────────────────────────────────────────────────────

TOTAL_ENDPOINTS=0
TOTAL_EXPORTS=0
TOTAL_FILES=0
TOTAL_ENTITIES=0

# Count API endpoints (Express/Fastify/Flask/FastAPI/Go/Rust)
count_endpoints() {
  local count=0

  # JavaScript/TypeScript: Express/Fastify routes
  local js_routes
  js_routes=$({ grep -rE '\.(get|post|put|patch|delete|options|head|all)[[:space:]]*\(' src/ lib/ app/ routes/ 2>/dev/null | grep -vE '(test|spec|mock|\.min\.)' || true; } | wc -l)
  count=$((count + $(echo "$js_routes" | tr -d ' \n')))

  # Python: Flask/FastAPI/Django routes
  local py_routes
  py_routes=$({ grep -rE '@(app|router|api)\.(route|get|post|put|patch|delete)' src/ lib/ app/ 2>/dev/null || true; } | wc -l)
  count=$((count + $(echo "$py_routes" | tr -d ' \n')))

  # Go: net/http, Gin, Echo routes
  local go_routes
  go_routes=$({ grep -rE '(HandleFunc|\.GET|\.POST|\.PUT|\.DELETE|\.PATCH)\(' cmd/ pkg/ internal/ 2>/dev/null || true; } | wc -l)
  count=$((count + $(echo "$go_routes" | tr -d ' \n')))

  # Rust: Actix/Axum routes
  local rust_routes
  rust_routes=$({ grep -rE '#\[(get|post|put|delete|patch)\(' src/ 2>/dev/null || true; } | wc -l)
  count=$((count + $(echo "$rust_routes" | tr -d ' \n')))

  TOTAL_ENDPOINTS=$count
}

# Count exported functions and classes
count_exports() {
  local count=0

  # JavaScript/TypeScript: module.exports, export function, export class
  local js_exports
  js_exports=$({ grep -rE '(module\.exports|export (default )?(async )?(function|class|const|let|var|interface|type|enum))[[:space:]]' src/ lib/ app/ 2>/dev/null | grep -vE '(test|spec|mock)' || true; } | wc -l)
  count=$((count + $(echo "$js_exports" | tr -d ' \n')))

  # Python: def/class at module level (rough approximation)
  local py_exports
  py_exports=$({ grep -rE '^(def |class )[A-Z]' src/ lib/ app/ 2>/dev/null | grep -vE '(test|spec|mock)' || true; } | wc -l)
  count=$((count + $(echo "$py_exports" | tr -d ' \n')))

  # Go: exported functions and types (capitalized names)
  local go_exports
  go_exports=$({ grep -rE '^func [A-Z]|^type [A-Z]' cmd/ pkg/ internal/ 2>/dev/null || true; } | wc -l)
  count=$((count + $(echo "$go_exports" | tr -d ' \n')))

  # Rust: pub fn, pub struct, pub enum
  local rust_exports
  rust_exports=$({ grep -rE '^pub (fn|struct|enum|trait|type|const)' src/ 2>/dev/null || true; } | wc -l)
  count=$((count + $(echo "$rust_exports" | tr -d ' \n')))

  TOTAL_EXPORTS=$count
}

# Count source files in include patterns
count_source_files() {
  TOTAL_FILES=$({ find src/ lib/ app/ cmd/ pkg/ internal/ routes/ -type f 2>/dev/null | grep -vE '(test|spec|mock|__pycache__|node_modules)' || true; } | wc -l)
  TOTAL_FILES=$(echo "$TOTAL_FILES" | tr -d ' \n')
}

# ─── Find documented entities ──────────────────────────────────────────────────

DOCUMENTED_FILES=0
DOCUMENTED_ENDPOINTS=0
DOC_FILES=()

collect_doc_files() {
  # Find all markdown files with livindocs markers
  while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    DOC_FILES+=("$f")
  done < <(find "$DOCS_DIR" -name "*.md" -type f 2>/dev/null; find . -maxdepth 1 -name "*.md" -type f 2>/dev/null)

  # Deduplicate
  if [[ ${#DOC_FILES[@]} -gt 0 ]]; then
    DOC_FILES=($(printf '%s\n' "${DOC_FILES[@]}" | sort -u))
  else
    DOC_FILES=()
  fi
}

count_documented() {
  local all_refs=""

  if [[ ${#DOC_FILES[@]} -eq 0 ]]; then
    return
  fi

  for doc in "${DOC_FILES[@]}"; do
    [[ ! -f "$doc" ]] && continue
    # Check if it has livindocs markers
    if ! grep -q 'livindocs:refs:' "$doc" 2>/dev/null; then
      continue
    fi

    # Extract all referenced files from livindocs:refs anchors
    local refs
    refs=$(sed -n 's/.*<!-- livindocs:refs:\([^>]*\) -->.*/\1/p' "$doc" 2>/dev/null || true)
    if [[ -n "$refs" ]]; then
      all_refs+="$refs"$'\n'
    fi
  done

  # Parse refs into unique file paths
  if [[ -n "$all_refs" ]]; then
    local unique_files
    unique_files=$(echo "$all_refs" | tr ',' '\n' | sed 's/:[0-9].*$//' | tr -d ' ' | sort -u)

    while IFS= read -r ref_path; do
      [[ -z "$ref_path" ]] && continue
      if [[ -f "$ref_path" ]] || [[ -d "$ref_path" ]]; then
        DOCUMENTED_FILES=$((DOCUMENTED_FILES + 1))
      fi
    done <<< "$unique_files"
  fi

  # Count documented endpoints (endpoints mentioned in API sections)
  for doc in "${DOC_FILES[@]}"; do
    [[ ! -f "$doc" ]] && continue
    local api_endpoints
    api_endpoints=$({ grep -cE '(GET|POST|PUT|PATCH|DELETE)[[:space:]]+/' "$doc" || true; })
    DOCUMENTED_ENDPOINTS=$((DOCUMENTED_ENDPOINTS + $(echo "$api_endpoints" | tr -d ' \n')))
  done
}

# ─── Identify gaps ─────────────────────────────────────────────────────────────

declare -a GAPS=()

find_gaps() {
  # Find source files with exports that aren't referenced in any doc
  local all_ref_files=""
  for doc in "${DOC_FILES[@]+"${DOC_FILES[@]}"}"; do
    [[ ! -f "$doc" ]] && continue
    local refs
    refs=$(sed -n 's/.*<!-- livindocs:refs:\([^>]*\) -->.*/\1/p' "$doc" 2>/dev/null || true)
    if [[ -n "$refs" ]]; then
      all_ref_files+="$refs"$'\n'
    fi
  done

  # Check each source directory for undocumented files with exports
  for dir in src lib app routes cmd pkg internal; do
    [[ ! -d "$dir" ]] && continue

    while IFS= read -r src_file; do
      [[ -z "$src_file" ]] && continue
      # Skip test files
      case "$src_file" in
        *test*|*spec*|*mock*) continue ;;
      esac

      # Check if this file has any exports
      local has_exports=false
      if grep -qE '(module\.exports|export |^pub |^func [A-Z]|^type [A-Z]|^def |^class )' "$src_file" 2>/dev/null; then
        has_exports=true
      fi

      if $has_exports; then
        # Check if it's referenced in any doc
        local basename_file
        basename_file=$(echo "$src_file" | sed 's|^\./||')
        if [[ -n "$all_ref_files" ]] && echo "$all_ref_files" | grep -q "$basename_file"; then
          continue
        fi

        # Count exports in this file
        local export_count
        export_count=$({ grep -cE '(module\.exports|export |^pub |^func [A-Z]|^type [A-Z]|^def |^class )' "$src_file" || true; })
        export_count=$(echo "$export_count" | tr -d ' \n')

        if [[ "$export_count" -gt 0 ]]; then
          GAPS+=("${basename_file} (${export_count} exports, 0 documented)")
        fi
      fi
    done < <(find "$dir" -type f -name "*.js" -o -name "*.ts" -o -name "*.tsx" -o -name "*.py" -o -name "*.go" -o -name "*.rs" 2>/dev/null)
  done
}

# ─── Run all checks ────────────────────────────────────────────────────────────

count_endpoints
count_exports
count_source_files
collect_doc_files
count_documented
find_gaps

TOTAL_ENTITIES=$((TOTAL_ENDPOINTS + TOTAL_EXPORTS))

# Calculate coverage percentages
if [[ $TOTAL_ENTITIES -gt 0 ]]; then
  ENTITY_COVERAGE=$(echo "scale=1; ($DOCUMENTED_ENDPOINTS + $DOCUMENTED_FILES) * 100 / $TOTAL_ENTITIES" | bc 2>/dev/null || echo "0.0")
else
  ENTITY_COVERAGE="0.0"
fi

if [[ $TOTAL_ENDPOINTS -gt 0 ]]; then
  ENDPOINT_COVERAGE=$(echo "scale=1; $DOCUMENTED_ENDPOINTS * 100 / $TOTAL_ENDPOINTS" | bc 2>/dev/null || echo "0.0")
else
  ENDPOINT_COVERAGE="N/A"
fi

if [[ $TOTAL_FILES -gt 0 ]]; then
  FILE_COVERAGE=$(echo "scale=1; $DOCUMENTED_FILES * 100 / $TOTAL_FILES" | bc 2>/dev/null || echo "0.0")
else
  FILE_COVERAGE="0.0"
fi

DOC_COUNT=${#DOC_FILES[@]}

# ─── Output ─────────────────────────────────────────────────────────────────────

echo "=== COVERAGE REPORT ==="
echo "SOURCE:"
echo "  TOTAL_FILES: $TOTAL_FILES"
echo "  TOTAL_ENDPOINTS: $TOTAL_ENDPOINTS"
echo "  TOTAL_EXPORTS: $TOTAL_EXPORTS"
echo "  TOTAL_ENTITIES: $TOTAL_ENTITIES"
echo ""
echo "DOCUMENTATION:"
echo "  DOC_FILES: $DOC_COUNT"
echo "  DOCUMENTED_FILES: $DOCUMENTED_FILES"
echo "  DOCUMENTED_ENDPOINTS: $DOCUMENTED_ENDPOINTS"
echo ""
echo "COVERAGE:"
echo "  FILE_COVERAGE: ${FILE_COVERAGE}%"
echo "  ENDPOINT_COVERAGE: ${ENDPOINT_COVERAGE}%"
echo "  ENTITY_COVERAGE: ${ENTITY_COVERAGE}%"

if [[ ${#GAPS[@]} -gt 0 ]]; then
  echo ""
  echo "GAPS:"
  for gap in "${GAPS[@]}"; do
    echo "  $gap"
  done
fi

echo "========================"
