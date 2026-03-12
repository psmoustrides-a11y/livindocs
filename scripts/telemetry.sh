#!/usr/bin/env bash
# telemetry.sh — Opt-in anonymous telemetry management
# Usage: telemetry.sh <check|enable|disable|report|record> [command-name] [project-dir]
# Manages telemetry settings. Never collects file paths, code, secrets, or identity.
# Respects DO_NOT_TRACK environment variable.

set -euo pipefail

COMMAND="${1:-check}"

# record command takes: record <cmd-name> <project-dir>
# all other commands take: <command> <project-dir>
if [[ "$COMMAND" == "record" ]]; then
  RECORD_CMD="${2:-unknown}"
  PROJECT_DIR="${3:-.}"
else
  PROJECT_DIR="${2:-.}"
fi
cd "$PROJECT_DIR"

CONFIG_FILE=".livindocs.yml"
CACHE_DIR=".livindocs/cache"
TELEMETRY_ID_FILE=".livindocs/telemetry-id"
TELEMETRY_DATA_FILE="$CACHE_DIR/telemetry.json"

# ─── Helpers ─────────────────────────────────────────────────────────────────

read_config_value() {
  local key="$1"
  local default="$2"
  if [[ -f "$CONFIG_FILE" ]]; then
    local value
    value=$({ grep -E "^[[:space:]]*${key}:" "$CONFIG_FILE" | head -1 | sed "s/^[[:space:]]*${key}:[[:space:]]*//" | sed 's/[[:space:]]*$//' || true; })
    if [[ -n "$value" ]]; then
      echo "$value"
      return
    fi
  fi
  echo "$default"
}

is_telemetry_enabled() {
  # DO_NOT_TRACK env var always wins
  if [[ "${DO_NOT_TRACK:-}" == "1" || "${DO_NOT_TRACK:-}" == "true" ]]; then
    echo "false"
    return
  fi

  # Check config file — look for telemetry.enabled or nested under telemetry:
  if [[ -f "$CONFIG_FILE" ]]; then
    local in_telemetry=false
    while IFS= read -r line; do
      if echo "$line" | grep -qE '^telemetry:'; then
        in_telemetry=true
        continue
      fi
      if [[ "$in_telemetry" == "true" ]]; then
        # Check if we've left the telemetry section (non-indented line)
        if echo "$line" | grep -qE '^[^[:space:]]'; then
          in_telemetry=false
          continue
        fi
        if echo "$line" | grep -qE '^[[:space:]]+enabled:[[:space:]]*true'; then
          echo "true"
          return
        fi
        if echo "$line" | grep -qE '^[[:space:]]+enabled:[[:space:]]*false'; then
          echo "false"
          return
        fi
      fi
    done < "$CONFIG_FILE"
  fi

  echo "false"
}

get_anonymous_id() {
  if [[ -f "$TELEMETRY_ID_FILE" ]]; then
    cat "$TELEMETRY_ID_FILE"
  else
    echo "none"
  fi
}

generate_uuid() {
  # macOS compatible UUID generation
  if command -v uuidgen >/dev/null 2>&1; then
    uuidgen | tr '[:upper:]' '[:lower:]'
  else
    python3 -c "import uuid; print(uuid.uuid4())"
  fi
}

set_telemetry_config() {
  local value="$1"

  if [[ ! -f "$CONFIG_FILE" ]]; then
    # Create minimal config with telemetry section
    cat > "$CONFIG_FILE" << YAML
version: 1

telemetry:
  enabled: ${value}
YAML
    return
  fi

  # Check if telemetry section exists
  if grep -qE '^telemetry:' "$CONFIG_FILE"; then
    # Update existing enabled field
    if grep -qE '^[[:space:]]+enabled:' "$CONFIG_FILE"; then
      sed -i.bak "s/^\\([[:space:]]*enabled:\\)[[:space:]]*.*/\\1 ${value}/" "$CONFIG_FILE"
      rm -f "${CONFIG_FILE}.bak"
    else
      # Add enabled under telemetry section
      sed -i.bak "/^telemetry:/a\\
\\  enabled: ${value}
" "$CONFIG_FILE"
      rm -f "${CONFIG_FILE}.bak"
    fi
  else
    # Append telemetry section
    printf '\ntelemetry:\n  enabled: %s\n' "$value" >> "$CONFIG_FILE"
  fi
}

# ─── Commands ────────────────────────────────────────────────────────────────

do_check() {
  local enabled
  enabled=$(is_telemetry_enabled)
  local anon_id
  anon_id=$(get_anonymous_id)
  local dnt="false"
  if [[ "${DO_NOT_TRACK:-}" == "1" || "${DO_NOT_TRACK:-}" == "true" ]]; then
    dnt="true"
  fi

  echo "=== TELEMETRY ==="
  if [[ "$enabled" == "true" ]]; then
    echo "STATUS: enabled"
  else
    echo "STATUS: disabled"
  fi
  echo "ANONYMOUS_ID: $anon_id"
  echo "DO_NOT_TRACK: $dnt"
  echo "================="
}

