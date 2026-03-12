---
name: generate
description: "Generate living documentation for a project. Analyzes the codebase, generates docs with quality verification, and embeds source references. Supports: readme (default), architecture, onboarding, adr, api, all. Flags: --budget <N>, --model <model>."
disable-model-invocation: true
allowed-tools: Bash, Read, Write, Glob, Grep, Agent
argument-hint: "[readme|architecture|onboarding|adr|api|all] [--budget <tokens>] [--model <model>]"
---

# livindocs:generate — Documentation Generator

You are generating documentation for this project. The doc type is: **$ARGUMENTS** (default: `readme` if empty).

Supported types:
- `readme` — Generate README.md (default)
- `architecture` — Generate docs/ARCHITECTURE.md with Mermaid diagrams
- `onboarding` — Generate docs/ONBOARDING.md for new developers
- `adr` — Generate Architecture Decision Records in docs/decisions/
- `api` — Generate docs/API.md with endpoint reference and usage examples
- `all` — Generate all doc types

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

### Parse flags from arguments

Check if `$ARGUMENTS` contains:
- `--budget <N>` — Override the token budget for this run. Extract the number. If present, this overrides the budget from `.livindocs.yml`.
- `--model <model>` — Override the model for generation passes. Valid values: `sonnet`, `opus`, `haiku`. If present, pass this to agents.

Read model selection config from `.livindocs.yml`:
```
!`grep -A5 '^models:' .livindocs.yml 2>/dev/null || echo "models: default"`
```

If `--model` flag is present, use that for all passes. Otherwise, use config values. Default routing:
- Analysis pass: sonnet
- Generation pass: sonnet
- Synthesis pass: sonnet (or opus if configured)
- Review pass: sonnet

### Load custom template (if configured)

```
!`grep 'templates_dir:' .livindocs.yml 2>/dev/null | awk '{print $2}' || echo "default"`
```

If a custom `templates_dir` is configured and the relevant template exists (e.g., `<templates_dir>/readme.md.hbs` for readme generation), read it and pass it to the writer agent as the structural guide. Otherwise, use the built-in template from `${CLAUDE_PLUGIN_ROOT}/templates/`.

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

If `--budget <N>` was specified, compare the estimated tokens against N. If the estimate exceeds N, treat it as ABORT regardless of the config decision. If it's under N, treat as SILENT.

## Step 4: Cache check

Check which files have changed since last analysis:
```
!`SCAN_OUT=$(${CLAUDE_PLUGIN_ROOT}/scripts/scan.sh .); echo "$SCAN_OUT" | ${CLAUDE_PLUGIN_ROOT}/scripts/cache.sh check . 2>/dev/null || echo "STATUS: no_manifest"`
```

If `STATUS: no_manifest` or `CHANGED: all`, proceed with full analysis.
If some files are `CACHED`, tell the analyzer to focus on changed files. Include the `CHANGED_FILES` list in the analyzer prompt.

## Step 4b: Monorepo detection

If the scan output includes `MONOREPO: true`, run the full monorepo detection:
```bash
${CLAUDE_PLUGIN_ROOT}/scripts/detect-monorepo.sh .
```

Store the monorepo detection results — they will be passed to the analyzer and architecture-writer agents.

## Step 4c: Custom plugin discovery

Check for custom analyzers and generators:
```bash
${CLAUDE_PLUGIN_ROOT}/scripts/run-custom-analyzers.sh list .
```

If `ANALYZER_COUNT` > 0, run all script-based custom analyzers:
```bash
${CLAUDE_PLUGIN_ROOT}/scripts/run-custom-analyzers.sh run-all .
```

Store the custom analyzer output — it will be passed to the analyzer agent as additional context.
Store the list of agent-based analyzers and custom generators for later steps.

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
- If scan showed `MONOREPO: true`, include the full monorepo detection output (packages, dependency graph, shared deps) and say "This is a monorepo. Include the monorepo field in the ProjectContext with package details and inter-package dependency graph."
- If cache showed changed files only, include the changed file list and say "Focus analysis on these changed files. Previous analysis is available in .livindocs/cache/context/latest.json — update it rather than starting from scratch."
- If custom script analyzers produced output, include that output and say "Custom analyzer findings are provided below. Integrate them into the ProjectContext under a customAnalysis key."
- If agent-based custom analyzers exist (TYPE: agent), include their file paths and say "After writing the initial ProjectContext, read each agent analyzer definition and add its findings under the specified output-key."
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

### Monorepo: Per-package documentation

If the project is a monorepo and type is `all` or `readme`:

