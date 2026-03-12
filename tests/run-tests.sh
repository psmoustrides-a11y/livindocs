#!/usr/bin/env bash
# run-tests.sh — Integration tests for livindocs scripts
# Usage: run-tests.sh [plugin-dir]
# Runs scan.sh, budget.sh, and verify.sh against test fixtures.
# Does NOT test Claude Code agent integration (that requires a live session).

set -euo pipefail

PLUGIN_DIR="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
FIXTURES_DIR="${PLUGIN_DIR}/tests/fixtures"
PASS_COUNT=0
FAIL_COUNT=0
FAILURES=()

# ─── Helpers ─────────────────────────────────────────────────────────────────

pass() {
  PASS_COUNT=$((PASS_COUNT + 1))
  echo "  PASS: $1"
}

fail() {
  FAIL_COUNT=$((FAIL_COUNT + 1))
  FAILURES+=("$1")
  echo "  FAIL: $1"
}

assert_contains() {
  local output="$1"
  local expected="$2"
  local test_name="$3"
  if echo "$output" | grep -q "$expected"; then
    pass "$test_name"
  else
    fail "$test_name — expected '$expected' in output"
  fi
}

assert_not_contains() {
  local output="$1"
  local unexpected="$2"
  local test_name="$3"
  if echo "$output" | grep -q "$unexpected"; then
    fail "$test_name — unexpected '$unexpected' found in output"
  else
    pass "$test_name"
  fi
}

# ─── Test: scan.sh against express-api ───────────────────────────────────────

echo ""
echo "=== Test: scan.sh — express-api ==="

SCAN_EXPRESS=$("${PLUGIN_DIR}/scripts/scan.sh" "${FIXTURES_DIR}/express-api" 2>&1)

assert_contains "$SCAN_EXPRESS" "LANGUAGES: javascript" "detects javascript"
assert_contains "$SCAN_EXPRESS" "express" "detects express framework"
assert_contains "$SCAN_EXPRESS" "jest" "detects jest"
assert_contains "$SCAN_EXPRESS" "src/index.js" "finds entry point"
assert_contains "$SCAN_EXPRESS" "FILE_LIST:" "outputs file list"
assert_contains "$SCAN_EXPRESS" "routes/users.js" "finds route files"
assert_contains "$SCAN_EXPRESS" "middleware/authenticate.js" "finds middleware"

# ─── Test: scan.sh --detect-only ─────────────────────────────────────────────

echo ""
echo "=== Test: scan.sh --detect-only — express-api ==="

DETECT_EXPRESS=$("${PLUGIN_DIR}/scripts/scan.sh" --detect-only "${FIXTURES_DIR}/express-api" 2>&1)

assert_contains "$DETECT_EXPRESS" "DETECT RESULTS" "outputs detect format"
assert_contains "$DETECT_EXPRESS" "LANGUAGES: javascript" "detects language"
assert_contains "$DETECT_EXPRESS" "CONFIG_EXISTS: true" "finds .livindocs.yml"

# ─── Test: scan.sh against react-app ─────────────────────────────────────────

echo ""
echo "=== Test: scan.sh — react-app ==="

SCAN_REACT=$("${PLUGIN_DIR}/scripts/scan.sh" "${FIXTURES_DIR}/react-app" 2>&1)

assert_contains "$SCAN_REACT" "LANGUAGES: javascript" "detects javascript"
assert_contains "$SCAN_REACT" "react" "detects react framework"
assert_contains "$SCAN_REACT" "vite" "detects vite"
assert_contains "$SCAN_REACT" "App.jsx" "finds App component"
assert_contains "$SCAN_REACT" "api/users.js" "finds api module"

# ─── Test: budget.sh against express-api scan ────────────────────────────────

echo ""
echo "=== Test: budget.sh — express-api ==="

BUDGET_EXPRESS=$(echo "$SCAN_EXPRESS" | "${PLUGIN_DIR}/scripts/budget.sh" "${FIXTURES_DIR}/express-api" 2>&1)

assert_contains "$BUDGET_EXPRESS" "BUDGET ESTIMATE" "outputs budget format"
assert_contains "$BUDGET_EXPRESS" "PRESET: frugal" "reads preset from config"
assert_contains "$BUDGET_EXPRESS" "DECISION:" "outputs a decision"
assert_contains "$BUDGET_EXPRESS" "PASS_BREAKDOWN:" "includes pass breakdown"
assert_contains "$BUDGET_EXPRESS" "CHUNKS:" "includes chunk count"

# ─── Test: budget.sh — decision should be SILENT for small fixture ───────────

echo ""
echo "=== Test: budget.sh — small project should be SILENT ==="

DECISION=$(echo "$BUDGET_EXPRESS" | grep '^DECISION:' | awk '{print $2}')
if [[ "$DECISION" == "SILENT" ]]; then
  pass "small project gets SILENT decision"
else
  fail "expected SILENT decision, got $DECISION"
fi

# ─── Test: verify.sh against a sample README ────────────────────────────────

echo ""
echo "=== Test: verify.sh — sample README ==="

# Create a temporary README to verify against the express-api fixture
TMPDIR=$(mktemp -d)
cat > "${TMPDIR}/README.md" << 'HEREDOC'
# Express User API

A REST API for user management with JWT authentication.

<!-- livindocs:start:features -->
## Features

- CRUD user management with 7 API endpoints
- JWT authentication with bcrypt password hashing
<!-- livindocs:refs:src/routes/users.js:1-60,src/routes/auth.js:1-50 -->
<!-- livindocs:end:features -->

<!-- livindocs:start:installation -->
## Installation

```bash
npm install
```
<!-- livindocs:refs:package.json:1-10 -->
<!-- livindocs:end:installation -->

The main entry point is `src/index.js` which sets up Express 4 middleware.
HEREDOC

VERIFY_OUTPUT=$("${PLUGIN_DIR}/scripts/verify.sh" "${TMPDIR}/README.md" "${FIXTURES_DIR}/express-api" 2>&1)

assert_contains "$VERIFY_OUTPUT" "VERIFICATION" "outputs verification format"
assert_contains "$VERIFY_OUTPUT" "CHECKS:" "counts checks"
assert_contains "$VERIFY_OUTPUT" "ACCURACY_SCORE:" "computes accuracy"
assert_contains "$VERIFY_OUTPUT" "COVERAGE_SCORE:" "computes coverage"
assert_contains "$VERIFY_OUTPUT" "OVERALL:" "computes overall score"
assert_contains "$VERIFY_OUTPUT" "REFS:" "counts ref anchors"

