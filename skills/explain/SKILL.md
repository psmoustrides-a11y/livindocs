---
name: explain
description: "Interactive codebase explainer. Point at a file, directory, or module and get a conversational explanation of what it does, how it connects to the rest of the system, and why it exists."
disable-model-invocation: true
allowed-tools: Bash, Read, Glob, Grep, Agent
argument-hint: "<path>"
---

# livindocs:explain — Interactive Codebase Explainer

You are explaining a part of the codebase to the user in a conversational, educational way.

Target path: **$ARGUMENTS**

## Step 1: Pre-flight

```
!`test -f .livindocs.yml && echo "CONFIG: true" || echo "CONFIG: false"`
```

If no config, tell the user to run `/livindocs:init` first and stop.

If `$ARGUMENTS` is empty, tell the user:
```
Usage: /livindocs:explain <path>

Examples:
  /livindocs:explain src/routes/auth.js       — Explain a single file
  /livindocs:explain src/middleware/           — Explain a directory/module
  /livindocs:explain src/                     — Explain the entire source tree
```
Stop.

## Step 2: Validate the target

Check if the target path exists:
```
!`test -e "$ARGUMENTS" && echo "TARGET: exists" || echo "TARGET: missing"`
```

If missing, suggest similar paths:
- Use Glob to find files matching partial names
- Tell the user: "Path not found: $ARGUMENTS. Did you mean: [suggestions]?"
- Stop.

Determine the target type:
```
!`test -d "$ARGUMENTS" && echo "TYPE: directory" || echo "TYPE: file"`
```

## Step 3: Load context

Check if ProjectContext exists for richer explanation:
```
!`test -f .livindocs/cache/context/latest.json && echo "CONTEXT: exists" || echo "CONTEXT: missing"`
```

If ProjectContext exists, read it — it provides module graph, data flows, and architecture info that enriches the explanation.

Read the `.livindocs.yml` for audience info — tailor the explanation to the configured audience.

## Step 4: Analyze the target

### If target is a file:

1. Read the file
2. If ProjectContext exists, find this file in the module graph to understand:
   - What imports it (who depends on this?)
   - What it imports (what does it depend on?)
   - Which data flows pass through it
   - Which design patterns it implements
3. Look for related files:
   - Test files (same name with .test. or .spec.)
   - Config files it references
   - Files in the same directory

### If target is a directory:

1. List all files in the directory
2. Read the 3-5 most important files (entry points first, then largest/most-imported)
3. If ProjectContext exists, find all modules in this directory and their relationships
4. Understand the directory's role in the broader architecture

## Step 5: Explain

Produce a conversational explanation with these sections:

### What it does
One paragraph summary of the target's purpose. Be concrete — mention actual function names, endpoints, classes.

### How it works
Walk through the key logic. For files: describe the flow from top to bottom or by the main exported functions. For directories: describe how the files work together.

### How it connects
Explain the target's place in the broader system:
- What depends on it (importers/callers)
- What it depends on (imports/external services)
- Where it sits in the request/data flow

### Why it exists
Infer the design rationale:
- What problem does it solve?
- Why is it structured this way (and not some other way)?
- What patterns or conventions does it follow?

### Key details
Highlight anything a developer should know:
- Non-obvious behavior or edge cases
- Configuration it depends on (env vars, config files)
- Related test files
- Potential gotchas

## Step 6: Offer follow-up

After the explanation, offer:
```
Want to dive deeper? I can explain:
  - [specific file or function mentioned in the explanation]
  - [related module]
  - [the data flow this participates in]

Or run /livindocs:generate to create full documentation.
```

## Rules

- This is a **read-only** command — never modify any files.
- Be conversational, not formal. Write as if you're a senior engineer walking a teammate through the code.
- Always ground explanations in actual code — quote specific lines, reference real function names.
- If the ProjectContext is missing, do your own analysis by reading files. Don't tell the user to generate docs first — just explain what you can see.
- Tailor depth to the audience from `.livindocs.yml`. For senior engineers, skip basics. For newcomers, explain conventions.
- If the target is very large (directory with 50+ files), summarize the high-level structure first and offer to drill into specific subdirectories.
