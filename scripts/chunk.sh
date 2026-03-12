#!/usr/bin/env bash
# chunk.sh — Group files into chunks for multi-pass analysis
# Usage: chunk.sh [project-dir]
# Reads scan output from stdin, groups files by directory, outputs a chunk plan.
# Respects max_files_per_chunk and summarization_threshold from .livindocs.yml.

set -euo pipefail

PROJECT_DIR="${1:-.}"
cd "$PROJECT_DIR"

CONFIG_FILE=".livindocs.yml"

# ─── Defaults ─────────────────────────────────────────────────────────────────

MAX_FILES_PER_CHUNK=50
SUMMARIZATION_THRESHOLD=500
PRIORITY="entry-points-first"

# ─── Load config ──────────────────────────────────────────────────────────────

load_chunk_config() {
  if [[ ! -f "$CONFIG_FILE" ]]; then
    return
  fi

  local val
  val=$(grep -A10 '^budget:' "$CONFIG_FILE" 2>/dev/null | grep 'summarization_threshold:' | awk '{print $2}' || true)
  if [[ -n "$val" ]]; then
    SUMMARIZATION_THRESHOLD="$val"
  fi

  val=$(grep -A10 '^chunking:' "$CONFIG_FILE" 2>/dev/null | grep 'max_files_per_chunk:' | awk '{print $2}' || true)
  if [[ -n "$val" ]]; then
    MAX_FILES_PER_CHUNK="$val"
  fi

  val=$(grep -A10 '^chunking:' "$CONFIG_FILE" 2>/dev/null | grep 'priority:' | awk '{print $2}' || true)
  if [[ -n "$val" ]]; then
    PRIORITY="$val"
  fi
}

# ─── Parse scan output ───────────────────────────────────────────────────────

SCAN_OUTPUT=$(cat)

# Extract entry points for priority sorting
ENTRY_POINTS=""
in_entry=false
while IFS= read -r line; do
  if [[ "$line" == "ENTRY_POINTS:"* ]]; then
    ENTRY_POINTS=$(echo "$line" | sed 's/^ENTRY_POINTS:[[:space:]]*//')
    continue
  fi
done <<< "$SCAN_OUTPUT"

# Extract file list with line counts
declare -a FILE_PATHS=()
declare -a FILE_LINES=()
declare -a FILE_DIRS=()

in_file_list=false
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
    local_path=$(echo "$line" | sed 's/^[[:space:]]*//' | sed 's/ ([0-9]* lines)$//')
    local_lines=$(echo "$line" | grep -oE '[0-9]+ lines' | grep -oE '[0-9]+' || echo "0")
    local_dir=$(dirname "$local_path")

    [[ -z "$local_path" ]] && continue

    FILE_PATHS+=("$local_path")
    FILE_LINES+=("${local_lines:-0}")
    FILE_DIRS+=("$local_dir")
  fi
done <<< "$SCAN_OUTPUT"

