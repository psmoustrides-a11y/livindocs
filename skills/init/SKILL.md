---
name: init
description: "Initialize livindocs in a project. Detects language/framework, creates .livindocs.yml config, and sets up build state tracking. Use when a user wants to set up livindocs for the first time in their project."
disable-model-invocation: true
allowed-tools: Bash, Read, Write, Glob
argument-hint: ""
---

# livindocs:init — Project Setup Wizard

You are setting up livindocs for this project. Follow these steps exactly.

## Step 1: Detect project characteristics

Run the detection script to understand the project:

```
!`${CLAUDE_PLUGIN_ROOT}/scripts/scan.sh --detect-only .`
```

Also check if a config already exists:
```
!`test -f .livindocs.yml && echo "CONFIG_EXISTS: true" || echo "CONFIG_EXISTS: false"`
```

## Step 2: Present findings and ask questions

Tell the user what you detected (languages, frameworks, entry points). If a `.livindocs.yml` already exists, ask if they want to reconfigure or keep the existing one.

Ask the user these questions (provide smart defaults based on detection):

1. **Project name** — Default: detect from package.json `name` field, go.mod module name, or directory name
2. **Description** — Default: detect from package.json `description` or ask user
3. **Audience** — Who will read these docs? (e.g., "Backend engineers familiar with Node.js")
4. **Include paths** — Which directories to scan. Default based on detected language:
   - JS/TS: `src/**`, `lib/**`, `app/**`
   - Python: `src/**`, `app/**`, `<package_name>/**`
   - Go: `cmd/**`, `pkg/**`, `internal/**`
   - Rust: `src/**`
5. **Budget preset** — `frugal` (fast, fewer passes), `balanced` (default), or `quality-first` (thorough)
6. **Quality profile** — `minimal`, `standard` (default), or `thorough`
7. **Tracking** — Ask if they want build state tracking enabled (default: yes). If yes, ask them to describe their project milestones or say "auto" to detect from existing docs/issues.

For each question, provide the detected default in brackets so the user can just press enter to accept.

## Step 3: Write .livindocs.yml

Based on the answers, write a `.livindocs.yml` file to the project root:

```yaml
version: 1

outputs:
  - readme

docs_dir: docs/

include:
  - <include patterns from answers>

exclude:
  - "**/*.test.*"
  - "**/*.spec.*"
  - node_modules/
  - dist/
  - build/

project:
  name: "<project name>"
  description: "<description>"
  audience: "<audience>"

budget:
  preset: <preset>

quality:
  profile: <profile>

tracking:
  enabled: <true/false>
  auto_detect: true
```

## Step 4: Create directory structure

Create the following directories if they don't exist:
- `docs/` — where generated documentation will go
- `.livindocs/` — plugin working directory (cache, state)
- `.livindocs/cache/` — analysis cache

## Step 5: Set up build state tracking

If tracking is enabled, create `.livindocs/build-state.json`. If the user described milestones, structure them. If they said "auto", create a minimal template:

```json
{
  "version": 1,
  "updated_at": "<ISO timestamp>",
  "milestones": [
    {
      "name": "<milestone name>",
      "items": [
        {
          "name": "<item name>",
          "status": "pending",
          "detect": {
            "file_exists": "<path>"
          }
        }
      ]
    }
  ]
}
```

For auto-detection, scan for:
- Existing milestone/roadmap files (MILESTONES.md, ROADMAP.md, TODO.md)
- GitHub issues/project boards (suggest connecting later)
- Common project milestones based on detected framework (e.g., for Express: "API routes", "Authentication", "Database", "Tests", "CI/CD")

## Step 6: Update .gitignore

Check if `.gitignore` exists. If so, ensure these entries are present (add them if missing):
```
.livindocs/cache/
.livindocs/config.local.yml
```

Do NOT add `.livindocs/build-state.json` to gitignore — it should be committed.

## Step 7: Summary

Print a summary of what was created:
```
livindocs initialized!

  Config: .livindocs.yml
  Docs dir: docs/
  Languages: <detected>
  Frameworks: <detected>
  Budget: <preset>
  Quality: <profile>
  Tracking: <enabled/disabled>

Next steps:
  /livindocs:generate readme  — Generate your README
  /livindocs:status           — View project progress
```
