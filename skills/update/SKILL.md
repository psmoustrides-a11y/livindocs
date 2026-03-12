---
name: update
description: "Incrementally update stale documentation sections. Runs staleness detection, identifies stale sections, and regenerates only those sections while preserving manual edits outside markers. Supports --dry-run to preview changes without writing."
disable-model-invocation: true
allowed-tools: Bash, Read, Write, Edit, Glob, Grep, Agent
argument-hint: "[--dry-run]"
---

# livindocs:update — Incremental Documentation Update

You are updating only the stale sections of the project's documentation, preserving all content outside livindocs markers.

Arguments: **$ARGUMENTS** (supports `--dry-run`, `--commit`)

## Step 1: Pre-flight

```
!`test -f .livindocs.yml && echo "CONFIG: true" || echo "CONFIG: false"`
```

If no config, tell the user to run `/livindocs:init` first and stop.

## Step 2: Run staleness detection

```
!`${CLAUDE_PLUGIN_ROOT}/scripts/staleness.sh .`
```

## Step 3: Evaluate results

Read the staleness report.

### If `STATUS: no_docs`:
Tell the user: "No documentation found. Run `/livindocs:generate` to create docs first."
Stop.

### If `OVERALL: current`:
Tell the user: "All documentation is up to date. Nothing to update."
Stop.

### If there are stale sections:
List the stale sections and tell the user which ones will be updated:
```
Found N stale section(s) to update:
  - README.md#features (src/routes/users.js changed)
  - README.md#api (src/routes/auth.js changed)

Regenerating stale sections...
```

## Step 4: Ensure ProjectContext is available

Check if a recent ProjectContext exists:
```
!`test -f .livindocs/cache/context/latest.json && echo "CONTEXT: exists" || echo "CONTEXT: missing"`
```

If missing, run a fresh analysis first:
```
!`mkdir -p .livindocs/cache/context`
```

Run a scan for the analyzer:
```
!`${CLAUDE_PLUGIN_ROOT}/scripts/scan.sh .`
```

Delegate to the **analyzer** agent:
- Provide the scan results from above
- Task: "Analyze this codebase and write a ProjectContext JSON to .livindocs/cache/context/latest.json"

## Step 5: Regenerate stale sections

For each stale section, determine which agent should handle it:
- Sections in `README.md` → delegate to the **writer** agent
- Sections in `docs/ARCHITECTURE.md` or `ARCHITECTURE.md` → delegate to the **architecture-writer** agent

When delegating, provide:
- The path to ProjectContext: `.livindocs/cache/context/latest.json`
- The specific section name(s) that need updating
- The current doc file content (so the agent preserves non-stale sections)
- Task: "Update ONLY the following stale sections in [DOC_FILE]: [SECTION_LIST]. Read the current file, re-analyze the referenced source files, and rewrite only the content between the livindocs:start and livindocs:end markers for each stale section. Preserve ALL other content exactly as-is."

### Dry-run mode

If `$ARGUMENTS` contains `--dry-run`:
- Tell the agent to generate the updated content but NOT write it to disk
- Instead, show the user a diff of what would change for each stale section:
  ```
  --- README.md#features (current)
  +++ README.md#features (proposed)
  @@ section content diff @@
  ```
- After showing the diff, ask: "Apply these changes? (Y/n)"
- If yes, write the changes. If no, stop.

### Normal mode

Let the agent write the updated file directly using the Edit tool (preserving content outside markers).

## Step 6: Verify updated sections

Run verification on each doc that was updated. Only verify docs that had stale sections regenerated:

If README.md was updated:
```bash
${CLAUDE_PLUGIN_ROOT}/scripts/verify.sh README.md .
```

If docs/ARCHITECTURE.md was updated:
```bash
${CLAUDE_PLUGIN_ROOT}/scripts/verify.sh docs/ARCHITECTURE.md .
```

Report any verification failures.

## Step 7: Update baseline

Save a new baseline snapshot after successful update:
```bash
${CLAUDE_PLUGIN_ROOT}/scripts/baseline.sh save .
```

## Step 8: Summary

```
Update complete.

Updated N section(s):
  - README.md#features — regenerated (src/routes/users.js changed)
  - README.md#api — regenerated (src/routes/auth.js changed)

Verification: PASSED/CHECKS claims verified
New baseline saved at TIMESTAMP.

To check freshness later: /livindocs:check
```

## Auto-commit mode

If `$ARGUMENTS` contains `--commit`:

After the update completes and verification passes, automatically commit the changes:
```bash
git add README.md docs/
git commit -m "docs: update generated documentation [livindocs]"
```

This mode is designed for CI/CD pipelines where docs should be auto-maintained. The commit message includes `[livindocs]` so it can be filtered in git log.

If both `--dry-run` and `--commit` are specified, `--dry-run` takes precedence (show diff, don't commit).

## Important rules

- NEVER modify content outside of `<!-- livindocs:start:SECTION -->` ... `<!-- livindocs:end:SECTION -->` markers.
- Only regenerate sections that are marked as STALE. Leave CURRENT and POSSIBLY_STALE sections alone.
- Always update `<!-- livindocs:refs: -->` anchors in regenerated sections to reflect current source file references.
- In dry-run mode, NEVER write files until the user confirms.
- In commit mode, only commit if verification passes.
