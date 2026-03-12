# Architecture

## Plugin Structure

```
livindocs/
├── package.json
├── plugin.json                  # Plugin manifest (commands, skills, metadata)
├── README.md
├── LICENSE
├── src/
│   ├── index.ts                 # Plugin entry point
│   ├── commands/                # Slash commands
│   │   ├── generate.ts          # /docs generate — full doc generation
│   │   ├── check.ts             # /docs check — staleness detection
│   │   ├── update.ts            # /docs update — incremental update
│   │   ├── explain.ts           # /docs explain — interactive codebase explainer
│   │   └── init.ts              # /docs init — project setup and config
│   ├── analyzers/               # Code analysis modules
│   │   ├── architecture.ts      # Module relationships, entry points, data flow
│   │   ├── api-surface.ts       # Public APIs, endpoints, exports
│   │   ├── dependencies.ts      # Dependency graph and external integrations
│   │   ├── patterns.ts          # Design patterns, conventions, magic numbers
│   │   └── git-history.ts       # Commit analysis for ADRs and change patterns
│   ├── generators/              # Document generators
│   │   ├── readme.ts            # README.md generation
│   │   ├── architecture.ts      # ARCHITECTURE.md generation
│   │   ├── onboarding.ts        # ONBOARDING.md generation
│   │   ├── adr.ts               # Architecture Decision Records
│   │   ├── api-reference.ts     # API docs with usage examples
│   │   └── changelog.ts         # Semantic changelog from git history
│   ├── differ/                  # Staleness detection engine
│   │   ├── semantic-diff.ts     # Compare code changes against existing docs
│   │   ├── coverage.ts          # What percentage of codebase is documented
│   │   └── reporter.ts          # Staleness report output
│   ├── config/                  # Configuration management
│   │   ├── schema.ts            # Config schema and validation
│   │   ├── defaults.ts          # Sensible defaults per language/framework
│   │   └── loader.ts            # Load .livindocs.yml config
│   ├── quality/                 # Documentation quality assurance
│   │   ├── reviewer.ts          # Self-critique pass — accuracy, coverage, clarity
│   │   ├── claim-extractor.ts   # Extract verifiable claims from generated docs
│   │   ├── programmatic-checks.ts # Deterministic verification (counts, imports, file refs)
│   │   ├── scorer.ts            # Quality scoring (accuracy, coverage, freshness, refs)
│   │   └── profiles.ts          # Quality profiles (minimal, standard, thorough)
│   ├── chunking/               # Large codebase handling
│   │   ├── strategy.ts          # Hierarchical chunking strategy
│   │   ├── budget.ts            # Token budget tracking and management
│   │   └── summarizer.ts        # File/module summarization for oversized inputs
│   ├── security/                # Secret detection and redaction
│   │   ├── secret-scanner.ts    # Regex-based secret pattern detection
│   │   ├── patterns.ts          # Known secret patterns (AWS, GCP, Stripe, etc.)
│   │   └── redactor.ts          # Redaction and placeholder insertion
│   ├── integrations/            # External service integrations
│   │   ├── github.ts            # GitHub API (PRs, issues, reviews)
│   │   └── ci.ts                # CI/CD output formatting
│   └── utils/
│       ├── file-scanner.ts      # Codebase file discovery and filtering
│       ├── language-detect.ts   # Language/framework detection
│       ├── markdown.ts          # Markdown generation helpers
│       ├── mermaid.ts           # Mermaid diagram generation helpers
│       ├── cost-tracker.ts      # Real-time token tracking during execution
│       ├── cost-estimator.ts    # Pre-execution cost estimation
│       ├── budget-enforcer.ts   # Budget limits, warnings, and abort logic
│       └── git.ts               # Git operations wrapper
├── skills/
│   └── livindocs/
│       └── SKILL.md             # Skill definition for doc generation best practices
├── templates/                   # Default doc templates (customizable)
│   ├── readme.md.hbs
│   ├── architecture.md.hbs
│   ├── onboarding.md.hbs
│   └── adr.md.hbs
└── tests/
    ├── fixtures/                # Sample codebases for testing
    │   ├── express-api/
    │   ├── react-app/
    │   ├── python-cli/
    │   └── monorepo/
    ├── analyzers/
    ├── generators/
    └── differ/
```

## Design Principles

### 1. Docs live in the repo
All output is plain Markdown committed alongside code. No external platform, no vendor lock-in. Works with any static site generator (Docusaurus, MkDocs, etc.) if teams want a docs site.

### 2. Non-destructive by default
Never overwrite manual edits. Use marker comments to delineate auto-generated sections:
```markdown
<!-- livindocs:start:architecture-overview -->
This section is auto-generated. Edit .livindocs.yml to customize.
...content...
<!-- livindocs:end:architecture-overview -->
```
Content outside markers is preserved.

### 3. Incremental, not regenerative
After initial generation, only update what's stale. Respect the user's time and Claude API costs.

