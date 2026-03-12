#!/usr/bin/env bash
# git-history.sh — Analyze git history for architectural decisions
# Usage:
#   git-history.sh commits <project-dir> [--limit N]   — Recent commits with file stats
#   git-history.sh decisions <project-dir> [--limit N]  — Commits likely to be architectural decisions
#   git-history.sh summary <project-dir>                — High-level repo summary
#
# Designed to work without GitHub API — pure git analysis.
# Falls back gracefully if not a git repo.

set -euo pipefail

COMMAND="${1:?Usage: git-history.sh <commits|decisions|summary> [project-dir] [--limit N]}"
shift
PROJECT_DIR="${1:-.}"
shift || true

# Parse optional flags
LIMIT=50
while [[ $# -gt 0 ]]; do
  case "$1" in
    --limit) LIMIT="${2:-50}"; shift 2 ;;
    *) shift ;;
  esac
done

cd "$PROJECT_DIR"

# ─── Check if git repo ─────────────────────────────────────────────────────────

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "=== GIT HISTORY ==="
  echo "STATUS: not_a_repo"
  echo "MESSAGE: Not a git repository. ADR generation requires git history."
  echo "==================="
  exit 0
fi

# ─── Helper: get commit details ────────────────────────────────────────────────

format_commits() {
  local limit="$1"
  # Format: HASH|DATE|AUTHOR|SUBJECT|FILES_CHANGED|INSERTIONS|DELETIONS
  git log --pretty=format:'%H|%aI|%an|%s' --shortstat -n "$limit" 2>/dev/null | awk '
    /^[a-f0-9]+\|/ {
      if (line != "") print line "|" files "|" ins "|" del
      line = $0
      files = 0; ins = 0; del = 0
    }
    /files? changed/ {
      for (i = 1; i <= NF; i++) {
        if ($(i+1) ~ /files?/) files = $i + 0
        if ($i ~ /insertion/) ins = $(i-1) + 0
        if ($i ~ /deletion/) del = $(i-1) + 0
      }
    }
    END { if (line != "") print line "|" files "|" ins "|" del }
  '
}

# ─── Helper: detect decision-worthy commits ─────────────────────────────────

is_decision_commit() {
  local subject="$1"
  local files_changed="$2"
  local insertions="$3"
  local deletions="$4"

  # Large refactors (many files or large changes)
  if [[ ${files_changed:-0} -ge 10 ]]; then
    echo "large-refactor"
    return 0
  fi

  # Large net change
  local total_changes=$(( ${insertions:-0} + ${deletions:-0} ))
  if [[ $total_changes -ge 200 ]]; then
    echo "large-change"
    return 0
  fi

  # Dependency changes (keywords in subject)
  local subject_lower
  subject_lower=$(echo "$subject" | tr '[:upper:]' '[:lower:]')

  # Config/infra changes (check before dependency to avoid "deployment" matching "dep")
  if echo "$subject_lower" | grep -qE '(docker|kubernetes|k8s|terraform|ci/cd|pipeline|workflow|deploy|infra)'; then
    echo "infrastructure-change"
    return 0
  fi

  if echo "$subject_lower" | grep -qE '(add|remove|upgrade|downgrade|migrate|switch|replace|bump)[[:space:]].*(dependenc|package|library|framework|version)'; then
    echo "dependency-change"
    return 0
  fi

  # Architecture keywords
  if echo "$subject_lower" | grep -qE '(refactor|restructure|reorganize|redesign|rearchitect|migrate|extract|split|merge|consolidate|decouple|modularize)'; then
    echo "architecture-change"
    return 0
  fi

  # Breaking changes
  if echo "$subject_lower" | grep -qE '(break|breaking|deprecat|remove|drop support|rename api|new api)'; then
    echo "breaking-change"
    return 0
  fi

  return 1
}

# ─── Command: commits ──────────────────────────────────────────────────────────

cmd_commits() {
  local total_commits
  total_commits=$(git rev-list --count HEAD 2>/dev/null || echo "0")

  echo "=== GIT COMMITS ==="
  echo "TOTAL_COMMITS: $total_commits"
  echo "SHOWING: $LIMIT"
  echo ""
  echo "COMMITS:"

  format_commits "$LIMIT" | while IFS='|' read -r hash date author subject files ins del; do
    echo "  HASH: ${hash:0:12}"
    echo "  DATE: $date"
    echo "  AUTHOR: $author"
    echo "  SUBJECT: $subject"
    echo "  STATS: files=$files insertions=$ins deletions=$del"
    echo "  ---"
  done

  echo "==================="
}

