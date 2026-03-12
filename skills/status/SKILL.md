---
name: status
description: "Show project build progress tracked by livindocs. Displays milestone completion, auto-detects newly completed items, and shows what still needs to be built. Use when a user wants to see project progress or check what's done."
disable-model-invocation: true
allowed-tools: Bash, Read
argument-hint: "[--refresh]"
---

# livindocs:status — Build Progress Tracker

You are showing the user their project's build progress as tracked by livindocs.

## Step 1: Check for build state

```
!`test -f .livindocs/build-state.json && echo "STATE_EXISTS: true" || echo "STATE_EXISTS: false"`
```

If no build state exists, tell the user:
```
No build state found. Run /livindocs:init to set up project tracking.
```
And stop.

## Step 2: Run auto-detection

If `$ARGUMENTS` contains `--refresh` or by default, run the progress detection script:

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/detect-progress.sh .
```

This checks each pending item's detection rules (file_exists, grep patterns, etc.) and marks newly completed items.

## Step 3: Read and display progress

Read `.livindocs/build-state.json` and display a formatted progress report.

Format the output as a clear, scannable table:

```
Project Progress: PROJECT_NAME
Last updated: TIMESTAMP

Overall: DONE/TOTAL items (XX%)
[=========>          ] XX%

Milestone: MILESTONE_NAME
  [x] Item 1 (auto-detected)
  [x] Item 2
  [ ] Item 3
  [ ] Item 4

Milestone: MILESTONE_NAME_2
  [x] Item 1 (auto-detected)
  [ ] Item 2

---
NEWLY_DETECTED items were auto-detected as complete since last check.

To add milestones: edit .livindocs/build-state.json
To refresh: /livindocs:status --refresh
```

## Step 4: Highlight changes

If `NEWLY_DETECTED` > 0 from the detection script, call out what was newly detected:

```
Newly completed (auto-detected):
  - [Milestone] Item name (detected via: file_exists src/auth/login.ts)
  - [Milestone] Item name (detected via: grep "verifyToken")
```

## Display rules

- Use `[x]` for done items and `[ ]` for pending items
- Group by milestone
- Show detection method for auto-detected items
- If a milestone is 100% complete, mark it with a checkmark
- Keep output concise — no lengthy descriptions, just item names and status