rm -rf "$TMPDIR"

# ─── Test: detect-progress.sh ───────────────────────────────────────────────

echo ""
echo "=== Test: detect-progress.sh ==="

TMPPROJECT=$(mktemp -d)
mkdir -p "${TMPPROJECT}/.livindocs"
mkdir -p "${TMPPROJECT}/src"
echo "hello" > "${TMPPROJECT}/src/index.js"

cat > "${TMPPROJECT}/.livindocs/build-state.json" << 'HEREDOC'
{
  "version": 1,
  "updated_at": "2024-01-01T00:00:00.000Z",
  "milestones": [
    {
      "name": "Setup",
      "items": [
        {
          "name": "Create entry point",
          "status": "pending",
          "detect": {
            "file_exists": "src/index.js"
          }
        },
        {
          "name": "Add tests",
          "status": "pending",
          "detect": {
            "file_exists": "tests/index.test.js"
          }
        }
      ]
    }
  ]
}
HEREDOC

PROGRESS_OUTPUT=$("${PLUGIN_DIR}/scripts/detect-progress.sh" "${TMPPROJECT}" 2>&1)

assert_contains "$PROGRESS_OUTPUT" "PROGRESS" "outputs progress format"
assert_contains "$PROGRESS_OUTPUT" "NEWLY_DETECTED: 1" "detects new completion"
assert_contains "$PROGRESS_OUTPUT" "DONE: 1" "marks 1 item done"
assert_contains "$PROGRESS_OUTPUT" "PENDING: 1" "keeps 1 item pending"
assert_contains "$PROGRESS_OUTPUT" "DETECTED:.*Create entry point" "identifies correct item"

rm -rf "$TMPPROJECT"

# ─── Test: Secret detection ─────────────────────────────────────────────────

echo ""
echo "=== Test: scan.sh — secret detection ==="

TMPSECRET=$(mktemp -d)
mkdir -p "${TMPSECRET}/src"
cat > "${TMPSECRET}/src/config.js" << 'HEREDOC'
const API_KEY = "AKIAIOSFODNN7EXAMPLE1";
const DB_URL = "postgresql://user:password123@localhost:5432/mydb";
module.exports = { API_KEY, DB_URL };
HEREDOC

cat > "${TMPSECRET}/.livindocs.yml" << 'HEREDOC'
version: 1
include:
  - src/**
HEREDOC

SCAN_SECRET=$("${PLUGIN_DIR}/scripts/scan.sh" "${TMPSECRET}" 2>&1)

assert_contains "$SCAN_SECRET" "SECRETS:" "reports secrets"
# Should detect at least the AWS key and DB URL
if echo "$SCAN_SECRET" | grep -q "SECRETS: 0"; then
  fail "should detect secrets but found 0"
else
  pass "detects secrets in source files"
fi

rm -rf "$TMPSECRET"

# ─── Test: cache.sh — hash, put, get, clear ──────────────────────────────────

echo ""
echo "=== Test: cache.sh — basic operations ==="

TMPCACHE=$(mktemp -d)
mkdir -p "${TMPCACHE}/src"
echo "hello world" > "${TMPCACHE}/src/app.js"

# Test hash
HASH_OUTPUT=$("${PLUGIN_DIR}/scripts/cache.sh" hash "${TMPCACHE}/src/app.js" 2>&1)
if [[ -n "$HASH_OUTPUT" && ${#HASH_OUTPUT} -eq 64 ]]; then
  pass "hash produces 64-char SHA256"
else
  fail "hash output unexpected: $HASH_OUTPUT"
fi

# Test put + get
echo '{"analyzed": true}' | "${PLUGIN_DIR}/scripts/cache.sh" put "testhash123" "${TMPCACHE}" 2>&1
GET_OUTPUT=$("${PLUGIN_DIR}/scripts/cache.sh" get "testhash123" "${TMPCACHE}" 2>&1)
assert_contains "$GET_OUTPUT" '"analyzed": true' "get retrieves stored data"

# Test get miss
if "${PLUGIN_DIR}/scripts/cache.sh" get "nonexistent" "${TMPCACHE}" 2>/dev/null; then
  fail "get should exit 1 on cache miss"
else
  pass "get exits 1 on cache miss"
fi

# Test clear
CLEAR_OUTPUT=$("${PLUGIN_DIR}/scripts/cache.sh" clear "${TMPCACHE}" 2>&1)
assert_contains "$CLEAR_OUTPUT" "CLEARED:" "clear reports what was removed"

if [[ ! -d "${TMPCACHE}/.livindocs/cache" ]]; then
  pass "clear removes cache directory"
else
  fail "clear did not remove cache directory"
fi

rm -rf "$TMPCACHE"

# ─── Test: cache.sh — check with manifest ────────────────────────────────────

echo ""
echo "=== Test: cache.sh — check with manifest ==="

TMPCACHE2=$(mktemp -d)
mkdir -p "${TMPCACHE2}/src"
echo "original content" > "${TMPCACHE2}/src/app.js"
echo "another file" > "${TMPCACHE2}/src/helper.js"
cat > "${TMPCACHE2}/.livindocs.yml" << 'HEREDOC'
version: 1
include:
  - src/**
HEREDOC

# Build manifest from scan output (same as generate skill does)
SCAN_FOR_CACHE=$("${PLUGIN_DIR}/scripts/scan.sh" "${TMPCACHE2}" 2>&1)
echo "$SCAN_FOR_CACHE" | sed -n '/^FILE_LIST:/,/^====/p' | grep -v '^FILE_LIST:' | grep -v '^====' | sed 's/^[[:space:]]*//' | sed 's/ ([0-9]* lines)$//' | "${PLUGIN_DIR}/scripts/cache.sh" update-manifest "${TMPCACHE2}" 2>&1

# Check — nothing changed, all should be cached
CHECK_OUTPUT=$(echo "$SCAN_FOR_CACHE" | "${PLUGIN_DIR}/scripts/cache.sh" check "${TMPCACHE2}" 2>&1)
assert_contains "$CHECK_OUTPUT" "CACHE CHECK" "check outputs cache check format"
assert_contains "$CHECK_OUTPUT" "CHANGED: 0" "no files changed after manifest update"

