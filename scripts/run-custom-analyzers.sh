#!/usr/bin/env bash
# run-custom-analyzers.sh — Discover and run custom analyzer plugins
# Usage:
#   run-custom-analyzers.sh list [project-dir]     — List discovered custom analyzers
#   run-custom-analyzers.sh run <name> [project-dir] — Run a specific custom analyzer
#   run-custom-analyzers.sh run-all [project-dir]  — Run all custom analyzers
#
# Custom analyzers are shell scripts in .livindocs/analyzers/ that follow the
# analyzer interface: accept a project dir, output structured findings.
#
# Custom generators are markdown agent definitions in .livindocs/generators/
# that define doc generation agents.

set -euo pipefail

COMMAND="${1:?Usage: run-custom-analyzers.sh <list|run|run-all> [name] [project-dir]}"
shift

# Parse args based on command
ANALYZER_NAME=""
PROJECT_DIR="."

case "$COMMAND" in
  run)
    ANALYZER_NAME="${1:?Usage: run-custom-analyzers.sh run <name> [project-dir]}"
    shift
    PROJECT_DIR="${1:-.}"
    ;;
  list|run-all)
    PROJECT_DIR="${1:-.}"
    ;;
  *)
    echo "Unknown command: $COMMAND" >&2
    echo "Usage: run-custom-analyzers.sh <list|run|run-all> [name] [project-dir]" >&2
    exit 1
    ;;
esac

cd "$PROJECT_DIR"

ANALYZERS_DIR=".livindocs/analyzers"
GENERATORS_DIR=".livindocs/generators"

# ─── Discover analyzers ──────────────────────────────────────────────────────

discover_analyzers() {
  # Shell script analyzers (.sh files)
  if [[ -d "$ANALYZERS_DIR" ]]; then
    for f in "$ANALYZERS_DIR"/*.sh; do
      [[ ! -f "$f" ]] && continue
      local name
      name=$(basename "$f" .sh)

      # Read metadata from header comments
      local description=""
      local file_filter=""
      description=$(sed -n 's/^#[[:space:]]*description:[[:space:]]*//p' "$f" 2>/dev/null | head -1 || true)
      file_filter=$(sed -n 's/^#[[:space:]]*file-filter:[[:space:]]*//p' "$f" 2>/dev/null | head -1 || true)

      echo "ANALYZER:"
      echo "  NAME: $name"
      echo "  TYPE: script"
      echo "  PATH: $f"
      echo "  DESCRIPTION: ${description:-No description}"
      echo "  FILE_FILTER: ${file_filter:-*}"
      echo "  ---"
    done
  fi

  # Markdown agent analyzers (.md files)
  if [[ -d "$ANALYZERS_DIR" ]]; then
    for f in "$ANALYZERS_DIR"/*.md; do
      [[ ! -f "$f" ]] && continue
      local name
      name=$(basename "$f" .md)

      # Read frontmatter
      local description=""
      local file_filter=""
      description=$(sed -n '/^---$/,/^---$/{ s/^description:[[:space:]]*//p; }' "$f" 2>/dev/null | head -1 || true)
      file_filter=$(sed -n '/^---$/,/^---$/{ s/^file-filter:[[:space:]]*//p; }' "$f" 2>/dev/null | head -1 || true)

      echo "ANALYZER:"
      echo "  NAME: $name"
      echo "  TYPE: agent"
      echo "  PATH: $f"
      echo "  DESCRIPTION: ${description:-No description}"
      echo "  FILE_FILTER: ${file_filter:-*}"
      echo "  ---"
    done
  fi
}

discover_generators() {
  if [[ ! -d "$GENERATORS_DIR" ]]; then
    return
  fi

  for f in "$GENERATORS_DIR"/*.md; do
    [[ ! -f "$f" ]] && continue
    local name
    name=$(basename "$f" .md)

    local description=""
    local output_file=""
    description=$(sed -n '/^---$/,/^---$/{ s/^description:[[:space:]]*//p; }' "$f" 2>/dev/null | head -1 || true)
    output_file=$(sed -n '/^---$/,/^---$/{ s/^output-file:[[:space:]]*//p; }' "$f" 2>/dev/null | head -1 || true)

    echo "GENERATOR:"
    echo "  NAME: $name"
    echo "  PATH: $f"
    echo "  DESCRIPTION: ${description:-No description}"
    echo "  OUTPUT_FILE: ${output_file:-docs/${name}.md}"
    echo "  ---"
  done
}

# ─── Run a script analyzer ────────────────────────────────────────────────────

