#!/usr/bin/env bash
# scan.sh — File discovery, language/framework detection, and secret scanning
# Usage: scan.sh [--detect-only] [project-dir]
#   --detect-only: Skip file scanning and secret detection, only detect language/framework
#   project-dir: Directory to scan (default: current directory)

set -euo pipefail

SCAN_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DETECT_ONLY=false
PROJECT_DIR="."

# Parse arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --detect-only)
      DETECT_ONLY=true
      shift
      ;;
    *)
      PROJECT_DIR="$1"
      shift
      ;;
  esac
done

cd "$PROJECT_DIR"

# ─── Config loading ──────────────────────────────────────────────────────────

INCLUDE_PATTERNS=()
EXCLUDE_PATTERNS=()
CONFIG_FILE=".livindocs.yml"

load_config() {
  if [[ -f "$CONFIG_FILE" ]]; then
    # Parse include patterns from YAML (simple grep-based parsing)
    local in_include=false
    local in_exclude=false
    while IFS= read -r line; do
      # Detect section starts
      if echo "$line" | grep -qE '^include:'; then
        in_include=true; in_exclude=false; continue
      elif echo "$line" | grep -qE '^exclude:'; then
        in_exclude=true; in_include=false; continue
      elif echo "$line" | grep -qE '^[a-z_]+:' && ! echo "$line" | grep -qE '^\s+-'; then
        in_include=false; in_exclude=false; continue
      fi

      # Collect list items (line starts with optional spaces, dash, space)
      if $in_include && echo "$line" | grep -qE '^[[:space:]]+-[[:space:]]+'; then
        local pattern
        pattern=$(echo "$line" | sed 's/^[[:space:]]*-[[:space:]]*//' | sed 's/^"//' | sed 's/"$//' | sed "s/^'//" | sed "s/'$//")
        INCLUDE_PATTERNS+=("$pattern")
      fi
      if $in_exclude && echo "$line" | grep -qE '^[[:space:]]+-[[:space:]]+'; then
        local pattern
        pattern=$(echo "$line" | sed 's/^[[:space:]]*-[[:space:]]*//' | sed 's/^"//' | sed 's/"$//' | sed "s/^'//" | sed "s/'$//")
        EXCLUDE_PATTERNS+=("$pattern")
      fi
    done < "$CONFIG_FILE"
  fi

  # Defaults if no config or empty patterns
  if [[ ${#INCLUDE_PATTERNS[@]} -eq 0 ]]; then
    INCLUDE_PATTERNS=("src/**" "lib/**" "app/**" "cmd/**" "pkg/**" "internal/**")
  fi
  if [[ ${#EXCLUDE_PATTERNS[@]} -eq 0 ]]; then
    EXCLUDE_PATTERNS=("**/*.test.*" "**/*.spec.*" "**/__tests__/**" "**/__mocks__/**")
  fi
}

# ─── Language and framework detection ────────────────────────────────────────

LANGUAGES=()
FRAMEWORKS=()
ENTRY_POINTS=()

detect_language() {
  # JavaScript/TypeScript
  if [[ -f "package.json" ]]; then
    LANGUAGES+=("javascript")

    # Check for TypeScript
    if [[ -f "tsconfig.json" ]] || grep -q '"typescript"' package.json 2>/dev/null; then
      LANGUAGES+=("typescript")
    fi

    # Detect frameworks from package.json dependencies
    local deps
    deps=$(cat package.json)

    if echo "$deps" | grep -qE '"(express|fastify|koa|hapi)"'; then
      if echo "$deps" | grep -q '"express"'; then FRAMEWORKS+=("express"); fi
      if echo "$deps" | grep -q '"fastify"'; then FRAMEWORKS+=("fastify"); fi
      if echo "$deps" | grep -q '"koa"'; then FRAMEWORKS+=("koa"); fi
      if echo "$deps" | grep -q '"hapi"'; then FRAMEWORKS+=("hapi"); fi
    fi
    if echo "$deps" | grep -q '"react"'; then FRAMEWORKS+=("react"); fi
    if echo "$deps" | grep -q '"next"'; then FRAMEWORKS+=("next"); fi
    if echo "$deps" | grep -q '"vue"'; then FRAMEWORKS+=("vue"); fi
    if echo "$deps" | grep -q '"nuxt"'; then FRAMEWORKS+=("nuxt"); fi
    if echo "$deps" | grep -q '"angular"'; then FRAMEWORKS+=("angular"); fi
    if echo "$deps" | grep -q '"svelte"'; then FRAMEWORKS+=("svelte"); fi
    if echo "$deps" | grep -q '"nestjs"'; then FRAMEWORKS+=("nestjs"); fi
    if echo "$deps" | grep -q '"@nestjs/core"'; then FRAMEWORKS+=("nestjs"); fi

    # Detect test frameworks
    if echo "$deps" | grep -qE '"(jest|vitest|mocha|ava)"'; then
      if echo "$deps" | grep -q '"jest"'; then FRAMEWORKS+=("jest"); fi
      if echo "$deps" | grep -q '"vitest"'; then FRAMEWORKS+=("vitest"); fi
      if echo "$deps" | grep -q '"mocha"'; then FRAMEWORKS+=("mocha"); fi
    fi

    # Detect build tools
    if [[ -f "vite.config.js" ]] || [[ -f "vite.config.ts" ]]; then FRAMEWORKS+=("vite"); fi
    if [[ -f "webpack.config.js" ]] || [[ -f "webpack.config.ts" ]]; then FRAMEWORKS+=("webpack"); fi
    if [[ -f "next.config.js" ]] || [[ -f "next.config.mjs" ]] || [[ -f "next.config.ts" ]]; then
      # Ensure next is added if not already detected from deps
      if ! printf '%s\n' "${FRAMEWORKS[@]}" | grep -q '^next$'; then
        FRAMEWORKS+=("next")
      fi
    fi

    # Detect entry points
    if [[ -f "src/index.ts" ]]; then ENTRY_POINTS+=("src/index.ts");
    elif [[ -f "src/index.js" ]]; then ENTRY_POINTS+=("src/index.js");
    elif [[ -f "src/main.ts" ]]; then ENTRY_POINTS+=("src/main.ts");
    elif [[ -f "src/main.js" ]]; then ENTRY_POINTS+=("src/main.js");
    elif [[ -f "index.ts" ]]; then ENTRY_POINTS+=("index.ts");
    elif [[ -f "index.js" ]]; then ENTRY_POINTS+=("index.js");
    elif [[ -f "src/App.tsx" ]]; then ENTRY_POINTS+=("src/App.tsx");
    elif [[ -f "src/App.jsx" ]]; then ENTRY_POINTS+=("src/App.jsx");
    fi

    # Check package.json main field
    local main_field
    main_field=$(sed -n 's/.*"main"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' package.json 2>/dev/null || true)
    if [[ -n "$main_field" ]] && [[ -f "$main_field" ]]; then
      ENTRY_POINTS+=("$main_field")
    fi
  fi

  # Python
  if [[ -f "requirements.txt" ]] || [[ -f "setup.py" ]] || [[ -f "pyproject.toml" ]] || [[ -f "Pipfile" ]]; then
    LANGUAGES+=("python")

    if [[ -f "requirements.txt" ]]; then
      if grep -qi "django" requirements.txt 2>/dev/null; then FRAMEWORKS+=("django"); fi
      if grep -qi "flask" requirements.txt 2>/dev/null; then FRAMEWORKS+=("flask"); fi
      if grep -qi "fastapi" requirements.txt 2>/dev/null; then FRAMEWORKS+=("fastapi"); fi
      if grep -qi "pytest" requirements.txt 2>/dev/null; then FRAMEWORKS+=("pytest"); fi
    fi
    if [[ -f "pyproject.toml" ]]; then
      if grep -qi "django" pyproject.toml 2>/dev/null; then FRAMEWORKS+=("django"); fi
      if grep -qi "flask" pyproject.toml 2>/dev/null; then FRAMEWORKS+=("flask"); fi
      if grep -qi "fastapi" pyproject.toml 2>/dev/null; then FRAMEWORKS+=("fastapi"); fi
    fi

    # Entry points
    if [[ -f "app.py" ]]; then ENTRY_POINTS+=("app.py");
    elif [[ -f "main.py" ]]; then ENTRY_POINTS+=("main.py");
    elif [[ -f "manage.py" ]]; then ENTRY_POINTS+=("manage.py");
    elif [[ -f "src/main.py" ]]; then ENTRY_POINTS+=("src/main.py");
    fi
  fi

  # Go
  if [[ -f "go.mod" ]]; then
    LANGUAGES+=("go")

    if grep -q "gin-gonic" go.mod 2>/dev/null; then FRAMEWORKS+=("gin"); fi
    if grep -q "gorilla/mux" go.mod 2>/dev/null; then FRAMEWORKS+=("gorilla"); fi
    if grep -q "labstack/echo" go.mod 2>/dev/null; then FRAMEWORKS+=("echo"); fi
    if grep -q "gofiber/fiber" go.mod 2>/dev/null; then FRAMEWORKS+=("fiber"); fi

    if [[ -f "main.go" ]]; then ENTRY_POINTS+=("main.go");
    elif [[ -f "cmd/main.go" ]]; then ENTRY_POINTS+=("cmd/main.go");
    elif [[ -d "cmd" ]]; then
      local go_entry
      go_entry=$(find cmd -name "main.go" -maxdepth 2 2>/dev/null | head -1)
      if [[ -n "$go_entry" ]]; then ENTRY_POINTS+=("$go_entry"); fi
    fi
  fi

  # Rust
  if [[ -f "Cargo.toml" ]]; then
    LANGUAGES+=("rust")

    if grep -q "actix-web" Cargo.toml 2>/dev/null; then FRAMEWORKS+=("actix"); fi
    if grep -q "axum" Cargo.toml 2>/dev/null; then FRAMEWORKS+=("axum"); fi
    if grep -q "rocket" Cargo.toml 2>/dev/null; then FRAMEWORKS+=("rocket"); fi
    if grep -q "tokio" Cargo.toml 2>/dev/null; then FRAMEWORKS+=("tokio"); fi

    if [[ -f "src/main.rs" ]]; then ENTRY_POINTS+=("src/main.rs");
    elif [[ -f "src/lib.rs" ]]; then ENTRY_POINTS+=("src/lib.rs");
    fi
  fi

  # Ruby
  if [[ -f "Gemfile" ]]; then
    LANGUAGES+=("ruby")
    if grep -q "rails" Gemfile 2>/dev/null; then FRAMEWORKS+=("rails"); fi
    if grep -q "sinatra" Gemfile 2>/dev/null; then FRAMEWORKS+=("sinatra"); fi
  fi

  # Java/Kotlin
  if [[ -f "pom.xml" ]] || [[ -f "build.gradle" ]] || [[ -f "build.gradle.kts" ]]; then
    if [[ -f "build.gradle.kts" ]] || find . -name "*.kt" -maxdepth 3 2>/dev/null | head -1 | grep -q .; then
      LANGUAGES+=("kotlin")
    else
      LANGUAGES+=("java")
    fi
    if grep -q "spring" pom.xml 2>/dev/null || grep -q "spring" build.gradle 2>/dev/null; then
      FRAMEWORKS+=("spring")
    fi
  fi

  # Deduplicate (handle empty arrays)
  if [[ ${#LANGUAGES[@]} -gt 0 ]]; then
    LANGUAGES=($(printf '%s\n' "${LANGUAGES[@]}" | sort -u))
  fi
  if [[ ${#FRAMEWORKS[@]} -gt 0 ]]; then
    FRAMEWORKS=($(printf '%s\n' "${FRAMEWORKS[@]}" | sort -u))
  fi
  if [[ ${#ENTRY_POINTS[@]} -gt 0 ]]; then
    ENTRY_POINTS=($(printf '%s\n' "${ENTRY_POINTS[@]}" | sort -u))
  fi
}

# ─── File scanning ───────────────────────────────────────────────────────────

FILES=()
TOTAL_LINES=0
WARNINGS=()

# Hard-excluded files/dirs — never scan these regardless of config
HARD_EXCLUDES=(
  ".env" ".env.*" "*.pem" "*.key" "*.p12" "*.pfx" "*.jks"
  "credentials.json" "secrets.yml" "secrets.yaml"
  "node_modules" "dist" "build" ".git" "vendor" ".next"
  "__pycache__" ".pytest_cache" "target" ".gradle"
  "*.min.js" "*.min.css" "*.map" "*.lock"
  "package-lock.json" "yarn.lock" "pnpm-lock.yaml"
)

scan_files() {
  # Build find command with hard excludes for directories
  local all_files
  all_files=$(find . -type f \
    -not -path "*/node_modules/*" \
    -not -path "*/.git/*" \
    -not -path "*/dist/*" \
    -not -path "*/build/*" \
    -not -path "*/vendor/*" \
    -not -path "*/.next/*" \
    -not -path "*/__pycache__/*" \
    -not -path "*/.pytest_cache/*" \
    -not -path "*/target/*" \
    -not -path "*/.gradle/*" \
    -not -path "*/.livindocs/cache/*" \
    -not -name ".env" \
    -not -name ".env.*" \
    -not -name "*.pem" \
    -not -name "*.key" \
    -not -name "*.p12" \
    -not -name "*.pfx" \
    -not -name "*.jks" \
    -not -name "*.min.js" \
    -not -name "*.min.css" \
    -not -name "*.map" \
    -not -name "*.lock" \
    -not -name "package-lock.json" \
    -not -name "yarn.lock" \
    -not -name "pnpm-lock.yaml" \
    -not -name "credentials.json" \
    -not -name "secrets.yml" \
    -not -name "secrets.yaml" \
    2>/dev/null | sed 's|^\./||' | sort)

  # Apply config excludes
  local filtered_files=""
  while IFS= read -r file; do
    [[ -z "$file" ]] && continue
    local excluded=false
    for exc in "${EXCLUDE_PATTERNS[@]}"; do
      local cleaned
      cleaned=$(echo "$exc" | sed 's/^\*\*\///')
      # Check if file matches exclude pattern
      case "$file" in
        ${cleaned}*|*/${cleaned}*) excluded=true; break ;;
      esac
      # Also try matching as a glob
      if [[ "$file" == $exc ]]; then
        excluded=true; break
      fi
    done
    if ! $excluded; then
      filtered_files+="${file}"$'\n'
    fi
  done <<< "$all_files"
  all_files="$filtered_files"

  # Filter to include patterns (if a file matches ANY include pattern, it's in)
  while IFS= read -r file; do
    [[ -z "$file" ]] && continue

    local matched=false
    for inc in "${INCLUDE_PATTERNS[@]}"; do
      # Convert glob to a path prefix check
      local prefix
      prefix=$(echo "$inc" | sed 's/\*\*$//' | sed 's/\*$//')
      if [[ "$file" == ${prefix}* ]]; then
        matched=true
        break
      fi
    done

    # Also include root-level config/entry files
    if [[ "$file" != *"/"* ]]; then
      case "$file" in
        package.json|tsconfig.json|go.mod|Cargo.toml|requirements.txt|pyproject.toml|Pipfile|Gemfile|pom.xml|build.gradle*)
          matched=true ;;
        *.md|*.yml|*.yaml|*.toml|*.json)
          matched=true ;;
        Makefile|Dockerfile|docker-compose.yml)
          matched=true ;;
      esac
    fi

    if $matched; then
      # Skip binary files
      if file "$file" 2>/dev/null | grep -qiE 'binary|image data|archive' && ! file "$file" 2>/dev/null | grep -qi 'text'; then
        WARNINGS+=("BINARY_SKIP: $file")
        continue
      fi

      local lines
      lines=$(wc -l < "$file" 2>/dev/null || echo "0")
      lines=$(echo "$lines" | tr -d ' ')
      FILES+=("${file} (${lines} lines)")
      TOTAL_LINES=$((TOTAL_LINES + lines))
    fi
  done <<< "$all_files"
}

# ─── Secret scanning ────────────────────────────────────────────────────────

SECRETS_FOUND=0
SECRETS_REDACTED=0
SECRET_WARNINGS=()

# Secret patterns: name|regex
# Secret patterns using extended regex (grep -E compatible)
SECRET_PATTERNS=(
  "AWS Access Key|AKIA[0-9A-Z]{16}"
  "OpenAI API Key|sk-[a-zA-Z0-9]{20,}"
  "GitHub Token|ghp_[A-Za-z0-9]{36}"
  "GitHub Token|gho_[A-Za-z0-9]{36}"
  "GitHub Token|ghu_[A-Za-z0-9]{36}"
  "GitLab Token|glpat-[A-Za-z0-9_-]{20}"
  "Stripe Key|sk_live_[a-zA-Z0-9]{24,}"
  "Stripe Key|pk_live_[a-zA-Z0-9]{24,}"
  "Twilio|SK[a-f0-9]{32}"
  "Slack Token|xox[bpors]-[0-9a-zA-Z-]{10,}"
  "Private Key Header|-----BEGIN.*PRIVATE KEY-----"
  "JWT Token|eyJ[a-zA-Z0-9_-]+\.[a-zA-Z0-9_-]+\.[a-zA-Z0-9_-]+"
  "Database URL|(mongodb|postgresql|postgres|mysql|redis|amqp)://[^[:space:]]{8,}"
  "Generic Secret|(api_key|api_secret|secret_key|private_key|auth_token|access_token)[[:space:]]*[=:][[:space:]]*['\"][^'\"]{8,}"
  "Generic Password|(password|passwd|pwd)[[:space:]]*[=:][[:space:]]*['\"][^'\"]{8,}"
  "Google API Key|AIza[0-9A-Za-z_-]{35}"
)

scan_secrets() {
  for entry in "${FILES[@]}"; do
    local file
    file=$(echo "$entry" | sed 's/ (.*//')

    # Skip non-text files and config files that are expected to have patterns
    case "$file" in
      *.md|*.hbs|*.lock|*.svg|*.png|*.jpg) continue ;;
    esac

    for pattern_entry in "${SECRET_PATTERNS[@]}"; do
      local name regex
      name="${pattern_entry%%|*}"
      regex="${pattern_entry#*|}"

      local matches
      matches=$(grep -nE "$regex" "$file" 2>/dev/null || true)
      if [[ -n "$matches" ]]; then
        while IFS= read -r match; do
          local line_num
          line_num=$(echo "$match" | cut -d: -f1)
          SECRETS_FOUND=$((SECRETS_FOUND + 1))
          SECRETS_REDACTED=$((SECRETS_REDACTED + 1))
          SECRET_WARNINGS+=("SECRET: ${name} in ${file}:${line_num}")
        done <<< "$matches"
      fi
    done
  done
}

# ─── Main execution ─────────────────────────────────────────────────────────

load_config
detect_language

if $DETECT_ONLY; then
  echo "=== DETECT RESULTS ==="
  echo "LANGUAGES: ${LANGUAGES[*]:-none}"
  echo "FRAMEWORKS: ${FRAMEWORKS[*]:-none}"
  echo "ENTRY_POINTS: ${ENTRY_POINTS[*]:-none}"
  echo "CONFIG_EXISTS: $([[ -f "$CONFIG_FILE" ]] && echo "true" || echo "false")"
  echo "======================"
  exit 0
fi

scan_files
scan_secrets

# ─── Monorepo detection ──────────────────────────────────────────────────────

MONOREPO_INFO=""
if [[ -f "$SCAN_SCRIPT_DIR/detect-monorepo.sh" ]]; then
  MONOREPO_INFO=$(bash "$SCAN_SCRIPT_DIR/detect-monorepo.sh" --check . 2>/dev/null || true)
fi
IS_MONOREPO=$(echo "$MONOREPO_INFO" | { grep "^MONOREPO:" || true; } | awk '{print $2}')
MONOREPO_TYPE=$(echo "$MONOREPO_INFO" | { grep "^TYPE:" || true; } | awk '{print $2}')

# ─── Output ──────────────────────────────────────────────────────────────────

echo "=== SCAN RESULTS ==="
echo "FILES: ${#FILES[@]}"
echo "LINES: $TOTAL_LINES"
echo "LANGUAGES: ${LANGUAGES[*]:+${LANGUAGES[*]}}${LANGUAGES[*]:-none}"
echo "FRAMEWORKS: ${FRAMEWORKS[*]:+${FRAMEWORKS[*]}}${FRAMEWORKS[*]:-none}"
echo "ENTRY_POINTS: ${ENTRY_POINTS[*]:+${ENTRY_POINTS[*]}}${ENTRY_POINTS[*]:-none}"
echo "MONOREPO: ${IS_MONOREPO:-false}"
if [[ "${IS_MONOREPO}" == "true" ]]; then
  echo "MONOREPO_TYPE: ${MONOREPO_TYPE:-unknown}"
fi
echo "SECRETS: ${SECRETS_FOUND} found, ${SECRETS_REDACTED} redacted"

if [[ ${#WARNINGS[@]} -gt 0 ]]; then
  echo "WARNINGS:"
  for w in "${WARNINGS[@]}"; do
    echo "  $w"
  done
fi

if [[ ${#SECRET_WARNINGS[@]} -gt 0 ]]; then
  echo "SECRET_WARNINGS:"
  for w in "${SECRET_WARNINGS[@]}"; do
    echo "  $w"
  done
fi

echo "FILE_LIST:"
for f in "${FILES[@]}"; do
  echo "  $f"
done
echo "===================="