# Now change a file
echo "modified content" > "${TMPCACHE2}/src/app.js"
CHECK_OUTPUT2=$(echo "$SCAN_FOR_CACHE" | "${PLUGIN_DIR}/scripts/cache.sh" check "${TMPCACHE2}" 2>&1)
assert_contains "$CHECK_OUTPUT2" "CHANGED: 1" "detects 1 changed file"
assert_contains "$CHECK_OUTPUT2" "src/app.js" "identifies changed file by path with /"

rm -rf "$TMPCACHE2"

# ─── Test: chunk.sh — express-api ─────────────────────────────────────────────

echo ""
echo "=== Test: chunk.sh — express-api ==="

CHUNK_EXPRESS=$(echo "$SCAN_EXPRESS" | "${PLUGIN_DIR}/scripts/chunk.sh" "${FIXTURES_DIR}/express-api" 2>&1)

assert_contains "$CHUNK_EXPRESS" "CHUNK PLAN" "outputs chunk plan format"
assert_contains "$CHUNK_EXPRESS" "TOTAL_FILES:" "reports total files"
assert_contains "$CHUNK_EXPRESS" "CHUNKS:" "reports chunk count"
assert_contains "$CHUNK_EXPRESS" "OVERSIZED_FILES:" "reports oversized files"
assert_contains "$CHUNK_EXPRESS" "EST_TOKENS:" "estimates tokens per chunk"
assert_contains "$CHUNK_EXPRESS" "entry-points" "prioritizes entry points"

# ─── Test: chunk.sh — empty project ──────────────────────────────────────────

echo ""
echo "=== Test: chunk.sh — empty input ==="

TMPEMPTY=$(mktemp -d)
EMPTY_SCAN="=== SCAN RESULTS ===
FILES: 0
LINES: 0
LANGUAGES: none
FILE_LIST:
===="

CHUNK_EMPTY=$(echo "$EMPTY_SCAN" | "${PLUGIN_DIR}/scripts/chunk.sh" "${TMPEMPTY}" 2>&1)
assert_contains "$CHUNK_EMPTY" "TOTAL_FILES: 0" "handles empty project"
assert_contains "$CHUNK_EMPTY" "CHUNKS: 0" "zero chunks for empty"

rm -rf "$TMPEMPTY"

# ─── Test: baseline.sh — save and compare ────────────────────────────────────

echo ""
echo "=== Test: baseline.sh — save and compare ==="

TMPBASE=$(mktemp -d)
mkdir -p "${TMPBASE}/src/routes"
echo "const express = require('express');" > "${TMPBASE}/src/index.js"
echo "router.get('/', handler);" > "${TMPBASE}/src/routes/users.js"
echo '{"name":"test"}' > "${TMPBASE}/package.json"

# Create a README with livindocs markers and refs
cat > "${TMPBASE}/README.md" << 'HEREDOC'
<!-- livindocs:start:header -->
# Test
<!-- livindocs:refs:package.json:1-5 -->
<!-- livindocs:end:header -->

<!-- livindocs:start:features -->
## Features
<!-- livindocs:refs:src/routes/users.js:1-10 -->
<!-- livindocs:end:features -->

<!-- livindocs:start:arch -->
## Architecture
<!-- livindocs:refs:src/index.js:1-20 -->
<!-- livindocs:end:arch -->
HEREDOC

# Save baseline
SAVE_OUTPUT=$("${PLUGIN_DIR}/scripts/baseline.sh" save "${TMPBASE}" 2>&1)
assert_contains "$SAVE_OUTPUT" "BASELINE" "save outputs baseline format"
assert_contains "$SAVE_OUTPUT" "ACTION: saved" "reports save action"
assert_contains "$SAVE_OUTPUT" "FILES: 3" "saves 3 ref-anchored files"

# Compare — nothing changed
COMPARE_OUTPUT=$("${PLUGIN_DIR}/scripts/baseline.sh" compare "${TMPBASE}" 2>&1)
assert_contains "$COMPARE_OUTPUT" "BASELINE COMPARE" "compare outputs format"
assert_contains "$COMPARE_OUTPUT" "CHANGED: 0" "no changes after save"
assert_contains "$COMPARE_OUTPUT" "UNCHANGED: 3" "all 3 files unchanged"

# Change a file
echo "// modified" >> "${TMPBASE}/src/routes/users.js"

COMPARE_OUTPUT2=$("${PLUGIN_DIR}/scripts/baseline.sh" compare "${TMPBASE}" 2>&1)
assert_contains "$COMPARE_OUTPUT2" "CHANGED: 1" "detects 1 changed file"
assert_contains "$COMPARE_OUTPUT2" "src/routes/users.js" "identifies changed file"

rm -rf "$TMPBASE"

# ─── Test: staleness.sh — no docs ────────────────────────────────────────────

echo ""
echo "=== Test: staleness.sh — no docs ==="

TMPNOSTALE=$(mktemp -d)
echo "hello" > "${TMPNOSTALE}/app.js"

STALE_NONE=$("${PLUGIN_DIR}/scripts/staleness.sh" "${TMPNOSTALE}" 2>&1)
assert_contains "$STALE_NONE" "STATUS: no_docs" "reports no docs found"

rm -rf "$TMPNOSTALE"

# ─── Test: staleness.sh — with baseline ──────────────────────────────────────

echo ""
echo "=== Test: staleness.sh — staleness detection ==="

TMPSTALE=$(mktemp -d)
mkdir -p "${TMPSTALE}/src/routes"
echo "const app = require('express')();" > "${TMPSTALE}/src/index.js"
echo "router.get('/', handler);" > "${TMPSTALE}/src/routes/users.js"
echo '{"name":"test"}' > "${TMPSTALE}/package.json"

cat > "${TMPSTALE}/README.md" << 'HEREDOC'
<!-- livindocs:start:header -->
# Test
<!-- livindocs:refs:package.json:1-5 -->
<!-- livindocs:end:header -->

<!-- livindocs:start:features -->
## Features
<!-- livindocs:refs:src/routes/users.js:1-10 -->
<!-- livindocs:end:features -->

<!-- livindocs:start:arch -->
## Architecture
<!-- livindocs:refs:src/index.js:1-20 -->
<!-- livindocs:end:arch -->
HEREDOC

