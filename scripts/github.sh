#!/usr/bin/env bash
# github.sh — GitHub API integration via gh CLI
# Usage:
#   github.sh prs <project-dir> [--limit N]      — Fetch recent merged PRs with descriptions
#   github.sh issues <project-dir> [--limit N]    — Fetch recent closed issues
#   github.sh reviews <project-dir> <pr-number>   — Fetch review comments for a PR
#   github.sh check <project-dir>                 — Check if GitHub is available
#
# Uses gh CLI for API access. Falls back gracefully if not authenticated.
# Supports GitHub Enterprise via github.base_url in .livindocs.yml.
# Caches responses in .livindocs/cache/github/ with configurable TTL.

set -euo pipefail

COMMAND="${1:?Usage: github.sh <prs|issues|reviews|check> [project-dir] [options]}"
shift
PROJECT_DIR="${1:-.}"
shift || true

# Parse optional flags
LIMIT=20
PR_NUMBER=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --limit) LIMIT="${2:-20}"; shift 2 ;;
    *) PR_NUMBER="$1"; shift ;;
  esac
done

cd "$PROJECT_DIR"

# ─── Read config ────────────────────────────────────────────────────────────────

GITHUB_BASE_URL=""
CACHE_TTL=3600  # 1 hour default

if [[ -f ".livindocs.yml" ]]; then
  # Read github.base_url for Enterprise support
  GITHUB_BASE_URL=$(sed -n '/^github:/,/^[^ ]/{ s/^[[:space:]]*base_url:[[:space:]]*\(.*\)/\1/p; }' .livindocs.yml 2>/dev/null | sed 's/^"\(.*\)"$/\1/' | sed "s/^'\(.*\)'$/\1/" | head -1 || true)
  [[ "$GITHUB_BASE_URL" == "null" ]] && GITHUB_BASE_URL=""
fi

CACHE_DIR=".livindocs/cache/github"

# ─── Check gh CLI availability ──────────────────────────────────────────────────

check_gh() {
  if ! command -v gh >/dev/null 2>&1; then
    echo "NOT_AVAILABLE"
    echo "REASON: gh CLI not installed"
    return 1
  fi

  # Check authentication
  if ! gh auth status >/dev/null 2>&1; then
    echo "NOT_AVAILABLE"
    echo "REASON: not authenticated (run 'gh auth login')"
    return 1
  fi

  # Check if we're in a git repo with a remote
  if ! git remote get-url origin >/dev/null 2>&1; then
    echo "NOT_AVAILABLE"
    echo "REASON: no git remote 'origin' configured"
    return 1
  fi

  echo "AVAILABLE"
  return 0
}

# ─── Cache helpers ──────────────────────────────────────────────────────────────

cache_get() {
  local key="$1"
  local cache_file="${CACHE_DIR}/${key}.json"

  if [[ ! -f "$cache_file" ]]; then
    return 1
  fi

  # Check TTL
  local file_age
  if [[ "$(uname)" == "Darwin" ]]; then
    local file_mtime
    file_mtime=$(stat -f '%m' "$cache_file" 2>/dev/null || echo "0")
    local now
    now=$(date +%s)
    file_age=$((now - file_mtime))
  else
    file_age=$(( $(date +%s) - $(stat -c '%Y' "$cache_file" 2>/dev/null || echo "0") ))
  fi

  if [[ $file_age -gt $CACHE_TTL ]]; then
    return 1  # Cache expired
  fi

  cat "$cache_file"
  return 0
}

cache_put() {
  local key="$1"
  local data="$2"
  mkdir -p "$CACHE_DIR"
  echo "$data" > "${CACHE_DIR}/${key}.json"
}

# ─── Build gh flags for Enterprise ──────────────────────────────────────────────

gh_flags() {
  if [[ -n "$GITHUB_BASE_URL" ]]; then
    echo "--hostname $(echo "$GITHUB_BASE_URL" | sed 's|https\?://||' | sed 's|/.*||')"
  fi
}

