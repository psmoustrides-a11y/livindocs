# livindocs

A Claude Code plugin that generates living documentation from your codebase. Unlike static doc generators that parse syntax and comments, livindocs uses Claude's reasoning to understand architecture, data flow, intent, and design decisions — producing documentation that no static tool can.

## Why

Documentation rot is universal. Static generators (Sphinx, JSDoc) require manual writing and go stale immediately. Commercial platforms (Swimm, Mintlify) are expensive and proprietary. Nobody auto-generates architectural docs, onboarding guides, or ADRs from code alone.

livindocs fills that gap — free, open-source, and powered by Claude.

## Install

Add livindocs to your Claude Code project:

```bash
claude install /path/to/livindocs
```

Or clone and install locally:

```bash
git clone https://github.com/livindocs/livindocs.git
claude install ./livindocs
```

## Quick Start

```
/livindocs:init              # Set up config for your project
/livindocs:generate readme   # Generate a README
/livindocs:generate architecture  # Generate ARCHITECTURE.md with Mermaid diagrams
/livindocs:generate onboarding   # Generate ONBOARDING.md for new developers
/livindocs:generate adr      # Generate Architecture Decision Records from git history
/livindocs:generate api      # Generate API reference docs
/livindocs:generate all      # Generate all doc types
/livindocs:check             # Check if docs are stale
/livindocs:check --coverage  # Check freshness + coverage report
/livindocs:update            # Regenerate only stale sections
/livindocs:update --commit   # Update and auto-commit (for CI)
/livindocs:explain src/auth/ # Explain a file or module interactively
/livindocs:status            # See what's been built
```

## Commands

### `/livindocs:init`

Interactive setup wizard. Detects your language, framework, and project structure. Generates a `.livindocs.yml` config with sensible defaults. Creates the `.livindocs/` directory and optional build-state tracking.

### `/livindocs:generate [type]`

Generate documentation from scratch. Supported types: `readme` (default), `architecture`, `onboarding`, `adr`, `api`, `all`.

The generation pipeline:
1. Scans your codebase (respecting include/exclude patterns)
2. Groups files into chunks and estimates scope
3. Checks cache — skips re-analyzing unchanged files
4. Analyzes code structure, APIs, dependencies, module graph, and data flows
5. Generates documentation with source reference anchors and Mermaid diagrams
6. Runs quality verification (configurable by profile: minimal/standard/thorough)
7. Reports a quality score

### `/livindocs:check`

Staleness detection. Compares current code against existing documentation by checking if source files referenced in `<!-- livindocs:refs: -->` anchors have changed since docs were last generated. Reports per-section severity: `current`, `possibly-stale`, `stale`. Supports `--verbose` for detailed file-level diff and `--coverage` for documentation coverage reporting. In CI environments (`CI=true`), outputs machine-parseable status with configurable exit codes via `LIVINDOCS_FAIL_ON`.

### `/livindocs:update [--dry-run] [--commit]`

Incremental update. Runs staleness detection, then regenerates only the stale sections while preserving all content outside livindocs markers. With `--dry-run`, shows a diff of proposed changes without writing. With `--commit`, auto-commits after a successful update (designed for CI pipelines).

### `/livindocs:explain <path>`

Interactive codebase explainer. Point at a file, directory, or module and get a conversational explanation of what it does, how it connects to the rest of the system, and why it exists. Uses ProjectContext (if available) for richer explanations with module graph and data flow context.

### `/livindocs:status`

Shows build progress with auto-detection. Reads `.livindocs/build-state.json`, checks which milestones have been completed (by detecting files, exports, grep patterns, or test results), and updates the state automatically.

## Configuration

Place a `.livindocs.yml` in your project root:

```yaml
version: 1

include:
  - src/**
  - lib/**

exclude:
  - "**/*.test.*"
  - node_modules/

project:
  name: "My Project"
  description: "Brief description"
  audience: "Backend engineers"

budget:
  preset: balanced   # frugal | balanced | quality-first

quality:
  profile: standard  # minimal | standard | thorough
```

See [docs/COMMANDS.md](docs/COMMANDS.md) for full config reference.

## How It Works

livindocs is a **declarative Claude Code plugin** — no TypeScript runtime. It consists of:

- **Skills** (`skills/`) — Slash commands that orchestrate the generation pipeline
- **Agents** (`agents/`) — Specialized analysis and writing agents with isolated context
- **Scripts** (`scripts/`) — Deterministic shell scripts for scanning, budgeting, verification, and progress detection

