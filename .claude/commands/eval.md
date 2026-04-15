# /eval — Exploration Benchmark (monthly. Verify that note structure actually works in practice)

> Workflow: `/inspect` -> `/repair` -> `/eval` (inspect -> repair -> verify)

Quantitatively evaluate the search quality and efficiency of the knowledge base through Claude Code's natural exploration (ADR-050). See `eval/concept.md` for metric definitions.

## Arguments

$ARGUMENTS — Optional. Can be combined.

- `--reuse-deep YYYY-MM-DD` — Reuse Deep Path results from the specified date (`eval/results/YYYY-MM-DD-deep.yaml`)
- `--refresh-deep` — Force regeneration of Deep Path for all queries (high cost)
- `--baseline` — Also copy results to `eval/baseline.yaml`
- `--compare YYYY-MM-DD` — Compare with results from the specified date and report differences
- No arguments — Auto-detect the latest Deep Path. Incrementally update if new notes exist

## Concept

Generate the ground truth set with **Deep Path** (unconstrained exhaustive exploration), then process the same queries with **Claude Code's natural exploration**. If the discovery rate via metadata (metadata_contribution) is high, it proves that note structuring is effective.

While /inspect's structural reachability check (Phase 1.8) deterministically measures "whether metadata paths exist," /eval empirically measures "whether Claude Code can actually reach them."

## Procedure

### Phase 1: Deep Path Preparation

1. If `--refresh-deep` is specified -> go to Phase 1a (full regeneration)
2. If `--reuse-deep YYYY-MM-DD` is specified -> Read and load the corresponding file
3. If no arguments:
   a. Search `eval/results/` for the latest `*-deep.yaml` using Glob
   b. If found, detect new notes since that date with `git diff --name-only {date}..HEAD -- knowledge/notes/`
   c. If 0 new notes -> load as-is
   d. If new notes exist -> go to Phase 1b (incremental update)
   e. If no Deep Path results found -> go to Phase 1a (full regeneration)

#### Phase 1a: Deep Path Full Regeneration

Launch the Deep Path agent for all 20 queries in `eval/queries.yaml`. Execute in parallel batches of 5.

Agent prompt:
```
You are an exhaustive exploration agent for a Rill PKM.
Thoroughly explore for files related to the following queries, without concern for cost.

## Exploration Rules (relaxed constraints)
1. Freely explore the entire repository. No directory restrictions
2. Grep with multiple keywords, synonyms, and related terms (no limit on number of searches)
3. Read discovered files and follow leads from in-body links and source references (no need to follow frontmatter related: fields)
4. No Read limit. Read everything you judge to be relevant

## Ground Truth Target Files
Only include the following files in the ground truth set. Do not include other files even if discovered.
- knowledge/notes/ — Atomic knowledge (core eval target)
- knowledge/people/, orgs/, projects/ — Entity files
- knowledge/me.md — Interest Profile
- workspace/{id}/_workspace.md — MOC (as navigation hubs)
- docs/decisions/ — ADRs (when relevant to design-related queries)
- tasks.md — Task information
- SPEC.md, docs/SPEC-app.md, taxonomy.md — System definitions

## Files NOT to include in the ground truth set
- workspace/{id}/NNN-*.md — Temporary artifacts (distilled to knowledge/notes/ via /distill)
- workspace/{id}/_summary.md — Completion summaries (same reason)
- inbox/ — Source files (referenced by knowledge/notes/ via source:)
- reports/ — Output reports

## Important
- Maximize coverage. Minimize missed files
- For each discovered file, briefly explain why it is relevant

## Queries
{queries}

## Output Format (YAML)
For each query:
- query: "query text"
  found_files:
    - path: "file path"
      relevance: "high" | "medium" | "low"
      reason: "One-line explanation of relevance"
  search_log: "Detailed description of the exploration process"
```

Save results to `eval/results/YYYY-MM-DD-deep.yaml`.

#### Phase 1b: Incremental Update

Perform a differential check of new notes only, based on existing Deep Path results.

1. Retrieve the frontmatter (tags, mentions) and file names of new notes
2. For each new note, determine relevance to existing queries using frontmatter + file name only
3. Add notes determined to be relevant to the existing ground truth set
4. Save updated results as `eval/results/YYYY-MM-DD-deep.yaml`

### Phase 2: Claude Code Natural Exploration (7 queries)

1. Select 7 queries from `eval/queries.yaml` via stratified sampling:
   - entity: 2
   - factual: 2
   - synthesis: 2
   - exploratory: 1
   * Prioritize queries different from the previous run (rotation)

2. For each query, execute natural exploration via the Agent tool (7 agents in parallel)

