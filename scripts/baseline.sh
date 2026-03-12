#!/usr/bin/env bash
# baseline.sh — Staleness baseline snapshot management
# Usage:
#   baseline.sh save <project-dir>     — Save current hashes for all ref-anchored files
#   baseline.sh compare <project-dir>  — Compare current state to saved baseline
#   baseline.sh show <project-dir>     — Show current baseline contents

set -euo pipefail

COMMAND="${1:?Usage: baseline.sh <save|compare|show> [project-dir]}"
PROJECT_DIR="${2:-.}"

cd "$PROJECT_DIR"

BASELINE_DIR=".livindocs/cache/staleness"
BASELINE_FILE="${BASELINE_DIR}/baseline.json"

# ─── Read docs_dir from config ────────────────────────────────────────────────

DOCS_DIR="docs/"
if [[ -f ".livindocs.yml" ]]; then
  config_docs_dir=$(sed -n 's/^docs_dir:[[:space:]]*\(.*\)/\1/p' .livindocs.yml 2>/dev/null | sed 's/[[:space:]]*$//' | sed 's/^[[:space:]]*//' | sed 's/^"\(.*\)"$/\1/' | sed "s/^'\(.*\)'$/\1/" || true)
  [[ -n "$config_docs_dir" ]] && DOCS_DIR="$config_docs_dir"
fi
# Ensure trailing slash
DOCS_DIR="${DOCS_DIR%/}/"

# ─── Extract ref-anchored files from all docs ─────────────────────────────────

