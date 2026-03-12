---
name: generate
description: "Generate living documentation for a project. Analyzes the codebase, generates docs with quality verification, and embeds source references. Supports: readme (default), architecture, all."
disable-model-invocation: true
allowed-tools: Bash, Read, Write, Glob, Grep, Agent
argument-hint: "[readme|architecture|all]"
---

# livindocs:generate — Documentation Generator

You are generating documentation for this project. The doc type is: **$ARGUMENTS** (default: `readme` if empty).

Supported types:
- `readme` — Generate README.md (default)
- `architecture` — Generate docs/ARCHITECTURE.md with Mermaid diagrams
- `all` — Generate both README.md and docs/ARCHITECTURE.md

## Step 1: Pre-flight checks

First, verify livindocs is initialized:
```
!`test -f .livindocs.yml && echo "INIT: true" || echo "INIT: false"`
```

If not initialized, tell the user to run `/livindocs:init` first and stop.

Read the quality profile:
```
!`grep -A5 '^quality:' .livindocs.yml 2>/dev/null | grep 'profile:' | awk '{print $2}' || echo "standard"`
```

Store the quality profile for later steps. Profiles: `minimal`, `standard`, `thorough`.

## Step 2: Scan and estimate

Run the scan, chunk, and budget scripts:

```
!`SCAN_OUT=$(${CLAUDE_PLUGIN_ROOT}/scripts/scan.sh .); echo "$SCAN_OUT"; echo "---CHUNK_PLAN---"; echo "$SCAN_OUT" | ${CLAUDE_PLUGIN_ROOT}/scripts/chunk.sh .; echo "---BUDGET---"; echo "$SCAN_OUT" | ${CLAUDE_PLUGIN_ROOT}/scripts/budget.sh .`
```

## Step 3: Budget gate

Read the `DECISION` field from the budget output:

- **SILENT**: Proceed without prompting. Tell the user: `Starting generation... [N files, LANGUAGE+FRAMEWORK, quality: PROFILE]`
- **WARN**: Show the estimate and ask: `This is a larger codebase (N files, ~TOKENS tokens, CHUNKS chunks). Proceed? (Y/n/adjust)`. If they say `adjust`, suggest reducing scope with include/exclude patterns or switching to `frugal` preset.
- **ABORT**: Tell the user the budget was exceeded and suggest scope reduction. Stop here.

## Step 4: Cache check

Check which files have changed since last analysis:
```
!`SCAN_OUT=$(${CLAUDE_PLUGIN_ROOT}/scripts/scan.sh .); echo "$SCAN_OUT" | ${CLAUDE_PLUGIN_ROOT}/scripts/cache.sh check . 2>/dev/null || echo "STATUS: no_manifest"`
```

If `STATUS: no_manifest` or `CHANGED: all`, proceed with full analysis.
If some files are `CACHED`, tell the analyzer to focus on changed files. Include the `CHANGED_FILES` list in the analyzer prompt.

## Step 5: Analysis pass

Report: `[Pass 1/N: Analyzing codebase...]` (N depends on doc type and quality profile)

First, ensure the cache directory exists:
```
!`mkdir -p .livindocs/cache/context`
```

Delegate to the **analyzer** agent. Provide it with:
- The full scan results (file list, languages, frameworks, entry points)
- The chunk plan (which files are in which chunks — for large codebases, tell the analyzer to process chunks sequentially)
- The project config from `.livindocs.yml`
- If cache showed changed files only, include the changed file list and say "Focus analysis on these changed files. Previous analysis is available in .livindocs/cache/context/latest.json — update it rather than starting from scratch."
- Task: "Analyze this codebase and write a ProjectContext JSON to .livindocs/cache/context/latest.json. Include moduleGraph, dataFlow, and designPatterns fields for architecture documentation."

Wait for the analyzer to complete. Then verify the output exists:
```
!`test -f .livindocs/cache/context/latest.json && echo "CONTEXT_WRITTEN" || echo "CONTEXT_MISSING"`
```

