# Think-output Distillation Agent

/distill Phase 1b sub-agent prompt. Processes 1 think-output = 1 agent, executing 4 tasks inline.

think-outputs are AI-extracted at write time (in-flight capture during a Claude Code session). They are already structured (`# Title` + concise paragraphs), so unlike journal there is **no organize step** — proceed directly to knowledge extraction.

## Target File
{file_path}

**Read this file first before starting processing.**

## Language

Use the language specified by `output_language` (ISO 639-1) for narrative output fields — namely the knowledge note bodies (including the `# Title` heading) created in Task 1, the task candidate `Title` and `hint` fields produced in Task 2, and the new key fact entries appended in Tasks 3 and 4. Unlike journal-agent there is no `_organized/` output for this category (think-outputs are structured at write time). Internal keys stay verbatim English regardless of `output_language` because the orchestrator and downstream agents string-match them: the original `inbox/think-outputs/{filename}` path used as `source` (NOT `_organized/`), frontmatter field names (`created`, `type`, `source`, `tags`, `mentions`, `related`) and their values, knowledge/notes/ slugs and paths, the `type` enum (`record` / `insight` / `reference`), mentions entity IDs (`people/{id}`, `orgs/{id}`, `projects/{id}`), tag slugs, the report section heading `### Created knowledge files`, the task pipe field names (`slug:` / `mentions:` / `source:` / `hint:` / `depends-on:` / `blocks:`) and the `No tasks` sentinel produced by the Task extraction rules. Follow the inline `style_guide` block for vocabulary boundaries on the narrative fields.

## Task 1: Knowledge Extraction
Create atomic knowledge files in knowledge/notes/ using `rill mkfile` (never Write — LLMs must never write `created` by hand).
**Follow the extraction rules and Evergreen check in `.claude/commands/_distill/knowledge-agent.md`.**
Read knowledge-agent.md first to review the rules before extracting.

- **Add `# Title` at the beginning of the body** (a concise title describing the content) — required
- source: Use the original think-output path (`inbox/think-outputs/{filename}` — NOT `_organized/`). think-outputs is the documented exception to the `_organized/` Read priority rule in `rill-data-model.md` because the file is already structured at write time.

## Task 2: Task Extraction
Extract tasks following the "Task extraction rules" in the shared context.
Use `inbox/think-outputs/{filename}` (the original, not `_organized/`) as the source.

## Task 3: Key Fact Accumulation (people/)
For people mentioned in the think-output, determine if there is new information to add to knowledge/people/{id}.md key facts.
- Read the target people/ file to check existing key facts
- Do not add semantically duplicate information (AI judgment)
- If adding, use Edit to append to the key facts section
- Guideline limit: 20 items. Report only if exceeded

## Task 4: Key Fact Accumulation (projects/)
For projects mentioned in the think-output, determine if there is new information to add to projects/{id}/_project.md key facts or Competitors (ADR-080: not the legacy knowledge/projects/{id}.md).
- Target: Only projects listed in the shared context
- Read the target projects/ file to check existing content
- Update targets:
  - Key facts: Project progress, important decisions, numerical results
  - Competitors: New competitive info (new services, pricing changes, partnerships, exits)
  - Watch Keywords: New keywords to monitor
- Do not add semantically duplicate information (AI judgment)
- If adding, use Edit to append to the relevant section
- Key fact guideline limit: 20 items. Report only if exceeded

## Shared Context
The following data is injected from the orchestrator's prompt (not included in this file):
- **Tag vocabulary**: YAML list format (name + desc). Refer to desc when selecting tags
- **People mapping**: id → name | aliases | company in extended one-line format
- **Orgs mapping**: id → name (aliases) in one-line format
- **Projects mapping**: id → name (status, tags) in one-line format
- **Task extraction rules**: Task extraction format and background writing rules
- `output_language` (optional): ISO 639-1 language code for narrative output fields (e.g. `"ja"`, `"en"`); when omitted, default to English
- `style_guide` (optional): short vocabulary-boundary rules for narrative fields (see Language section); when omitted, write narrative fields in plain English

## Read Budget
- Target file: Full Read — 1 time
- knowledge-agent.md template: Read — 1 time
- knowledge/notes/ existing files: **Frontmatter only** (up to first 10 lines for type/tags comparison during Evergreen check. Full Read prohibited)
- knowledge/people/, projects/: Read only for key fact targets (max 3 files)

## Output
After processing, report the following **concisely** (do not return file contents):
- (No `_organized/` path — this category does not produce one)
- **### Created knowledge files** — list of newly created knowledge/notes/ paths (one per line, no commentary). Use this exact section heading so the orchestrator can aggregate. Include ONLY newly created files (not Evergreen-skipped ones).
- Skipped knowledge (existing filename + reason in one line)
- Extracted tasks (pipe format per task extraction rules)
- Updated people/ files (key fact additions, paths only)
- Updated projects/ files (key fact/Competitors additions, paths only)
- New tag names (if any)
