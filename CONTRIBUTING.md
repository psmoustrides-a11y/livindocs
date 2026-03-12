# Contributing to livindocs

## Dev Environment Setup

1. Clone the repo:
   ```bash
   git clone https://github.com/your-org/livindocs.git
   ```

2. Install as a Claude Code plugin:
   ```bash
   claude plugin add /path/to/livindocs
   ```

3. Verify it works:
   ```bash
   claude /docs status
   ```

## Project Structure

```
livindocs/
├── skills/              # Slash commands (each is a dir with SKILL.md)
│   ├── generate/        # /docs generate
│   ├── check/           # /docs check
│   ├── update/          # /docs update
│   ├── explain/         # /docs explain
│   ├── init/            # /docs init
│   └── status/          # /docs status
├── agents/              # Specialized worker agents (.md files)
│   ├── analyzer.md      # Code analysis agent
│   ├── writer.md        # General doc writer
│   ├── architecture-writer.md
│   ├── api-analyzer.md
│   ├── api-reference-writer.md
│   ├── onboarding-writer.md
│   └── adr-generator.md
├── scripts/             # Shell scripts for deterministic logic
│   ├── scan.sh          # File discovery and language detection
│   ├── chunk.sh         # File grouping for multi-pass analysis
│   ├── budget.sh        # Cost estimation and enforcement
│   ├── cache.sh         # Content-hash caching
│   ├── verify.sh        # Programmatic claim verification
│   ├── coverage.sh      # Documentation coverage
│   ├── staleness.sh     # Staleness detection
│   ├── baseline.sh      # Staleness baselines
│   ├── git-history.sh   # Git history analysis
│   ├── github.sh        # GitHub API integration
│   ├── detect-monorepo.sh
│   ├── detect-progress.sh
│   ├── run-custom-analyzers.sh
│   ├── benchmark.sh     # Performance benchmarking
│   ├── telemetry.sh     # Opt-in telemetry
│   └── version-docs.sh  # Versioned documentation
├── templates/           # Handlebars doc templates
├── tests/
│   ├── fixtures/        # Sample projects for testing
│   └── run-tests.sh     # Test runner
├── ci/                  # CI/CD integration configs
├── docs/                # Generated documentation
├── CLAUDE.md            # Plugin instructions
└── README.md
```

This is a **declarative Claude Code plugin** -- there is no TypeScript runtime. Skills define slash commands via SKILL.md frontmatter, agents handle specialized work via .md files, and shell scripts handle all deterministic logic.

## Adding a New Skill

Skills are slash commands. Each skill lives in `skills/<name>/SKILL.md`.

1. Create the directory:
   ```bash
   mkdir skills/my-command
   ```

2. Create `skills/my-command/SKILL.md` with frontmatter:
   ```markdown
   ---
   name: my-command
   description: Short description of what this command does
   ---

   # Instructions for the agent

   Describe what the skill should do, what scripts to call,
   what agents to delegate to, and what output to produce.
   ```

3. Add tests in `tests/run-tests.sh` if the skill depends on scripts.

## Adding a New Agent

Agents are specialized workers that skills delegate to. Each agent is a single `.md` file in `agents/`.

1. Create `agents/my-agent.md` with frontmatter:
   ```markdown
   ---
   name: my-agent
   description: What this agent specializes in
   ---

   # Instructions

   Describe the agent's role, what inputs it expects,
   what tools it should use, and what output format to produce.
   ```

2. Reference the agent from a skill's SKILL.md when delegating work.

## Adding a New Script

Scripts handle deterministic logic (file scanning, config parsing, caching, etc.).

1. Create `scripts/my-script.sh`:
   ```bash
   #!/usr/bin/env bash
   # my-script.sh — Brief description
   # Usage: my-script.sh [args]

   set -euo pipefail

   # Script logic here
   ```

2. Make it executable:
   ```bash
   chmod +x scripts/my-script.sh
   ```

3. Add tests in `tests/run-tests.sh`.

### Shell Script Conventions

All scripts must be **macOS compatible**. Follow these rules:

- **Always start with** `set -euo pipefail`
- **No `grep -P`** -- use `grep -E` for extended regex
- **POSIX character classes** -- use `[[:space:]]` not `\s`
- **Safe grep in pipefail** -- wrap grep in braces to prevent pipefail exits on no-match:
  ```bash
  # BAD: exits non-zero if grep finds nothing
  result=$(echo "$data" | grep 'pattern')

  # GOOD: safe under pipefail
  result=$({ echo "$data" | grep 'pattern' || true; })
  ```
- **Structured output blocks** -- scripts output machine-parseable blocks:
  ```
  === SECTION NAME ===
  KEY: value
  KEY: value
  ====================
  ```
- **No GNU-specific flags** -- stick to POSIX/BSD tool behavior
- **Use `awk` for field extraction** instead of GNU-only `cut` options

## Testing

Run the test suite:

```bash
bash tests/run-tests.sh
```

Tests run scripts against fixture projects in `tests/fixtures/` and verify output. Tests do not require a live Claude Code session.

When adding a new script, add corresponding test cases to `tests/run-tests.sh` using the existing `assert_contains` / `assert_not_contains` helpers.

## Git Workflow

- **Branch naming**: `feat/description`, `fix/description`, `docs/description`
- **Conventional commits**: `feat:`, `fix:`, `docs:`, `refactor:`, `test:`, `chore:`
- **Base branch**: `main` is always releasable

## PR Requirements

- All tests pass (`bash tests/run-tests.sh`)
- New features include tests
- Shell scripts are macOS compatible
- No hardcoded paths or platform-specific assumptions