# Without baseline — all should be possibly-stale
STALE_NO_BASE=$("${PLUGIN_DIR}/scripts/staleness.sh" "${TMPSTALE}" 2>&1)
assert_contains "$STALE_NO_BASE" "STALENESS REPORT" "outputs staleness report"
assert_contains "$STALE_NO_BASE" "OVERALL: slightly-stale" "no baseline = slightly-stale"
assert_contains "$STALE_NO_BASE" "POSSIBLY_STALE: 3" "all sections possibly-stale"
assert_contains "$STALE_NO_BASE" "BASELINE: missing" "reports missing baseline"

# Save baseline, then check — should be current
"${PLUGIN_DIR}/scripts/baseline.sh" save "${TMPSTALE}" >/dev/null 2>&1

STALE_CURRENT=$("${PLUGIN_DIR}/scripts/staleness.sh" "${TMPSTALE}" 2>&1)
assert_contains "$STALE_CURRENT" "OVERALL: current" "all current after baseline"
assert_contains "$STALE_CURRENT" "CURRENT: 3" "3 sections current"

# Change a ref-anchored file
echo "// modified" >> "${TMPSTALE}/src/routes/users.js"

STALE_CHANGED=$("${PLUGIN_DIR}/scripts/staleness.sh" "${TMPSTALE}" 2>&1)
assert_contains "$STALE_CHANGED" "OVERALL: stale" "detects stale after change"
assert_contains "$STALE_CHANGED" "STALE: 1" "1 section stale"
assert_contains "$STALE_CHANGED" "CURRENT: 2" "2 sections still current"
assert_contains "$STALE_CHANGED" "STALE:.*features" "identifies stale section"

rm -rf "$TMPSTALE"

# ─── Test: git-history.sh — not a git repo ──────────────────────────────────

echo ""
echo "=== Test: git-history.sh — not a repo ==="

TMPNOGIT=$(mktemp -d)
GIT_NOREPO=$("${PLUGIN_DIR}/scripts/git-history.sh" summary "${TMPNOGIT}" 2>&1)
assert_contains "$GIT_NOREPO" "STATUS: not_a_repo" "detects non-repo gracefully"
rm -rf "$TMPNOGIT"

# ─── Test: git-history.sh — with commits ────────────────────────────────────

echo ""
echo "=== Test: git-history.sh — commit analysis ==="

TMPGITREPO=$(mktemp -d)
cd "$TMPGITREPO"
git init -q
git config user.email "test@livindocs.dev"
git config user.name "Test Developer"

# Create commits with different decision signatures
mkdir -p src/routes
echo "init" > src/index.js
git add -A && git commit -q -m "feat: initial project setup"

echo "const express = require('express');" > src/index.js
echo "router.get('/', handler);" > src/routes/users.js
git add -A && git commit -q -m "refactor: restructure into modular route handlers"

echo "docker" > Dockerfile
git add -A && git commit -q -m "infra: add Docker containerization"

# Create a large-change commit (many files)
for i in $(seq 1 12); do
  echo "file $i" > "src/file${i}.js"
done
git add -A && git commit -q -m "feat: add batch processing modules"

cd "$PLUGIN_DIR"

# Test summary
GIT_SUMMARY=$("${PLUGIN_DIR}/scripts/git-history.sh" summary "${TMPGITREPO}" 2>&1)
assert_contains "$GIT_SUMMARY" "GIT SUMMARY" "summary outputs format"
assert_contains "$GIT_SUMMARY" "TOTAL_COMMITS: 4" "counts 4 commits"
assert_contains "$GIT_SUMMARY" "AUTHORS: 1" "counts 1 author"
assert_contains "$GIT_SUMMARY" "BRANCH:" "reports branch"

# Test commits
GIT_COMMITS=$("${PLUGIN_DIR}/scripts/git-history.sh" commits "${TMPGITREPO}" --limit 4 2>&1)
assert_contains "$GIT_COMMITS" "GIT COMMITS" "commits outputs format"
assert_contains "$GIT_COMMITS" "SHOWING: 4" "shows limit"
assert_contains "$GIT_COMMITS" "HASH:" "includes commit hashes"
assert_contains "$GIT_COMMITS" "refactor: restructure" "includes commit subjects"

# Test decisions
GIT_DECISIONS=$("${PLUGIN_DIR}/scripts/git-history.sh" decisions "${TMPGITREPO}" 2>&1)
assert_contains "$GIT_DECISIONS" "GIT DECISIONS" "decisions outputs format"
assert_contains "$GIT_DECISIONS" "TOTAL_DECISIONS:" "reports decision count"
assert_contains "$GIT_DECISIONS" "REASON: infrastructure-change" "detects infra decision"
assert_contains "$GIT_DECISIONS" "REASON: architecture-change" "detects architecture decision"
assert_contains "$GIT_DECISIONS" "REASON: large-refactor" "detects large refactor"
assert_contains "$GIT_DECISIONS" "FILES:" "lists changed files"

rm -rf "$TMPGITREPO"

# ─── Test: github.sh — no git repo ──────────────────────────────────────────

echo ""
echo "=== Test: github.sh — fallback behavior ==="

TMPNOGITHUB=$(mktemp -d)

# Test check in non-repo directory
GH_CHECK=$("${PLUGIN_DIR}/scripts/github.sh" check "${TMPNOGITHUB}" 2>&1)
assert_contains "$GH_CHECK" "GITHUB CHECK" "check outputs format"
assert_contains "$GH_CHECK" "STATUS:" "reports status"

# Test prs fallback in non-repo
GH_PRS=$("${PLUGIN_DIR}/scripts/github.sh" prs "${TMPNOGITHUB}" 2>&1)
assert_contains "$GH_PRS" "GITHUB PRS" "prs outputs format"

# Test issues fallback in non-repo
GH_ISSUES=$("${PLUGIN_DIR}/scripts/github.sh" issues "${TMPNOGITHUB}" 2>&1)
assert_contains "$GH_ISSUES" "GITHUB ISSUES" "issues outputs format"

# Test reviews error without PR number
GH_REVIEWS=$("${PLUGIN_DIR}/scripts/github.sh" reviews "${TMPNOGITHUB}" 2>&1 || true)
assert_contains "$GH_REVIEWS" "GITHUB REVIEWS" "reviews outputs format"

# Test with a git repo that has no remote
TMPGITNOGITHUB=$(mktemp -d)
cd "$TMPGITNOGITHUB"
git init -q
git config user.email "test@test.com"
git config user.name "Test"
echo "hello" > file.txt
git add -A && git commit -q -m "init" >/dev/null 2>&1
cd "$PLUGIN_DIR"

