---
type: system-doc
---

# Metadata Quality Evaluation Concept

A framework for quantitatively managing the quality of structural metadata (tags, mentions, type, source) in a Rill knowledge base.

> **Note**: The `related` field is excluded from evaluation. Claude Code's exploration follows a Search-First paradigm (Grep → Read → reason → next Grep), and following frontmatter related links is extremely rare. Deep Path does not instruct related traversal either. `related` is maintained as a human navigation aid but is not included in metadata quality evaluation.

## Why Measure Metadata Quality

Rill's notes are freely explored by Claude Code using Glob/Grep/Read. When metadata is rich, Claude Code can reach the right notes through frontmatter grep alone without reading the body text. This directly reduces token consumption and improves exploration accuracy.

**Metadata quality = the degree to which a note's relevance can be judged without reading its body text**

However, metadata "quantity" alone does not measure quality. Adding many tags increases coverage but also increases noise. Only by actually exploring with Claude Code can you verify whether structuring is working correctly.

## 3-Axis Evaluation Framework

### Axis 1: Static Metrics (/inspect Phase 1.7)

Measures the metadata completeness of individual notes via grep/glob. No ground truth required, virtually zero cost.

| Metric | Definition | Calculation | Target |
|--------|-----------|-------------|--------|
| **mentions_coverage** | Proportion of notes with 1+ mentions | notes containing `mentions:` / total notes | > 0.90 |
| **tag_coverage** | Proportion of notes with 1+ tags | notes containing `tags: [` / total notes (excluding `tags: []`) | > 0.95 |
| **orphan_rate** | Proportion with no mentions AND no entity prefix in filename | Notes unreachable from any entry point | < 0.05 |
| **tag_balance** | Usage count distribution across tags | max_count, median_count, max_tag | max < 50 |
| **sampling_precision** | /inspect sampling audit accuracy | PASS/MINOR/MAJOR counts and ratios | PASS rate > 70% |

**Entity prefix definition**: A filename that starts with any id from knowledge/people/, knowledge/orgs/, or knowledge/projects/. Example: `acme-saas-pricing-model.md` has the `acme-saas` prefix.

### Axis 2: Structural Reachability (/inspect Phase 1.8)

**Deterministically** checks whether metadata paths (mentions grep, tags grep, filename glob) exist for the Deep Path ground truth set. While Axis 1 measures "whether metadata is present," Axis 2 measures "whether the correct notes can be reached via that metadata."

| Metric | Definition | Target |
|--------|-----------|--------|
| **structural_reachability** | Proportion of ground truth notes reachable via 1+ paths | > 0.85 |
| **avg_path_count** | Average number of reachable paths per ground truth note (redundancy) | > 1.5 |
| **avg_noise_per_path** | Average number of notes hit per path (noise prediction) | < 30 |

**Prerequisite**: eval/results/YYYY-MM-DD-deep.yaml must exist. Skipped otherwise.

### Axis 3: Exploration Benchmark (/eval)

Run Claude Code without constraints and **empirically** measure whether it can efficiently discover the correct files. Verifies "actual exploration behavior" that Axes 1-2 cannot measure. Exploration scope is the entire repository (knowledge/, workspace/, docs/, etc.) with no directory restrictions.

| Metric | Definition |
|--------|-----------|
| **precision** | Proportion of files found via natural exploration that are also in the Deep Path set |
| **recall** | Proportion of Deep Path high+medium files also found via natural exploration |
| **avg_tokens_per_query** | Average token consumption per query |
| **avg_tool_calls_per_query** | Average tool calls per query |
| **metadata_contribution** | Proportion of files discovered via metadata/structure (frontmatter grep/glob, entity-file) |

## Tool Responsibilities

### /inspect — Note Health Check (Axis 1 + Axis 2)

**Mental model**: "Check whether notes are broken and properly structured"

- Axis 1: Static metrics (Phase 1.7)
- Axis 2: Structural reachability check (Phase 1.8, only when Deep Path results exist)
- Taxonomy health + sampling audit + file integrity
- Issue detection → .refresh-queue → repaired by /repair
- Cost: 30-60K tok
- Frequency: 1-2x per week, after /distill

### /eval — Exploration Benchmark (Axis 3)

**Mental model**: "Verify that Claude Code can actually find the right notes efficiently"

- Claude Code natural exploration (7 queries, stratified sampling) vs Deep Path
- Measures "actual exploration quality and efficiency" that /inspect cannot capture
- Cost: 130-160K tok
- Frequency: Monthly or after major changes

### Deep Path — Ground Truth Generation

- Unconstrained exhaustive exploration. Provides the reference set (ground truth) for all 3 axes
- Saved to `eval/results/YYYY-MM-DD-deep.yaml`
- Reusable via `--reuse-deep`. Efficient via incremental updates
- Full regeneration via `--refresh-deep` (400-500K tok)

### Ground Truth Scope

Files included in the ground truth set (persistent knowledge/structure):
- knowledge/notes/, people/, orgs/, projects/, me.md
- workspace/{id}/_workspace.md (as MOC)
- docs/decisions/, tasks.md, SPEC.md, taxonomy.md