For each package detected by `detect-monorepo.sh`:
1. Run the analyzer agent scoped to that package's directory
2. Run the writer agent to generate a `README.md` inside the package directory (e.g., `packages/api/README.md`)
3. Include cross-references to related packages in each package README

The root-level docs (README.md, ARCHITECTURE.md) should provide the unified view, while per-package docs cover package-specific details.

Report: `[Pass M/N: Generating per-package docs for N packages...]`

### If type is `onboarding` or `all`:

Report: `[Pass M/N: Generating ONBOARDING.md...]`

Ensure docs directory exists:
```bash
mkdir -p docs
```

Delegate to the **onboarding-writer** agent. Provide it with:
- The path to ProjectContext: `.livindocs/cache/context/latest.json`
- The project config from `.livindocs.yml`
- The quality profile
- Task: "Generate docs/ONBOARDING.md — a practical onboarding guide for new developers joining this project"

Wait for the onboarding-writer to complete.

### If type is `adr` or `all`:

Report: `[Pass M/N: Generating Architecture Decision Records...]`

First, check if GitHub data is available:
```bash
${CLAUDE_PLUGIN_ROOT}/scripts/github.sh check .
```

Then gather git history:
```bash
${CLAUDE_PLUGIN_ROOT}/scripts/git-history.sh decisions . --limit 100
```

If GitHub is available, also fetch PR data:
```bash
${CLAUDE_PLUGIN_ROOT}/scripts/github.sh prs . --limit 50
```

Delegate to the **adr-generator** agent. Provide it with:
- The git history decisions output
- The GitHub PR data (if available)
- The path to ProjectContext: `.livindocs/cache/context/latest.json`
- Task: "Generate Architecture Decision Records in docs/decisions/ from git history and PR data"

Wait for the adr-generator to complete.

### If type is `api` or `all`:

Report: `[Pass M/N: Analyzing API surface...]`

Ensure docs directory exists:
```bash
mkdir -p docs
```

First, delegate to the **api-analyzer** agent to enrich the ProjectContext with detailed API data:
- Provide: The path to ProjectContext `.livindocs/cache/context/latest.json`
- Task: "Analyze the API surface of this codebase — endpoints, parameters, auth, responses — and update the ProjectContext with an apiSurface field"

Wait for the api-analyzer to complete.

Then delegate to the **api-reference-writer** agent:
- Provide: The path to ProjectContext `.livindocs/cache/context/latest.json`
- The project config from `.livindocs.yml`
- The quality profile
- Task: "Generate docs/API.md with complete endpoint reference, usage examples, and source reference anchors"

Wait for the api-reference-writer to complete.

### Custom generators

If custom generators were discovered in Step 4c (GENERATOR_COUNT > 0):

Report: `[Pass M/N: Running custom generators...]`

For each custom generator `.md` file in `.livindocs/generators/`:
1. Read the generator definition to understand what it should produce
2. Launch it as an Agent with access to Read, Write, Edit, Glob, Grep, and Bash tools
3. Provide it with:
   - The path to ProjectContext: `.livindocs/cache/context/latest.json`
   - The project config from `.livindocs.yml`
   - Task: the generator's own instructions from its markdown body
4. After the agent completes, verify the output file exists

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
And if onboarding was generated:
```bash
${CLAUDE_PLUGIN_ROOT}/scripts/verify.sh docs/ONBOARDING.md .
```
And if API docs were generated:
```bash
${CLAUDE_PLUGIN_ROOT}/scripts/verify.sh docs/API.md .
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

## Step 8b: Coverage report

Run the coverage reporter to show how much of the codebase is documented:
```bash
${CLAUDE_PLUGIN_ROOT}/scripts/coverage.sh .
```

Include the coverage percentages in the summary output.

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

## Step 11: Record telemetry

If telemetry is enabled, record this generation run:
```bash
${CLAUDE_PLUGIN_ROOT}/scripts/telemetry.sh record generate .
```

This only runs if the user has opted in. No sensitive data is collected.

## Important rules

- NEVER include secrets in generated docs. If the scan found secrets, those files' content must be described generically, never quoted.
- ALWAYS use `<!-- livindocs:start:SECTION -->` and `<!-- livindocs:end:SECTION -->` markers around every section.
- ALWAYS include `<!-- livindocs:refs:FILE:LINES -->` anchors after each section citing the source files.
- If a doc file already exists, preserve content OUTSIDE of livindocs markers. Only replace content inside markers.
- For architecture docs, ALWAYS include at least one Mermaid diagram (dependency graph at minimum).
