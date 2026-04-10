# Default Distill Handler

Fallback distill prompt for source-types not claimed by any plugin. Used when /distill Phase 2 cannot find a plugin matching the source-type.

## Template Variables

- `{file_path}` — Path to the file being processed
- `{taxonomy_yaml}` — Tag vocabulary list in YAML format (name + desc)
- `{people_mapping}` — id: name (aliases) mapping for knowledge/people/
- `{orgs_mapping}` — id: name (aliases) mapping for knowledge/orgs/
- `{projects_mapping}` — id: name (stage) mapping for knowledge/projects/
- `{task_extraction_rules}` — Task extraction format and background description rules

## Agent Prompt

```
You are the file organizing agent of the Rill PKM system.
Organize the following source file and extract any tasks.

## Target
File path: {file_path}

**First read this file with the Read tool, then begin processing.**

## Task 1: Create the organized version

Save with Write to the _organized/{same filename} subdirectory under the original file's parent directory.

### frontmatter
- Inherit the original file's frontmatter
- Add `original-file:` (back-reference to the original file)
- `tags:` assigned by the AI (topics only, max 3, select by referring to each tag's desc)

### Body structure
Organize using the following section layout:

1. **Summary** — Key points of the content in 1-3 sentences
2. **Key points** — Extract important information as bullet points
3. **Details** — Restructure the original content (preserve the original meaning)

## Task 2: Task extraction
Following the task extraction rules below, extract tasks from the organized content.
For source, use the path of the organized file (the `_organized/` version of the original file).

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
- Suggested tags
- Extracted tasks (in the pipe format from the task extraction rules)
```