### Architecture

```
/livindocs:generate
    │
    ├── scan.sh            # File discovery, language/framework detection, secret scanning
    ├── chunk.sh           # Group files by module for multi-pass analysis
    ├── budget.sh          # Scope estimation, budget enforcement
    ├── cache.sh           # Content-hash caching, skip unchanged files
    │
    ├── Analyzer Agent     # Reads code, maps structure, module graph, data flows
    ├── Writer Agent       # Generates README with markers and source refs
    ├── Arch-Writer Agent  # Generates ARCHITECTURE.md with Mermaid diagrams
    ├── Onboarding Agent   # Generates ONBOARDING.md for new developers
    ├── ADR Generator      # Generates Architecture Decision Records
    ├── API Analyzer       # Analyzes REST/GraphQL endpoints, auth, responses
    ├── API Ref Writer     # Generates docs/API.md with endpoint reference
    │
    ├── git-history.sh     # Git history analysis for ADR inference
    ├── github.sh          # GitHub API integration (PRs, issues, reviews)
    ├── detect-monorepo.sh     # Workspace detection (npm/pnpm/lerna/cargo/go)
    ├── run-custom-analyzers.sh # Custom plugin discovery and execution
    ├── coverage.sh            # Documentation coverage reporting
    ├── verify.sh              # Programmatic claim verification
    └── detect-progress.sh     # Auto-detect milestone completion
```

### CI/CD Integration

livindocs works in CI pipelines to gate PRs on documentation freshness:

**GitHub Actions:**
```yaml
- uses: livindocs/action@v1
  with:
    command: check
    fail-on: stale
```

**GitLab CI:**
```yaml
include:
  - remote: 'https://raw.githubusercontent.com/livindocs/livindocs/main/ci/gitlab-ci.yml'
```

CI modes:
- **check** — read-only, exits non-zero if docs are stale (for PR gates)
- **update --dry-run** — shows what would change (for PR comments)
- **update --commit** — updates docs and auto-commits (for doc maintenance bots)

### Quality Assurance

Generated docs go through multiple verification layers:

1. **Structural analysis** — deterministic file scanning, no LLM
2. **Semantic analysis** — LLM reads code and produces structured findings
3. **Self-critique** — writer agent verifies its own claims against source
4. **Programmatic checks** — file paths, endpoint counts, dependency versions verified by script

Quality profiles control the depth of review:

| Profile | Self-critique | Programmatic checks | Token cost |
|---|---|---|---|
| `minimal` | No | No | 1.0x |
| `standard` | Yes | Yes | ~1.3x |
| `thorough` | Yes | Yes | ~1.6x |

### Budget Presets

| Preset | Quality | Auto-approve | Warn threshold | Max tokens |
|---|---|---|---|---|
| `frugal` | minimal | 20K | 50K | 100K |
| `balanced` | standard | 50K | 150K | unlimited |
| `quality-first` | thorough | 100K | 300K | unlimited |

### Secret Detection

livindocs scans for secrets (API keys, tokens, connection strings) and never includes them in generated docs. 16 built-in patterns cover AWS, GCP, Stripe, JWT, SSH keys, database URLs, and more. Files like `.env`, `*.pem`, and `credentials.json` are excluded by default.

### Monorepo Support

livindocs auto-detects monorepos using workspace configuration files:

- **npm/yarn** — `package.json` with `workspaces` field
- **pnpm** — `pnpm-workspace.yaml`
- **lerna** — `lerna.json`
- **Cargo** — `Cargo.toml` with `[workspace]` section
- **Go** — `go.work` file

When a monorepo is detected:
- **Root-level docs** show the full system architecture with package relationship diagrams
- **Per-package docs** are generated inside each package directory
- Inter-package dependencies and shared dependencies are automatically mapped

### Custom Analyzers & Generators

Extend livindocs with project-specific analysis and documentation:

- **Script analyzers** (`.livindocs/analyzers/*.sh`) — Shell scripts that output structured findings. Run deterministically before LLM analysis.
- **Agent analyzers** (`.livindocs/analyzers/*.md`) — Markdown agent definitions that analyze specific aspects of your code using Claude's reasoning.
- **Custom generators** (`.livindocs/generators/*.md`) — Markdown agent definitions that produce additional documentation files.

Custom analyzer findings are merged into the ProjectContext and available to all generators (both built-in and custom).

