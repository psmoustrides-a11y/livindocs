#!/usr/bin/env bash
# benchmark.sh — Performance benchmark for livindocs scripts
# Usage: benchmark.sh [--compare] <project-dir>
# Times scan.sh, chunk.sh, and budget.sh against a project directory.
# With --compare, saves results and compares against previous runs.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ─── Argument parsing ────────────────────────────────────────────────────────

COMPARE=false
PROJECT_DIR=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --compare)
      COMPARE=true
      shift
      ;;
    *)
      PROJECT_DIR="$1"
      shift
      ;;
  esac
done

if [[ -z "$PROJECT_DIR" ]]; then
  echo "Usage: benchmark.sh [--compare] <project-dir>" >&2
  exit 1
fi

if [[ ! -d "$PROJECT_DIR" ]]; then
  echo "Error: directory not found: $PROJECT_DIR" >&2
  exit 1
fi

PROJECT_DIR="$(cd "$PROJECT_DIR" && pwd)"

# ─── Millisecond timestamp (macOS compatible) ────────────────────────────────

now_ms() {
  python3 -c "import time; print(int(time.time()*1000))"
}

# ─── Run benchmarks ─────────────────────────────────────────────────────────

# Run scan.sh and capture output (needed for chunk.sh and budget.sh)
START=$(now_ms)
SCAN_OUTPUT=$(bash "$SCRIPT_DIR/scan.sh" "$PROJECT_DIR" 2>/dev/null)
END=$(now_ms)
SCAN_MS=$((END - START))

# Extract file and line counts from scan output
FILE_COUNT=$({ echo "$SCAN_OUTPUT" | grep '^FILES:' | awk '{print $2}' || true; })
LINE_COUNT=$({ echo "$SCAN_OUTPUT" | grep '^LINES:' | awk '{print $2}' || true; })
FILE_COUNT=${FILE_COUNT:-0}
LINE_COUNT=${LINE_COUNT:-0}

# Run chunk.sh
START=$(now_ms)
echo "$SCAN_OUTPUT" | bash "$SCRIPT_DIR/chunk.sh" "$PROJECT_DIR" >/dev/null 2>/dev/null
END=$(now_ms)
CHUNK_MS=$((END - START))

# Run budget.sh
START=$(now_ms)
echo "$SCAN_OUTPUT" | bash "$SCRIPT_DIR/budget.sh" "$PROJECT_DIR" >/dev/null 2>/dev/null
END=$(now_ms)
BUDGET_MS=$((END - START))

TOTAL_MS=$((SCAN_MS + CHUNK_MS + BUDGET_MS))

# ─── Output results ─────────────────────────────────────────────────────────

echo "=== BENCHMARK RESULTS ==="
echo "PROJECT: $PROJECT_DIR"
echo "FILES: $FILE_COUNT"
echo "LINES: $LINE_COUNT"
echo ""
echo "TIMINGS:"
echo "  scan.sh: ${SCAN_MS}ms"
echo "  chunk.sh: ${CHUNK_MS}ms"
echo "  budget.sh: ${BUDGET_MS}ms"
echo ""
echo "TOTAL: ${TOTAL_MS}ms"

# ─── Comparison mode ─────────────────────────────────────────────────────────

if [[ "$COMPARE" == "true" ]]; then
  CACHE_DIR="$PROJECT_DIR/.livindocs/cache"
  BENCHMARK_FILE="$CACHE_DIR/benchmark.json"

  # Load previous results if they exist
  if [[ -f "$BENCHMARK_FILE" ]]; then
    PREV_SCAN=$({ python3 -c "import json; d=json.load(open('$BENCHMARK_FILE')); print(d.get('scan_ms', 0))" 2>/dev/null || echo "0"; })
    PREV_CHUNK=$({ python3 -c "import json; d=json.load(open('$BENCHMARK_FILE')); print(d.get('chunk_ms', 0))" 2>/dev/null || echo "0"; })
    PREV_BUDGET=$({ python3 -c "import json; d=json.load(open('$BENCHMARK_FILE')); print(d.get('budget_ms', 0))" 2>/dev/null || echo "0"; })
    PREV_TOTAL=$({ python3 -c "import json; d=json.load(open('$BENCHMARK_FILE')); print(d.get('total_ms', 0))" 2>/dev/null || echo "0"; })

    # Calculate diffs
    format_diff() {
      local name="$1"
      local current="$2"
      local previous="$3"

      if [[ "$previous" -eq 0 ]]; then
        echo "  $name: no previous data"
        return
      fi

      local diff=$((current - previous))
      local sign="+"
      local direction="slower"
      if [[ $diff -lt 0 ]]; then
        sign=""
        direction="faster"
        diff=$(( -diff ))
      fi

      local pct=0
      if [[ "$previous" -gt 0 ]]; then
        pct=$(( (diff * 100) / previous ))
      fi

      if [[ "$current" -le "$previous" ]]; then
        echo "  $name: -${diff}ms (${pct}% faster)"
      else
        echo "  $name: +${diff}ms (${pct}% slower)"
      fi
    }

    echo ""
    echo "COMPARISON:"
    format_diff "scan.sh" "$SCAN_MS" "$PREV_SCAN"
    format_diff "chunk.sh" "$CHUNK_MS" "$PREV_CHUNK"
    format_diff "budget.sh" "$BUDGET_MS" "$PREV_BUDGET"
    format_diff "TOTAL" "$TOTAL_MS" "$PREV_TOTAL"
  else
    echo ""
    echo "COMPARISON: no previous benchmark found (first run)"
  fi

  # Save current results
  mkdir -p "$CACHE_DIR"
  python3 -c "
import json, datetime
data = {
    'scan_ms': $SCAN_MS,
    'chunk_ms': $CHUNK_MS,
    'budget_ms': $BUDGET_MS,
    'total_ms': $TOTAL_MS,
    'files': $FILE_COUNT,
    'lines': $LINE_COUNT,
    'timestamp': datetime.datetime.now(datetime.timezone.utc).isoformat()
}
with open('$BENCHMARK_FILE', 'w') as f:
    json.dump(data, f, indent=2)
"
  echo "SAVED: $BENCHMARK_FILE"
fi

echo "========================="