# ─── Command: check ─────────────────────────────────────────────────────────────

cmd_check() {
  echo "=== GITHUB CHECK ==="

  local status
  status=$(check_gh 2>&1) || true

  if echo "$status" | grep -q "^AVAILABLE$"; then
    local repo
    repo=$(gh repo view --json nameWithOwner -q '.nameWithOwner' 2>/dev/null || echo "unknown")
    echo "STATUS: available"
    echo "REPO: $repo"
    if [[ -n "$GITHUB_BASE_URL" ]]; then
      echo "ENTERPRISE: $GITHUB_BASE_URL"
    else
      echo "ENTERPRISE: none"
    fi
  else
    echo "STATUS: not_available"
    local reason
    reason=$(echo "$status" | grep "REASON:" | head -1 || echo "REASON: unknown")
    echo "$reason"
    echo "FALLBACK: git-only analysis available"
  fi

  echo "===================="
}

# ─── Command: prs ───────────────────────────────────────────────────────────────

cmd_prs() {
  # Try cache first
  local cached
  cached=$(cache_get "prs_${LIMIT}" 2>/dev/null) || true
  if [[ -n "$cached" ]]; then
    echo "$cached"
    return 0
  fi

  # Check availability
  if ! check_gh >/dev/null 2>&1; then
    echo "=== GITHUB PRS ==="
    echo "STATUS: not_available"
    echo "FALLBACK: Use git-history.sh for commit-based analysis"
    echo "==================="
    return 0
  fi

  local output
  output=$(gh pr list --state merged --limit "$LIMIT" --json number,title,body,mergedAt,author,files,labels 2>/dev/null) || true

  if [[ -z "$output" || "$output" == "[]" ]]; then
    echo "=== GITHUB PRS ==="
    echo "STATUS: no_prs"
    echo "COUNT: 0"
    echo "==================="
    return 0
  fi

  # Cache the raw response
  cache_put "prs_${LIMIT}" "$output"

  # Format output
  echo "=== GITHUB PRS ==="
  echo "STATUS: ok"

  local count
  count=$(echo "$output" | grep -c '"number"' || echo "0")
  echo "COUNT: $count"
  echo ""
  echo "PRS:"

  # Parse with simple sed/grep (no jq dependency)
  echo "$output" | sed 's/},{/}\n{/g' | while IFS= read -r pr; do
    local num title author merged_at body
    num=$(echo "$pr" | sed -n 's/.*"number":\([0-9]*\).*/\1/p' | head -1)
    title=$(echo "$pr" | sed -n 's/.*"title":"\([^"]*\)".*/\1/p' | head -1)
    author=$(echo "$pr" | sed -n 's/.*"login":"\([^"]*\)".*/\1/p' | head -1)
    merged_at=$(echo "$pr" | sed -n 's/.*"mergedAt":"\([^"]*\)".*/\1/p' | head -1)

    [[ -z "$num" ]] && continue

    echo "  NUMBER: $num"
    echo "  TITLE: $title"
    echo "  AUTHOR: $author"
    echo "  MERGED: $merged_at"

    # Extract labels
    local labels
    labels=$(echo "$pr" | grep -oE '"name":"[^"]*"' | sed 's/"name":"//;s/"//' | paste -sd, - 2>/dev/null || true)
    [[ -n "$labels" ]] && echo "  LABELS: $labels"

    # Extract file count
    local file_count
    file_count=$(echo "$pr" | grep -c '"path"' || echo "0")
    echo "  FILES_CHANGED: $file_count"

    echo "  ---"
  done

  echo "==================="
}

# ─── Command: issues ────────────────────────────────────────────────────────────

