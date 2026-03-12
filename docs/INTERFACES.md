# Key Interfaces

```typescript
// Core analysis result that all analyzers produce
interface AnalysisResult {
  type: 'architecture' | 'api-surface' | 'dependencies' | 'patterns' | 'git-history';
  confidence: number; // 0-1, how confident the analysis is
  data: Record<string, unknown>;
  metadata: {
    filesAnalyzed: number;
    languagesDetected: string[];
    frameworksDetected: string[];
    analyzedAt: string; // ISO timestamp
  };
}

// Project context built from all analyzers
interface ProjectContext {
  name: string;
  description: string;
  languages: LanguageInfo[];
  frameworks: FrameworkInfo[];
  entryPoints: string[];
  moduleGraph: ModuleNode[];
  apiSurface: ApiEndpoint[];
  dependencies: DependencyInfo[];
  patterns: PatternMatch[];
  gitHistory: GitAnalysis;
}

// Config loaded from .livindocs.yml
interface LivingDocsConfig {
  version: number;
  outputs: DocType[];
  docs_dir: string;
  include: string[];
  exclude: string[];
  project: {
    name: string;
    description: string;
    audience: string;
  };
  staleness: {
    enabled: boolean;
    threshold: 'strict' | 'moderate' | 'relaxed';
    ignore_patterns: string[];
  };
  templates_dir?: string;
}

// Staleness check result
interface StalenessReport {
  overall: 'current' | 'slightly-stale' | 'stale' | 'very-stale';
  sections: StalenessSection[];
  suggestions: string[];
  lastChecked: string;
}

interface StalenessSection {
  file: string;
  section: string;
  status: 'current' | 'possibly-stale' | 'stale';
  reason: string;
  relevantChanges: string[]; // commit SHAs that may have caused staleness
}

// Quality assurance
interface QualityReview {
  doc: string;
  docType: DocType;
  sourceFiles: string[];
  claims: ClaimVerification[];
  coverageGaps: string[];
  accuracyScore: number;           // 0-1
  coverageScore: number;           // 0-1
  overallScore: number;            // 0-100
  suggestions: string[];
  reviewIterations: number;        // How many critique-fix cycles were run
}

interface ClaimVerification {
  claim: string;                   // e.g., "The API has 12 REST endpoints"
  type: 'endpoint-count' | 'import-exists' | 'file-exists' | 'dep-version' | 'signature-match' | 'semantic';
  sourceRef: string;               // File and line that supports this claim
  verified: boolean;
  verificationMethod: 'programmatic' | 'llm-review';
  correction?: string;             // If not verified, what the truth is
}

interface QualityScore {
  overall: number;                 // 0-100
  accuracy: number;                // All claims verified?
  coverage: number;                // Important code aspects documented?
  freshness: number;               // Generated from current code?
  referenceCount: number;          // How many source anchors
  unverifiedClaims: number;        // Claims we couldn't verify
}

// Budget estimation and tracking
interface CostEstimate {
  passes: PassEstimate[];
  totalInputTokens: number;
  totalOutputTokens: number;
  cacheSavingsTokens: number;
  netInputTokens: number;
  netOutputTokens: number;
  estimatedCostUSD: number;
  model: string;
  qualityProfile: string;
  confidence: 'high' | 'medium' | 'low';
}

interface PassEstimate {
  name: string;
  type: 'structural' | 'analysis' | 'synthesis' | 'generation' | 'review';
  inputTokens: number;
  outputTokens: number;
  chunks: number;
  model: string;
  cached: boolean;
}

interface LiveBudgetTracker {
  budgetLimit: number;
  estimatedTotal: number;
  actualUsed: number;
  currentPass: string;
  passesCompleted: number;
  passesRemaining: number;
  projectedTotal: number;
  overBudgetRisk: boolean;
}

// Custom analyzer interface (for plugin system)
interface Analyzer {
  name: string;
  description: string;
  fileFilter(path: string): boolean;
  analyze(files: FileContext[]): Promise<AnalysisResult>;
}

interface FileContext {
  path: string;
  content: string;
  language: string;
  size: number;
  lastModified: string;
  gitBlame?: GitBlameInfo;
}

// Chunking strategy
interface ChunkingConfig {
  max_tokens_per_pass: number;     // Default: 150,000
  max_files_per_chunk: number;     // Default: 50
  priority: 'entry-points-first' | 'change-frequency' | 'alphabetical';
  summarization_threshold: number;  // Lines — files above this get pre-summarized
}

interface ChunkingPlan {
  totalFiles: number;
  totalEstimatedTokens: number;
  passes: ChunkPass[];
  warnings: string[];              // e.g., "Module src/core/ split into 3 sub-chunks"
}

interface ChunkPass {
  passNumber: number;
  type: 'structural' | 'module-analysis' | 'synthesis' | 'detail-generation';
  files: string[];
  estimatedTokens: number;
  dependencies: number[];          // Which passes must complete before this one
}

// Secret detection
interface SecretScanResult {
  file: string;
  line: number;
  pattern: string;                 // Which pattern matched (e.g., "AWS Access Key")
  redacted: boolean;
  severity: 'critical' | 'high' | 'medium';
}

// Cost tracking
interface CostReport {
  command: string;
  inputTokens: number;
  outputTokens: number;
  estimatedCostUSD: number;
  passBreakdown: PassCost[];
  cacheHits: number;               // Files served from cache instead of re-analyzed
  cacheSavingsTokens: number;      // Tokens saved by caching
}

interface PassCost {
  pass: string;
  model: string;
  inputTokens: number;
  outputTokens: number;
}

// GitHub integration
interface GitHubContext {
  prs: PullRequestSummary[];       // Recent PRs with descriptions
  issues: IssueSummary[];          // Referenced issues
  reviews: ReviewThread[];         // Architectural discussions in reviews
  available: boolean;              // Whether GitHub API is accessible
  fallbackReason?: string;         // Why we fell back to git-only
}

// Monorepo
interface MonorepoContext {
  isMonorepo: boolean;
  detectedBy: string;              // "pnpm-workspace.yaml", "package.json workspaces", etc.
  packages: PackageInfo[];
  sharedDependencies: string[];    // Deps used by multiple packages
  packageGraph: PackageDependency[]; // Inter-package dependency edges
}

interface PackageInfo {
  name: string;
  path: string;
  languages: string[];
  frameworks: string[];
  entryPoints: string[];
  dependencies: string[];          // Other packages in the monorepo this depends on
}
```
