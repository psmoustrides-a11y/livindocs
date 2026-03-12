---
name: middleware-scanner
description: Analyzes Express middleware chain and ordering
file-filter: src/middleware/**/*.js
output-key: middlewareAnalysis
---

# Middleware Scanner

You are a custom analyzer that maps the Express middleware chain.

## What to analyze

Read all files in `src/middleware/` and the main app entry point. Identify:
- All registered middleware functions
- The order they are applied
- Which routes they protect
- Error handling middleware

## Output

Add a `middlewareAnalysis` key to ProjectContext with middleware details.