do_enable() {
  local dnt="false"
  if [[ "${DO_NOT_TRACK:-}" == "1" || "${DO_NOT_TRACK:-}" == "true" ]]; then
    echo "=== TELEMETRY ==="
    echo "STATUS: disabled"
    echo "REASON: DO_NOT_TRACK environment variable is set"
    echo "================="
    exit 0
  fi

  set_telemetry_config "true"

  # Generate anonymous ID
  mkdir -p "$(dirname "$TELEMETRY_ID_FILE")"
  generate_uuid > "$TELEMETRY_ID_FILE"

  # Initialize telemetry data file
  mkdir -p "$CACHE_DIR"
  if [[ ! -f "$TELEMETRY_DATA_FILE" ]]; then
    python3 -c "
import json, datetime
data = {
    'command_counts': {},
    'languages': [],
    'repo_size_bucket': 'unknown',
    'last_reported': datetime.datetime.now(datetime.timezone.utc).isoformat()
}
with open('$TELEMETRY_DATA_FILE', 'w') as f:
    json.dump(data, f, indent=2)
"
  fi

  echo "=== TELEMETRY ==="
  echo "STATUS: enabled"
  echo "ANONYMOUS_ID: $(cat "$TELEMETRY_ID_FILE")"
  echo "DO_NOT_TRACK: false"
  echo "================="
}

do_disable() {
  set_telemetry_config "false"

  # Remove telemetry ID
  rm -f "$TELEMETRY_ID_FILE"

  echo "=== TELEMETRY ==="
  echo "STATUS: disabled"
  echo "ANONYMOUS_ID: none"
  echo "DO_NOT_TRACK: ${DO_NOT_TRACK:-false}"
  echo "================="
}

do_report() {
  local enabled
  enabled=$(is_telemetry_enabled)
  local anon_id
  anon_id=$(get_anonymous_id)
  local dnt="false"
  if [[ "${DO_NOT_TRACK:-}" == "1" || "${DO_NOT_TRACK:-}" == "true" ]]; then
    dnt="true"
  fi

  echo "=== TELEMETRY ==="
  if [[ "$enabled" == "true" ]]; then
    echo "STATUS: enabled"
  else
    echo "STATUS: disabled"
  fi
  echo "ANONYMOUS_ID: $anon_id"
  echo "DO_NOT_TRACK: $dnt"

  if [[ -f "$TELEMETRY_DATA_FILE" ]]; then
    echo ""
    echo "COLLECTED_DATA:"

    # Extract command counts
    echo "  COMMAND_COUNTS:"
    python3 -c "
import json
try:
    with open('$TELEMETRY_DATA_FILE') as f:
        data = json.load(f)
    counts = data.get('command_counts', {})
    if counts:
        for cmd, count in sorted(counts.items()):
            print(f'    {cmd}: {count}')
    else:
        print('    (none)')
except Exception:
    print('    (none)')
"

    # Extract languages
    LANGUAGES=$({ python3 -c "
import json
try:
    with open('$TELEMETRY_DATA_FILE') as f:
        data = json.load(f)
    langs = data.get('languages', [])
    if langs:
        print(', '.join(langs))
    else:
        print('(none)')
except Exception:
    print('(none)')
" 2>/dev/null || echo "(none)"; })
    echo "  LANGUAGES: $LANGUAGES"

    # Extract repo size bucket
    REPO_SIZE=$({ python3 -c "
import json
try:
    with open('$TELEMETRY_DATA_FILE') as f:
        data = json.load(f)
    print(data.get('repo_size_bucket', 'unknown'))
except Exception:
    print('unknown')
" 2>/dev/null || echo "unknown"; })
    echo "  REPO_SIZE: $REPO_SIZE"

    # Extract last reported timestamp
    LAST_REPORTED=$({ python3 -c "
import json
try:
    with open('$TELEMETRY_DATA_FILE') as f:
        data = json.load(f)
    print(data.get('last_reported', 'never'))
except Exception:
    print('never')
" 2>/dev/null || echo "never"; })
    echo "  LAST_REPORTED: $LAST_REPORTED"
  else
    echo ""
    echo "COLLECTED_DATA: none (no telemetry data file found)"
  fi

  echo "================="
}

# ─── Main ────────────────────────────────────────────────────────────────────

case "$COMMAND" in
  check)
    do_check
    ;;
  enable)
    do_enable
    ;;
  disable)
    do_disable
    ;;
  report)
    do_report
    ;;
  record)
    # Record a command execution: telemetry.sh record <command> [project-dir]
    enabled=$(is_telemetry_enabled)
    if [[ "$enabled" != "true" ]]; then
      echo "STATUS: disabled"
      exit 0
    fi
    mkdir -p "$CACHE_DIR"
    if [[ ! -f "$TELEMETRY_DATA_FILE" ]]; then
      echo '{"command_counts":{},"languages":[],"repo_size_bucket":"unknown","last_reported":"never"}' > "$TELEMETRY_DATA_FILE"
    fi
    python3 -c "
import json, datetime
with open('$TELEMETRY_DATA_FILE') as f:
    data = json.load(f)
counts = data.get('command_counts', {})
counts['$RECORD_CMD'] = counts.get('$RECORD_CMD', 0) + 1
data['command_counts'] = counts
data['last_reported'] = datetime.datetime.now(datetime.timezone.utc).isoformat()
with open('$TELEMETRY_DATA_FILE', 'w') as f:
    json.dump(data, f, indent=2)
"
    echo "STATUS: recorded"
    echo "COMMAND: $RECORD_CMD"
    ;;
  *)
    echo "Usage: telemetry.sh <check|enable|disable|report|record> [project-dir]" >&2
    exit 1
    ;;
esac