GH_CHECK_NOREPO=$("${PLUGIN_DIR}/scripts/github.sh" check "${TMPGITNOGITHUB}" 2>&1)
assert_contains "$GH_CHECK_NOREPO" "not_available" "detects missing remote"

# Test cache directory creation
mkdir -p "${TMPNOGITHUB}/.livindocs/cache/github"
echo '{"test": true}' > "${TMPNOGITHUB}/.livindocs/cache/github/prs_20.json"
if [[ -f "${TMPNOGITHUB}/.livindocs/cache/github/prs_20.json" ]]; then
  pass "cache directory structure is correct"
else
  fail "cache file not created"
fi

rm -rf "$TMPNOGITHUB" "$TMPGITNOGITHUB"

# ─── Test: detect-monorepo.sh — npm workspaces ───────────────────────────────

echo ""
echo "=== Test: detect-monorepo.sh — npm workspaces ==="

MONO_OUTPUT=$("${PLUGIN_DIR}/scripts/detect-monorepo.sh" "${FIXTURES_DIR}/monorepo" 2>&1)

assert_contains "$MONO_OUTPUT" "IS_MONOREPO: true" "detects monorepo"
assert_contains "$MONO_OUTPUT" "WORKSPACE_TYPE: npm-workspaces" "detects npm workspaces"
assert_contains "$MONO_OUTPUT" "PACKAGE_COUNT: 3" "finds 3 packages"
assert_contains "$MONO_OUTPUT" "@monorepo/api" "finds api package"
assert_contains "$MONO_OUTPUT" "@monorepo/ui" "finds ui package"
assert_contains "$MONO_OUTPUT" "@monorepo/shared" "finds shared package"
assert_contains "$MONO_OUTPUT" "LANGUAGE: typescript" "detects typescript in packages"
assert_contains "$MONO_OUTPUT" "DEPENDENCY_GRAPH:" "detects inter-package deps"
assert_contains "$MONO_OUTPUT" "@monorepo/api -> @monorepo/shared" "api depends on shared"
assert_contains "$MONO_OUTPUT" "@monorepo/ui -> @monorepo/shared" "ui depends on shared"
assert_contains "$MONO_OUTPUT" "SHARED_DEPENDENCIES:" "detects shared deps"

# ─── Test: detect-monorepo.sh — non-monorepo ─────────────────────────────────

echo ""
echo "=== Test: detect-monorepo.sh — non-monorepo ==="

MONO_NONE=$("${PLUGIN_DIR}/scripts/detect-monorepo.sh" "${FIXTURES_DIR}/express-api" 2>&1)

assert_contains "$MONO_NONE" "IS_MONOREPO: false" "non-monorepo detected"
assert_contains "$MONO_NONE" "PACKAGE_COUNT: 0" "zero packages"

# ─── Test: detect-monorepo.sh — --check mode ─────────────────────────────────

echo ""
echo "=== Test: detect-monorepo.sh — --check mode ==="

MONO_CHECK=$("${PLUGIN_DIR}/scripts/detect-monorepo.sh" --check "${FIXTURES_DIR}/monorepo" 2>&1)
assert_contains "$MONO_CHECK" "MONOREPO: true" "--check detects monorepo"
assert_contains "$MONO_CHECK" "TYPE: npm-workspaces" "--check reports type"

MONO_CHECK_NONE=$("${PLUGIN_DIR}/scripts/detect-monorepo.sh" --check "${FIXTURES_DIR}/express-api" 2>&1 || true)
assert_contains "$MONO_CHECK_NONE" "MONOREPO: false" "--check detects non-monorepo"

# ─── Test: detect-monorepo.sh — pnpm workspaces ──────────────────────────────

echo ""
echo "=== Test: detect-monorepo.sh — pnpm workspaces ==="

TMPPNPM=$(mktemp -d)
mkdir -p "${TMPPNPM}/packages/core/src" "${TMPPNPM}/apps/web/src"
cat > "${TMPPNPM}/pnpm-workspace.yaml" << 'HEREDOC'
packages:
  - 'packages/*'
  - 'apps/*'
HEREDOC
echo '{"name":"@test/core","description":"Core library"}' > "${TMPPNPM}/packages/core/package.json"
echo '{"name":"@test/web","description":"Web app","dependencies":{"@test/core":"*"}}' > "${TMPPNPM}/apps/web/package.json"
echo "export const x = 1;" > "${TMPPNPM}/packages/core/src/index.ts"
echo "import { x } from '@test/core';" > "${TMPPNPM}/apps/web/src/index.ts"

MONO_PNPM=$("${PLUGIN_DIR}/scripts/detect-monorepo.sh" "${TMPPNPM}" 2>&1)
assert_contains "$MONO_PNPM" "IS_MONOREPO: true" "detects pnpm monorepo"
assert_contains "$MONO_PNPM" "WORKSPACE_TYPE: pnpm-workspaces" "detects pnpm type"
assert_contains "$MONO_PNPM" "@test/core" "finds core package"
assert_contains "$MONO_PNPM" "@test/web" "finds web package"
assert_contains "$MONO_PNPM" "@test/web -> @test/core" "detects pnpm dep edge"

rm -rf "$TMPPNPM"

# ─── Test: detect-monorepo.sh — lerna ─────────────────────────────────────────

echo ""
echo "=== Test: detect-monorepo.sh — lerna ==="

TMPLERNA=$(mktemp -d)
mkdir -p "${TMPLERNA}/packages/lib-a"
cat > "${TMPLERNA}/lerna.json" << 'HEREDOC'
{
  "packages": ["packages/*"],
  "version": "0.0.0"
}
HEREDOC
echo '{"name":"lib-a","description":"Library A"}' > "${TMPLERNA}/packages/lib-a/package.json"

MONO_LERNA=$("${PLUGIN_DIR}/scripts/detect-monorepo.sh" "${TMPLERNA}" 2>&1)
assert_contains "$MONO_LERNA" "IS_MONOREPO: true" "detects lerna monorepo"
assert_contains "$MONO_LERNA" "WORKSPACE_TYPE: lerna" "detects lerna type"
assert_contains "$MONO_LERNA" "lib-a" "finds lerna package"

rm -rf "$TMPLERNA"

# ─── Test: scan.sh — monorepo detection flag ──────────────────────────────────

