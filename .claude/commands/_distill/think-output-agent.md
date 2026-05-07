# Think-output Distillation Agent

/distill Phase 1b sub-agent prompt. Processes 1 think-output = 1 agent, executing 4 tasks inline.

think-outputs are AI-extracted at write time (in-flight capture during a Claude Code session). They are already structured (`# Title` + concise paragraphs), so unlike journal there is **no organize step** — proceed directly to knowledge extraction.

## Target File
{file_path}

**Read this file first before starting processing.**

## Task 1: Knowledge Extraction
Create atomic knowledge files in knowledge/notes/ using Write.
**Follow the extraction rules and Evergreen check in `.claude/commands/_distill/knowledge-agent.md`.**
Read knowledge-agent.md first to review the rules before extracting.

- **Add `# Title` at the beginning of the body** (a concise title describing the content) — required
- source: Use the original think-output path (`inbox/think-outputs/{filename}` — NOT `_organized/`). think-outputs is the documented exception to the `_organized/` Read priority rule in `rill-data-model.md` because the file is already structured at write time.

## Task 2: Task Extraction
Extract tasks following the "Task extraction rules" in the shared context.
Use `inbox/think-outputs/{filename}` (the original, not `_organized/`) as the source.
Include related knowledge/notes/ files from Task 1 in the context field as `Title::path` format.

## Task 3: Key Fact Accumulation (people/)
For people mentioned in the think-output, determine if there is new information to add to knowledge/people/{id}.md key facts.
- Read the target people/ file to check existing key facts
- Do not add semantically duplicate information (AI judgment)
- If adding, use Edit to append to the key facts section
- Guideline limit: 20 items. Report only if exceeded

## Task 4: Key Fact Accumulation (projects/)
For projects mentioned in the think-output, determine if there is new information to add to knowledge/projects/{id}.md key facts or Competitors.
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
- **Projects mapping**: id → name (stage, tags) in one-line format
- **Task extraction rules**: Task extraction format and background writing rules

## Read Budget
- Target file: Full Read — 1 time
- knowledge-agent.md template: Read — 1 time
- knowledge/notes/ existing files: **Frontmatter only** (up to first 10 lines for type/tags comparison during Evergreen check. Full Read prohibited)
- knowledge/people/, knowledge/projects/: Read only for key fact targets (max 3 files)

## Output
After processing, report the following **concisely** (do not return file contents):
- (No `_organized/` path — this category does not produce one)
- **### Created knowledge files** — list of newly created knowledge/notes/ paths (one per line, no commentary). Use this exact section heading so the orchestrator can aggregate. Include ONLY newly created files (not Evergreen-skipped ones).
- Skipped knowledge (existing filename + reason in one line)
- Extracted tasks (pipe format per task extraction rules)
- Updated people/ files (key fact additions, paths only)
- Updated projects/ files (key fact/Competitors additions, paths only)
- New tag names (if any)
