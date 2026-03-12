# livindocs — Claude Code Plugin

An open-source Claude Code plugin that generates living documentation using Claude's reasoning to understand architecture, data flow, intent, and design decisions.

**Name:** `livindocs`
**License:** MIT
**Type:** Declarative Claude Code plugin (skills + agents + shell scripts)

## Problem

Documentation rot is universal. Static generators require manual writing and go stale. Commercial platforms are expensive and proprietary. Nobody auto-generates architectural docs, onboarding guides, or ADRs. This plugin fills that gap.

## Architecture

This is a **declarative Claude Code plugin** — no TypeScript runtime. The plugin consists of:

- **Skills** (`skills/`) — Slash commands with YAML frontmatter + markdown instructions
- **Agents** (`agents/`) — Specialized agents with isolated context windows
- **Scripts** (`scripts/`) — Deterministic shell scripts for scanning, budgeting, verification

Data flows through the pipeline: `scan.sh → budget.sh → Analyzer Agent → Writer Agent → verify.sh`

Agents communicate via `.livindocs/cache/context/latest.json` (ProjectContext JSON).

## Commands

- `/livindocs:init` — Setup wizard, generates `.livindocs.yml`
- `/livindocs:generate [type]` — Generate docs (readme, architecture, all)
- `/livindocs:check` — Staleness detection with per-section severity
- `/livindocs:update [--dry-run]` — Incremental update of stale sections only
- `/livindocs:status` — Show build progress with auto-detection

## Development Conventions

### Shell Scripts
- All scripts must work on macOS (no `grep -P`, no GNU-only features)
- Use `grep -E` and POSIX character classes (`[[:space:]]` not `\s`)
- No external dependencies beyond standard Unix tools (no `jq`, no `timeout`)
- Scripts output structured blocks (`=== SECTION ===`) for machine parsing

### Git Workflow
- `main` branch is always releasable
- Feature branches: `feat/description`
- Conventional commits: `feat:`, `fix:`, `docs:`, `refactor:`, `test:`

### Testing
- Integration tests in `tests/run-tests.sh`
- Test against fixture codebases in `tests/fixtures/`
- Run: `bash tests/run-tests.sh`

## Supported Languages (v1)

1. TypeScript/JavaScript (Node.js, React, Next.js, Express)
2. Python (Django, Flask, FastAPI)
3. Go
4. Rust

## Detailed Documentation

- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) — Design principles, caching, chunking, error handling
- [docs/COMMANDS.md](docs/COMMANDS.md) — Command details and `.livindocs.yml` config reference
- [docs/INTERFACES.md](docs/INTERFACES.md) — TypeScript interfaces for ProjectContext, Quality, Budget
- [docs/QUALITY.md](docs/QUALITY.md) — 4-layer quality assurance system, profiles, scoring
- [docs/BUDGET.md](docs/BUDGET.md) — Cost estimation, enforcement, presets
- [docs/SECURITY.md](docs/SECURITY.md) — Secret detection and redaction
- [docs/MILESTONES.md](docs/MILESTONES.md) — Milestone plan M1-M7
- [docs/INTEGRATIONS.md](docs/INTEGRATIONS.md) — GitHub, monorepo, CI/CD, diagrams