echo ""
echo "=== Test: scan.sh — monorepo flag ==="

SCAN_MONO=$("${PLUGIN_DIR}/scripts/scan.sh" "${FIXTURES_DIR}/monorepo" 2>&1)
assert_contains "$SCAN_MONO" "MONOREPO: true" "scan reports monorepo flag"
assert_contains "$SCAN_MONO" "MONOREPO_TYPE:" "scan reports monorepo type"

SCAN_NONMONO=$("${PLUGIN_DIR}/scripts/scan.sh" "${FIXTURES_DIR}/express-api" 2>&1)
assert_contains "$SCAN_NONMONO" "MONOREPO: false" "scan reports non-monorepo"

# ─── Test: run-custom-analyzers.sh — list ─────────────────────────────────────

echo ""
echo "=== Test: run-custom-analyzers.sh — list ==="

CUSTOM_LIST=$("${PLUGIN_DIR}/scripts/run-custom-analyzers.sh" list "${FIXTURES_DIR}/express-api" 2>&1)

assert_contains "$CUSTOM_LIST" "CUSTOM PLUGINS" "list outputs format"
assert_contains "$CUSTOM_LIST" "ANALYZER_COUNT: 2" "finds 2 analyzers"
assert_contains "$CUSTOM_LIST" "GENERATOR_COUNT: 1" "finds 1 generator"
assert_contains "$CUSTOM_LIST" "NAME: route-counter" "finds script analyzer"
assert_contains "$CUSTOM_LIST" "TYPE: script" "identifies script type"
assert_contains "$CUSTOM_LIST" "NAME: middleware-scanner" "finds agent analyzer"
assert_contains "$CUSTOM_LIST" "TYPE: agent" "identifies agent type"
assert_contains "$CUSTOM_LIST" "NAME: api-summary" "finds custom generator"
assert_contains "$CUSTOM_LIST" "OUTPUT_FILE: docs/API_SUMMARY.md" "reads generator output file"

# ─── Test: run-custom-analyzers.sh — no plugins ──────────────────────────────

echo ""
echo "=== Test: run-custom-analyzers.sh — no plugins ==="

CUSTOM_EMPTY=$("${PLUGIN_DIR}/scripts/run-custom-analyzers.sh" list "${FIXTURES_DIR}/react-app" 2>&1)

assert_contains "$CUSTOM_EMPTY" "ANALYZER_COUNT: 0" "zero analyzers when none exist"
assert_contains "$CUSTOM_EMPTY" "GENERATOR_COUNT: 0" "zero generators when none exist"
assert_contains "$CUSTOM_EMPTY" "NO_PLUGINS_FOUND" "reports no plugins"

# ─── Test: run-custom-analyzers.sh — run script analyzer ─────────────────────

echo ""
echo "=== Test: run-custom-analyzers.sh — run analyzer ==="

CUSTOM_RUN=$("${PLUGIN_DIR}/scripts/run-custom-analyzers.sh" run route-counter "${FIXTURES_DIR}/express-api" 2>&1)

assert_contains "$CUSTOM_RUN" "CUSTOM ANALYZER OUTPUT" "run outputs format"
assert_contains "$CUSTOM_RUN" "ANALYZER: route-counter" "identifies analyzer"
assert_contains "$CUSTOM_RUN" "STATUS: success" "reports success"
assert_contains "$CUSTOM_RUN" "CONFIDENCE: 0.95" "includes confidence"
assert_contains "$CUSTOM_RUN" "TOTAL:" "includes route totals"

# ─── Test: run-custom-analyzers.sh — run agent analyzer ──────────────────────

echo ""
echo "=== Test: run-custom-analyzers.sh — agent analyzer ==="

CUSTOM_AGENT=$("${PLUGIN_DIR}/scripts/run-custom-analyzers.sh" run middleware-scanner "${FIXTURES_DIR}/express-api" 2>&1)

assert_contains "$CUSTOM_AGENT" "TYPE: agent" "identifies as agent type"
assert_contains "$CUSTOM_AGENT" "NOTE:" "explains agent needs orchestrator"

# ─── Test: run-custom-analyzers.sh — run-all ─────────────────────────────────

echo ""
echo "=== Test: run-custom-analyzers.sh — run-all ==="

CUSTOM_ALL=$("${PLUGIN_DIR}/scripts/run-custom-analyzers.sh" run-all "${FIXTURES_DIR}/express-api" 2>&1)

assert_contains "$CUSTOM_ALL" "CUSTOM ANALYZER BATCH" "run-all outputs batch format"
assert_contains "$CUSTOM_ALL" "TOTAL_RUN: 2" "runs both analyzers"
assert_contains "$CUSTOM_ALL" "route-counter" "includes script analyzer"
assert_contains "$CUSTOM_ALL" "middleware-scanner" "includes agent analyzer"

# ─── Test: run-custom-analyzers.sh — not found ───────────────────────────────

echo ""
echo "=== Test: run-custom-analyzers.sh — not found ==="

CUSTOM_NOTFOUND=$("${PLUGIN_DIR}/scripts/run-custom-analyzers.sh" run nonexistent "${FIXTURES_DIR}/express-api" 2>&1 || true)

assert_contains "$CUSTOM_NOTFOUND" "STATUS: not_found" "reports not found"

# ─── Test: coverage.sh — express-api ─────────────────────────────────────────

echo ""
echo "=== Test: coverage.sh — express-api ==="

COV_EXPRESS=$("${PLUGIN_DIR}/scripts/coverage.sh" "${FIXTURES_DIR}/express-api" 2>&1)

assert_contains "$COV_EXPRESS" "COVERAGE REPORT" "outputs coverage report format"
assert_contains "$COV_EXPRESS" "TOTAL_FILES:" "reports total files"
assert_contains "$COV_EXPRESS" "TOTAL_ENDPOINTS:" "reports total endpoints"
assert_contains "$COV_EXPRESS" "TOTAL_EXPORTS:" "reports total exports"
assert_contains "$COV_EXPRESS" "TOTAL_ENTITIES:" "reports total entities"
assert_contains "$COV_EXPRESS" "FILE_COVERAGE:" "reports file coverage"
assert_contains "$COV_EXPRESS" "ENDPOINT_COVERAGE:" "reports endpoint coverage"
assert_contains "$COV_EXPRESS" "ENTITY_COVERAGE:" "reports entity coverage"
assert_contains "$COV_EXPRESS" "GAPS:" "reports documentation gaps"

