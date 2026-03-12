# Documentation Quality Assurance

The difference between a useful doc tool and a toy is whether the output is accurate and trustworthy enough that developers actually rely on it. We build quality in at four layers.

## Layer 1: Deep analysis before generation

Never go straight from code to prose. The generation pipeline follows a strict sequence:

```
Source code -> Structural analysis -> Semantic analysis -> ProjectContext -> Generation -> Validation -> Output
```

**Structural analysis** (deterministic, no LLM): file tree, imports/exports, dependency graphs, framework config parsing, git stats. This is cheap and provably correct.

**Semantic analysis** (LLM-powered): reads code in context and produces structured findings — what each module does, how data flows, what patterns are in use, what design decisions are implicit. This is where Claude's reasoning adds value.

**ProjectContext assembly**: all analysis results are merged into a typed `ProjectContext` object. The generator works from this structured context, not raw code. This prevents the LLM from "drifting" during generation — it's answering specific questions from structured data, not free-associating about source files.

## Layer 2: Self-critique pass

After initial generation, every doc goes through a review pass:

```typescript
interface QualityReview {
  doc: string;                     // The generated document
  sourceFiles: string[];           // Files that were used as context
  claims: ClaimVerification[];     // Every factual claim extracted and verified
  coverageGaps: string[];          // Important code aspects the doc doesn't mention
  accuracyScore: number;           // 0-1 confidence that the doc is correct
  suggestions: string[];           // Specific improvements
}

interface ClaimVerification {
  claim: string;                   // e.g., "The API has 12 REST endpoints"
  sourceRef: string;               // File and line that supports this claim
  verified: boolean;               // Whether the claim checks out
  correction?: string;             // If not verified, what the truth is
}
```

The review pass asks three questions:
1. **Is anything wrong?** — Check factual claims against source code
2. **Is anything missing?** — Compare what the doc covers vs. what the codebase contains
3. **Is anything misleading?** — Look for oversimplifications that could lead a reader astray

If the review finds issues, the doc is regenerated with corrections. This costs ~30% more tokens but catches hallucinations before they reach the user.

## Layer 3: Programmatic verification

Some claims can be verified without an LLM:

- **Endpoint counts**: parse route files and count — if the doc says 12, there should be 12
- **Import relationships**: if the doc says "A depends on B", verify the import exists
- **File references**: if the doc mentions `src/auth/oauth.ts`, verify the file exists
- **Dependency versions**: if the doc mentions "uses Express 4.x", check package.json
- **Exported function signatures**: if the API doc shows a function signature, verify it matches

```typescript
interface ProgrammaticCheck {
  type: 'endpoint-count' | 'import-exists' | 'file-exists' | 'dep-version' | 'signature-match';
  claim: string;
  expected: string | number;
  actual: string | number;
  passed: boolean;
}
```

These checks run automatically after generation and before writing output. Failures trigger a targeted regeneration of the affected section.

## Layer 4: Reference anchoring

Every section in the generated docs includes source references — not just for the reader, but to keep the generation grounded.

```markdown
<!-- livindocs:start:auth-overview -->
## Authentication

The auth system uses JWT tokens with refresh token rotation. Login requests
hit `/api/auth/login` which validates credentials against the user store
and returns a token pair.

<!-- livindocs:refs:src/auth/login.ts:15-42,src/auth/tokens.ts:8-30 -->
<!-- livindocs:end:auth-overview -->
```

The `refs` comment is invisible in rendered Markdown but serves two purposes:
1. **Staleness detection** — when those file ranges change, we know this section needs review
2. **Regeneration targeting** — when updating, we re-read exactly those ranges to refresh the section

## Quality Profiles

Different teams have different quality needs. The config supports quality profiles:

```yaml
# .livindocs.yml
quality:
  profile: standard          # minimal | standard | thorough
  self_critique: true        # Enable the review pass (default: true for standard+)
  programmatic_checks: true  # Enable automated claim verification
  max_review_iterations: 2   # How many critique-fix cycles before accepting output
  reference_anchoring: true  # Embed source refs in generated docs
```

| Profile | Self-critique | Programmatic checks | Review iterations | Token cost multiplier |
|---|---|---|---|---|
| `minimal` | No | No | 0 | 1.0x |
| `standard` | Yes | Yes | 1 | ~1.3x |
| `thorough` | Yes | Yes | 2 | ~1.6x |

Default is `standard`. Use `minimal` for rapid iteration or cost-sensitive environments. Use `thorough` for production documentation that needs to be highly reliable.

## Doc Quality Scoring

After generation, every doc gets a quality score displayed to the user:

```
README.md — Quality: 92/100
   Accuracy: 95 (all claims verified)
   Coverage: 88 (missing: error handling patterns)
   Freshness: 100 (generated from current code)
   Refs: 14 source anchors

ARCHITECTURE.md — Quality: 74/100
   Accuracy: 80 (2 unverified claims about data flow)
   Coverage: 65 (missing: caching layer, queue system)
   Freshness: 100
   Refs: 8 source anchors
   Suggestion: Run with --thorough for better coverage of src/infra/
```

This gives users confidence in what they're getting and clear direction on how to improve it.
