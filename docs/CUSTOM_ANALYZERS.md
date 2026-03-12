# Custom Analyzers & Generators

livindocs supports custom analyzer and generator plugins that extend the documentation pipeline with project-specific logic.

## Overview

- **Custom analyzers** produce structured findings that get merged into the ProjectContext
- **Custom generators** produce additional documentation files from the ProjectContext
- Both live in the `.livindocs/` directory alongside your project config

```
.livindocs/
├── analyzers/              # Custom analyzer plugins
│   ├── rpc-analyzer.sh     # Shell script analyzer
│   └── domain-model.md     # Agent-based analyzer
├── generators/             # Custom generator plugins
│   └── runbook.md          # Agent-based generator
└── .livindocs.yml
```

## Custom Analyzers

### Shell Script Analyzers (`.sh`)

Shell script analyzers are executable scripts that output structured text. They run deterministically before the LLM analysis pass.

**File location:** `.livindocs/analyzers/<name>.sh`

**Interface:**

```bash
#!/usr/bin/env bash
# description: Analyzes internal RPC framework conventions
# file-filter: *.rpc.ts

# The script receives the project directory as $1
PROJECT_DIR="${1:-.}"
cd "$PROJECT_DIR"

# Output structured findings in key-value format
echo "=== CUSTOM FINDINGS ==="
echo "ANALYZER: rpc-conventions"
echo "CONFIDENCE: 0.9"
echo ""

# Your analysis logic here
echo "FINDINGS:"
echo "  - Found 12 RPC service definitions"
echo "  - All services use the BaseRPC pattern"
echo "  - Error handling: Result<T, RpcError> pattern"
echo ""

echo "DATA:"
echo "  RPC_SERVICE_COUNT: 12"
echo "  PATTERN: BaseRPC"
echo "  ERROR_HANDLING: Result type"

echo "========================"
```

**Header comments:**
- `# description:` — One-line description (shown in `list` output)
- `# file-filter:` — Glob pattern for files this analyzer cares about (informational, used by the agent)

**Rules:**
- Must be executable (`chmod +x`)
- Receives project directory as first argument
- Must output to stdout (stderr is captured but not parsed)
- Exit 0 on success, non-zero on failure
- Output is passed to the analyzer agent as additional context

### Agent-Based Analyzers (`.md`)

Agent-based analyzers are markdown files with frontmatter that define a Claude agent. They run during the LLM analysis pass with full access to read tools.

**File location:** `.livindocs/analyzers/<name>.md`

**Interface:**

