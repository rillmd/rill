---
gui:
  label: "/distill"
  hint: "Run knowledge extraction, task extraction, and entity detection"
  match:
    - "inbox/**/*.md"
    - "reports/**/*.md"
  arg: path
  order: 30
  mode: auto
---

# /distill — Unified Distillation Command

Batch-processes unprocessed inbox/journal/ and inbox/*/ files. Uses flat orchestrator pattern with external templates + parallel agent spawning (D48). Workspace distillation is handled by /close in the parent context (ADR-072).

## Arguments

$ARGUMENTS — one of the following:
- **Omitted**: Auto-detect unprocessed files and run the full pipeline
- **File path**: Run single-file distillation on the specified file (e.g., `reports/newsletter/2026-03-20.md`)
- **Directory path**: Run single-file distillation on all .md files in the directory

## Procedure

### Single-File Mode (with arguments)

When the argument is a file or directory, execute the following:

1. **Shared context preparation** (same as Step 1 of batch mode)
2. **Target determination**: Check if the argument is a `workspace/*/` directory
   - **If workspace directory** → Display "Workspace distillation is handled by /close. Use `/close {workspace-id}`" and exit (ADR-072)
   - **Otherwise** → Normal distillation mode (below)

#### Normal Distillation Mode

When a file or non-workspace directory is specified.

1. **Resolve target files**: If directory, target all .md files inside (exclude `_workspace.md`, `_summary.md`, `_organized/`). If `_organized/` has a file with the same name, prefer that one
2. **Knowledge extraction**: Launch an Agent per target file (`_distill/knowledge-agent.md` template + shared context injection. Max 5 parallel)
3. **Entity detection**: If newly created knowledge/notes/ mentions reference entities not in knowledge/people/ or knowledge/orgs/, auto-create them (Phase 2.5 equivalent)
4. **Task extraction**: For each target file, launch `_task/create-agent.md` as a sub-agent in `mode=extract` (parallel up to 5). Pass `source_path` = the target file, the shared context (taxonomy + entity mappings), and the list of knowledge/notes/ paths created in step 2 as hints. The sub-agent owns duplicate checking, substance writing, and file creation per `.claude/rules/rill-tasks.md`. It sets `status=draft` via `rill mkfile --field` (ADR-069)
5. **Post-processing**: Run `rill strip-entity-tags` on created knowledge/notes/, append new tags to taxonomy.md
6. **Summary display**: List of created knowledge, entity creation count, added tasks

※ Organized version creation (Phase 2) is not executed (target files are assumed already structured)
※ Profile update (Phase 4) and Plugin hooks (Phase 5) are not executed

### Batch Pipeline Mode (no arguments)

### Step 1: Shared Context Preparation (once in parent context)

- Read the "Topic Tags" table from `taxonomy.md` and generate **YAML list format (name + desc)** (exclude deprecated tags). Example: `- name: api-design\n    desc: API, interface, and protocol design`
  **Important: Tag vocabulary must always be passed in YAML list format**. Inline format like `tag(description)` is prohibited (ADR-046 D46-3)
- Generate **entity ID list** from all filenames (without extension) in knowledge/{people,orgs,projects}/ (used for entity stripping in post-processing)
- Read `knowledge/people/*.md` and compress into **extended one-line mapping format** (e.g., `people/jane-smith: Jane Smith | aliases: Jane,J. Smith | company: acme-corp`) — type prefix required (ADR-053). company is an orgs/ id. Aliases are comma-separated
- Read `knowledge/orgs/*.md` and compress into **one-line mapping format** (e.g., `orgs/acme-corp: Acme Corporation (Acme, Acme Inc)`)
- Read `knowledge/projects/*.md` and compress into **one-line mapping format** (e.g., `projects/phoenix: Project Phoenix (active, tags: infrastructure)`)
- Read `.claude/commands/_distill/task-extraction.md` and store contents in `{task_extraction_rules}` variable (single definition of task extraction rules)
- ※ Do not generate knowledge/notes/ filename list (each agent explores via Glob/Grep, D48-2)
- ※ Task duplicate checking is done by parent context in batch (scan existing tickets in `tasks/`)
- **Important: Do not read target file contents in parent context. Pass only file paths to agents, let agents Read internally**

### Step 2: Collect Processing Targets

Collect unprocessed files in 2 categories:

- **Root drop zone relocation** (runs first): Glob `inbox/*.md` (root-level Markdown files only, not inside subdirectories). For each match, excluding `inbox/CLAUDE.md`, move it to `inbox/sources/{filename}` using `git mv` when the file is tracked, otherwise `mv`. This enables users to drop arbitrary Markdown files directly into `inbox/` as a generic drop zone; relocated files are then picked up by the Phase 2 `sources/` glob below. If no root-level matches exist, skip silently.
- **Refresh queue check**: Read `knowledge/.refresh-queue`. If not empty, display "knowledge/.refresh-queue has N pending refreshes. Use /repair to process them" (not processed by /distill itself)
- **Phase 1**: Glob `inbox/journal/*.md` → compare with `inbox/journal/.processed` → unprocessed journals (exclude `_organized/` files and `.gitkeep`)
- **Phase 2**: Glob `inbox/{meetings,web-clips,tweets,think-outputs,sources}/*.md` → compare with each subdirectory's `.processed` → unprocessed inbox files (exclude `_organized/`, `.gitkeep`, `.processed`)

※ Workspace distillation is handled by /close in the parent context (ADR-072). Not processed in batch pipeline

Display target counts for all categories. If all 0, display "No unprocessed files" and exit.

### Step 3: Plugin Discovery

1. Read `plugins/.enabled` to get the list of enabled plugins. If the file does not exist or is empty, skip to Step 4 using `plugins/_default-distill.md` for all files
2. For each enabled plugin name, Read `plugins/{name}/plugin.md` frontmatter. Build `source-type` → plugin directory name mapping (e.g., `meeting → google-meet`, `tweet → twitter`, `web-clip → web-clipper`)
3. Resolve prompt path for each Phase 2 file:
   - **source-type determination**: Infer from inbox subdirectory name (`inbox/tweets/` → `tweet`, `inbox/web-clips/` → `web-clip`, `inbox/meetings/` → `meeting`). If subdirectory name doesn't match mapping, Read the original file's frontmatter `source-type`
   - Mapping match → `plugins/{name}/distill.md`
   - No match → `plugins/_default-distill.md`

### Step 4: Group 1 — Parallel Agent Launch

Phase 1/2 are mutually independent. Mix all files into a queue and launch **max 5 agents in parallel** in background (`run_in_background: true`). If more than 5, batch in groups of 5 and wait for previous batch to complete.

#### Phase 2 Pre-processing: Frontmatter Check
For each Phase 2 file, check frontmatter presence before Agent launch. If no frontmatter, auto-infer `created` and `source-type` from file creation date and directory name.

#### Agent Launch

Each agent's prompt composition (template files are **Read by the agent itself**. Do not Read in parent):

```
Follow the instructions in .claude/commands/_distill/{template-name}.md to process the following file.
First Read that template file to review instructions, then Read the target file.

Target: {file_path}

Shared context:
### Tag vocabulary (YAML list format. Refer to desc when selecting tags)
{taxonomy_yaml}

### People mapping
{people_mapping}

### Orgs mapping
{orgs_mapping}

### Projects mapping
{projects_mapping}

### Task extraction rules
{task_extraction_rules}
```

- **Phase 1**: `_distill/journal-agent.md` (1 file/Agent)
- **Phase 2**: Resolved plugin `distill.md` (1 file/Agent). Read the plugin's distill.md, extract the ``` block template from `## Agent Prompt` section → expand template variables (`{file_path}`, `{taxonomy_yaml}`, `{people_mapping}`, `{orgs_mapping}`, `{projects_mapping}`, `{task_extraction_rules}`) → pass expanded prompt directly to Agent's prompt

**Error handling**: If an agent reports an error, skip that file and proceed to the next. Skipped files are not appended to `.processed`.

### Step 5: Group 1 Result Collection

After all agents complete:
1. Batch-update `.processed` (do not append files that errored/skipped):
   - journal: Append filenames to `inbox/journal/.processed`
   - inbox/*: Append `filename:organized` to each subdirectory's `.processed`
2. **Entity ID stripping (deterministic post-processing)**: Run `rill strip-entity-tags <file-paths ...>` on created/updated knowledge/notes/ (ADR-046 D46-2)
3. Aggregate task candidates from all Phase 1 + Phase 2 agents. For each candidate, launch `_task/create-agent.md` as a sub-agent in `mode=extract` (max 5 parallel, `run_in_background: true`). Pass the candidate pipe line, the `source_path` already recorded in it, and the shared context (taxonomy_yaml, people/orgs/projects mappings). The sub-agent handles duplicate checking, substance-rule-compliant body writing, and file creation via `rill mkfile tasks --field 'status=draft' ...` (ADR-069). Legacy parent-side parsing of `| background:` / `| context:` fields and `Title::path` conversion is no longer performed here — substance writing is owned by the sub-agent per `.claude/rules/rill-tasks.md`
4. If new tags are reported, append to `taxonomy.md` (verify no conflict with deprecated tags)

### Step 6: Group 2 — Parallel Agent Launch

Phase 2.5 and Phase 3 are mutually independent, so execute in parallel.

- **Phase 2.5: Entity Auto-extraction** (execute directly in parent context):
  1. Read `participants:` and `tags:` from `inbox/*/_organized/` files processed in Group 1
  2. **String-match** each participant name against People mapping name/aliases (mapping is already loaded in context from Step 1. No Grep needed for known entities)
  3. Only Grep `knowledge/people/` for participants not found in mapping
  4. Participants not found → Auto-create new Person entity (minimal frontmatter + short description)
  5. String-match organizations from body/participants against Orgs mapping name/aliases (no Grep needed for known orgs)
  6. Orgs not found in mapping → Grep knowledge/orgs/ → if not found, auto-create new Org entity (id: kebab-case, aliases: name variants, relationship: context-inferred)
  7. If corresponding people/ company field is a string, update to orgs/ id
  8. Keep created entity IDs consistent with taxonomy.md tags
  9. Report creation results in summary

- **Phase 3: Knowledge Extraction** (`_distill/knowledge-agent.md`, launch Agent per organized file):
  1. Identify files with status `organized` from each subdirectory's `.processed` (exclude `extracted`, `skipped`)
  2. If no candidates, display "No knowledge extraction candidates" and skip
  3. Launch Agent per file (max 5 parallel, `run_in_background: true`)
  4. Inject shared context (taxonomy_yaml, people/orgs/projects mappings)

### Step 7: Group 2 Result Collection

1. Run `rill strip-entity-tags` on knowledge/notes/ created in Phase 3
2. Update `.processed` status to `extracted` (leave errored/skipped files as-is)
3. Append new tags to `taxonomy.md`

### Step 8: Group 3

- **Phase 4**: Update Interest Profile with `_distill/profile-agent.md`. Inject the following summary into prompt:
  ```
  Follow the instructions in .claude/commands/_distill/profile-agent.md to update the Interest Profile.
  First Read that template file to review instructions.

  ## Current /distill Processing Results Summary

  ### Newly created knowledge/notes/
  {list of filenames and tags from Phase 1-3}

  ### Newly created/updated projects/
  {updated projects/ filenames and change content}

  ### Extracted tasks
  {list of approved tasks}

  ### Newly created entities (people/, orgs/)
  {list of entities created in Phase 2.5}
  ```
  Skip if 0 files were processed in Phase 1-3.

- **Phase 5**: Read `plugins/.enabled`. For each enabled plugin, check if `plugins/{name}/hooks/post-distill.md` exists. If `.enabled` does not exist or is empty, skip Phase 5. For each found hook, launch Agent. Pass the following context:
  - **Created file list**: File paths of _organized/, knowledge/notes/, knowledge/people/, knowledge/orgs/ created in Phase 1-3
  - **mentions mapping**: person-id / org-id list extracted from mentions in created knowledge/notes/
  - **Added tasks**: List of approved new tasks
  - **Plugin path**: `plugins/{plugin-name}/`
  - **Failures are non-fatal**: Log and skip errors during hook execution

### Step 9: Pages Pending Update (Phase 2 of the pages-wiki-redesign — "new candidates" push)

After all Phases complete, before the final summary:

1. **Aggregate newly created knowledge/notes/ paths** from:
   - Phase 1 journal-agent outputs → `### Created knowledge files` section
   - Phase 3 knowledge-agent outputs → `### Created knowledge files` section
   - Plugin distill.md agent outputs (if the plugin follows the same `### Created knowledge files` convention)
