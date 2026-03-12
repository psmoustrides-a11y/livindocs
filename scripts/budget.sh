#!/usr/bin/env bash
# budget.sh — Scope estimation and budget enforcement
# Usage: budget.sh [project-dir]
# Reads scan output from stdin (piped from scan.sh)
# Reads .livindocs.yml for budget config

set -euo pipefail

PROJECT_DIR="${1:-.}"
cd "$PROJECT_DIR"

CONFIG_FILE=".livindocs.yml"

# ─── Read scan output from stdin ─────────────────────────────────────────────

SCAN_OUTPUT=$(cat)
FILE_COUNT=$(echo "$SCAN_OUTPUT" | grep '^FILES:' | awk '{print $2}')
LINE_COUNT=$(echo "$SCAN_OUTPUT" | grep '^LINES:' | awk '{print $2}')
LANGUAGES=$(echo "$SCAN_OUTPUT" | grep '^LANGUAGES:' | cut -d' ' -f2-)

FILE_COUNT=${FILE_COUNT:-0}
LINE_COUNT=${LINE_COUNT:-0}

# ─── Load budget config ─────────────────────────────────────────────────────

PRESET="balanced"
QUALITY_PROFILE="standard"
MAX_TOKENS=""
WARN_THRESHOLD=""
AUTO_APPROVE=""
SUMMARIZATION_THRESHOLD="500"

load_budget_config() {
  if [[ ! -f "$CONFIG_FILE" ]]; then
    return
  fi

  # Parse budget preset
  local preset_val
  preset_val=$(grep -A5 '^budget:' "$CONFIG_FILE" 2>/dev/null | grep 'preset:' | awk '{print $2}' || true)
  if [[ -n "$preset_val" ]]; then
    PRESET="$preset_val"
  fi

  # Parse explicit budget values (override preset)
  local max_val warn_val auto_val summ_val
  max_val=$(grep -A10 '^budget:' "$CONFIG_FILE" 2>/dev/null | grep 'max_tokens_per_run:' | awk '{print $2}' || true)
  warn_val=$(grep -A10 '^budget:' "$CONFIG_FILE" 2>/dev/null | grep 'warn_threshold:' | awk '{print $2}' || true)
  auto_val=$(grep -A10 '^budget:' "$CONFIG_FILE" 2>/dev/null | grep 'auto_approve_below:' | awk '{print $2}' || true)
  summ_val=$(grep -A10 '^budget:' "$CONFIG_FILE" 2>/dev/null | grep 'summarization_threshold:' | awk '{print $2}' || true)

  if [[ -n "$max_val" && "$max_val" != "null" ]]; then MAX_TOKENS="$max_val"; fi
  if [[ -n "$warn_val" ]]; then WARN_THRESHOLD="$warn_val"; fi
  if [[ -n "$auto_val" ]]; then AUTO_APPROVE="$auto_val"; fi
  if [[ -n "$summ_val" ]]; then SUMMARIZATION_THRESHOLD="$summ_val"; fi

  # Parse quality profile
  local quality_val
  quality_val=$(grep -A5 '^quality:' "$CONFIG_FILE" 2>/dev/null | grep 'profile:' | awk '{print $2}' || true)
  if [[ -n "$quality_val" ]]; then
    QUALITY_PROFILE="$quality_val"
  fi
}

# ─── Apply preset defaults ──────────────────────────────────────────────────

apply_preset() {
  case "$PRESET" in
    frugal)
      WARN_THRESHOLD="${WARN_THRESHOLD:-50000}"
      AUTO_APPROVE="${AUTO_APPROVE:-20000}"
      MAX_TOKENS="${MAX_TOKENS:-100000}"
      QUALITY_PROFILE="${QUALITY_PROFILE:-minimal}"
      ;;
    balanced)
      WARN_THRESHOLD="${WARN_THRESHOLD:-150000}"
      AUTO_APPROVE="${AUTO_APPROVE:-50000}"
      MAX_TOKENS="${MAX_TOKENS:-}"
      QUALITY_PROFILE="${QUALITY_PROFILE:-standard}"
      ;;
    quality-first)
      WARN_THRESHOLD="${WARN_THRESHOLD:-300000}"
      AUTO_APPROVE="${AUTO_APPROVE:-100000}"
      MAX_TOKENS="${MAX_TOKENS:-}"
      QUALITY_PROFILE="${QUALITY_PROFILE:-thorough}"
      ;;
    *)
      # Default to balanced
      WARN_THRESHOLD="${WARN_THRESHOLD:-150000}"
      AUTO_APPROVE="${AUTO_APPROVE:-50000}"
      MAX_TOKENS="${MAX_TOKENS:-}"
      QUALITY_PROFILE="${QUALITY_PROFILE:-standard}"
      ;;
  esac
}

# ─── Token estimation ───────────────────────────────────────────────────────