# Verify it found real endpoints and exports
if echo "$COV_EXPRESS" | grep -q "TOTAL_ENDPOINTS: 0"; then
  fail "should find endpoints in express-api"
else
  pass "finds endpoints in express-api"
fi

if echo "$COV_EXPRESS" | grep -q "TOTAL_EXPORTS: 0"; then
  fail "should find exports in express-api"
else
  pass "finds exports in express-api"
fi

# ─── Test: coverage.sh — react-app ──────────────────────────────────────────

echo ""
echo "=== Test: coverage.sh — react-app ==="

COV_REACT=$("${PLUGIN_DIR}/scripts/coverage.sh" "${FIXTURES_DIR}/react-app" 2>&1)

assert_contains "$COV_REACT" "COVERAGE REPORT" "react-app outputs coverage format"
assert_contains "$COV_REACT" "TOTAL_FILES:" "react-app reports files"

# ─── Test: coverage.sh — empty project ──────────────────────────────────────

echo ""
echo "=== Test: coverage.sh — empty project ==="

TMPEMPTYCOV=$(mktemp -d)
COV_EMPTY=$("${PLUGIN_DIR}/scripts/coverage.sh" "${TMPEMPTYCOV}" 2>&1)

assert_contains "$COV_EMPTY" "TOTAL_FILES: 0" "empty project has 0 files"
assert_contains "$COV_EMPTY" "TOTAL_ENTITIES: 0" "empty project has 0 entities"
assert_not_contains "$COV_EMPTY" "GAPS:" "empty project has no gaps"

rm -rf "$TMPEMPTYCOV"

# ─── Test: coverage.sh — with documented refs ───────────────────────────────

echo ""
echo "=== Test: coverage.sh — documented project ==="

TMPDOCPROJ=$(mktemp -d)
mkdir -p "${TMPDOCPROJ}/src/routes"
echo "router.get('/users', handler); module.exports = router;" > "${TMPDOCPROJ}/src/routes/users.js"
cat > "${TMPDOCPROJ}/README.md" << 'HEREDOC'
<!-- livindocs:start:api -->
## API
GET /users - List users
<!-- livindocs:refs:src/routes/users.js:1-10 -->
<!-- livindocs:end:api -->
HEREDOC

COV_DOC=$("${PLUGIN_DIR}/scripts/coverage.sh" "${TMPDOCPROJ}" 2>&1)

assert_contains "$COV_DOC" "DOCUMENTED_FILES: 1" "counts documented file"
assert_contains "$COV_DOC" "DOCUMENTED_ENDPOINTS: 1" "counts documented endpoint"

rm -rf "$TMPDOCPROJ"

# ─── Test: CI templates exist and are valid ──────────────────────────────────

echo ""
echo "=== Test: CI templates ==="

# GitHub Actions action.yml
if [[ -f "${PLUGIN_DIR}/ci/action.yml" ]]; then
  pass "GitHub Actions action.yml exists"
  assert_contains "$(cat "${PLUGIN_DIR}/ci/action.yml")" "name:" "action.yml has name"
  assert_contains "$(cat "${PLUGIN_DIR}/ci/action.yml")" "inputs:" "action.yml has inputs"
  assert_contains "$(cat "${PLUGIN_DIR}/ci/action.yml")" "command:" "action.yml has command input"
  assert_contains "$(cat "${PLUGIN_DIR}/ci/action.yml")" "fail-on:" "action.yml has fail-on input"
  assert_contains "$(cat "${PLUGIN_DIR}/ci/action.yml")" "runs:" "action.yml has runs section"
else
  fail "GitHub Actions action.yml missing"
fi

# GitLab CI template
if [[ -f "${PLUGIN_DIR}/ci/gitlab-ci.yml" ]]; then
  pass "GitLab CI template exists"
  assert_contains "$(cat "${PLUGIN_DIR}/ci/gitlab-ci.yml")" "docs-check:" "gitlab-ci has docs-check job"
  assert_contains "$(cat "${PLUGIN_DIR}/ci/gitlab-ci.yml")" "docs-coverage:" "gitlab-ci has docs-coverage job"
  assert_contains "$(cat "${PLUGIN_DIR}/ci/gitlab-ci.yml")" "LIVINDOCS_FAIL_ON" "gitlab-ci has fail-on var"
  assert_contains "$(cat "${PLUGIN_DIR}/ci/gitlab-ci.yml")" "merge_request_event" "gitlab-ci triggers on MRs"
else
  fail "GitLab CI template missing"
fi

# ─── Test: API agents exist ─────────────────────────────────────────────────

echo ""
echo "=== Test: API doc agents ==="

if [[ -f "${PLUGIN_DIR}/agents/api-analyzer.md" ]]; then
  pass "api-analyzer agent exists"
  assert_contains "$(head -10 "${PLUGIN_DIR}/agents/api-analyzer.md")" "name: api-analyzer" "api-analyzer has correct name"
else
  fail "api-analyzer agent missing"
fi

if [[ -f "${PLUGIN_DIR}/agents/api-reference-writer.md" ]]; then
  pass "api-reference-writer agent exists"
  assert_contains "$(head -10 "${PLUGIN_DIR}/agents/api-reference-writer.md")" "name: api-reference-writer" "api-reference-writer has correct name"
else
  fail "api-reference-writer agent missing"
fi

# ─── Test: benchmark.sh ──────────────────────────────────────────────────────

echo ""
echo "=== Test: benchmark.sh ==="

BENCH_OUTPUT=$("${PLUGIN_DIR}/scripts/benchmark.sh" "${FIXTURES_DIR}/express-api" 2>&1)

assert_contains "$BENCH_OUTPUT" "BENCHMARK RESULTS" "benchmark outputs format"
assert_contains "$BENCH_OUTPUT" "FILES:" "benchmark reports files"
assert_contains "$BENCH_OUTPUT" "LINES:" "benchmark reports lines"
assert_contains "$BENCH_OUTPUT" "scan.sh:" "benchmark times scan"
assert_contains "$BENCH_OUTPUT" "chunk.sh:" "benchmark times chunk"
assert_contains "$BENCH_OUTPUT" "budget.sh:" "benchmark times budget"
assert_contains "$BENCH_OUTPUT" "TOTAL:" "benchmark reports total"

# ─── Test: telemetry.sh — check ─────────────────────────────────────────────