cmd_issues() {
  # Try cache first
  local cached
  cached=$(cache_get "issues_${LIMIT}" 2>/dev/null) || true
  if [[ -n "$cached" ]]; then
    echo "$cached"
    return 0
  fi

  # Check availability
  if ! check_gh >/dev/null 2>&1; then
    echo "=== GITHUB ISSUES ==="
    echo "STATUS: not_available"
    echo "FALLBACK: Use git log commit messages for context"
    echo "====================="
    return 0
  fi

  local output
  output=$(gh issue list --state closed --limit "$LIMIT" --json number,title,body,closedAt,author,labels 2>/dev/null) || true

  if [[ -z "$output" || "$output" == "[]" ]]; then
    echo "=== GITHUB ISSUES ==="
    echo "STATUS: no_issues"
    echo "COUNT: 0"
    echo "====================="
    return 0
  fi

  cache_put "issues_${LIMIT}" "$output"

  echo "=== GITHUB ISSUES ==="
  echo "STATUS: ok"

  local count
  count=$(echo "$output" | grep -c '"number"' || echo "0")
  echo "COUNT: $count"
  echo ""
  echo "ISSUES:"

  echo "$output" | sed 's/},{/}\n{/g' | while IFS= read -r issue; do
    local num title author closed_at
    num=$(echo "$issue" | sed -n 's/.*"number":\([0-9]*\).*/\1/p' | head -1)
    title=$(echo "$issue" | sed -n 's/.*"title":"\([^"]*\)".*/\1/p' | head -1)
    author=$(echo "$issue" | sed -n 's/.*"login":"\([^"]*\)".*/\1/p' | head -1)
    closed_at=$(echo "$issue" | sed -n 's/.*"closedAt":"\([^"]*\)".*/\1/p' | head -1)

    [[ -z "$num" ]] && continue

    echo "  NUMBER: $num"
    echo "  TITLE: $title"
    echo "  AUTHOR: $author"
    echo "  CLOSED: $closed_at"

    local labels
    labels=$(echo "$issue" | grep -oE '"name":"[^"]*"' | sed 's/"name":"//;s/"//' | paste -sd, - 2>/dev/null || true)
    [[ -n "$labels" ]] && echo "  LABELS: $labels"

    echo "  ---"
  done

  echo "====================="
}

# ─── Command: reviews ───────────────────────────────────────────────────────────

cmd_reviews() {
  if [[ -z "$PR_NUMBER" ]]; then
    echo "=== GITHUB REVIEWS ==="
    echo "ERROR: PR number required. Usage: github.sh reviews <project-dir> <pr-number>"
    echo "======================"
    exit 1
  fi

  # Try cache first
  local cached
  cached=$(cache_get "reviews_${PR_NUMBER}" 2>/dev/null) || true
  if [[ -n "$cached" ]]; then
    echo "$cached"
    return 0
  fi

  # Check availability
  if ! check_gh >/dev/null 2>&1; then
    echo "=== GITHUB REVIEWS ==="
    echo "STATUS: not_available"
    echo "======================"
    return 0
  fi

  local output
  output=$(gh pr view "$PR_NUMBER" --json reviews,comments 2>/dev/null) || true

  if [[ -z "$output" ]]; then
    echo "=== GITHUB REVIEWS ==="
    echo "STATUS: not_found"
    echo "PR: $PR_NUMBER"
    echo "======================"
    return 0
  fi

  cache_put "reviews_${PR_NUMBER}" "$output"

  echo "=== GITHUB REVIEWS ==="
  echo "STATUS: ok"
  echo "PR: $PR_NUMBER"

  local review_count
  review_count=$(echo "$output" | grep -c '"state"' || echo "0")
  echo "REVIEWS: $review_count"

  local comment_count
  comment_count=$(echo "$output" | grep -c '"body"' || echo "0")
  echo "COMMENTS: $comment_count"

  echo ""
  echo "RAW:"
  echo "$output"

  echo "======================"
}

# ─── Dispatch ──────────────────────────────────────────────────────────────────

case "$COMMAND" in
  check)   cmd_check ;;
  prs)     cmd_prs ;;
  issues)  cmd_issues ;;
  reviews) cmd_reviews ;;
  *)
    echo "Unknown command: $COMMAND" >&2
    echo "Usage: github.sh <prs|issues|reviews|check> [project-dir] [options]" >&2
    exit 1
    ;;
esac