Agent prompt:
```
You are an exploration agent for a Rill PKM.
Find files related to the following query.
Feel free to use Glob, Grep, and Read. No directory restrictions.

## Repository Structure
- knowledge/notes/ — Atomic knowledge (1 file = 1 atomic piece of knowledge)
- knowledge/people/, orgs/, projects/ — Entity files (search anchors + normalization hubs)
- workspace/{id}/ — Workspaces (_workspace.md is the MOC)
- tasks.md — Task list
- inbox/*/_organized/ — Organized sources

## Metadata Structure

### knowledge/notes/ frontmatter schema
- `type`: record (facts/data) / insight (observations/interpretations) / reference (external citations)
- `source`: Source file path (required; every note has one)
- `tags`: Topic classification tags. Max 3. Inline array. Vocabulary managed via taxonomy.md
- `mentions`: Array of typed entity references. Format: [people/id, orgs/id, projects/id]
- `related`: List of related note paths (navigation aid for humans; low utility for exploration)

### Entity files
- knowledge/people/{id}.md — Person entities. `aliases` field manages name variants (e.g., aliases: [Alex Chen, alex-chen, A. Chen]). `company` field references orgs/{id}
- knowledge/orgs/{id}.md — Organization entities. Has `aliases` field
- knowledge/projects/{id}.md — Project entities. `See Also` section contains navigation links to related workspaces and tasks

### File naming conventions
- knowledge/notes/ file names often use the entity ID as a prefix (e.g., acme-saas-pricing-model.md -> related to projects/acme-saas)
- File names are English kebab-case reflecting content

### Workspace structure
- workspace/{id}/_workspace.md is the MOC (Map of Contents). Has a curated list of topic-related notes in the "Related Files (MOC)" section
- Artifact files within workspaces (NNN-description.md) also contain related information
- `tags` and `mentions` fields classify topics

## Query
{query}

## Output Format
List of discovered files:
- path: "file path"
  found_via: "mentions-grep" | "tags-grep" | "filename-glob" | "content-grep" | "read-follow" | "related-follow" | "entity-file"
  reason: "One-line explanation of relevance"

Note: found_via classification criteria:
- `read-follow`: Discovered by following Markdown links or MOC entries found when Reading a file
- `related-follow`: Discovered by following the frontmatter `related:` field found when Reading a file

Search log:
  Record the list of tools used and search terms.
```

### Phase 3: Comparison & Scoring

Compare the Deep Path ground truth set with the natural exploration results. Compare by exact path match.

Scoring target: Only files in the Deep Path ground truth target set. If natural exploration discovers non-target files such as workspace/NNN-*.md, exclude them from precision/recall calculation (neither false positive nor false negative).

For each query:
- **precision**: Proportion of target files found by natural exploration that are also in Deep Path (high+medium+low)
- **recall**: Proportion of Deep Path (high+medium) files also found by natural exploration
- **metadata_contribution**: Proportion of files in natural exploration where `found_via` is mentions-grep, tags-grep, filename-glob, or entity-file (how much metadata/structure contributed to exploration)

Aggregate usage information from each agent:
- **avg_tokens_per_query**: Average token consumption per query
- **avg_tool_calls_per_query**: Average tool call count per query

### Phase 4: Save Results & Report

1. Save results to `eval/results/YYYY-MM-DD.yaml`
2. Write aggregate metrics to the `search` section of `eval/metrics/YYYY-MM-DD.yaml`:

```yaml
search:
  precision: 0.XX
  recall: 0.XX
  avg_tokens_per_query: NNNNN
  avg_tool_calls_per_query: N.N
  metadata_contribution: 0.XX
  queries_evaluated: 7
  sampling_method: stratified
```

If `eval/metrics/YYYY-MM-DD.yaml` already exists (i.e., /inspect was run the same day), preserve the `static` section and only add the `search` section.

3. Update `eval/metrics/latest.yaml`
4. If `--baseline` flag is present, also copy to `eval/baseline.yaml`
5. Display summary to console:

