#!/usr/bin/env bash
# cache.sh — Content-hash-based caching for analysis results
# Usage:
#   cache.sh hash <file>                  — Print content hash of a file
#   cache.sh get <hash>                   — Print cached analysis for hash (exit 1 if miss)
#   cache.sh put <hash>                   — Read analysis from stdin, store under hash
#   cache.sh check <project-dir>          — Compare file hashes against manifest, report changed files
#   cache.sh invalidate <project-dir>     — Remove stale cache entries
#   cache.sh clear <project-dir>          — Remove all cache data

set -euo pipefail

COMMAND="${1:?Usage: cache.sh <hash|get|put|check|invalidate|clear> [args]}"
shift

# ─── Hash a file ──────────────────────────────────────────────────────────────

cmd_hash() {
  local file="${1:?Usage: cache.sh hash <file>}"
  if [[ ! -f "$file" ]]; then
    echo "ERROR: File not found: $file" >&2
    exit 1
  fi
  # Use shasum (available on macOS and Linux)
  shasum -a 256 "$file" | awk '{print $1}'
}

# ─── Get cached analysis ─────────────────────────────────────────────────────

cmd_get() {
  local hash="${1:?Usage: cache.sh get <hash>}"
  local project_dir="${2:-.}"
  local cache_file="${project_dir}/.livindocs/cache/analysis/${hash}.json"

  if [[ -f "$cache_file" ]]; then
    cat "$cache_file"
    exit 0
  else
    exit 1
  fi
}

# ─── Put analysis into cache ─────────────────────────────────────────────────

cmd_put() {
  local hash="${1:?Usage: cache.sh put <hash> [project-dir]}"
  local project_dir="${2:-.}"
  local cache_dir="${project_dir}/.livindocs/cache/analysis"

  mkdir -p "$cache_dir"

  # Read analysis from stdin
  cat > "${cache_dir}/${hash}.json"
}

# ─── Check which files have changed ──────────────────────────────────────────

cmd_check() {
  local project_dir="${1:-.}"
  local manifest="${project_dir}/.livindocs/cache/analysis/manifest.json"

  cd "$project_dir"

  # If no manifest, everything is new
  if [[ ! -f "$manifest" ]]; then
    echo "=== CACHE CHECK ==="
    echo "STATUS: no_manifest"
    echo "CHANGED: all"
    echo "CACHED: 0"
    echo "==================="
    exit 0
  fi

  local changed=0
  local cached=0
  local total=0
  local changed_files=()

  # Read scan output from stdin — expects FILE_LIST section
  local scan_output
  scan_output=$(cat)

  # Extract file paths from scan output
  local in_file_list=false
  while IFS= read -r line; do
    if [[ "$line" == "FILE_LIST:" ]]; then
      in_file_list=true
      continue
    fi
    if [[ "$line" == "===="* ]]; then
      in_file_list=false
      continue
    fi
    if $in_file_list && [[ -n "$line" ]]; then
      # Extract file path (format: "  path/to/file (N lines)")
      local filepath
      filepath=$(echo "$line" | sed 's/^[[:space:]]*//' | sed 's/ ([0-9]* lines)$//')
      [[ -z "$filepath" ]] && continue
      [[ ! -f "$filepath" ]] && continue

      total=$((total + 1))

      # Get current hash
      local current_hash
      current_hash=$(shasum -a 256 "$filepath" 2>/dev/null | awk '{print $1}')

      # Look up cached hash in manifest (use | delimiter to avoid / in paths)
      local cached_hash escaped_path
      escaped_path=$(printf '%s' "$filepath" | sed 's/[.[\*^$|]/\\&/g')
      cached_hash=$(sed -n "s|.*\"${escaped_path}\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*|\1|p" "$manifest" 2>/dev/null || true)

      if [[ -n "$cached_hash" && "$current_hash" == "$cached_hash" ]]; then
        cached=$((cached + 1))
      else
        changed=$((changed + 1))
        changed_files+=("$filepath")
      fi
    fi
  done <<< "$scan_output"

  echo "=== CACHE CHECK ==="
  echo "STATUS: checked"
  echo "TOTAL: $total"
  echo "CHANGED: $changed"
  echo "CACHED: $cached"
  if [[ ${#changed_files[@]} -gt 0 ]]; then
    echo "CHANGED_FILES:"
    for f in "${changed_files[@]}"; do
      echo "  $f"
    done
  fi
  echo "==================="
}

# ─── Update manifest with current file hashes ────────────────────────────────

cmd_update_manifest() {
  local project_dir="${1:-.}"
  local cache_dir="${project_dir}/.livindocs/cache/analysis"
  local manifest="${cache_dir}/manifest.json"

  mkdir -p "$cache_dir"

  cd "$project_dir"

  # Read file list from stdin (one path per line)
  local first=true
  echo "{" > "$manifest"

  while IFS= read -r filepath; do
    [[ -z "$filepath" ]] && continue
    [[ ! -f "$filepath" ]] && continue

    local hash
    hash=$(shasum -a 256 "$filepath" 2>/dev/null | awk '{print $1}')

    if $first; then
      first=false
    else
      # Add comma to previous line
      sed -i.bak '$ s/$/,/' "$manifest" && rm -f "${manifest}.bak"
    fi

    echo "  \"${filepath}\": \"${hash}\"" >> "$manifest"
  done

  echo "}" >> "$manifest"
}

# ─── Invalidate stale cache entries ──────────────────────────────────────────

cmd_invalidate() {
  local project_dir="${1:-.}"
  local cache_dir="${project_dir}/.livindocs/cache/analysis"
  local manifest="${cache_dir}/manifest.json"

  if [[ ! -f "$manifest" ]]; then
    echo "INVALIDATED: 0"
    return
  fi

  local removed=0

  # Check each cached hash — if no file maps to it anymore, remove the cache entry
  for cache_file in "${cache_dir}"/*.json; do
    [[ "$cache_file" == *manifest.json ]] && continue
    [[ ! -f "$cache_file" ]] && continue

    local hash
    hash=$(basename "$cache_file" .json)

    # Check if any file in manifest still has this hash
    if ! grep -q "\"${hash}\"" "$manifest" 2>/dev/null; then
      rm -f "$cache_file"
      removed=$((removed + 1))
    fi
  done

  echo "INVALIDATED: $removed"
}

# ─── Clear all cache data ────────────────────────────────────────────────────

cmd_clear() {
  local project_dir="${1:-.}"
  local cache_dir="${project_dir}/.livindocs/cache"

  if [[ -d "$cache_dir" ]]; then
    rm -rf "$cache_dir"
    echo "CLEARED: $cache_dir"
  else
    echo "CLEARED: nothing (no cache directory)"
  fi
}

# ─── Dispatch ─────────────────────────────────────────────────────────────────

case "$COMMAND" in
  hash)
    cmd_hash "$@"
    ;;
  get)
    cmd_get "$@"
    ;;
  put)
    cmd_put "$@"
    ;;
  check)
    cmd_check "$@"
    ;;
  update-manifest)
    cmd_update_manifest "$@"
    ;;
  invalidate)
    cmd_invalidate "$@"
    ;;
  clear)
    cmd_clear "$@"
    ;;
  *)
    echo "Unknown command: $COMMAND" >&2
    echo "Usage: cache.sh <hash|get|put|check|update-manifest|invalidate|clear> [args]" >&2
    exit 1
    ;;
esac