```markdown
---
name: domain-model
description: Analyzes domain model entities and their relationships
file-filter: "src/models/**"
output-key: domainModel
---

# Domain Model Analyzer

You are a custom analyzer for the livindocs documentation plugin.

## What to analyze

Read all files matching `src/models/**` and identify:
- Entity names and their properties
- Relationships between entities (1:1, 1:N, N:M)
- Validation rules
- Database schema implications

## Output format

Add a `domainModel` key to the ProjectContext JSON with this structure:

```json
{
  "domainModel": {
    "entities": [
      {
        "name": "User",
        "file": "src/models/user.ts",
        "properties": ["id", "email", "name", "role"],
        "relationships": [
          { "target": "Order", "type": "1:N", "field": "orders" }
        ]
      }
    ],
    "diagram": "erDiagram\n  User ||--o{ Order : places"
  }
}
```

## Rules

- Only document entities you can verify in the source code
- Include file references for every entity
- Generate a Mermaid ER diagram if there are relationships
```

**Frontmatter fields:**
- `name` (required) — Unique identifier
- `description` (required) — One-line description
- `file-filter` — Glob pattern for relevant files
- `output-key` — Key name to add to the ProjectContext JSON

**How it runs:**
The generate skill launches agent-based analyzers via the Agent tool after the main analyzer completes. The agent reads the relevant files and updates `.livindocs/cache/context/latest.json` with its findings under the specified `output-key`.

## Custom Generators

Custom generators are markdown agent definitions that produce additional documentation files.

**File location:** `.livindocs/generators/<name>.md`

**Interface:**

```markdown
---
name: runbook
description: Generates an operations runbook from infrastructure config
output-file: docs/RUNBOOK.md
---

# Runbook Generator

You are a custom documentation generator for the livindocs plugin.

## Input

Read the ProjectContext from `.livindocs/cache/context/latest.json`.
Also read any infrastructure files:
- `Dockerfile`, `docker-compose.yml`
- `k8s/`, `terraform/`, `.github/workflows/`
- Environment config files

## Output

Generate `docs/RUNBOOK.md` with these sections:

### Deployment
How to deploy this service. Include actual commands from Makefile/scripts.

### Monitoring
What to monitor, based on detected logging/metrics patterns.

### Troubleshooting
Common failure modes based on error handling patterns in the code.

## Rules

- Wrap all sections in livindocs markers
- Include source reference anchors
- Only document what you can verify in the code
- Skip sections where no relevant config/code exists
```

**Frontmatter fields:**
- `name` (required) — Unique identifier
- `description` (required) — One-line description
- `output-file` (required) — Where to write the generated doc

**How it runs:**
The generate skill discovers custom generators and runs them after the built-in generators. Each generator is launched as an Agent with access to Read, Write, Edit, Glob, Grep, and Bash tools.

## Discovery

Run the discovery script to see what custom plugins are installed:

```bash
scripts/run-custom-analyzers.sh list .
```

Output:
```
=== CUSTOM PLUGINS ===
ANALYZERS_DIR: .livindocs/analyzers
GENERATORS_DIR: .livindocs/generators
ANALYZER_COUNT: 2
GENERATOR_COUNT: 1

ANALYZER:
  NAME: rpc-conventions
  TYPE: script
  PATH: .livindocs/analyzers/rpc-conventions.sh
  DESCRIPTION: Analyzes internal RPC framework conventions
  FILE_FILTER: *.rpc.ts
  ---
ANALYZER:
  NAME: domain-model
  TYPE: agent
  PATH: .livindocs/analyzers/domain-model.md
  DESCRIPTION: Analyzes domain model entities
  FILE_FILTER: src/models/**
  ---
GENERATOR:
  NAME: runbook
  PATH: .livindocs/generators/runbook.md
  DESCRIPTION: Generates an operations runbook
  OUTPUT_FILE: docs/RUNBOOK.md
  ---
=======================
```

## Integration with `/livindocs:generate`

When you run `/livindocs:generate all`:

1. **Scan** — File discovery, language detection
2. **Custom script analyzers** — All `.sh` analyzers in `.livindocs/analyzers/` run deterministically
3. **Built-in analysis** — The analyzer agent reads code and produces ProjectContext
4. **Custom agent analyzers** — All `.md` analyzers run and add their findings to ProjectContext
5. **Built-in generators** — README, ARCHITECTURE, ONBOARDING, ADRs
6. **Custom generators** — All `.md` generators in `.livindocs/generators/` run
7. **Verification** — Quality checks on all generated docs

Custom analyzer findings are available to both built-in and custom generators through the ProjectContext.

## Examples

### Analyzing internal conventions

```bash
#!/usr/bin/env bash
# description: Detects team coding conventions from .eslintrc and tsconfig
# file-filter: .eslintrc*,tsconfig.json

PROJECT_DIR="${1:-.}"
cd "$PROJECT_DIR"

echo "=== CUSTOM FINDINGS ==="
echo "ANALYZER: coding-conventions"

if [[ -f ".eslintrc.json" ]] || [[ -f ".eslintrc.js" ]]; then
  echo "ESLINT: detected"
  # Extract key rules
  if grep -q "no-any" .eslintrc* 2>/dev/null; then
    echo "RULE: no-any types enforced"
  fi
fi

if [[ -f "tsconfig.json" ]]; then
  if grep -q '"strict": true' tsconfig.json; then
    echo "TYPESCRIPT: strict mode enabled"
  fi
fi

echo "========================"
```

### Generating API changelog

```markdown
---
name: api-changelog
description: Generates API changelog from git history
output-file: docs/API_CHANGELOG.md
---

# API Changelog Generator

Read git history for changes to API route files. Generate a changelog
grouped by version tag or date range. Include breaking changes prominently.

Use `git log --all --oneline -- src/routes/` to find relevant commits.
```
