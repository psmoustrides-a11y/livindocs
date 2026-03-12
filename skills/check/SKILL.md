---
name: check
description: "Check documentation freshness. Compares existing docs against current code to detect stale sections. Shows per-section staleness with severity levels (current, possibly-stale, stale). Use when a user wants to know if their docs are up to date."
disable-model-invocation: true
allowed-tools: Bash, Read
argument-hint: "[--verbose]"
---

# livindocs:check — Staleness Detection

You are checking whether the project's documentation is up to date.

## Step 1: Pre-flight

Verify docs exist:
```
!`test -f .livindocs.yml && echo "CONFIG: true" || echo "CONFIG: false"`
```

If no config, tell the user to run `/livindocs:init` first and stop.

## Step 2: Run staleness detection

```
!`${CLAUDE_PLUGIN_ROOT}/scripts/staleness.sh .`
```

## Step 3: Display report

Read the staleness report output and present it to the user in a formatted table.

### If `STATUS: no_docs`:
Tell the user: "No documentation with livindocs markers found. Run `/livindocs:generate` to create docs."

### If `OVERALL: current`:
```
Documentation is up to date.

All N sections are current (last baseline: TIMESTAMP).

  Section                          Status
  ─────────────────────────────────────────
  README.md#header                 current
  README.md#features               current
  ...
```

### If `OVERALL: slightly-stale` or `stale` or `very-stale`:
```
Documentation needs attention.

N/TOTAL sections are stale or possibly stale.

  Section                          Status          Changed refs
  ────────────────────────────────────────────────────────────────
  README.md#header                 current
  README.md#features               STALE           src/routes/users.js
  README.md#architecture           current
  ...

Stale sections reference source files that have changed since docs were last generated.
Run `/livindocs:update` to regenerate only the stale sections.
Run `/livindocs:generate all` to regenerate everything.
```

### If `BASELINE: missing`:
Add a note: "No baseline found — all sections show as possibly-stale. Run `/livindocs:generate` to establish a baseline."

## Step 4: Verbose mode

If the user passed `--verbose` (check $ARGUMENTS), also show the baseline comparison:
```
!`${CLAUDE_PLUGIN_ROOT}/scripts/baseline.sh compare .`
```

### If `STATUS: no_baseline`:
Tell the user: "No baseline found. Run `/livindocs:generate` to create a baseline for detailed comparison."

### If `STATUS: compared`:
Display the full list of changed, missing, and new files.

## Step 5: Coverage report (optional)

If the user passed `--coverage` (check $ARGUMENTS), also run the coverage reporter:
```bash
${CLAUDE_PLUGIN_ROOT}/scripts/coverage.sh .
```

Display the coverage summary after the staleness report.

## CI mode

If the environment variable `CI=true` is set or the user passed `--ci`:

Output a structured, machine-parseable summary instead of the human-friendly table:
```
LIVINDOCS_STATUS=current|stale|possibly-stale
LIVINDOCS_STALE_COUNT=N
LIVINDOCS_TOTAL_SECTIONS=N
LIVINDOCS_BASELINE=present|missing
```

Exit codes for CI:
- `0` — docs are current
- `1` — docs are stale (when `LIVINDOCS_FAIL_ON=stale`)
- `1` — docs are possibly-stale or worse (when `LIVINDOCS_FAIL_ON=possibly-stale`)

The `LIVINDOCS_FAIL_ON` environment variable controls the threshold (default: `stale`).

## Rules

- This is a read-only command — never modify any files.
- Use severity indicators in the table: `current` (plain), `POSSIBLY_STALE` (warning), `STALE` (alert).
- Always suggest next steps based on the result.
