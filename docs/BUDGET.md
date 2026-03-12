# Budget Estimation and Control

This tool calls the Claude API, which costs money. Every token matters. The budget system ensures users always know what they'll spend before they spend it, and never get surprised.

## Pre-execution Cost Estimation

Before any LLM calls, we estimate the full cost and show it to the user:

```
$ /docs generate all

Cost Estimate for: generate all
   Codebase: 847 files, ~180K lines, 4 languages
   Quality profile: standard

   Pass 1 — Structural scan:      ~2K tokens   (no LLM, free)
   Pass 2 — Module analysis:      ~85K input, ~20K output  (6 chunks)
   Pass 3 — Cross-module synth:   ~15K input, ~8K output
   Pass 4 — Doc generation:       ~40K input, ~25K output
   Pass 5 — Quality review:       ~30K input, ~10K output
   ---
   Total estimate:                ~170K input, ~63K output
   Cache savings:                 ~45K tokens (from previous run)
   Net cost:                      ~125K input, ~63K output
   Estimated cost:                ~$0.28 (using claude-sonnet-4-6)

   Proceed? (Y/n/adjust)
```

The `adjust` option lets users tweak before running:
- Switch to `minimal` quality to cut ~30%
- Exclude specific directories to reduce scope
- Use a cheaper model for some passes

## How Estimation Works

**Estimation method:**
1. Count files, measure total size in bytes
2. Apply a bytes-to-tokens ratio (empirically calibrated per language — TypeScript averages ~3.5 bytes/token, Python ~4.0)
3. Factor in chunking overhead (each chunk has prompt/system overhead of ~2K tokens)
4. Factor in quality profile multiplier
5. Check cache — subtract any files that haven't changed since last run
6. Apply model-specific pricing

Estimation confidence:
- **High**: small-medium repos where we can count everything precisely
- **Medium**: large repos where chunking makes estimation less precise
- **Low**: first run on a very large repo with no cache baseline

## Budget Enforcement

```yaml
# .livindocs.yml
budget:
  max_tokens_per_run: 200000       # Hard ceiling — abort if exceeded
  warn_threshold: 100000           # Prompt user for confirmation above this
  max_cost_usd: 1.00               # Dollar-based ceiling (alternative to token-based)
  auto_approve_below: 50000        # Skip confirmation prompt for small runs
```

**Enforcement behavior:**
1. Before execution: estimate and compare to budget
2. If estimate < `auto_approve_below`: proceed silently
3. If estimate > `warn_threshold` but < `max_tokens_per_run`: ask for confirmation
4. If estimate > `max_tokens_per_run`: refuse to proceed, suggest scope reduction
5. During execution: track actual tokens in real-time
6. If actuals exceed estimate by >20%: pause and ask user whether to continue

## Real-time Token Tracking

During a run, the user sees progress:
```
Analyzing modules... [Pass 2/5]
   Tokens: 42K / 125K estimated (34%)
   Chunks: 3/6 complete
   Cost so far: $0.09
```

## Post-execution Cost Report

After every run:
```
Generation complete!

Cost Report
   Total input tokens:   118,432
   Total output tokens:   58,291
   Estimated cost:        $0.26
   Cache savings:         42,100 tokens saved ($0.06 saved)

   Breakdown by pass:
   Structural scan:     0 tokens (deterministic)
   Module analysis:     78,200 input / 19,400 output
   Cross-module synth:  12,800 input / 7,200 output
   Doc generation:      18,100 input / 22,400 output
   Quality review:       9,332 input / 9,291 output

   vs. estimate: -5% (under estimate)
```

## Cost Optimization Strategies

**Automatic optimizations (always on):**
- Content-hash caching — never re-analyze unchanged files
- Structural analysis is deterministic (no LLM, zero token cost)
- Module summaries are cached and reused across passes
- Git diff-based staleness checks (compare hashes, not content)

**User-controlled optimizations:**
- `--budget 50k` — hard token limit per run
- `--quality minimal` — skip self-critique, ~30% cheaper
- `--scope src/api/` — only analyze/generate for a specific directory
- `--skip-review` — skip the quality review pass for a quick draft
- `--model haiku` — use a cheaper model (lower quality but much cheaper)
- `--incremental` — only regenerate stale sections (default for `update`)

**Smart model routing:**
Not all passes need the same model quality. Default routing:

| Pass | Default Model | Why |
|---|---|---|
| Structural scan | None (deterministic) | No LLM needed |
| Module analysis | Sonnet | Good balance of comprehension and cost |
| Cross-module synthesis | Sonnet (Opus optional) | Architecture reasoning benefits from stronger model |
| Doc generation | Sonnet | Prose quality is strong on Sonnet |
| Quality review | Sonnet | Claim verification doesn't need Opus |

Users who want maximum quality can set `synthesis: claude-opus-4-6` in config — this routes only the cross-module synthesis pass to Opus (where reasoning depth matters most) while keeping everything else on Sonnet. Typical cost increase: ~15-20% for meaningfully better architecture docs.

## Budget Presets

For users who don't want to tune individual settings:

```yaml
# .livindocs.yml
budget:
  preset: balanced   # frugal | balanced | quality-first
```

| Preset | Quality profile | Model | Auto-approve | Warn threshold | Description |
|---|---|---|---|---|---|
| `frugal` | minimal | sonnet | 20K | 50K | Fastest, cheapest. Good for iteration. |
| `balanced` | standard | sonnet | 50K | 150K | Default. Good quality at reasonable cost. |
| `quality-first` | thorough | sonnet+opus | 100K | 300K | Best output. Uses Opus for synthesis. |
