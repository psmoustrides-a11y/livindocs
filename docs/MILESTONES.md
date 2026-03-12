# Milestone Plan

## M1: Foundation (v0.1)
- [ ] Plugin scaffold (plugin.json, commands wired up)
- [ ] `/docs init` — config wizard with `.livindocs.yml` generation
- [ ] File scanner with include/exclude glob patterns
- [ ] Language/framework detection heuristic
- [ ] Secret scanner — pattern-based detection, redaction engine, default exclusion list
- [ ] `/docs generate readme` — README generation only
- [ ] Pre-execution cost estimator (bytes-to-tokens ratio, pass breakdown, user confirmation prompt)
- [ ] Real-time token tracker during execution
- [ ] Post-execution cost report
- [ ] Budget enforcement (warn threshold, hard ceiling, auto-approve-below)
- [ ] Budget presets (frugal, balanced, quality-first)
- [ ] Programmatic claim verification (file exists, import exists, endpoint counts)
- [ ] Reference anchoring in generated output (source refs as HTML comments)
- [ ] Quality scoring output (accuracy, coverage, freshness)
- [ ] Basic test suite with 2 fixture projects (express-api, react-app)

## M2: Architecture Docs + Caching + Quality (v0.2)
- [ ] Architecture analyzer (module graph, entry points, data flow)
- [ ] `/docs generate architecture` — ARCHITECTURE.md
- [ ] Dependency analyzer
- [ ] Mermaid diagram generation (module graph, data flow, API routes)
- [ ] `.livindocs/cache/` — content-hash-based caching system
- [ ] Cache invalidation on file changes
- [ ] Chunking engine — hierarchical multi-pass strategy for large repos
- [ ] File/module summarizer for oversized inputs
- [ ] Self-critique review pass (accuracy, coverage, misleading content detection)
- [ ] Claim extraction and verification pipeline
- [ ] Quality profiles (minimal, standard, thorough) with config support
- [ ] Smart model routing (different models for different passes)

## M3: Staleness Detection (v0.3)
- [ ] Semantic diff engine (meaning-based, not just timestamp)
- [ ] `/docs check` command with severity levels
- [ ] `/docs update` command with incremental regeneration
- [ ] Marker-based section management (non-destructive updates)
- [ ] Staleness baseline snapshots in cache
- [ ] `--dry-run` flag for update (show diff without writing)

## M4: GitHub Integration + ADRs (v0.4)
- [ ] GitHub API integration (PR descriptions, issues, review threads)
- [ ] GitHub Enterprise support (configurable base URL)
- [ ] Graceful fallback to git-only when no token available
- [ ] GitHub response caching with TTL
- [ ] Git history analyzer (refactoring patterns, dep changes)
- [ ] ADR generator from commit + PR history
- [ ] Onboarding guide generator
- [ ] `/docs explain` interactive mode

## M5: Monorepo + Custom Analyzers (v0.5)
- [ ] Monorepo detection (workspaces, pnpm, lerna, cargo, go)
- [ ] Per-package doc generation
- [ ] Unified root-level architecture doc with package relationship diagram
- [ ] Cross-reference linking between package docs
- [ ] Custom analyzer plugin system (`.livindocs/analyzers/`)
- [ ] Custom generator plugin system
- [ ] Analyzer SDK package (`@livindocs/sdk`)

## M6: API Docs + CI (v0.6)
- [ ] API surface analyzer (REST endpoints, GraphQL schemas, exported functions)
- [ ] API reference generator with usage examples
- [ ] Coverage reporter (% of codebase documented)
- [ ] CI integration — GitHub Actions action (`livindocs/action@v1`)
- [ ] CI integration — GitLab CI template
- [ ] CI modes: `check` (gate PRs), `update --dry-run` (PR comments), `update --commit` (auto-maintain)

## M7: Community Release (v1.0)
- [ ] Documentation for the documentation tool (using livindocs itself — meta!)
- [ ] Plugin marketplace submission
- [ ] Contributor guide (CONTRIBUTING.md)
- [ ] Template customization docs
- [ ] Performance benchmarks for repos of various sizes
- [ ] Versioned documentation support (git-tag/branch strategy)
- [ ] Opt-in anonymous telemetry
- [ ] Model selection config (Sonnet for analysis, optional Opus for synthesis)
- [ ] `--budget` flag for cost-conscious users