### 4. Language-agnostic, framework-aware
Core analyzers work with any language (file structure, git history, naming patterns). Framework-specific analyzers (Express routes, React components, Django views) provide richer output when detected.

### 5. Configurable depth
Some teams want a README and architecture doc. Others want full API references with examples. The config controls what gets generated — no bloat by default.

## Technical Decisions

### Language: TypeScript
Claude Code plugins are Node.js-based. TypeScript gives us type safety and better DX for contributors.

### No runtime dependencies on specific doc formats
Output is always Markdown. We don't depend on Sphinx, JSDoc, or any other doc toolchain. Users can pipe our Markdown into whatever they want.

### Marker-based section management
We use HTML comments as markers (invisible in rendered Markdown) to track which sections are auto-generated. This lets us do surgical updates without clobbering manual content.

### Git history analysis for ADRs
Architecture Decision Records are inferred from:
- Large refactoring commits (file renames, new directories)
- Dependency additions/removals
- Config file changes
- PR descriptions (if available via GitHub API)

### Framework detection heuristic
We detect frameworks by checking:
1. Package manager files (package.json, requirements.txt, go.mod, Cargo.toml, etc.)
2. Config files (next.config.js, angular.json, django settings, etc.)
3. Directory structure patterns
4. Import patterns in source files

## Caching: `.livindocs/cache/`

Analysis results are cached in `.livindocs/cache/` at the project root. This directory should be gitignored. Cache entries are keyed by file content hash so they auto-invalidate when code changes. Cache stores:
- Analysis results per-file and per-module
- The full `ProjectContext` from the last generation run
- Staleness baselines (snapshot of code state when docs were last generated)
- GitHub API responses (PR data, issue references) with TTL expiry

```
.livindocs/
├── cache/
│   ├── analysis/              # Cached analyzer outputs keyed by content hash
│   │   ├── {hash}.json
│   │   └── manifest.json      # Maps file paths → cache keys + timestamps
│   ├── context/               # Last full ProjectContext snapshot
│   │   └── latest.json
│   ├── github/                # GitHub API response cache with TTL
│   │   └── prs.json
│   └── staleness/             # Baseline snapshots for diff comparison
│       └── baseline.json
├── analyzers/                 # Custom analyzer plugins (user-installed)
│   └── .gitkeep
└── config.local.yml           # Local overrides (gitignored)
```

## Chunking Strategy for Large Codebases

Large codebases will exceed Claude's context window. We handle this with a multi-pass hierarchical strategy:

**Pass 1: Structural scan (low token cost)**
- File tree enumeration, file sizes, language detection
- Package manager file parsing (deps, scripts, entry points)
- Config file parsing
- Git log analysis (recent commits, file change frequency)
- This pass rarely exceeds context limits — it's mostly metadata

**Pass 2: Module-level analysis (chunked)**
- Group files by module/directory (natural boundaries)
- Analyze each module independently within a single context window
- Each module analysis produces a `ModuleContext` summary
- Priority ordering: entry points first, then high-change-frequency files, then the rest

**Pass 3: Cross-module synthesis (summaries only)**
- Feed all `ModuleContext` summaries (not full source) into a synthesis pass
- This is where architecture docs, data flow diagrams, and system-level docs are generated
- Module summaries are compact enough that even large codebases fit

**Pass 4: Detail generation (targeted)**
- API docs, onboarding guides, and other detail-heavy docs are generated per-module
- Only the relevant module's source code is loaded for each generation

**Budget management:**
```typescript
interface ChunkingConfig {
  max_tokens_per_pass: number;     // Default: 150,000 (leave headroom for output)
  max_files_per_chunk: number;     // Default: 50
  priority: 'entry-points-first' | 'change-frequency' | 'alphabetical';
  summarization_threshold: number;  // File size above which we summarize instead of include verbatim
}
```

**Fallback for extremely large repos:**
- If a single module exceeds the context window, we split it further by subdirectory
- Files over `summarization_threshold` (default 500 lines) get a summary pass before inclusion
- Users can set `include`/`exclude` patterns to scope down what gets analyzed

## Error Handling and Resilience

### Graceful degradation
- If GitHub API is unavailable → fall back to git-only analysis
- If a file can't be parsed → skip it, log warning, continue with rest
- If Claude API rate-limits → queue and retry with exponential backoff
- If cache is corrupted → delete cache, regenerate from scratch
- If a custom analyzer throws → isolate the error, skip that analyzer, warn user

### User-facing errors
All errors should be actionable. Instead of "Analysis failed", say:
- "Could not analyze src/auth/oauth.ts: file contains binary content. Skipping."
- "GitHub API returned 403. Set GITHUB_TOKEN env var for PR analysis, or run without GitHub integration."
- "Context window exceeded for module src/core/ (847 files, ~320K tokens). Splitting into sub-modules."