run_analyzer_script() {
  local script_path="$1"

  if [[ ! -x "$script_path" ]]; then
    chmod +x "$script_path" 2>/dev/null || true
  fi

  echo "=== CUSTOM ANALYZER OUTPUT ==="
  echo "ANALYZER: $(basename "$script_path" .sh)"
  echo "TYPE: script"
  echo ""

  # Run the script, passing the project directory
  if bash "$script_path" . 2>&1; then
    echo ""
    echo "STATUS: success"
  else
    echo ""
    echo "STATUS: error"
    echo "EXIT_CODE: $?"
  fi

  echo "==============================="
}

# ─── Command: list ────────────────────────────────────────────────────────────

cmd_list() {
  echo "=== CUSTOM PLUGINS ==="

  local analyzer_count=0
  local generator_count=0

  if [[ -d "$ANALYZERS_DIR" ]]; then
    local sh_count md_count
    sh_count=$(find "$ANALYZERS_DIR" -name "*.sh" -type f 2>/dev/null | wc -l | tr -d ' ')
    md_count=$(find "$ANALYZERS_DIR" -name "*.md" -type f 2>/dev/null | wc -l | tr -d ' ')
    analyzer_count=$((sh_count + md_count))
  fi

  if [[ -d "$GENERATORS_DIR" ]]; then
    generator_count=$(find "$GENERATORS_DIR" -name "*.md" -type f 2>/dev/null | wc -l | tr -d ' ')
  fi

  echo "ANALYZERS_DIR: $ANALYZERS_DIR"
  echo "GENERATORS_DIR: $GENERATORS_DIR"
  echo "ANALYZER_COUNT: $analyzer_count"
  echo "GENERATOR_COUNT: $generator_count"
  echo ""

  if [[ $analyzer_count -gt 0 ]]; then
    discover_analyzers
  fi

  if [[ $generator_count -gt 0 ]]; then
    discover_generators
  fi

  if [[ $analyzer_count -eq 0 && $generator_count -eq 0 ]]; then
    echo "NO_PLUGINS_FOUND"
    echo "To add custom analyzers, create scripts in $ANALYZERS_DIR/"
    echo "To add custom generators, create agent definitions in $GENERATORS_DIR/"
  fi

  echo "======================="
}

# ─── Command: run ─────────────────────────────────────────────────────────────

cmd_run() {
  local name="$ANALYZER_NAME"

  # Look for script analyzer
  if [[ -f "$ANALYZERS_DIR/${name}.sh" ]]; then
    run_analyzer_script "$ANALYZERS_DIR/${name}.sh"
    return 0
  fi

  # Look for agent analyzer
  if [[ -f "$ANALYZERS_DIR/${name}.md" ]]; then
    echo "=== CUSTOM ANALYZER OUTPUT ==="
    echo "ANALYZER: $name"
    echo "TYPE: agent"
    echo "PATH: $ANALYZERS_DIR/${name}.md"
    echo "NOTE: Agent analyzers must be run by the orchestrating skill via the Agent tool"
    echo "==============================="
    return 0
  fi

  echo "=== CUSTOM ANALYZER OUTPUT ==="
  echo "ANALYZER: $name"
  echo "STATUS: not_found"
  echo "SEARCHED: $ANALYZERS_DIR/${name}.sh, $ANALYZERS_DIR/${name}.md"
  echo "==============================="
  return 1
}

# ─── Command: run-all ────────────────────────────────────────────────────────

cmd_run_all() {
  echo "=== CUSTOM ANALYZER BATCH ==="

  local count=0

  # Run all script analyzers
  if [[ -d "$ANALYZERS_DIR" ]]; then
    for f in "$ANALYZERS_DIR"/*.sh; do
      [[ ! -f "$f" ]] && continue
      echo ""
      run_analyzer_script "$f"
      count=$((count + 1))
    done
  fi

  # List agent analyzers (they need to be run by the skill)
  if [[ -d "$ANALYZERS_DIR" ]]; then
    for f in "$ANALYZERS_DIR"/*.md; do
      [[ ! -f "$f" ]] && continue
      local name
      name=$(basename "$f" .md)
      echo ""
      echo "=== CUSTOM ANALYZER OUTPUT ==="
      echo "ANALYZER: $name"
      echo "TYPE: agent"
      echo "PATH: $f"
      echo "NOTE: Agent analyzers must be run by the orchestrating skill via the Agent tool"
      echo "==============================="
      count=$((count + 1))
    done
  fi

  echo ""
  echo "TOTAL_RUN: $count"
  echo "=============================="
}

# ─── Dispatch ─────────────────────────────────────────────────────────────────

case "$COMMAND" in
  list)    cmd_list ;;
  run)     cmd_run ;;
  run-all) cmd_run_all ;;
esac
