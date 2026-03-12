# Commands

## `/docs init`
Interactive setup wizard. Detects language, framework, and project structure. Generates a `.livindocs.yml` config with sensible defaults. Creates the `docs/` directory if needed.

## `/docs generate [type]`
Generate documentation from scratch. Types: `readme`, `architecture`, `onboarding`, `api`, `adr`, or `all` (default).

**Behavior:**
1. Scan the codebase using include/exclude patterns
2. Run relevant analyzers (architecture, API surface, patterns, etc.)
3. Build a context model of the project
4. Generate docs using templates + Claude's reasoning
5. Write markdown files to the configured output locations
6. Print a summary of what was generated

## `/docs check`
Staleness detection. Compares current code against existing documentation.

**Behavior:**
1. Read existing docs from `docs_dir`
2. Analyze current codebase state
3. Diff semantically — not just file timestamps, but actual meaning
4. Report: what's stale, what's missing, what's accurate
5. Output a staleness report with severity levels

## `/docs update`
Incremental update. Only regenerates sections that are stale.

**Behavior:**
1. Run `/docs check` internally
2. For each stale section, regenerate just that section
3. Preserve any manual edits outside of auto-generated markers
4. Show a diff of proposed changes for user approval before writing

## `/docs explain [path]`
Interactive mode. User points at a file, module, or directory and gets a conversational explanation of what it does, how it connects to the rest of the system, and why it exists.

## Config File (.livindocs.yml)

Users place this in their project root to customize behavior:

```yaml
# .livindocs.yml
version: 1

# What to generate
outputs:
  - readme          # README.md
  - architecture    # docs/ARCHITECTURE.md
  - onboarding      # docs/ONBOARDING.md
  - api-reference   # docs/API.md
  - adr             # docs/decisions/*.md

# Where to put generated docs
docs_dir: docs/

# What to scan (glob patterns)
include:
  - src/**
  - lib/**
  - app/**

exclude:
  - "**/*.test.*"
  - "**/*.spec.*"
  - node_modules/
  - dist/
  - build/

# Project context (helps Claude generate better docs)
project:
  name: "My Project"
  description: "Brief description for context"
  audience: "Backend engineers familiar with Node.js"

# Staleness detection
staleness:
  enabled: true
  threshold: moderate  # strict | moderate | relaxed
  ignore_patterns:
    - "docs/legacy/**"

# Monorepo support
monorepo:
  enabled: auto  # auto | true | false
  packages:
    - packages/*
    - apps/*
  unified_docs: true
  per_package_docs: true
  cross_references: true

# GitHub integration
github:
  enabled: true           # Set false for git-only mode
  pr_analysis: true       # Analyze PR descriptions for ADRs
  issue_references: true  # Link issues to relevant docs
  base_url: null          # Set for GitHub Enterprise: https://github.example.com/api/v3

# Model selection (cost vs quality tradeoff)
models:
  analysis: claude-sonnet-4-6
  generation: claude-sonnet-4-6
  synthesis: claude-sonnet-4-6  # Set to claude-opus-4-6 for premium quality

# Token budget
budget:
  max_tokens_per_run: null       # null = unlimited, or set e.g. 200000
  warn_threshold: 100000         # Warn user before proceeding past this
  summarization_threshold: 500   # Lines — files larger than this get summarized first

# Diagram generation
diagrams:
  enabled: true
  format: mermaid                # mermaid | none
  render_images: false           # Set true to also output SVG/PNG via mermaid-cli

# Telemetry (anonymous, opt-in only)
telemetry:
  enabled: false

# Template overrides (optional)
templates_dir: .livindocs/templates/
```
