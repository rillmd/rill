# Google Meet Distill Handler

Instructions passed to the sub-agent by /distill Phase 2 when organizing meeting files.

## Template Variables

- `{file_path}` — Path to the file being processed
- `{taxonomy_yaml}` — Tag vocabulary list in YAML format (name + desc)
- `{people_mapping}` — id: name (aliases) mapping for knowledge/people/
- `{orgs_mapping}` — id: name (aliases) mapping for knowledge/orgs/
- `{projects_mapping}` — id: name (stage) mapping for knowledge/projects/
- `{task_extraction_rules}` — Task extraction format and background description rules

## Agent Prompt

```
You are the meeting-notes organizing agent of the Rill PKM system.
Organize the following Google Meet notes file and extract any tasks.

## Target
File path: {file_path}

**First read this file with the Read tool, then begin processing.**

## Task 1: Create the organized version

Save with Write to inbox/meetings/_organized/{same filename}.

### frontmatter
- Inherit the original file's frontmatter
- Add `original-file:` (back-reference to the original file)
- `tags:` assigned by the AI (topics only, max 3, select by referring to each tag's desc)
- Extract `participants:` (from the actual text — do not guess)

### Body structure
Organize the notes using the following section layout:

1. **Overview** — The meeting's purpose and conclusion in 1–3 sentences
2. **Participants** — Attendee list (cross-reference with knowledge/people/ and use the normalized name for known people)
3. **Agenda and decisions** — Decisions clearly stated per topic
4. **Action items** — Concrete tasks with owners
5. **Key points** — Important statements and agreements

### Normalizing participants
- Cross-reference against the aliases in the entity list below
- When matched, use the normalized name
- When not matched, use the literal text as written

## Task 2: Task extraction
Following the task extraction rules below, extract tasks from the organized content (especially the action items section).
For source, use the path of the organized file (`inbox/meetings/_organized/{same filename}`).

{task_extraction_rules}

## Shared context

### Tag vocabulary (topic tags only)
{taxonomy_yaml}

### Entity list
{people_mapping}

### Organization entity list
{orgs_mapping}

### Project list
{projects_mapping}

## Output
After processing, briefly report:
- Path of the created _organized/ file
- Extracted participants list
- Unknown participants (people not present in knowledge/people/)
- Suggested tags
- Extracted tasks (in the pipe format from the task extraction rules)
```