See [docs/CUSTOM_ANALYZERS.md](docs/CUSTOM_ANALYZERS.md) for the full interface spec.

## Supported Languages

- TypeScript / JavaScript (Node.js, React, Next.js, Express, Fastify)
- Python (Django, Flask, FastAPI)
- Go
- Rust

## Build State Tracking

livindocs tracks project milestones in `.livindocs/build-state.json`. Each item has a detection strategy:

- `file_exists` — check if a file exists
- `grep` — search for a pattern in the codebase
- `export_exists` — check for an exported symbol
- `test_passes` — run a test command

Run `/livindocs:status` to auto-detect completed items and see what's left.

## Development

### Running Tests

```bash
bash tests/run-tests.sh
```

Tests run against fixture projects in `tests/fixtures/` and verify all four shell scripts.

### Project Structure

```
livindocs/
├── .claude-plugin/plugin.json   # Plugin manifest
├── skills/
│   ├── init/SKILL.md            # /livindocs:init
│   ├── generate/SKILL.md        # /livindocs:generate
│   ├── check/SKILL.md           # /livindocs:check
│   ├── update/SKILL.md          # /livindocs:update
│   ├── explain/SKILL.md         # /livindocs:explain
│   └── status/SKILL.md          # /livindocs:status
├── agents/
│   ├── analyzer.md              # Codebase analysis agent
│   ├── writer.md                # README generation agent
│   ├── architecture-writer.md   # ARCHITECTURE.md + Mermaid diagrams agent
│   ├── onboarding-writer.md     # ONBOARDING.md generation agent
│   ├── adr-generator.md         # Architecture Decision Records from git history
│   ├── api-analyzer.md          # API surface analysis agent
│   └── api-reference-writer.md  # API reference doc generation agent
├── scripts/
│   ├── scan.sh                  # File discovery + secret scanning
│   ├── chunk.sh                 # File grouping for multi-pass analysis
│   ├── budget.sh                # Scope estimation + enforcement
│   ├── cache.sh                 # Content-hash caching
│   ├── verify.sh                # Programmatic claim verification
│   ├── coverage.sh              # Documentation coverage reporting
│   ├── staleness.sh             # Per-section staleness detection
│   ├── baseline.sh              # Staleness baseline snapshots
│   ├── git-history.sh           # Git history analysis for ADR inference
│   ├── github.sh                # GitHub API integration via gh CLI
│   ├── detect-monorepo.sh       # Monorepo workspace detection
│   ├── run-custom-analyzers.sh  # Custom plugin discovery & execution
│   ├── benchmark.sh             # Performance benchmarking
│   ├── telemetry.sh             # Opt-in anonymous telemetry
│   ├── version-docs.sh          # Versioned documentation snapshots
│   └── detect-progress.sh       # Milestone auto-detection
├── tests/
│   ├── run-tests.sh             # Integration test suite
│   └── fixtures/                # Test codebases
├── ci/
│   ├── action.yml               # GitHub Actions composite action
│   └── gitlab-ci.yml            # GitLab CI template
├── templates/
│   ├── readme.md.hbs            # README template
│   ├── architecture.md.hbs      # Architecture doc template
│   ├── onboarding.md.hbs        # Onboarding guide template
│   └── adr.md.hbs               # ADR template
├── docs/
│   ├── COMMANDS.md              # Full config reference
│   ├── MILESTONES.md            # Milestone details
│   ├── CUSTOM_ANALYZERS.md     # Custom plugin interface spec
│   └── TEMPLATES.md             # Template customization guide
├── CONTRIBUTING.md               # Contributor guide
└── CLAUDE.md                    # Dev conventions
```

## Roadmap

- **M1 (v0.1)** — Foundation: README generation, scanning, budget, verification, progress tracking
- **M2 (v0.2)** — Architecture docs, Mermaid diagrams, caching, chunking, quality profiles
- **M3 (v0.3)** — Staleness detection, incremental updates, baseline snapshots
- **M4 (v0.4)** — Git history analysis, ADR generation, interactive explain command
- **M5 (v0.5)** — Monorepo support, custom analyzers, custom generators
- **M6 (v0.6)** — API docs, coverage reporting, CI/CD integration (GitHub Actions + GitLab CI)
- **M7 (v1.0)** — Community release: templates, benchmarks, versioned docs, telemetry, model selection, `--budget` flag *(current)*

See [docs/MILESTONES.md](docs/MILESTONES.md) for details.

## License

MIT