extract_ref_files() {
  local ref_files=()

  # Find all markdown files that might contain livindocs markers
  # Check: root README.md, configured docs_dir, and any root-level .md files
  local doc_files=()
  for f in README.md ${DOCS_DIR}*.md *.md; do
    [[ -f "$f" ]] && doc_files+=("$f")
  done 2>/dev/null

  for doc in "${doc_files[@]}"; do
    # Extract file paths from <!-- livindocs:refs:FILE:LINES --> anchors
    while IFS= read -r ref_line; do
      [[ -z "$ref_line" ]] && continue
      # Split comma-separated refs
      IFS=',' read -ra refs <<< "$ref_line"
      for ref in "${refs[@]}"; do
        # Strip line range (e.g., :1-42) and whitespace
        local file_path
        file_path=$(printf '%s' "$ref" | sed 's/:[0-9].*$//' | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')
        [[ -z "$file_path" ]] && continue
        ref_files+=("$file_path")
      done
    done < <(sed -n 's/.*<!-- livindocs:refs:\([^>]*\) -->.*/\1/p' "$doc" 2>/dev/null || true)
  done

  # Deduplicate
  if [[ ${#ref_files[@]} -gt 0 ]]; then
    printf '%s\n' "${ref_files[@]}" | sort -u
  fi
}

# ─── Save baseline ───────────────────────────────────────────────────────────

cmd_save() {
  mkdir -p "$BASELINE_DIR"

  local ref_files
  ref_files=$(extract_ref_files)

  local first=true
  local count=0
  local timestamp
  timestamp=$(date -u +"%Y-%m-%dT%H:%M:%S.000Z")

  {
    echo "{"
    echo "  \"saved_at\": \"${timestamp}\","
    echo "  \"files\": {"

    while IFS= read -r filepath; do
      [[ -z "$filepath" ]] && continue

      local hash=""
      if [[ -f "$filepath" ]]; then
        hash=$(shasum -a 256 "$filepath" 2>/dev/null | awk '{print $1}')
      elif [[ -d "$filepath" ]]; then
        # For directory refs, hash the directory listing
        hash=$(find "$filepath" -type f 2>/dev/null | sort | xargs shasum -a 256 2>/dev/null | shasum -a 256 | awk '{print $1}')
      fi

      if [[ -n "$hash" ]]; then
        if $first; then
          first=false
        else
          echo ","
        fi
        printf '    "%s": "%s"' "$filepath" "$hash"
        count=$((count + 1))
      fi
    done <<< "$ref_files"

    echo ""
    echo "  }"
    echo "}"
  } > "$BASELINE_FILE"

  echo "=== BASELINE ==="
  echo "ACTION: saved"
  echo "FILES: $count"
  echo "TIMESTAMP: $timestamp"
  echo "PATH: $BASELINE_FILE"
  echo "================="
}

# ─── Compare current state to baseline ────────────────────────────────────────

cmd_compare() {
  if [[ ! -f "$BASELINE_FILE" ]]; then
    echo "=== BASELINE COMPARE ==="
    echo "STATUS: no_baseline"
    echo "MESSAGE: No baseline found. Run /livindocs:generate first to create one."
    echo "========================="
    exit 0
  fi

  local ref_files
  ref_files=$(extract_ref_files)

  local changed=0
  local unchanged=0
  local missing=0
  local new_files=0
  local total=0
  local changed_list=()
  local missing_list=()
  local new_list=()

  while IFS= read -r filepath; do
    [[ -z "$filepath" ]] && continue
    total=$((total + 1))

    # Get current hash
    local current_hash=""
    if [[ -f "$filepath" ]]; then
      current_hash=$(shasum -a 256 "$filepath" 2>/dev/null | awk '{print $1}')
    elif [[ -d "$filepath" ]]; then
      current_hash=$(find "$filepath" -type f 2>/dev/null | sort | xargs shasum -a 256 2>/dev/null | shasum -a 256 | awk '{print $1}')
    fi

    # Look up baseline hash (use | delimiter to avoid / in paths)
    local escaped_path
    escaped_path=$(printf '%s' "$filepath" | sed 's/[.[\*^$|]/\\&/g')
    local baseline_hash
    baseline_hash=$(sed -n "s|.*\"${escaped_path}\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*|\1|p" "$BASELINE_FILE" 2>/dev/null || true)

    if [[ -z "$current_hash" ]]; then
      # File/dir no longer exists
      missing=$((missing + 1))
      missing_list+=("$filepath")
    elif [[ -z "$baseline_hash" ]]; then
      # New file not in baseline
      new_files=$((new_files + 1))
      new_list+=("$filepath")
    elif [[ "$current_hash" != "$baseline_hash" ]]; then
      # File changed since baseline
      changed=$((changed + 1))
      changed_list+=("$filepath")
    else
      unchanged=$((unchanged + 1))
    fi
  done <<< "$ref_files"

  echo "=== BASELINE COMPARE ==="
  echo "STATUS: compared"
  echo "TOTAL: $total"
  echo "UNCHANGED: $unchanged"
  echo "CHANGED: $changed"
  echo "MISSING: $missing"
  echo "NEW: $new_files"

  if [[ ${#changed_list[@]} -gt 0 ]]; then
    echo "CHANGED_FILES:"
    for f in "${changed_list[@]}"; do
      echo "  $f"
    done
  fi

  if [[ ${#missing_list[@]} -gt 0 ]]; then
    echo "MISSING_FILES:"
    for f in "${missing_list[@]}"; do
      echo "  $f"
    done
  fi

  if [[ ${#new_list[@]} -gt 0 ]]; then
    echo "NEW_FILES:"
    for f in "${new_list[@]}"; do
      echo "  $f"
    done
  fi

  echo "========================="
}

# ─── Show baseline ───────────────────────────────────────────────────────────

cmd_show() {
  if [[ ! -f "$BASELINE_FILE" ]]; then
    echo "No baseline found at $BASELINE_FILE"
    exit 1
  fi
  cat "$BASELINE_FILE"
}

# ─── Dispatch ─────────────────────────────────────────────────────────────────

case "$COMMAND" in
  save)    cmd_save ;;
  compare) cmd_compare ;;
  show)    cmd_show ;;
  *)
    echo "Unknown command: $COMMAND" >&2
    echo "Usage: baseline.sh <save|compare|show> [project-dir]" >&2
    exit 1
    ;;
esac
