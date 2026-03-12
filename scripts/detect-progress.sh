#!/usr/bin/env bash
# detect-progress.sh — Auto-detect milestone completion from build-state.json
# Usage: detect-progress.sh [project-dir]
# Reads .livindocs/build-state.json, runs detection checks, updates the file.

set -eo pipefail

PROJECT_DIR="${1:-.}"
cd "$PROJECT_DIR"

BUILD_STATE=".livindocs/build-state.json"

if [[ ! -f "$BUILD_STATE" ]]; then
  echo "=== PROGRESS ==="
  echo "ERROR: No build-state.json found. Run /livindocs:init to create one."
  echo "================="
  exit 1
fi

# ─── Detection strategies ───────────────────────────────────────────────────

check_file_exists() {
  [[ -f "$1" ]]
}

check_grep() {
  grep -rq "$1" "${2:-.}" 2>/dev/null
}

check_export_exists() {
  grep -rqE "(export[[:space:]]+(default[[:space:]]+)?(function|class|const|let|var)[[:space:]]+${1}|module\.exports.*${1}|exports\.${1})" "${2:-.}" 2>/dev/null
}

check_test_passes() {
  eval "$1" >/dev/null 2>&1
}

# ─── Extract value from JSON line ───────────────────────────────────────────
# Simple JSON value extractor: given a line like '  "key": "value"', extract value

extract_json_value() {
  echo "$1" | sed -n 's/.*"'"$2"'"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p'
}

# ─── Parse and evaluate build state ─────────────────────────────────────────

TOTAL_ITEMS=0
DONE_ITEMS=0
PENDING_ITEMS=0
NEWLY_DETECTED=0
DETECTION_RESULTS=()

process_build_state() {
  local current_milestone=""
  local current_item=""
  local current_status=""
  local detect_type=""
  local detect_value=""
  local detect_value2=""
  local in_detect=false
  local in_items=false

  while IFS= read -r line; do
    # Track milestone name (appears before "items" array)
    if echo "$line" | grep -q '"items"'; then
      in_items=true
      continue
    fi

    # Extract name fields
    if echo "$line" | grep -q '"name"'; then
      local name_val
      name_val=$(extract_json_value "$line" "name")
      if [[ -n "$name_val" ]]; then
        if $in_items; then
          current_item="$name_val"
        else
          current_milestone="$name_val"
          current_item=""
          in_items=false
        fi
      fi
    fi

    # Track status
    if echo "$line" | grep -q '"status"'; then
      current_status=$(extract_json_value "$line" "status")
      if [[ -n "$current_status" ]]; then
        TOTAL_ITEMS=$((TOTAL_ITEMS + 1))
        if [[ "$current_status" == "done" ]]; then
          DONE_ITEMS=$((DONE_ITEMS + 1))
        else
          PENDING_ITEMS=$((PENDING_ITEMS + 1))
        fi
      fi
    fi

    # Track detect block
    if echo "$line" | grep -q '"detect"'; then
      in_detect=true
    fi

    if $in_detect; then
      if echo "$line" | grep -q '"file_exists"'; then
        detect_type="file_exists"
        detect_value=$(extract_json_value "$line" "file_exists")
      fi
      if echo "$line" | grep -q '"grep"'; then
        detect_type="grep"
        detect_value=$(extract_json_value "$line" "grep")
      fi
      if echo "$line" | grep -q '"grep_path"'; then
        detect_value2=$(extract_json_value "$line" "grep_path")
      fi
      if echo "$line" | grep -q '"export_exists"'; then
        detect_type="export_exists"
        detect_value=$(extract_json_value "$line" "export_exists")
      fi
      if echo "$line" | grep -q '"test_passes"'; then
        detect_type="test_passes"
        detect_value=$(extract_json_value "$line" "test_passes")
      fi

      # End of detect block (closing brace)
      if echo "$line" | grep -q '}' && [[ -n "$detect_type" ]]; then
        in_detect=false

        if [[ "$current_status" == "pending" && -n "$detect_type" ]]; then
          local detected=false

          case "$detect_type" in
            file_exists)
              if check_file_exists "$detect_value"; then detected=true; fi
              ;;
            grep)
              if check_grep "$detect_value" "${detect_value2:-.}"; then detected=true; fi
              ;;
            export_exists)
              if check_export_exists "$detect_value" "${detect_value2:-.}"; then detected=true; fi
              ;;
            test_passes)
              if check_test_passes "$detect_value"; then detected=true; fi
              ;;
          esac

          if $detected; then
            NEWLY_DETECTED=$((NEWLY_DETECTED + 1))
            DONE_ITEMS=$((DONE_ITEMS + 1))
            PENDING_ITEMS=$((PENDING_ITEMS - 1))
            DETECTION_RESULTS+=("DETECTED: [${current_milestone}] ${current_item} (${detect_type}: ${detect_value})")
          else
            DETECTION_RESULTS+=("PENDING: [${current_milestone}] ${current_item}")
          fi
        elif [[ "$current_status" == "done" ]]; then
          DETECTION_RESULTS+=("DONE: [${current_milestone}] ${current_item}")
        fi

        detect_type=""
        detect_value=""
        detect_value2=""
      fi
    fi
  done < "$BUILD_STATE"
}

process_build_state

# ─── Update build-state.json with newly detected items ──────────────────────

if [[ $NEWLY_DETECTED -gt 0 ]]; then
  for result in "${DETECTION_RESULTS[@]}"; do
    if [[ "$result" == DETECTED:* ]]; then
      item_name=$(echo "$result" | sed 's/DETECTED: \[.*\] //' | sed 's/ (.*//')

      tmpfile=$(mktemp)
      found_item=false
      while IFS= read -r line; do
        if echo "$line" | grep -q "\"name\": \"${item_name}\""; then
          found_item=true
        fi
        if $found_item && echo "$line" | grep -q '"status": "pending"'; then
          line=$(echo "$line" | sed 's/"status": "pending"/"status": "done"/')
          found_item=false
        fi
        echo "$line"
      done < "$BUILD_STATE" > "$tmpfile"
      mv "$tmpfile" "$BUILD_STATE"
    fi
  done
fi

# ─── Output ──────────────────────────────────────────────────────────────────

COMPLETION_PCT=0
if [[ $TOTAL_ITEMS -gt 0 ]]; then
  COMPLETION_PCT=$((DONE_ITEMS * 100 / TOTAL_ITEMS))
fi

echo "=== PROGRESS ==="
echo "TOTAL_ITEMS: $TOTAL_ITEMS"
echo "DONE: $DONE_ITEMS"
echo "PENDING: $PENDING_ITEMS"
echo "NEWLY_DETECTED: $NEWLY_DETECTED"
echo "COMPLETION: ${COMPLETION_PCT}%"
echo ""
echo "ITEMS:"
if [[ ${#DETECTION_RESULTS[@]} -gt 0 ]]; then
  for result in "${DETECTION_RESULTS[@]}"; do
    echo "  $result"
  done
fi
echo "================="