Files NOT included in the ground truth set (temporary or pre-distillation intermediates):
- workspace/{id}/NNN-*.md, _summary.md — distilled to knowledge/notes/ via /distill
- inbox/ — source files (referenced by knowledge/notes/ via source:)
- reports/ — output reports

**Design rationale**: Workspace artifacts are atomized into knowledge/notes/ via /distill Phase 1.5. What /eval should measure is reachability of post-distillation persistent knowledge, not reachability of pre-distillation raw materials.

## Calibration

Verify correlations across the 3 axes to check whether static metrics actually correspond to search quality.

| Axis 1/2 Metric | Axis 3 Metric | Expected Correlation |
|-----------------|--------------|---------------------|
| mentions_coverage ↑ | metadata_contribution ↑ | More mentions → more metadata-driven discovery |
| structural_reachability ↑ | recall ↑ | If reachable paths exist → actually discovered |
| orphan_rate ↓ | recall ↑ | Fewer orphan notes → fewer missed notes |
| avg_noise_per_path ↓ | precision ↑ | Less noise → higher precision |
| tag_balance improved | avg_tokens_per_query ↓ | Right-sized tags → better exploration efficiency |

**When correlations break down**:
- Axis 1 good + Axis 2 good + Axis 3 recall low → Problem with Claude Code's exploration strategy (metadata is sufficient but not utilized)
- Axis 1 good + Axis 2 low → Metadata exists but lacks connection to queries (review tag granularity and entity linkages)
- Axis 1 low + Axis 2 low + Axis 3 recall low → Metadata completeness issue. Address with /repair

## Diagnostic Matrix

Diagnose metadata state using Recall × Precision in 4 quadrants.

```
                    Precision
                 High            Low
        ┌──────────────┬──────────────┐
  High  │  Healthy     │  Noisy       │
Recall  │  Metadata    │  Tags/       │
        │  working     │  mentions    │
        │  accurately  │  too broad   │
        ├──────────────┼──────────────┤
  Low   │  Metadata    │  Fundamental │
        │  insufficient│  design      │
        │  (many       │  problem     │
        │  orphans)    │              │
        └──────────────┴──────────────┘
```

| State | Recall | Precision | Action |
|-------|--------|-----------|--------|
| Healthy | > 0.70 | > 0.70 | Maintain |
| Metadata insufficient | < 0.60 | > 0.70 | Improve /distill assignment logic, /inspect .refresh-queue |
| Noisy | > 0.70 | < 0.60 | Tag splitting (/inspect proposals), refine mentions |
| Fundamental problem | < 0.60 | < 0.60 | Taxonomy redesign |

## Data Management

### Storage Structure

```
eval/
├── concept.md              # This document (metric definitions)
├── queries.yaml            # Evaluation query set (20 items, with IDs)
├── metrics/                # Metrics data (time-series accumulation)
│   └── YYYY-MM-DD.yaml     # Daily metrics (static + search)
├── results/                # /eval detailed results
│   ├── YYYY-MM-DD.yaml     # Per-query scores and analysis
│   └── YYYY-MM-DD-deep.yaml # Deep Path raw results (for --reuse-deep)
└── baseline.yaml           # Baseline (saved via --baseline)
```

Latest metrics retrieval: `ls eval/metrics/ | sort | tail -1` (`latest.yaml` is deprecated, ADR-059).

### Metrics File Format

```yaml
date: 2026-03-18
sources: [gc, eval]  # [gc] | [eval] | [gc, eval]

static:
  mentions_coverage: 0.93
  tag_coverage: 0.998
  orphan_rate: 0.068
  tag_balance:
    max_count: 60
    median_count: 16
    max_tag: "information-architecture"
  total_notes: 643
  sampling_precision:
    good: 13
    minor: 7
    major: 0
  structural_reachability: 0.85   # Phase 1.8 (null if skipped)
  avg_path_count: 1.8             # Phase 1.8 (null if skipped)
  avg_noise_per_path: 25.0        # Phase 1.8 (null if skipped)

search:
  precision: 0.XX
  recall: 0.XX
  avg_tokens_per_query: NNNNN
  avg_tool_calls_per_query: N.N
  metadata_contribution: 0.XX
  queries_evaluated: 7
  sampling_method: stratified
```

- /inspect writes the `static` section
- /eval writes the `search` section (merges with /inspect results if run on the same day)
- /repair also recalculates and writes the `static` section after completion (immediate reflection of fixes)

## Deprecated: Fast Path Agent

During the initial 3 runs of /eval (2026-03-17–18), Fast Path (constrained metadata-only agent exploration) was found to have the following issues and was deprecated (ADR-050 D50-5 revision):

1. Agent behavioral variance dominated Precision, making it unreliable as a metadata quality indicator
2. Non-deterministic — results varied across runs even with identical metadata
3. Was measuring "constrained agent exploration capability" rather than "metadata quality"

Replacement: Structural reachability check (deterministic, /inspect Phase 1.8) + Claude Code natural exploration (/eval Phase 2).
