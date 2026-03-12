#!/usr/bin/env bash
# detect-monorepo.sh — Detect monorepo workspace configuration and list packages
# Usage:
#   detect-monorepo.sh [project-dir]           — Full detection with package listing
#   detect-monorepo.sh --check [project-dir]   — Quick check: is this a monorepo? (exit 0=yes, 1=no)
#
# Detects: npm/yarn workspaces, pnpm workspaces, lerna, cargo workspaces, go workspaces
# Output: Structured text block with workspace type, packages, and their metadata

set -euo pipefail

CHECK_ONLY=false
PROJECT_DIR="."

while [[ $# -gt 0 ]]; do
  case "$1" in
    --check) CHECK_ONLY=true; shift ;;
    *) PROJECT_DIR="$1"; shift ;;
  esac
done

cd "$PROJECT_DIR"

# ─── Detection functions ──────────────────────────────────────────────────────

WORKSPACE_TYPE=""
WORKSPACE_CONFIG=""
PACKAGE_PATTERNS=()

detect_npm_yarn_workspaces() {
  if [[ ! -f "package.json" ]]; then
    return 1
  fi

  # Look for "workspaces" field in package.json
  local ws
  ws=$(sed -n '/"workspaces"/,/\]/p' package.json 2>/dev/null || true)
  if [[ -z "$ws" ]]; then
    return 1
  fi

  WORKSPACE_TYPE="npm-workspaces"
  WORKSPACE_CONFIG="package.json"

  # Extract workspace patterns from the array
  # Handles: "workspaces": ["packages/*", "apps/*"]
  # Also handles nested: "workspaces": { "packages": ["packages/*"] }
  while IFS= read -r pattern; do
    pattern=$(echo "$pattern" | sed 's/^[[:space:]]*"//;s/"[[:space:]]*,*$//' | tr -d '"')
    [[ -z "$pattern" ]] && continue
    [[ "$pattern" == *"workspaces"* ]] && continue
    [[ "$pattern" == *"{"* ]] && continue
    [[ "$pattern" == *"}"* ]] && continue
    [[ "$pattern" == *"]"* ]] && continue
    [[ "$pattern" == *"["* ]] && continue
    [[ "$pattern" == *"packages"* && "$pattern" != *"/"* ]] && continue
    PACKAGE_PATTERNS+=("$pattern")
  done <<< "$ws"

  return 0
}

detect_pnpm_workspaces() {
  if [[ ! -f "pnpm-workspace.yaml" ]]; then
    return 1
  fi

  WORKSPACE_TYPE="pnpm-workspaces"
  WORKSPACE_CONFIG="pnpm-workspace.yaml"

  # Parse packages list from pnpm-workspace.yaml
  local in_packages=false
  while IFS= read -r line; do
    if echo "$line" | grep -qE '^packages:'; then
      in_packages=true
      continue
    fi
    # Stop at next top-level key
    if $in_packages && echo "$line" | grep -qE '^[a-z]'; then
      break
    fi
    if $in_packages && echo "$line" | grep -qE '^[[:space:]]+-'; then
      local pattern
      pattern=$(echo "$line" | sed 's/^[[:space:]]*-[[:space:]]*//' | sed 's/^"//' | sed 's/"$//' | sed "s/^'//" | sed "s/'$//")
      [[ -n "$pattern" ]] && PACKAGE_PATTERNS+=("$pattern")
    fi
  done < "pnpm-workspace.yaml"

  return 0
}