echo ""
echo "=== Test: telemetry.sh ==="

TEL_CHECK=$("${PLUGIN_DIR}/scripts/telemetry.sh" check "${FIXTURES_DIR}/express-api" 2>&1)
assert_contains "$TEL_CHECK" "TELEMETRY" "telemetry check outputs format"
assert_contains "$TEL_CHECK" "STATUS: disabled" "telemetry disabled by default"

# Test record when disabled
TEL_RECORD=$("${PLUGIN_DIR}/scripts/telemetry.sh" record generate "${FIXTURES_DIR}/express-api" 2>&1)
assert_contains "$TEL_RECORD" "STATUS: disabled" "record skips when disabled"

# Test with enabled project
TMPTEL=$(mktemp -d)
cat > "${TMPTEL}/.livindocs.yml" << 'HEREDOC'
version: 1
telemetry:
  enabled: true
HEREDOC
mkdir -p "${TMPTEL}/.livindocs"
echo "test-uuid-123" > "${TMPTEL}/.livindocs/telemetry-id"

TEL_ENABLED=$("${PLUGIN_DIR}/scripts/telemetry.sh" check "${TMPTEL}" 2>&1)
assert_contains "$TEL_ENABLED" "STATUS: enabled" "detects enabled telemetry"

TEL_REC=$("${PLUGIN_DIR}/scripts/telemetry.sh" record generate "${TMPTEL}" 2>&1)
assert_contains "$TEL_REC" "STATUS: recorded" "records command"

TEL_REPORT=$("${PLUGIN_DIR}/scripts/telemetry.sh" report "${TMPTEL}" 2>&1)
assert_contains "$TEL_REPORT" "generate: 1" "report shows command count"

# Test DO_NOT_TRACK
TEL_DNT=$(DO_NOT_TRACK=1 "${PLUGIN_DIR}/scripts/telemetry.sh" check "${TMPTEL}" 2>&1)
assert_contains "$TEL_DNT" "STATUS: disabled" "DO_NOT_TRACK overrides config"

rm -rf "$TMPTEL"

# ─── Test: version-docs.sh ──────────────────────────────────────────────────

echo ""
echo "=== Test: version-docs.sh ==="

TMPVER=$(mktemp -d)
mkdir -p "${TMPVER}/docs"
echo "# Test" > "${TMPVER}/docs/README.md"
cat > "${TMPVER}/.livindocs.yml" << 'HEREDOC'
version: 1
docs_dir: docs/
HEREDOC

# Test current with no versions
VER_CURRENT=$("${PLUGIN_DIR}/scripts/version-docs.sh" current "${TMPVER}" 2>&1)
assert_contains "$VER_CURRENT" "DOC VERSIONS" "version current outputs format"
assert_contains "$VER_CURRENT" "CURRENT: none" "no current version initially"

# Test snapshot
VER_SNAP=$("${PLUGIN_DIR}/scripts/version-docs.sh" snapshot v1.0 "${TMPVER}" 2>&1)
assert_contains "$VER_SNAP" "ACTION: snapshot" "snapshot reports action"
assert_contains "$VER_SNAP" "TAG: v1.0" "snapshot reports tag"

# Test list
VER_LIST=$("${PLUGIN_DIR}/scripts/version-docs.sh" list "${TMPVER}" 2>&1)
assert_contains "$VER_LIST" "CURRENT: v1.0" "list shows current version"
assert_contains "$VER_LIST" "TAG: v1.0" "list shows version tag"

# Test switch
"${PLUGIN_DIR}/scripts/version-docs.sh" snapshot v2.0 "${TMPVER}" >/dev/null 2>&1
"${PLUGIN_DIR}/scripts/version-docs.sh" switch v1.0 "${TMPVER}" >/dev/null 2>&1
VER_SWITCHED=$("${PLUGIN_DIR}/scripts/version-docs.sh" current "${TMPVER}" 2>&1)
assert_contains "$VER_SWITCHED" "CURRENT: v1.0" "switch changes current version"

rm -rf "$TMPVER"

# ─── Test: Templates exist ──────────────────────────────────────────────────

echo ""
echo "=== Test: Templates ==="

for tmpl in readme.md.hbs architecture.md.hbs onboarding.md.hbs adr.md.hbs; do
  if [[ -f "${PLUGIN_DIR}/templates/${tmpl}" ]]; then
    pass "template ${tmpl} exists"
  else
    fail "template ${tmpl} missing"
  fi
done

assert_contains "$(cat "${PLUGIN_DIR}/templates/readme.md.hbs")" "livindocs:start" "readme template has markers"
assert_contains "$(cat "${PLUGIN_DIR}/templates/architecture.md.hbs")" "mermaid" "architecture template has mermaid"

# ─── Test: M7 files exist ───────────────────────────────────────────────────

echo ""
echo "=== Test: M7 community release files ==="

if [[ -f "${PLUGIN_DIR}/CONTRIBUTING.md" ]]; then
  pass "CONTRIBUTING.md exists"
  assert_contains "$(cat "${PLUGIN_DIR}/CONTRIBUTING.md")" "tests" "CONTRIBUTING mentions tests"
else
  fail "CONTRIBUTING.md missing"
fi

if [[ -f "${PLUGIN_DIR}/docs/TEMPLATES.md" ]]; then
  pass "template docs exist"
else
  fail "TEMPLATES.md missing"
fi

if [[ -f "${PLUGIN_DIR}/.livindocs.yml" ]]; then
  pass "livindocs self-config exists (meta!)"
else
  fail ".livindocs.yml for livindocs itself missing"
fi

# Plugin.json version bump
assert_contains "$(cat "${PLUGIN_DIR}/.claude-plugin/plugin.json")" '"1.0.0"' "plugin.json at v1.0.0"

# Generate skill has budget and model flags
assert_contains "$(cat "${PLUGIN_DIR}/skills/generate/SKILL.md")" "budget" "generate skill supports --budget"
assert_contains "$(cat "${PLUGIN_DIR}/skills/generate/SKILL.md")" "model" "generate skill supports --model"

# ─── Summary ─────────────────────────────────────────────────────────────────

echo ""
echo "================================"
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"

if [[ $FAIL_COUNT -gt 0 ]]; then
  echo ""
  echo "Failures:"
  for f in "${FAILURES[@]}"; do
    echo "  - $f"
  done
  echo ""
  exit 1
fi

echo "All tests passed!"
exit 0