# ─── Command: decisions ────────────────────────────────────────────────────────

cmd_decisions() {
  local decision_count=0

  echo "=== GIT DECISIONS ==="
  echo ""
  echo "DECISIONS:"

  { format_commits "$LIMIT" || true; } | while IFS='|' read -r hash date author subject files ins del; do
    local reason=""
    reason=$(is_decision_commit "$subject" "$files" "$ins" "$del" 2>/dev/null) || true
    [[ -z "$reason" ]] && continue

    echo "  HASH: ${hash:0:12}"
    echo "  DATE: $date"
    echo "  AUTHOR: $author"
    echo "  SUBJECT: $subject"
    echo "  REASON: $reason"
    echo "  STATS: files=$files insertions=$ins deletions=$del"

    # Get the files changed in this commit
    local changed_files
    changed_files=$(git diff-tree --no-commit-id --name-only -r "$hash" 2>/dev/null | head -20 || true)
    if [[ -n "$changed_files" ]]; then
      echo "  FILES:"
      echo "$changed_files" | while IFS= read -r f; do
        echo "    $f"
      done
    fi
    echo "  ---"
  done || true

  # Count decisions
  local count
  count=$({ format_commits "$LIMIT" || true; } | {
    local c=0
    while IFS='|' read -r hash date author subject files ins del; do
      local r=""
      r=$(is_decision_commit "$subject" "$files" "$ins" "$del" 2>/dev/null) || true
      [[ -n "$r" ]] && c=$((c + 1))
    done
    echo "$c"
  })

  echo ""
  echo "TOTAL_DECISIONS: $count"
  echo "====================="
}

# ─── Command: summary ─────────────────────────────────────────────────────────

cmd_summary() {
  local total_commits
  total_commits=$(git rev-list --count HEAD 2>/dev/null || echo "0")

  local first_commit_date
  first_commit_date=$(git log --reverse --format='%aI' | head -1 2>/dev/null || echo "unknown")

  local last_commit_date
  last_commit_date=$(git log -1 --format='%aI' 2>/dev/null || echo "unknown")

  local branch
  branch=$(git branch --show-current 2>/dev/null || echo "unknown")

  # Count unique authors
  local authors
  authors=$(git log --format='%an' | sort -u | wc -l | tr -d ' ')

  # Top contributors
  local top_contributors
  top_contributors=$(git shortlog -sn --no-merges 2>/dev/null | head -5)

  # Recent activity (commits in last 30 days)
  local recent_commits
  recent_commits=$(git log --since="30 days ago" --oneline 2>/dev/null | wc -l | tr -d ' ')

  # Most changed files
  local hotspots
  hotspots=$(git log --name-only --pretty=format: -n 100 2>/dev/null | grep -v '^$' | sort | uniq -c | sort -rn | head -10)

  # Tags
  local tags
  tags=$(git tag --sort=-creatordate 2>/dev/null | head -5)

  echo "=== GIT SUMMARY ==="
  echo "TOTAL_COMMITS: $total_commits"
  echo "BRANCH: $branch"
  echo "FIRST_COMMIT: $first_commit_date"
  echo "LAST_COMMIT: $last_commit_date"
  echo "AUTHORS: $authors"
  echo "RECENT_COMMITS_30D: $recent_commits"
  echo ""

  if [[ -n "$top_contributors" ]]; then
    echo "TOP_CONTRIBUTORS:"
    echo "$top_contributors" | while IFS= read -r line; do
      echo "  $line"
    done
    echo ""
  fi

  if [[ -n "$hotspots" ]]; then
    echo "HOTSPOTS:"
    echo "$hotspots" | while IFS= read -r line; do
      echo "  $line"
    done
    echo ""
  fi

  if [[ -n "$tags" ]]; then
    echo "RECENT_TAGS:"
    echo "$tags" | while IFS= read -r tag; do
      echo "  $tag"
    done
    echo ""
  fi

  echo "==================="
}

# ─── Dispatch ──────────────────────────────────────────────────────────────────

case "$COMMAND" in
  commits)   cmd_commits ;;
  decisions) cmd_decisions ;;
  summary)   cmd_summary ;;
  *)
    echo "Unknown command: $COMMAND" >&2
    echo "Usage: git-history.sh <commits|decisions|summary> [project-dir] [--limit N]" >&2
    exit 1
    ;;
esac
