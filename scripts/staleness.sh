#!/usr/bin/env bash
# staleness.sh — Detect stale documentation sections
# Usage: staleness.sh [project-dir]
# Scans docs with livindocs markers, compares ref-anchored files against baseline,
# reports per-section staleness with severity levels.

set -euo pipefail

PROJECT_DIR="${1:-.}"
cd "$PROJECT_DIR"

BASELINE_FILE=".livindocs/cache/staleness/baseline.json"

# ─── Read docs_dir from config ────────────────────────────────────────────────

DOCS_DIR="docs/"
if [[ -f ".livindocs.yml" ]]; then
  config_docs_dir=$(sed -n 's/^docs_dir:[[:space:]]*\(.*\)/\1/p' .livindocs.yml 2>/dev/null | sed 's/[[:space:]]*$//' | sed 's/^[[:space:]]*//' | sed 's/^"\(.*\)"$/\1/' | sed "s/^'\(.*\)'$/\1/" || true)
  [[ -n "$config_docs_dir" ]] && DOCS_DIR="$config_docs_dir"
fi
# Ensure trailing slash
DOCS_DIR="${DOCS_DIR%/}/"

# ─── Find all docs with livindocs markers ─────────────────────────────────────

find_docs() {
  local docs=()
  for f in README.md ${DOCS_DIR}*.md *.md; do
    if [[ -f "$f" ]] && grep -q 'livindocs:start:' "$f" 2>/dev/null; then
      docs+=("$f")
    fi
  done 2>/dev/null
  if [[ ${#docs[@]} -gt 0 ]]; then
    printf '%s\n' "${docs[@]}" | sort -u
  fi
}

# ─── Extract sections from a doc ─────────────────────────────────────────────

extract_sections() {
  local doc="$1"
  # Output: section_name|ref_files (pipe-separated refs)
  local current_section=""
  local current_refs=""

  while IFS= read -r line; do
    # Match start marker
    local start_match
    start_match=$(echo "$line" | sed -n 's/.*<!-- livindocs:start:\([^ >]*\).*/\1/p')
    if [[ -n "$start_match" ]]; then
      current_section="$start_match"
      current_refs=""
    fi

    # Match refs
    local refs_match
    refs_match=$(echo "$line" | sed -n 's/.*<!-- livindocs:refs:\([^>]*\) -->.*/\1/p')
    if [[ -n "$refs_match" && -n "$current_section" ]]; then
      if [[ -n "$current_refs" ]]; then
        current_refs="${current_refs},${refs_match}"
      else
        current_refs="$refs_match"
      fi
    fi

    # Match end marker
    local end_match
    end_match=$(echo "$line" | sed -n 's/.*<!-- livindocs:end:\([^ >]*\).*/\1/p')
    if [[ -n "$end_match" && "$end_match" == "$current_section" ]]; then
      echo "${current_section}|${current_refs}"
      current_section=""
      current_refs=""
    fi
  done < "$doc"
}

# ─── Check if a file has changed since baseline ──────────────────────────────

file_changed() {
  local filepath="$1"

  # Strip line range
  filepath=$(echo "$filepath" | sed 's/:[0-9].*$//' | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')
  [[ -z "$filepath" ]] && return 1

  # If no baseline, everything is "unknown" — treat as possibly stale
  if [[ ! -f "$BASELINE_FILE" ]]; then
    return 0
  fi

  # Get current hash
  local current_hash=""
  if [[ -f "$filepath" ]]; then
    current_hash=$(shasum -a 256 "$filepath" 2>/dev/null | awk '{print $1}')
  elif [[ -d "$filepath" ]]; then
    current_hash=$(find "$filepath" -type f 2>/dev/null | sort | xargs shasum -a 256 2>/dev/null | shasum -a 256 | awk '{print $1}')
  else
    # File doesn't exist — definitely stale
    return 0
  fi

  # Look up baseline hash
  local escaped_path
  escaped_path=$(printf '%s' "$filepath" | sed 's/[.[\*^$|]/\\&/g')
  local baseline_hash
  baseline_hash=$(sed -n "s|.*\"${escaped_path}\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*|\1|p" "$BASELINE_FILE" 2>/dev/null || true)

  if [[ -z "$baseline_hash" ]]; then
    # Not in baseline — treat as possibly stale
    return 0
  fi

  [[ "$current_hash" != "$baseline_hash" ]]
}

# ─── Determine section severity ──────────────────────────────────────────────

# Returns: current, possibly-stale, stale
# Logic:
#   - All refs unchanged → current
#   - Some refs changed → stale
#   - No refs at all → possibly-stale (can't verify)
#   - No baseline exists → possibly-stale for all

section_severity() {
  local refs="$1"
  local has_baseline=true

  [[ ! -f "$BASELINE_FILE" ]] && has_baseline=false

  if [[ -z "$refs" ]]; then
    echo "possibly-stale"
    return
  fi

  local total=0
  local changed=0

  IFS=',' read -ra ref_parts <<< "$refs"
  for ref in "${ref_parts[@]}"; do
    local file_path
    file_path=$(echo "$ref" | sed 's/:[0-9].*$//' | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')
    [[ -z "$file_path" ]] && continue

    total=$((total + 1))

    if file_changed "$file_path"; then
      changed=$((changed + 1))
    fi
  done

  if [[ $total -eq 0 ]]; then
    echo "possibly-stale"
  elif ! $has_baseline; then
    echo "possibly-stale"
  elif [[ $changed -eq 0 ]]; then
    echo "current"
  elif [[ $changed -lt $total ]]; then
    echo "stale"
  else
    echo "stale"
  fi
}

# ─── Main ────────────────────────────────────────────────────────────────────

DOCS=$(find_docs)

if [[ -z "$DOCS" ]]; then
  echo "=== STALENESS REPORT ==="
  echo "STATUS: no_docs"
  echo "MESSAGE: No documentation with livindocs markers found."
  echo "========================="
  exit 0
fi

TOTAL_SECTIONS=0
CURRENT_SECTIONS=0
POSSIBLY_STALE=0
STALE_SECTIONS=0
SECTION_RESULTS=()

while IFS= read -r doc; do
  [[ -z "$doc" ]] && continue

  while IFS='|' read -r section refs; do
    [[ -z "$section" ]] && continue

    TOTAL_SECTIONS=$((TOTAL_SECTIONS + 1))

    severity=$(section_severity "$refs")

    case "$severity" in
      current)
        CURRENT_SECTIONS=$((CURRENT_SECTIONS + 1))
        SECTION_RESULTS+=("CURRENT: ${doc}#${section}")
        ;;
      possibly-stale)
        POSSIBLY_STALE=$((POSSIBLY_STALE + 1))
        SECTION_RESULTS+=("POSSIBLY_STALE: ${doc}#${section} (refs: ${refs:-none})")
        ;;
      stale)
        STALE_SECTIONS=$((STALE_SECTIONS + 1))
        SECTION_RESULTS+=("STALE: ${doc}#${section} (refs: ${refs})")
        ;;
    esac
  done < <(extract_sections "$doc")
done <<< "$DOCS"

# Determine overall staleness
OVERALL="current"
if [[ $STALE_SECTIONS -gt 0 ]]; then
  if [[ $STALE_SECTIONS -gt $((TOTAL_SECTIONS / 2)) ]]; then
    OVERALL="very-stale"
  else
    OVERALL="stale"
  fi
elif [[ $POSSIBLY_STALE -gt 0 ]]; then
  OVERALL="slightly-stale"
fi

# ─── Output ──────────────────────────────────────────────────────────────────

echo "=== STALENESS REPORT ==="
echo "OVERALL: $OVERALL"
echo "TOTAL_SECTIONS: $TOTAL_SECTIONS"
echo "CURRENT: $CURRENT_SECTIONS"
echo "POSSIBLY_STALE: $POSSIBLY_STALE"
echo "STALE: $STALE_SECTIONS"

if [[ ! -f "$BASELINE_FILE" ]]; then
  echo "BASELINE: missing"
else
  local_timestamp=$(sed -n 's/.*"saved_at"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$BASELINE_FILE" 2>/dev/null || echo "unknown")
  echo "BASELINE: $local_timestamp"
fi

echo ""
echo "SECTIONS:"
if [[ ${#SECTION_RESULTS[@]} -gt 0 ]]; then
  for result in "${SECTION_RESULTS[@]}"; do
    echo "  $result"
  done
fi
echo "========================="