detect_lerna() {
  if [[ ! -f "lerna.json" ]]; then
    return 1
  fi

  WORKSPACE_TYPE="lerna"
  WORKSPACE_CONFIG="lerna.json"

  # Extract packages patterns from lerna.json
  # Parse quoted strings from the "packages" array
  local packages_line
  packages_line=$(sed -n '/"packages"/,/\]/p' lerna.json 2>/dev/null | tr '\n' ' ' || true)
  if [[ -z "$packages_line" ]]; then
    # Default lerna pattern
    PACKAGE_PATTERNS+=("packages/*")
    return 0
  fi

  # Extract all quoted strings that contain a path separator
  while IFS= read -r pattern; do
    [[ -z "$pattern" ]] && continue
    PACKAGE_PATTERNS+=("$pattern")
  done < <(echo "$packages_line" | grep -oE '"[^"]*/"[^"]*|"[^"]*\*[^"]*"' | tr -d '"')

  # If no patterns found, use default
  if [[ ${#PACKAGE_PATTERNS[@]} -eq 0 ]]; then
    PACKAGE_PATTERNS+=("packages/*")
  fi

  return 0
}

detect_cargo_workspaces() {
  if [[ ! -f "Cargo.toml" ]]; then
    return 1
  fi

  # Look for [workspace] section with members
  if ! grep -q '^\[workspace\]' Cargo.toml 2>/dev/null; then
    return 1
  fi

  WORKSPACE_TYPE="cargo-workspaces"
  WORKSPACE_CONFIG="Cargo.toml"

  # Extract members from [workspace] section
  local in_members=false
  while IFS= read -r line; do
    if echo "$line" | grep -qE '^members[[:space:]]*='; then
      in_members=true
      # Handle single-line: members = ["crates/*"]
      if echo "$line" | grep -q '\]'; then
        while IFS= read -r pattern; do
          pattern=$(echo "$pattern" | sed 's/^[[:space:]]*"//;s/"[[:space:]]*,*$//' | tr -d '"')
          [[ -z "$pattern" ]] && continue
          [[ "$pattern" == *"members"* ]] && continue
          [[ "$pattern" == *"["* || "$pattern" == *"]"* ]] && continue
          PACKAGE_PATTERNS+=("$pattern")
        done <<< "$(echo "$line" | sed 's/.*\[//;s/\].*//' | tr ',' '\n')"
        in_members=false
      fi
      continue
    fi
    if $in_members; then
      if echo "$line" | grep -q '\]'; then
        in_members=false
      fi
      local pattern
      pattern=$(echo "$line" | sed 's/^[[:space:]]*"//;s/"[[:space:]]*,*$//' | tr -d '[]"' | sed 's/[[:space:]]//g')
      [[ -n "$pattern" ]] && PACKAGE_PATTERNS+=("$pattern")
    fi
  done < Cargo.toml

  return 0
}

detect_go_workspaces() {
  if [[ ! -f "go.work" ]]; then
    return 1
  fi

  WORKSPACE_TYPE="go-workspaces"
  WORKSPACE_CONFIG="go.work"

  # Extract use directives from go.work
  local in_use=false
  while IFS= read -r line; do
    # Single-line: use ./cmd/foo
    if echo "$line" | grep -qE '^use[[:space:]]+\./'; then
      local dir
      dir=$(echo "$line" | sed 's/^use[[:space:]]*//' | sed 's/[[:space:]]*$//')
      PACKAGE_PATTERNS+=("$dir")
      continue
    fi
    # Multi-line: use ( ... )
    if echo "$line" | grep -qE '^use[[:space:]]*\('; then
      in_use=true
      continue
    fi
    if $in_use; then
      if echo "$line" | grep -q ')'; then
        in_use=false
        continue
      fi
      local dir
      dir=$(echo "$line" | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')
      [[ -n "$dir" ]] && PACKAGE_PATTERNS+=("$dir")
    fi
  done < go.work

  return 0
}

# ─── Run detection ────────────────────────────────────────────────────────────

# Try each detection method in order of popularity
detect_pnpm_workspaces || detect_npm_yarn_workspaces || detect_lerna || detect_cargo_workspaces || detect_go_workspaces || true

# Also check .livindocs.yml monorepo config
CONFIG_MONOREPO="auto"
CONFIG_PACKAGES=()
if [[ -f ".livindocs.yml" ]]; then
  local_enabled=$(sed -n '/^monorepo:/,/^[^ ]/{ s/^[[:space:]]*enabled:[[:space:]]*\(.*\)/\1/p; }' .livindocs.yml 2>/dev/null | head -1 || true)
  if [[ -n "$local_enabled" ]]; then
    CONFIG_MONOREPO="$local_enabled"
  fi

  # Read packages from config
  in_monorepo=false
  in_packages=false
  while IFS= read -r line; do
    if echo "$line" | grep -qE '^monorepo:'; then
      in_monorepo=true
      continue
    fi
    if $in_monorepo && echo "$line" | grep -qE '^[[:space:]]+packages:'; then
      in_packages=true
      continue
    fi
    if $in_monorepo && echo "$line" | grep -qE '^[a-z]'; then
      in_monorepo=false
      in_packages=false
      continue
    fi
    if $in_packages && echo "$line" | grep -qE '^[[:space:]]+-'; then
      cfg_pattern=$(echo "$line" | sed 's/^[[:space:]]*-[[:space:]]*//' | sed 's/^"//' | sed 's/"$//' | sed "s/^'//" | sed "s/'$//")
      [[ -n "$cfg_pattern" ]] && CONFIG_PACKAGES+=("$cfg_pattern")
    fi
  done < .livindocs.yml 2>/dev/null || true

  # If config explicitly sets packages, use those as overrides
  if [[ ${#CONFIG_PACKAGES[@]} -gt 0 ]]; then
    PACKAGE_PATTERNS=("${CONFIG_PACKAGES[@]}")
  fi
fi

# Determine if this is a monorepo
IS_MONOREPO=false
if [[ "$CONFIG_MONOREPO" == "true" ]]; then
  IS_MONOREPO=true
elif [[ "$CONFIG_MONOREPO" == "false" ]]; then
  IS_MONOREPO=false
elif [[ -n "$WORKSPACE_TYPE" ]]; then
  IS_MONOREPO=true
fi

# Quick check mode
if $CHECK_ONLY; then
  if $IS_MONOREPO; then
    echo "MONOREPO: true"
    echo "TYPE: ${WORKSPACE_TYPE:-config}"
    exit 0
  else
    echo "MONOREPO: false"
    exit 1
  fi
fi

# ─── Resolve package directories ─────────────────────────────────────────────

declare -a PKG_NAMES=()
declare -a PKG_PATHS=()
declare -a PKG_LANGUAGES=()
declare -a PKG_DESCRIPTIONS=()

if $IS_MONOREPO && [[ ${#PACKAGE_PATTERNS[@]} -gt 0 ]]; then
  for pattern in "${PACKAGE_PATTERNS[@]}"; do
    # Expand glob pattern to actual directories
    # Handle patterns like "packages/*", "apps/*", "./services/*"
    clean_pattern=$(echo "$pattern" | sed 's|^\./||' | sed 's|/\*$||' | sed 's|\*$||')

    if [[ -d "$clean_pattern" ]]; then
      # Pattern is a directory itself — check if it has subdirectories (packages)
      if echo "$pattern" | grep -q '\*'; then
        # Glob pattern like "packages/*" — list subdirectories
        for pkg_dir in "$clean_pattern"/*/; do
          [[ ! -d "$pkg_dir" ]] && continue
          pkg_dir=$(echo "$pkg_dir" | sed 's|/$||')

          pkg_name=""
          # Try to get name from package.json
          if [[ -f "$pkg_dir/package.json" ]]; then
            pkg_name=$(sed -n 's/.*"name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$pkg_dir/package.json" 2>/dev/null | head -1 || true)
          fi
          # Fallback: use directory name
          if [[ -z "$pkg_name" ]]; then
            pkg_name=$(basename "$pkg_dir")
          fi

          # Detect language
          pkg_lang="unknown"
          if [[ -f "$pkg_dir/package.json" ]]; then
            if [[ -f "$pkg_dir/tsconfig.json" ]]; then
              pkg_lang="typescript"
            else
              pkg_lang="javascript"
            fi
          elif [[ -f "$pkg_dir/Cargo.toml" ]]; then
            pkg_lang="rust"
          elif [[ -f "$pkg_dir/go.mod" ]]; then
            pkg_lang="go"
          elif [[ -f "$pkg_dir/pyproject.toml" ]] || [[ -f "$pkg_dir/setup.py" ]]; then
            pkg_lang="python"
          fi

          # Get description from package.json if available
          pkg_desc=""
          if [[ -f "$pkg_dir/package.json" ]]; then
            pkg_desc=$(sed -n 's/.*"description"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$pkg_dir/package.json" 2>/dev/null | head -1 || true)
          fi

          PKG_NAMES+=("$pkg_name")
          PKG_PATHS+=("$pkg_dir")
          PKG_LANGUAGES+=("$pkg_lang")
          PKG_DESCRIPTIONS+=("$pkg_desc")
        done
      else
        # Exact directory — treat it as a single package
        pkg_name=$(basename "$clean_pattern")
        PKG_NAMES+=("$pkg_name")
        PKG_PATHS+=("$clean_pattern")
        PKG_LANGUAGES+=("unknown")
        PKG_DESCRIPTIONS+=("")
      fi
    fi
  done
fi

# ─── Detect inter-package dependencies ────────────────────────────────────────

declare -a DEP_EDGES=()

if $IS_MONOREPO && [[ ${#PKG_NAMES[@]} -gt 1 ]]; then
  for i in "${!PKG_PATHS[@]}"; do
    dep_pkg_path="${PKG_PATHS[$i]}"
    dep_pkg_name="${PKG_NAMES[$i]}"

    # Check package.json dependencies for references to other packages
    if [[ -f "$dep_pkg_path/package.json" ]]; then
      for j in "${!PKG_NAMES[@]}"; do
        [[ $i -eq $j ]] && continue
        other_name="${PKG_NAMES[$j]}"
        if grep -q "\"$other_name\"" "$dep_pkg_path/package.json" 2>/dev/null; then
          DEP_EDGES+=("${dep_pkg_name} -> ${other_name}")
        fi
      done
    fi

    # Check Cargo.toml for workspace dependencies
    if [[ -f "$dep_pkg_path/Cargo.toml" ]]; then
      for j in "${!PKG_NAMES[@]}"; do
        [[ $i -eq $j ]] && continue
        other_name="${PKG_NAMES[$j]}"
        if grep -q "$other_name" "$dep_pkg_path/Cargo.toml" 2>/dev/null; then
          DEP_EDGES+=("${dep_pkg_name} -> ${other_name}")
        fi
      done
    fi

    # Check Go imports for workspace module references
    if [[ -f "$dep_pkg_path/go.mod" ]]; then
      module_prefix=$(head -1 go.work 2>/dev/null | sed 's/^module[[:space:]]*//' || true)
      if [[ -n "$module_prefix" ]]; then
        for j in "${!PKG_PATHS[@]}"; do
          [[ $i -eq $j ]] && continue
          other_path="${PKG_PATHS[$j]}"
          other_name="${PKG_NAMES[$j]}"
          if grep -r "$module_prefix/$other_path" "$dep_pkg_path" --include="*.go" -q 2>/dev/null; then
            DEP_EDGES+=("${dep_pkg_name} -> ${other_name}")
          fi
        done
      fi
    fi
  done
fi

# ─── Detect shared dependencies ──────────────────────────────────────────────

declare -a SHARED_DEPS=()

if $IS_MONOREPO && [[ ${#PKG_PATHS[@]} -gt 1 ]]; then
  # Collect all deps across packages
  tmp_all_deps=""
  for shared_pkg_path in "${PKG_PATHS[@]}"; do
    if [[ -f "$shared_pkg_path/package.json" ]]; then
      shared_deps=$(sed -n '/"dependencies"/,/}/p' "$shared_pkg_path/package.json" 2>/dev/null | grep -oE '"[^"]+":' | sed 's/"//g;s/://' | grep -v dependencies || true)
      if [[ -n "$shared_deps" ]]; then
        tmp_all_deps+="$shared_deps"$'\n'
      fi
    fi
  done

  if [[ -n "$tmp_all_deps" ]]; then
    # Find deps that appear more than once
    SHARED_DEPS=($(echo "$tmp_all_deps" | sort | uniq -c | sort -rn | awk '$1 > 1 { print $2 }' | head -10))
  fi
fi

# ─── Output ───────────────────────────────────────────────────────────────────

echo "=== MONOREPO DETECTION ==="
echo "IS_MONOREPO: $IS_MONOREPO"
echo "WORKSPACE_TYPE: ${WORKSPACE_TYPE:-none}"
echo "WORKSPACE_CONFIG: ${WORKSPACE_CONFIG:-none}"
echo "CONFIG_OVERRIDE: $CONFIG_MONOREPO"
echo "PACKAGE_COUNT: ${#PKG_NAMES[@]}"

if [[ ${#PACKAGE_PATTERNS[@]} -gt 0 ]]; then
  echo "PATTERNS:"
  for p in "${PACKAGE_PATTERNS[@]}"; do
    echo "  $p"
  done
fi

if [[ ${#PKG_NAMES[@]} -gt 0 ]]; then
  echo ""
  echo "PACKAGES:"
  for i in "${!PKG_NAMES[@]}"; do
    echo "  PACKAGE_${i}:"
    echo "    NAME: ${PKG_NAMES[$i]}"
    echo "    PATH: ${PKG_PATHS[$i]}"
    echo "    LANGUAGE: ${PKG_LANGUAGES[$i]}"
    if [[ -n "${PKG_DESCRIPTIONS[$i]}" ]]; then
      echo "    DESCRIPTION: ${PKG_DESCRIPTIONS[$i]}"
    fi
  done
fi

if [[ ${#DEP_EDGES[@]} -gt 0 ]]; then
  echo ""
  echo "DEPENDENCY_GRAPH:"
  for edge in "${DEP_EDGES[@]}"; do
    echo "  $edge"
  done
fi

if [[ ${#SHARED_DEPS[@]} -gt 0 ]]; then
  echo ""
  echo "SHARED_DEPENDENCIES:"
  for dep in "${SHARED_DEPS[@]}"; do
    echo "  $dep"
  done
fi

echo "=========================="
