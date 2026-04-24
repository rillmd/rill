# /inspect — Note Quality Inspection (weekly. Detect issues and queue them for repair)

**Conduct ALL conversation with the user in the language defined by `.claude/rules/personal-language.md`** (or the user's input language if absent). The English instructions below are for skill clarity, not for output style. Exceptions: code blocks, slash commands, technical terms (Markdown, frontmatter, etc.).

> Workflow: `/inspect` -> `/repair` -> `/eval` (Inspect -> Repair -> Verify)

Diagnoses taxonomy health, metadata accuracy, and file integrity, and reports any issues found. Performs diagnostics + minor queue operations (ADR-046 D46-8). Does not modify file body content. Files where sampling audits detect mismatches are appended to `.refresh-queue` and repaired by `/repair`.

## Arguments

$ARGUMENTS — None (no arguments required)

## Steps

### Phase 1: Taxonomy Health

1. Retrieve the list of approved tags from the "Topic Tags" table in `taxonomy.md`
2. Retrieve the list of deprecated tags from the "Deprecated Tags" table in `taxonomy.md`
3. Generate an entity ID list from all filenames (without extensions) in knowledge/{people,orgs,projects}/
4. Aggregate frontmatter from all knowledge/notes/*.md files. If the file count is large (100+), use the Agent tool for parallel processing:
   - Split the file list into batches of 50
   - Each agent uses Grep/Read to collect tags and mentions from frontmatter
   - Merge results in the parent context
5. Check the following:
   - **Tag frequency distribution**: Count usage for each tag. Warn about topic tags exceeding 50 uses as "split candidates"
   - **Unapproved tags**: Detect tags that are neither in the approved nor deprecated lists
   - **Deprecated tag usage**: Detect files still using deprecated tags (migration gaps)
   - **Entity contamination**: Detect files where entity IDs appear in tags (D46-2 gaps)
   - **Unused tags**: Detect approved tags with 0 usage count
   - **Low-usage tags (5 or fewer)**: Detect approved tags with 5 or fewer uses. **However, low usage does not mean unnecessary**. New topics start with 1 use. The criteria for deciding whether to merge are two axes: "time elapsed since creation date" and "semantic overlap with existing tags"

### Phase 1.5: Tag Scaling Proposals

Generate taxonomy improvement proposals based on Phase 1 aggregation results.

#### Metadata Accuracy Sampling Audit

Randomly sample 20 files from the entire knowledge/notes/ pool and use AI to verify whether the frontmatter metadata is correct. Files with mismatches are appended to `.refresh-queue` and auto-corrected during the next /distill Phase 0.5.

1. Randomly select 20 files from knowledge/notes/
2. Use the Agent tool to Read sample file contents and evaluate on the following **5 axes**:
   - **tags**: Do they match the content? (max 3, topic only, no entity ID contamination)
   - **mentions**: Are people/orgs/projects entity IDs mentioned in the body correctly listed in typed format (`people/id`, `orgs/id`, `projects/id`)? (check for omissions, excess, and untyped entries. ADR-053)
   - **related**: Are related notes actually relevant? Are there more appropriate related notes? (quick check via Glob/Grep)
   - **type**: Does the record / insight / reference classification match the content?
   - **source**: Does the referenced file exist and is it a valid origin for the content? (existence check only; path changes are suggested only)
3. Overall judgment for each file:
   - PASS: No issues across all axes
   - MINOR: Minor mismatches on 1-2 axes
   - MAJOR: Mismatches on 3+ axes, or a critical error
4. **Append files judged as MINOR or MAJOR to `.refresh-queue`** (metadata will be fully corrected during the next /distill Phase 0.5)
5. Include mismatch rates and specific mismatches in the report

Agent prompt:
```
You are a Rill PKM metadata accuracy audit agent.
Verify whether the frontmatter metadata of the following files matches their content on 5 axes.

## Target Files
{list of file paths (20 files)}

## Tag Vocabulary (YAML list format)
{name + desc list}

## Entity Mapping
### People
{id -> name (aliases) one-line format}

### Orgs
{id -> name (aliases) one-line format}

### Projects
{id -> name (stage, tags) one-line format}

## Evaluation Criteria
Read each file and verify on the following 5 axes:

### 1. tags
- Max 3, topic only (entity IDs go in mentions)
- Refer to the tag vocabulary desc and check whether the most appropriate tags were chosen for the content
- Judgment: PASS=appropriate / MINOR=room for improvement / MAJOR=inappropriate

### 2. mentions
- Are people, organizations, and projects mentioned in the body correctly listed using entity IDs from the entity mapping?
- Detect omissions (mentioned in body but missing from mentions) and excess (in mentions but not mentioned in body)
- Judgment: PASS=appropriate / MINOR=omissions or excess / MAJOR=significantly inaccurate

### 3. related
- Are the current related notes actually relevant in content?
- Do a quick check via Glob/Grep and suggest better related note candidates if any
- If related is not set, briefly check whether there are notes that clearly should be related
- Judgment: PASS=appropriate / MINOR=room for improvement / MAJOR=unrelated notes included

### 4. type
- Does the record (facts/data) / insight (observations/interpretations) / reference (external citations) classification match the content?
- Check for non-standard types (analysis, decision, etc.) that remain
- Judgment: PASS=appropriate / MAJOR=inappropriate

### 5. source
- Does the file pointed to by the source field exist? (check via Glob)
- Judgment: PASS=exists / MAJOR=does not exist or not set

## Overall Judgment
- PASS: No issues across all axes
- MINOR: Minor mismatches on 1-2 axes
- MAJOR: Mismatches on 3+ axes, or a critical error (type is completely wrong, source is broken, etc.)

## Output Format
For each file:
- filename — overall judgment (PASS/MINOR/MAJOR)
  - tags: {judgment} current:[{tags}] -> recommended:[{recommended}] (only on mismatch)
  - mentions: {judgment} current:[{mentions}] -> recommended:[{recommended}] (only on mismatch)
  - related: {judgment} improvement suggestion: (only on mismatch)
  - type: {judgment} current:{type} -> recommended:{recommended} (only on mismatch)
  - source: {judgment} (only if broken)

Summary at the end:
- Overall: PASS {n} / MINOR {n} / MAJOR {n} (estimated accuracy: {pass_rate}%)
- Per-axis accuracy: tags {rate}% / mentions {rate}% / related {rate}% / type {rate}% / source {rate}%
```

#### Split Execution (tags exceeding 50 uses)

If there are tags exceeding 50 uses, generate subcategories and add them to taxonomy.md using the following steps:

1. Randomly sample up to 20 files that have the target tag
2. Use the Agent tool to Read sample file contents and perform theme clustering
3. Finalize 2-4 subcategories. For each subcategory:
   - Tag name (kebab-case)
   - Description (desc)
   - Estimated number of matching files from the sample
4. **Add the new tags to the "Topic Tags" table in taxonomy.md via Edit**
5. **Append all files with the target tag to `.refresh-queue`** (/repair will execute reassignment to the new subtags)
6. Include the results in the report

Agent prompt:
```
You are a Rill PKM taxonomy analysis agent.
All of the following files have the "{tag}" tag assigned.
Read their contents and classify them into 2-4 subcategories by theme.

## Target Files
{list of file paths (up to 20 files)}

## Current Tag Definition
{tag}: {desc}

## Output Format
For each subcategory:
- Proposed tag name (kebab-case)
- Description (one line)
- List of matching sample filenames
- Estimated match rate (percentage within sample)
```

#### Merge Execution (low-usage tags)

**Be cautious about what to merge**. Low usage does not mean unnecessary. New topics start with 1 use, so merging too aggressively creates an infinite loop where /distill recreates the same tag.

Conditions for executing a merge (**all must be met**):
1. Usage count of 3 or fewer
2. The tag has been in taxonomy.md for **30+ days** (give new tags time to grow)
3. **Semantically overlaps** with another approved tag (judge by comparing desc)

If tags meet the conditions:
1. Check the tags of files with the target tag and identify frequently co-occurring tags
2. Determine the most appropriate merge target tag
3. **Move to the "Deprecated Tags" table in taxonomy.md** (Edit to remove from "Topic Tags" and add to "Deprecated Tags" in `-> {target}` format)
4. **Append files with the target tag to `.refresh-queue`** (/repair will execute reassignment to the target tag)
5. Include the results in the report
6. Low-usage tags that do not meet the conditions are noted as "growing tags" for continued observation

### Phase 1.7: Static Metrics Calculation

Calculate static metadata quality metrics using Phase 1 aggregation data (see eval/concept.md).

1. **mentions_coverage**: Proportion of notes in knowledge/notes/ that have 1+ entities in the `mentions:` field. `mentions: []` (empty array) counts as "none"
2. **tag_coverage**: Proportion of notes in knowledge/notes/ that have 1+ tags in the `tags:` field. `tags: []` (empty array) counts as "none"
3. **orphan_rate**: Proportion of notes with no mentions AND whose filename does not start with any id from knowledge/people/, orgs/, or projects/. These notes are hard to reach via entity-based reverse lookup. **Reuse the entity ID list generated in Phase 1 Step 3** for filename prefix matching
4. **tag_balance**: Calculate max_count, median_count, and max_tag from the per-tag usage counts aggregated in Phase 1

Save the calculation results along with the Phase 1.5 sampling_precision results to `eval/metrics/YYYY-MM-DD.yaml`:

```yaml
date: YYYY-MM-DD
sources: [gc]

static:
  mentions_coverage: 0.XX
  tag_coverage: 0.XX
  orphan_rate: 0.XX
  tag_balance:
    max_count: N
    median_count: N
    max_tag: "tag-name"
  total_notes: N
  sampling_precision:
    good: N
    minor: N
    major: N
  structural_reachability: 0.XX    # Phase 1.8 (null if skipped)
  avg_path_count: N.N              # Phase 1.8 (null if skipped)
  avg_noise_per_path: N.N          # Phase 1.8 (null if skipped)

search: null
```

Do not write to `eval/metrics/latest.yaml` (deprecated, ADR-059). Retrieve the latest metrics with `ls eval/metrics/ | sort | tail -1`.

If an existing `eval/metrics/YYYY-MM-DD.yaml` exists (same-day /eval already ran), preserve the `search` section and update only the `static` section.

### Phase 1.8: Structural Reachability Check (only if Deep Path results exist)

Use the latest Deep Path results from eval/results/ to deterministically check metadata paths to ground-truth notes (ADR-050 D50-8).

1. Glob search `eval/results/` for the latest `*-deep.yaml`. If not found, skip Phase 1.8 and display "No Deep Path results found — run `/eval --refresh-deep`" in the report
2. Load the Deep Path results and extract found_notes (relevance: high + medium) from all queries as the ground-truth set
3. For each query, extract entity IDs and topic keywords from the query text:
   - Match against the entity ID list from Phase 1 Step 3
   - Match against approved tags from taxonomy.md
4. For each ground-truth note, check reachability via the following 3 paths (grep/glob only, no Read needed):
   a. **mentions path**: Does `grep "mentions:.*{type}/{entity-id}" knowledge/notes/{filename}` match?
   b. **tags path**: Does `grep "tags:.*{tag}" knowledge/notes/{filename}` match?
   c. **filename path**: Does the note's filename start with the query's entity ID?
5. For each path that matches, also record the hit count when grep/glob-ing the entire `knowledge/notes/` with that path (noise estimate)
6. Calculate the following metrics:
   - **structural_reachability**: Proportion of ground-truth notes reachable via 1+ paths (target > 0.85)
   - **avg_path_count**: Average number of reachable paths per ground-truth note (target > 1.5)
   - **avg_noise_per_path**: Average number of note hits per reachable path (target < 30)
7. Append unreachable notes (0 paths) to `knowledge/.refresh-queue` (only if not already in the queue)
8. Write the calculation results to the `static` section of `eval/metrics/YYYY-MM-DD.yaml` saved in Phase 1.7 (`structural_reachability`, `avg_path_count`, `avg_noise_per_path`). If Phase 1.8 was skipped, leave as `null`

### Phase 2: File Integrity

Check the following against knowledge/notes/*.md (can be run concurrently with Phase 1 aggregation):

1. **Required frontmatter fields**: Detect missing `created`, `type`, `source`
2. **Source reference check**: Verify that the file pointed to by the `source` field exists
3. **Mentions reference check**: For each value in `mentions` (`{type}/{id}` format. ADR-053), verify that the corresponding `knowledge/{type}/{id}.md` exists. Also detect bare IDs without type prefixes

### Phase 2.5: .refresh-queue Update

Use Phase 1-2 aggregation data and Phase 1.5 tag accuracy audit results to append files needing refresh to `knowledge/.refresh-queue`.

1. Collect file paths matching the following **deterministic** conditions (no AI judgment needed):
   - `tags: []` (empty array)
   - `tags` has only 1 tag and that tag exceeds 50 uses in Phase 1 aggregation
   - `mentions` field does not exist
   - `type` is not one of `record` / `insight` / `reference`
   - `tags` contains a deprecated tag (migration gap)
2. Add files judged as **MINOR or MAJOR** in the Phase 1.5 metadata accuracy sampling audit
3. Read `knowledge/.refresh-queue` if it exists to get existing entries (empty list if it doesn't exist)
4. Append only paths that do not duplicate existing entries (one file path per line)
5. Include the number of appended entries in the report

### Phase 3: Report Output

Display a summary to the console:

```
## Metadata Quality Metrics

| Metric | Value | Target | Status |
|--------|-------|--------|--------|
| mentions_coverage | 0.XX | > 0.90 | ✓/⚠ |
| tag_coverage | 0.XX | > 0.95 | ✓/⚠ |
| orphan_rate | 0.XX | < 0.05 | ✓/⚠ |
| tag_balance (max) | N ({tag}) | < 50 | ✓/⚠ |
| structural_reachability | 0.XX | > 0.85 | ✓/⚠ |
| avg_path_count | N.N | > 1.5 | ✓/⚠ |
| avg_noise_per_path | N.N | < 30 | ✓/⚠ |

## Taxonomy Health

### Tag Distribution Top 10
1. {tag}: {count} files
...

### Metadata Accuracy Sampling Audit (20 files)
- Overall accuracy: {accuracy}% (PASS {n} / MINOR {n} / MAJOR {n})
- Per-axis accuracy: tags {rate}% / mentions {rate}% / related {rate}% / type {rate}% / source {rate}%
- Mismatched files:
  - {file} — MINOR tags:[{current}]->[{recommended}], mentions:omission[{ids}]
  - {file} — MAJOR type:{current}->{recommended}, source:broken

### Split Candidates (50+ uses)
- {tag}: {count} files

### Split Execution
#### {tag} ({count} files) -> new tags added to taxonomy.md:
1. **{proposed-tag}** — {desc} (estimated {n} files, {rate}%)
2. **{proposed-tag}** — {desc} (estimated {n} files, {rate}%)
-> {n} matching files appended to .refresh-queue

### Unapproved Tags
- {tag} ({count} files) — merge candidate: {suggestion}

### Deprecated Tag Usage (migration gaps)
- {tag}: {count} files

### Entity Contamination
- {count} files have entity IDs mixed into tags

### Unused Tags (0 files)
- {tag}, {tag}, ...

### Low-Usage Tags (5 or fewer)
- {tag}: {count} files (added: {date})

### Merge Execution (3 or fewer + 30+ days old + semantic overlap)
- **{tag}** ({count} files) -> merged into {target-tag} (moved to deprecated table in taxonomy.md, matching files appended to .refresh-queue)

### Growing Tags (under observation)
- {tag}: {count} files (added: {date}, {n} days until merge consideration)

## Structural Reachability (Deep Path based)

### Unreachable Notes (0 paths)
| Query | Note | Cause |
|-------|------|-------|
| Q2 | xxx.md | No match on mentions/tags/filename |

### Single-Path Notes (1 path only, no redundancy)
| Query | Note | Only Path |
|-------|------|-----------|
| Q3 | yyy.md | filename only |

-> Unreachable notes appended to .refresh-queue

## File Integrity

### Missing required fields: {count} files
### Broken source references: {count} files
### Broken mentions references: {count} files

## Refresh Queue

### .refresh-queue appended: {count} files (cumulative: {total} files)
```

If no issues are found, display "Health check complete. No issues found."

## Rules

- **Do not modify file body content**. However, the following are exceptions that are executed automatically:
  - Appending to `knowledge/.refresh-queue` (queue operation. Permitted by ADR-046 D46-8)
  - Tag splitting (adding new tags) and merging (moving to deprecated table) in `taxonomy.md` (ADR-058)
- For unapproved tags, add a mapping to the closest approved tag in the deprecated tags table of taxonomy.md, and append the affected files to `.refresh-queue`
- Files with entity contamination are appended to `.refresh-queue` (/repair will execute the tags -> mentions migration)
- When processing a large number of files, use the Agent tool for parallelization to conserve context

## Post-Processing

After displaying the report, execute the following:

```bash
rill activity-log add "inspect — tags:{total_tags_count}, issues:{total_issues_count}, queued:{queued_count}"
```