```
## Exploration Benchmark (YYYY-MM-DD)

### Score Summary
| Metric | Value | Interpretation |
|--------|-------|----------------|
| Precision | 0.XX | XX% of exploration results are correct notes |
| Recall | 0.XX | XX% of correct notes were discovered |
| Metadata Contribution | 0.XX | XX% of discoveries were via metadata |
| Avg Tokens/Query | NNNNN | Exploration cost per query |
| Avg Tool Calls/Query | N.N | Operations per query |

### Calibration (correlation with /inspect metrics)
| /inspect Metric | Value | /eval Metric | Value | Correlation |
|-----------------|-------|--------------|-------|-------------|
| structural_reachability | 0.XX | recall | 0.XX | {positive/inverse/none} |
| mentions_coverage | 0.XX | metadata_contribution | 0.XX | {positive/inverse/none} |

### Target Queries (stratified sampling, 7 queries)
| ID | Query | Type | Precision | Recall | Tokens | Metadata% |
|----|-------|------|-----------|--------|--------|-----------|
| Q1 | Alex Chen's... | entity | 0.XX | 0.XX | NNNNN | 0.XX |
| ... |

### Token Usage
| Path | Total Tokens | Tool Calls | Duration |
|------|-------------|------------|----------|
| Deep Path | N | N | Ns |
| Natural Exploration Total | N | N | Ns |
| **Total** | **N** | **N** | **Ns** |

### Improvement Recommendations
1. {recommendation}
```

6. When `--compare YYYY-MM-DD` is used, add a diff section:

```
### Previous Comparison (vs YYYY-MM-DD)
| Metric | Previous | Current | Change |
|--------|----------|---------|--------|
| Precision | 0.XX | 0.XX | +0.XX |
| Recall | 0.XX | 0.XX | +0.XX |
| Metadata Contribution | 0.XX | 0.XX | +0.XX |
| Avg Tokens/Query | NNNNN | NNNNN | -NNNNN |
```

### Phase 5: Analysis Report Generation

Analyze the Phase 4 scoring results and generate a report.

#### File Creation

Create the file with `rill mkfile` (to ensure timestamp accuracy):

```bash
rill mkfile reports/eval --type eval-report
```

Append the body text to the output path using Edit (frontmatter is already generated by `rill mkfile`).

#### Report Body Structure

1. **Executive Summary** (3-5 lines)
   - Overall scores (Precision / Recall / Metadata Contribution)
   - Quadrant determination using the diagnostic matrix from eval/concept.md (healthy / metadata-deficient / noisy / fundamental issue)
   - If a previous comparison exists, note the direction of change

2. **Performance Analysis by Query Type**
   - Organize average scores per type (entity / factual / synthesis / exploratory) in a table
   - Identify gap patterns between types (e.g., entity high / synthesis low -> metadata works for entity search but is insufficient for concept search)

3. **High-Score and Low-Score Query Analysis**
   - Highest scoring query: Why it succeeded (tag structure, mentions, filename prefix, etc.)
   - Lowest scoring query: Why it failed (reasons for 0% metadata_contribution, reasons for low recall)
   - Analyze "what was found" and "what was missed" with specific note paths

4. **Cross-Axis Calibration**
   - Cross-reference the static section (axes 1-2) and search section (axis 3) of `eval/metrics/YYYY-MM-DD.yaml`
   - Gap analysis between structural_reachability and recall
   - Gap analysis between mentions_coverage and metadata_contribution
   - Diagnosis based on the calibration table in eval/concept.md

5. **Improvement Recommendations** (3-5 items, in priority order)
   - For each recommendation, include "problem," "proposed solution," and "expected effect"
   - Organize into 3 categories: metadata improvement (tags/mentions enhancement, filename prefix), exploration strategy, and Deep Path definition
   - Do not recommend strengthening the related field (inconsistent with the Search-First paradigm; see eval/concept.md)

6. **Previous Comparison** (when using `--compare`, or when previous results exist for the same day)
   - Metrics diff table
   - Identify improved/degraded queries and analyze causes

#### Analysis Guidelines

- **Explain the "why," not just numbers**: Illustrate the mechanisms behind scores with concrete examples
- **Leverage missed_high_medium**: Examine the frontmatter of notes in Deep Path that were missed by natural exploration, and analyze "why they were not found" (missing tags, missing mentions, search terms not hitting content-grep, etc.)
- **Analyze found_via distribution**: Evaluate metadata effectiveness from the ratio of mentions-grep/tags-grep/filename-glob (metadata-based) vs content-grep/read-follow (content-based)
- **Compare against ideal model**: If any queries achieve Precision 1.0 / Recall 1.0, extract those conditions and examine applicability to other queries

## Rules

- **Do not modify file contents**. Evaluation only
- Deep Path must explore thoroughly (the quality of the ground truth set is the standard for everything)
- Provide natural exploration agents with Rill structural knowledge (equivalent to CLAUDE.md information)
- Save results as YAML in `eval/results/`, aggregate metrics in `eval/metrics/`
- Save analysis reports to `reports/eval/YYYY-MM-DD.md`

## Exit Processing

```bash
rill activity-log add "eval — precision:{precision}, recall:{recall}, metadata_contribution:{mc}, queries:{n}"
```