estimate_tokens() {
  # Bytes-to-tokens ratio varies by language
  local ratio=3.8  # default
  case "$LANGUAGES" in
    *typescript*|*javascript*) ratio=3.5 ;;
    *python*) ratio=4.0 ;;
    *go*) ratio=3.6 ;;
    *rust*) ratio=3.4 ;;
    *java*|*kotlin*) ratio=3.3 ;;
    *ruby*) ratio=4.2 ;;
  esac

  # Estimate total source bytes from line count (avg ~40 bytes/line)
  local total_bytes=$((LINE_COUNT * 40))
  local base_tokens
  base_tokens=$(echo "$total_bytes / $ratio" | bc 2>/dev/null || echo "$((total_bytes * 10 / ${ratio/./}))")

  # Calculate per-pass estimates
  # Pass 1: Structural scan — deterministic, 0 tokens
  local pass_structural=0

  # Pass 2: Analysis — reads source files, produces ProjectContext
  # ~40% of total source tokens as input, ~3K output
  local pass_analysis_input=$((base_tokens * 40 / 100))
  local pass_analysis_output=3000
  local pass_analysis=$((pass_analysis_input + pass_analysis_output))

  # Pass 3: Generation — reads ProjectContext (~5K), produces doc (~4K)
  local pass_generation=$((5000 + 4000))

  # Pass 4: Review — reads doc + context for critique
  # Quality profile multiplier
  local pass_review=0
  case "$QUALITY_PROFILE" in
    minimal)
      pass_review=0
      ;;
    standard)
      pass_review=$((pass_generation * 130 / 100))  # 1.3x
      ;;
    thorough)
      pass_review=$((pass_generation * 160 / 100))  # 1.6x with extra iteration
      ;;
  esac

  PASS_STRUCTURAL=$pass_structural
  PASS_ANALYSIS=$pass_analysis
  PASS_GENERATION=$pass_generation
  PASS_REVIEW=$pass_review
  ESTIMATED_TOTAL=$((pass_structural + pass_analysis + pass_generation + pass_review))

  # Chunking info
  local files_per_chunk=50
  CHUNK_COUNT=$(( (FILE_COUNT + files_per_chunk - 1) / files_per_chunk ))
  if [[ $CHUNK_COUNT -lt 1 ]]; then CHUNK_COUNT=1; fi

  # Count files over summarization threshold
  OVERSIZED_FILES=0
  while IFS= read -r line; do
    local lines_in_file
    lines_in_file=$(echo "$line" | grep -oE '[0-9]+ lines' | grep -oE '[0-9]+' || echo "0")
    if [[ $lines_in_file -gt $SUMMARIZATION_THRESHOLD ]]; then
      OVERSIZED_FILES=$((OVERSIZED_FILES + 1))
    fi
  done <<< "$(echo "$SCAN_OUTPUT" | sed -n '/^FILE_LIST:/,/^====/p' | grep -v '^FILE_LIST:' | grep -v '^====' || true)"
}

# ─── Budget enforcement ─────────────────────────────────────────────────────

enforce_budget() {
  # Check hard ceiling
  if [[ -n "$MAX_TOKENS" ]] && [[ $ESTIMATED_TOTAL -gt $MAX_TOKENS ]]; then
    DECISION="ABORT"
    DECISION_MSG="Estimated ${ESTIMATED_TOTAL} tokens exceeds max_tokens_per_run (${MAX_TOKENS}). Reduce scope with include/exclude patterns or increase budget limit."
    return
  fi

  # Check warn threshold
  if [[ $ESTIMATED_TOTAL -gt $WARN_THRESHOLD ]]; then
    DECISION="WARN"
    DECISION_MSG="Estimated ${ESTIMATED_TOTAL} tokens (${FILE_COUNT} files, ${CHUNK_COUNT} chunks). This is a large run. Proceed?"
    return
  fi

  # Check auto-approve
  if [[ $ESTIMATED_TOTAL -le $AUTO_APPROVE ]]; then
    DECISION="SILENT"
    DECISION_MSG=""
    return
  fi

  # Between auto-approve and warn — still proceed but note
  DECISION="SILENT"
  DECISION_MSG=""
}

# ─── Main ────────────────────────────────────────────────────────────────────

load_budget_config
apply_preset
estimate_tokens
enforce_budget

# ─── Output ──────────────────────────────────────────────────────────────────

echo "=== BUDGET ESTIMATE ==="
echo "PRESET: $PRESET"
echo "QUALITY_PROFILE: $QUALITY_PROFILE"
echo "FILES: $FILE_COUNT"
echo "LINES: $LINE_COUNT"
echo "CHUNKS: $CHUNK_COUNT"
echo "OVERSIZED_FILES: $OVERSIZED_FILES (>${SUMMARIZATION_THRESHOLD} lines)"
echo "ESTIMATED_TOKENS: $ESTIMATED_TOTAL"
echo "PASS_BREAKDOWN: structural=$PASS_STRUCTURAL analysis=$PASS_ANALYSIS generation=$PASS_GENERATION review=$PASS_REVIEW"
echo "LIMITS: max=${MAX_TOKENS:-unlimited} warn=${WARN_THRESHOLD} auto_approve=${AUTO_APPROVE}"
echo "DECISION: $DECISION"
if [[ -n "${DECISION_MSG:-}" ]]; then
  echo "DECISION_MSG: $DECISION_MSG"
fi
echo "========================"