2. **Exclude** refresh-agent output (refresh-agent is not part of /distill, but this guard exists so future integrations don't accidentally feed Evergreen updates into pending)
3. If the aggregated list is empty, skip this step
4. Write the aggregated paths to a temporary sources file (one per line, absolute or repo-relative paths both accepted by the CLI), then invoke:
   ```bash
   tmp=$(mktemp)
   printf '%s\n' "${created_files[@]}" > "$tmp"
   rill pages-pending-update --sources-file "$tmp" --origin distill
   rm -f "$tmp"
   ```
5. The CLI matches each new file's `mentions` (Layer 2) or `tags` (Layer 3 fallback, only for pages without mentions) against all `pages/*.md` and upserts entries into `pages/.pending`
6. **Do NOT pass `--force` blindly.** If the CLI prints `⚠ bulk update detected`, the aggregated list is likely contaminated with Evergreen updates or a migration slipped in — investigate rather than override

Design reference: `workspace/2026-04-15-pages-wiki-redesign/006-matching-strategy-revision.md`

### Step 10: Summary + Task Approval

After all Phases complete, display the following summary:
- **Phase 1**: Processed / skipped count, created file list
- **Phase 2**: Organized / skipped count, created file list
- **Phase 2.5**: Entity creation / skip count
- **Phase 3**: Extraction / skip count, created knowledge list
- **Phase 4**: Interest Profile update content (only if changes occurred)
- **Phase 5**: Hook execution results (plugin name, result summary)
- Task candidate list (Phase 1-2 total) — created as ticket files (/briefing will highlight new tasks)

## Rules

- **Never modify inbox/ original files** (read-only. Exception: auto-adding frontmatter is allowed)
- `inbox/journal/.processed` records filenames only (no path prefix. e.g., `2026-02-13-1921.md`)
- `inbox/{subdir}/.processed` uses `filename:status` format (e.g., `2026-02-16-meeting.md:organized`)
- Agent prompt templates (`.claude/commands/_distill/`) are **Read by agents themselves** (do not Read in parent context). Exception: `task-extraction.md` is Read by parent and injected as shared context data for child agents so they can return task *candidates*; actual ticket writing is delegated to the `_task/create-agent.md` sub-agent invoked by the orchestrator
- Plugin distill.md is Read by parent, template variables expanded, and injected inline into prompt
- Template variable names are unified: `{taxonomy_yaml}`, `{people_mapping}`, `{orgs_mapping}`, `{projects_mapping}`, `{task_extraction_rules}`, `{file_path}`
- **Error handling**: If an agent returns an error, skip that file and do not append to `.processed`. Include skip count in summary
- **zsh compatibility**: Refer to CLAUDE.md rule 26
