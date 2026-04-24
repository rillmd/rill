# /repair — Note Quality Repair (Run after /inspect. Batch-processes the queue)

**Conduct ALL conversation with the user in the language defined by `.claude/rules/personal-language.md`** (or the user's input language if absent). The English instructions below are for skill clarity, not for output style. Exceptions: code blocks, slash commands, technical terms (Markdown, frontmatter, etc.).

> Workflow: `/inspect` → `/repair` → `/eval` (Inspect → Repair → Evaluate)

Reads files from `knowledge/.refresh-queue` and batch-updates frontmatter metadata (tags, mentions, type). `/inspect` diagnoses and queues files; `/repair` performs the repairs.

## Arguments

$ARGUMENTS — None (queue-driven, no arguments needed)

## Steps

### Step 1: Read Queue

1. Read `knowledge/.refresh-queue`
2. If empty or does not exist → display "Queue is empty. Run /inspect to diagnose and populate the queue." and exit
3. Verify each file path exists (Glob). Exclude and log any paths that no longer exist
4. Display the count of valid files

### Step 2: Build Shared Context

Build the following once (shared prefix for all agents):

1. Read `taxonomy.md`
2. Generate tag vocabulary in **YAML list format (name + desc)** from the "Topic Tags" table (ADR-046 D46-3)
3. Generate **deprecated tag → successor mapping** from the "Deprecated Tags" table
4. **Identify mega-tags (50+ uses)**: Bulk-extract tags from `knowledge/notes/*.md` frontmatter and tally usage counts (Bash one-liner: `for f in knowledge/notes/*.md; do awk ... done | sort | uniq -c | sort -rn`). List tag names with 50+ uses. If none, note "No mega-tags"
5. Read `knowledge/people/*.md` and compress into **one-line mapping format** (e.g., `alex-chen: Alex Chen (Alex, Chen)`)
6. Read `knowledge/orgs/*.md` and compress into **one-line mapping format**
7. Read `knowledge/projects/*.md` and compress into **one-line mapping format**
8. Generate an **entity ID list** (comma-separated) from all filenames (without extension) in knowledge/{people,orgs,projects}/

**Important: Do not read the full text of target files in the parent context. Pass only file paths to agents and let agents Read them internally**

### Step 3: Batch Splitting

1. Process all files in the queue (no upper limit)
2. Split into batches with a maximum of **30 files per agent** (can be increased up to 70 after confirming accuracy in production use)
3. Grouping files with the same issue (e.g., same deprecated tag) within a batch is efficient but not required
4. Launch **up to 4 agents in parallel**. If there are more than 4 batches, wait for previous batches to complete before launching the next

### Step 4: Launch Parallel Agents

Prompt structure for each agent:

```
Follow the instructions in .claude/commands/_distill/refresh-agent.md to process the following files.
First Read that template file to confirm the instructions, then Read the target files.

Target files:
{file_paths (newline-separated)}

Shared context:
### Tag vocabulary (YAML list format. Refer to desc when selecting tags. Tags not in this vocabulary are prohibited)
{taxonomy_yaml}

### Deprecated tag → successor mapping (replace deprecated tags with their successors)
{deprecated_tag_mapping}

### Mega-tag list (50+ uses. Prefer more specific sub-tags over these)
{mega_tag_list}

### People mapping
{people_mapping}

### Orgs mapping
{orgs_mapping}

### Projects mapping
{projects_mapping}

### Entity ID list
{entity_ids}
```

Launch with Agent tool using `run_in_background: true` and `model: "sonnet"`. The Sonnet routing was validated 2026-04-19 in the Tier 1 routing eval (3/3 PASS, 53% cost reduction vs Opus). Haiku was tested but failed (1/3 PASS — catastrophic field hallucination on multi-rule cases including invented tags and corrupted source/created fields), so do not downgrade further.

### Step 5: Aggregate Results + Deterministic Post-processing

After all agents complete:

1. Aggregate results from each agent:
   - success: list of successfully updated files
   - skipped: list of skipped files
   - failed: list of failed files

2. **Entity ID stripping (deterministic post-processing)**: Run `rill strip-entity-tags <file_paths ...>` via Bash on success files (ADR-046 D46-2). Safety net for cases where the LLM leaves entity IDs in tags

3. **New tag validation**: Check tags on success files. If any tags not in taxonomy.md were assigned, log a warning (do not auto-fix — will be caught by next /inspect run)

4. **Queue update**: Remove success + skipped files from `knowledge/.refresh-queue`. Leave failed files in the queue (will be reprocessed on next /repair run). If the queue becomes empty, clear the file contents

### Step 6: Report + Completion

Display a summary to the console:

```
## /repair Results

- Successfully processed: {success_count} files
- Skipped: {skipped_count} files
- Failed: {failed_count} files
- Remaining in queue: {remaining_count} files

### Changes Made
| File | tags | mentions | type |
|------|------|----------|------|
| {name} | {old} → {new} | +{added_ids} | {change} |
...

### Entity ID Stripping
- Removed entity IDs from tags in {count} files

### New Tag Warnings (tags not in taxonomy.md)
- {tag}: {count} files — will be detected and handled in next /inspect
```

Completion:

```bash
rill activity-log add repair "processed:{success}, skipped:{skipped}, failed:{failed}, remaining:{remaining}"
```

### Step 7: Metrics Recalculation

Immediately reflect the metadata fixes from /repair in eval/metrics/ (ADR-059).
Only perform lightweight Grep-based tallying, not the full /inspect measurement (sampling_precision, structural_reachability, etc.):

1. `mentions_coverage`: files in knowledge/notes/ containing `mentions:` / total files (excluding `mentions: []`)
2. `tag_coverage`: files in knowledge/notes/ containing `tags: [` / total files (excluding `tags: []`)
3. `tag_balance`: Grep all tag counts and calculate max_count, median_count, max_tag
4. `total_notes`: file count in knowledge/notes/

Write to `eval/metrics/YYYY-MM-DD.yaml` (today's date):
- If file exists, update only the 4 items above in the `static` section (preserve other static items and search section)
- If file does not exist, create new with `sources: [repair]`, the 4 items above only, others set to null

## Rules

- **Do not modify file body text**. Only update frontmatter
- **Do not change source, created, or related fields**
- **Creating new tags is prohibited**. Only use approved tags from taxonomy.md
- Idempotency: running multiple times on the same file produces the same result
- Error handling: failure on an individual file does not affect other files (leave in queue for next /repair run)