TOTAL_FILES=${#FILE_PATHS[@]}

if [[ $TOTAL_FILES -eq 0 ]]; then
  echo "=== CHUNK PLAN ==="
  echo "TOTAL_FILES: 0"
  echo "CHUNKS: 0"
  echo "OVERSIZED_FILES: 0"
  echo "==================="
  exit 0
fi

# ─── Identify oversized files ────────────────────────────────────────────────

declare -a OVERSIZED=()
for i in "${!FILE_PATHS[@]}"; do
  if [[ ${FILE_LINES[$i]} -gt $SUMMARIZATION_THRESHOLD ]]; then
    OVERSIZED+=("${FILE_PATHS[$i]}")
  fi
done

# ─── Group files by top-level directory ───────────────────────────────────────

# Get unique directories
declare -a UNIQUE_DIRS=()
if [[ ${#FILE_DIRS[@]} -gt 0 ]]; then
  while IFS= read -r dir; do
    UNIQUE_DIRS+=("$dir")
  done < <(printf '%s\n' "${FILE_DIRS[@]}" | sort -u)
fi

# ─── Build chunks ────────────────────────────────────────────────────────────

declare -a CHUNK_NAMES=()
declare -a CHUNK_FILES=()
declare -a CHUNK_SIZES=()
declare -a CHUNK_EST_LINES=()

current_chunk_name=""
current_chunk_files=""
current_chunk_count=0
current_chunk_lines=0
chunk_index=0

flush_chunk() {
  if [[ $current_chunk_count -gt 0 ]]; then
    CHUNK_NAMES+=("$current_chunk_name")
    CHUNK_FILES+=("$current_chunk_files")
    CHUNK_SIZES+=("$current_chunk_count")
    CHUNK_EST_LINES+=("$current_chunk_lines")
    chunk_index=$((chunk_index + 1))
  fi
  current_chunk_files=""
  current_chunk_count=0
  current_chunk_lines=0
}

# Sort files: entry points first if configured
if [[ "$PRIORITY" == "entry-points-first" && -n "$ENTRY_POINTS" ]]; then
  # Process entry point files first in a special chunk
  current_chunk_name="entry-points"
  for i in "${!FILE_PATHS[@]}"; do
    if echo "$ENTRY_POINTS" | grep -qF "${FILE_PATHS[$i]}"; then
      if [[ $current_chunk_count -ge $MAX_FILES_PER_CHUNK ]]; then
        flush_chunk
        current_chunk_name="entry-points-${chunk_index}"
      fi
      if [[ -n "$current_chunk_files" ]]; then
        current_chunk_files="${current_chunk_files}|${FILE_PATHS[$i]}"
      else
        current_chunk_files="${FILE_PATHS[$i]}"
      fi
      current_chunk_count=$((current_chunk_count + 1))
      current_chunk_lines=$((current_chunk_lines + FILE_LINES[i]))
    fi
  done
  flush_chunk
fi

# Process remaining files grouped by directory
for dir in "${UNIQUE_DIRS[@]}"; do
  current_chunk_name="$dir"

  for i in "${!FILE_PATHS[@]}"; do
    # Skip entry points if already processed
    if [[ "$PRIORITY" == "entry-points-first" && -n "$ENTRY_POINTS" ]]; then
      if echo "$ENTRY_POINTS" | grep -qF "${FILE_PATHS[$i]}"; then
        continue
      fi
    fi

    if [[ "${FILE_DIRS[$i]}" == "$dir" ]]; then
      if [[ $current_chunk_count -ge $MAX_FILES_PER_CHUNK ]]; then
        flush_chunk
        current_chunk_name="${dir}-${chunk_index}"
      fi
      if [[ -n "$current_chunk_files" ]]; then
        current_chunk_files="${current_chunk_files}|${FILE_PATHS[$i]}"
      else
        current_chunk_files="${FILE_PATHS[$i]}"
      fi
      current_chunk_count=$((current_chunk_count + 1))
      current_chunk_lines=$((current_chunk_lines + FILE_LINES[i]))
    fi
  done

  flush_chunk
done

TOTAL_CHUNKS=${#CHUNK_NAMES[@]}

# ─── Estimate tokens per chunk ───────────────────────────────────────────────
# ~40 bytes/line, ~3.5 bytes/token average

declare -a CHUNK_EST_TOKENS=()
TOTAL_EST_TOKENS=0
for i in "${!CHUNK_EST_LINES[@]}"; do
  local_tokens=$(( CHUNK_EST_LINES[i] * 40 * 10 / 35 ))
  CHUNK_EST_TOKENS+=("$local_tokens")
  TOTAL_EST_TOKENS=$((TOTAL_EST_TOKENS + local_tokens))
done

# ─── Output ──────────────────────────────────────────────────────────────────

echo "=== CHUNK PLAN ==="
echo "TOTAL_FILES: $TOTAL_FILES"
echo "CHUNKS: $TOTAL_CHUNKS"
echo "MAX_FILES_PER_CHUNK: $MAX_FILES_PER_CHUNK"
echo "SUMMARIZATION_THRESHOLD: $SUMMARIZATION_THRESHOLD"
echo "OVERSIZED_FILES: ${#OVERSIZED[@]}"
echo "TOTAL_EST_TOKENS: $TOTAL_EST_TOKENS"
echo "PRIORITY: $PRIORITY"
echo ""

for i in "${!CHUNK_NAMES[@]}"; do
  echo "CHUNK_${i}:"
  echo "  NAME: ${CHUNK_NAMES[$i]}"
  echo "  FILES: ${CHUNK_SIZES[$i]}"
  echo "  LINES: ${CHUNK_EST_LINES[$i]}"
  echo "  EST_TOKENS: ${CHUNK_EST_TOKENS[$i]}"
  # Print file list (pipe-separated)
  echo "  FILE_LIST: ${CHUNK_FILES[$i]}"
done

if [[ ${#OVERSIZED[@]} -gt 0 ]]; then
  echo ""
  echo "OVERSIZED:"
  for f in "${OVERSIZED[@]}"; do
    echo "  $f"
  done
fi

echo "==================="