Update the cache manifest with current file hashes:
```
!`${CLAUDE_PLUGIN_ROOT}/scripts/scan.sh . | sed -n '/^FILE_LIST:/,/^====/p' | grep -v '^FILE_LIST:' | grep -v '^====' | sed 's/^[[:space:]]*//' | sed 's/ ([0-9]* lines)$//' | ${CLAUDE_PLUGIN_ROOT}/scripts/cache.sh update-manifest .`
```

Report: `[Pass 1/N: Complete — ProjectContext written]`

## Step 6: Generation pass

### If type is `readme` or `all`:

Report: `[Pass 2/N: Generating README...]`

Delegate to the **writer** agent. Provide it with:
- The path to ProjectContext: `.livindocs/cache/context/latest.json`
- The project config from `.livindocs.yml`
- The quality profile
- Task: "Generate a README.md with livindocs markers and source reference anchors"

Wait for the writer to complete.

### If type is `architecture` or `all`:

Report: `[Pass M/N: Generating ARCHITECTURE.md...]`

Ensure docs directory exists:
```bash
mkdir -p docs
```

Delegate to the **architecture-writer** agent. Provide it with:
- The path to ProjectContext: `.livindocs/cache/context/latest.json`
- The project config from `.livindocs.yml`
- The quality profile
- Task: "Generate docs/ARCHITECTURE.md with Mermaid diagrams, module dependency graph, data flow diagrams, and source reference anchors"

Wait for the architecture-writer to complete.

Report: `[Pass M/N: Complete — docs written]`

## Step 7: Quality verification

### For `minimal` quality profile:
Skip verification entirely. Report: `[Quality: minimal — verification skipped]`

### For `standard` quality profile:
Run verification once on each generated doc:
```bash
${CLAUDE_PLUGIN_ROOT}/scripts/verify.sh README.md .
```
And if architecture was generated:
```bash
${CLAUDE_PLUGIN_ROOT}/scripts/verify.sh docs/ARCHITECTURE.md .
```

If `FAILED` count > 0 and `ACCURACY_SCORE` < 0.80, tell the relevant writer agent to fix the specific failures.

### For `thorough` quality profile:
Run verification. If any failures, tell the writer to fix them, then run verification **again** (two review cycles). Only accept if the second pass shows improvement.

## Step 8: Post-run summary

Print a quality scorecard for each generated doc:

```
[doc_name] generated successfully.

Quality: OVERALL/100
  Accuracy:  ACCURACY_SCORE  (PASSED/CHECKS claims verified)
  Coverage:  COVERAGE_SCORE  (gaps: COVERAGE_GAPS or "none")
  Freshness: 100 (generated from current code)
  Source refs: REF_COUNT anchors embedded
  Diagrams: N (architecture docs only)

Run summary:
  Files analyzed: FILE_COUNT (LINE_COUNT lines)
  Chunks: CHUNK_COUNT
  Languages: LANGUAGES
  Frameworks: FRAMEWORKS
  Quality profile: PROFILE
  Cache: N files cached, M changed

To generate more: /livindocs:generate [readme|architecture|all]
To view project progress: /livindocs:status
```

## Step 9: Save staleness baseline

Save a baseline snapshot so `/livindocs:check` can detect future changes:
```bash
${CLAUDE_PLUGIN_ROOT}/scripts/baseline.sh save .
```

## Step 10: Update build state

If `.livindocs/build-state.json` exists, run the progress detection:
```bash
${CLAUDE_PLUGIN_ROOT}/scripts/detect-progress.sh .
```

This will auto-detect any newly completed items based on the files that now exist.

## Important rules

- NEVER include secrets in generated docs. If the scan found secrets, those files' content must be described generically, never quoted.
- ALWAYS use `<!-- livindocs:start:SECTION -->` and `<!-- livindocs:end:SECTION -->` markers around every section.
- ALWAYS include `<!-- livindocs:refs:FILE:LINES -->` anchors after each section citing the source files.
- If a doc file already exists, preserve content OUTSIDE of livindocs markers. Only replace content inside markers.
- For architecture docs, ALWAYS include at least one Mermaid diagram (dependency graph at minimum).
