#!/usr/bin/env bash
# version-docs.sh — Versioned documentation management
# Usage: version-docs.sh <list|snapshot|switch|current> [args] [project-dir]
# Manages versioned documentation snapshots.

set -euo pipefail

COMMAND="${1:-}"
shift || true

PROJECT_DIR=""
ARGS=()

# Collect arguments — last non-flag argument that is a directory becomes PROJECT_DIR
while [[ $# -gt 0 ]]; do
  ARGS+=("$1")
  shift
done

# Try to detect project dir from last argument
if [[ ${#ARGS[@]} -gt 0 ]]; then
  LAST_ARG="${ARGS[${#ARGS[@]}-1]}"
  if [[ -d "$LAST_ARG" ]]; then
    PROJECT_DIR="$LAST_ARG"
    unset 'ARGS[${#ARGS[@]}-1]'
  fi
fi

PROJECT_DIR="${PROJECT_DIR:-.}"
cd "$PROJECT_DIR"

CONFIG_FILE=".livindocs.yml"
VERSIONS_DIR=".livindocs/versions"
CURRENT_FILE=".livindocs/versions/.current"

# ─── Helpers ─────────────────────────────────────────────────────────────────

get_docs_dir() {
  local docs_dir="docs"
  if [[ -f "$CONFIG_FILE" ]]; then
    local val
    val=$({ grep -E '^docs_dir:' "$CONFIG_FILE" | head -1 | sed 's/^docs_dir:[[:space:]]*//' | sed 's/[[:space:]]*$//' || true; })
    if [[ -n "$val" ]]; then
      docs_dir="$val"
    fi
  fi
  echo "$docs_dir"
}

get_strategy() {
  local strategy="manual"
  if [[ -f "$CONFIG_FILE" ]]; then
    # Look for strategy under versioning section
    local in_versioning=false
    while IFS= read -r line; do
      if echo "$line" | grep -qE '^versioning:'; then
        in_versioning=true
        continue
      fi
      if [[ "$in_versioning" == "true" ]]; then
        if echo "$line" | grep -qE '^[^[:space:]]'; then
          in_versioning=false
          continue
        fi
        if echo "$line" | grep -qE '^[[:space:]]+strategy:'; then
          strategy=$(echo "$line" | sed 's/^[[:space:]]*strategy:[[:space:]]*//' | sed 's/[[:space:]]*$//')
          break
        fi
      fi
    done < "$CONFIG_FILE"
  fi
  echo "$strategy"
}

get_current_version() {
  if [[ -f "$CURRENT_FILE" ]]; then
    cat "$CURRENT_FILE"
  else
    echo "none"
  fi
}

iso_timestamp() {
  python3 -c "import datetime; print(datetime.datetime.now(datetime.timezone.utc).isoformat())"
}

# ─── Commands ────────────────────────────────────────────────────────────────

do_list() {
  local strategy
  strategy=$(get_strategy)
  local current
  current=$(get_current_version)

  echo "=== DOC VERSIONS ==="
  echo "STRATEGY: $strategy"
  echo "CURRENT: $current"
  echo "VERSIONS:"

  if [[ -d "$VERSIONS_DIR" ]]; then
    local found=false
    for version_dir in "$VERSIONS_DIR"/*/; do
      [[ -d "$version_dir" ]] || continue
      # Skip hidden dirs
      local dirname
      dirname=$(basename "$version_dir")
      if [[ "$dirname" == .* ]]; then
        continue
      fi

      found=true
      local tag="$dirname"
      local created="unknown"
      if [[ -f "${version_dir}.metadata" ]]; then
        created=$({ grep -E '^created:' "${version_dir}.metadata" | sed 's/^created:[[:space:]]*//' || true; })
        created="${created:-unknown}"
      fi

      echo "  TAG: $tag"
      echo "  PATH: ${VERSIONS_DIR}/${tag}/"
      echo "  CREATED: $created"
      echo ""
    done

    if [[ "$found" == "false" ]]; then
      echo "  (none)"
    fi
  else
    echo "  (none)"
  fi

  # If strategy is git-tag, also list available git tags
  if [[ "$strategy" == "git-tag" ]]; then
    if command -v git >/dev/null 2>&1 && git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
      echo "GIT_TAGS:"
      local tags
      tags=$({ git tag --sort=-version:refname 2>/dev/null || true; })
      if [[ -n "$tags" ]]; then
        while IFS= read -r tag; do
          local has_snapshot="no"
          if [[ -d "${VERSIONS_DIR}/${tag}" ]]; then
            has_snapshot="yes"
          fi
          echo "  TAG: $tag (snapshot: $has_snapshot)"
        done <<< "$tags"
      else
        echo "  (no tags found)"
      fi
    fi
  fi

  echo "===================="
}

do_snapshot() {
  local tag="${ARGS[0]:-}"

  if [[ -z "$tag" ]]; then
    echo "Usage: version-docs.sh snapshot <tag> [project-dir]" >&2
    exit 1
  fi

  local docs_dir
  docs_dir=$(get_docs_dir)

  if [[ ! -d "$docs_dir" ]]; then
    echo "Error: docs directory not found: $docs_dir" >&2
    exit 1
  fi

  local target_dir="${VERSIONS_DIR}/${tag}"

  # Create versions directory
  mkdir -p "$target_dir"

  # Copy docs to version snapshot
  cp -R "${docs_dir}/"* "$target_dir/" 2>/dev/null || true

  # Write metadata
  local timestamp
  timestamp=$(iso_timestamp)
  cat > "${target_dir}/.metadata" << META
tag: ${tag}
created: ${timestamp}
source: ${docs_dir}
META

  # Set as current if no current version exists
  if [[ ! -f "$CURRENT_FILE" ]]; then
    echo "$tag" > "$CURRENT_FILE"
  fi

  echo "=== DOC VERSIONS ==="
  echo "ACTION: snapshot"
  echo "TAG: $tag"
  echo "PATH: $target_dir/"
  echo "CREATED: $timestamp"
  echo "SOURCE: $docs_dir/"
  echo "===================="
}

do_switch() {
  local tag="${ARGS[0]:-}"

  if [[ -z "$tag" ]]; then
    echo "Usage: version-docs.sh switch <tag> [project-dir]" >&2
    exit 1
  fi

  local target_dir="${VERSIONS_DIR}/${tag}"

  if [[ ! -d "$target_dir" ]]; then
    echo "Error: version not found: $tag" >&2
    echo "Run 'version-docs.sh list' to see available versions." >&2
    exit 1
  fi

  # Update current pointer
  mkdir -p "$(dirname "$CURRENT_FILE")"
  echo "$tag" > "$CURRENT_FILE"

  echo "=== DOC VERSIONS ==="
  echo "ACTION: switch"
  echo "CURRENT: $tag"
  echo "PATH: $target_dir/"
  echo "===================="
}

do_current() {
  local current
  current=$(get_current_version)
  local strategy
  strategy=$(get_strategy)

  echo "=== DOC VERSIONS ==="
  echo "STRATEGY: $strategy"
  echo "CURRENT: $current"
  if [[ "$current" != "none" && -d "${VERSIONS_DIR}/${current}" ]]; then
    echo "PATH: ${VERSIONS_DIR}/${current}/"
    if [[ -f "${VERSIONS_DIR}/${current}/.metadata" ]]; then
      local created
      created=$({ grep -E '^created:' "${VERSIONS_DIR}/${current}/.metadata" | sed 's/^created:[[:space:]]*//' || true; })
      echo "CREATED: ${created:-unknown}"
    fi
  fi
  echo "===================="
}

# ─── Main ────────────────────────────────────────────────────────────────────

case "$COMMAND" in
  list)
    do_list
    ;;
  snapshot)
    do_snapshot
    ;;
  switch)
    do_switch
    ;;
  current)
    do_current
    ;;
  *)
    echo "Usage: version-docs.sh <list|snapshot|switch|current> [args] [project-dir]" >&2
    exit 1
    ;;
esac
