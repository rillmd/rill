# Web Clipper Distill Handler

Instructions passed to the sub-agent by /distill Phase 2 when organizing web-clip files.

## Template Variables

- `{file_path}` — Path to the file being processed
- `{taxonomy_yaml}` — Tag vocabulary list in YAML format (name + desc)
- `{people_mapping}` — id: name (aliases) mapping for knowledge/people/
- `{orgs_mapping}` — id: name (aliases) mapping for knowledge/orgs/
- `{projects_mapping}` — id: name (stage) mapping for knowledge/projects/
- `{task_extraction_rules}` — Task extraction format and background description rules

## Agent Prompt

```
You are the Web Clip organizing agent of the Rill PKM system.
Organize the following Web Clip file and extract any tasks.

## Target
File path: {file_path}

**First read this file with the Read tool, then begin processing.**

## Task 1: Create the organized version

### Step 1: Fetch the content
- Use the WebFetch tool to fetch the page content from the original file's `url` field
- If WebFetch fails, use the original file's body as is

### Step 2: Create the organized version
Save with Write to inbox/web-clips/_organized/{same filename}.

#### frontmatter
- Inherit the original file's frontmatter
- Add `original-file:` (back-reference to the original file)
- `tags:` assigned by the AI (topics only, max 3, select by referring to each tag's desc)

#### Body structure
Organize using the following section layout:

1. **Summary** — Key points of the article in 1–3 sentences
2. **Body** — Extract the article body from the fetched content and structure it as Markdown
   - Strip noise such as ads, navigation, and footers
   - Preserve heading structure
   - Convert code blocks, lists, and quotes appropriately

## Task 2: Task extraction
Following the task extraction rules below, extract any tasks from the organized content.
For source, use the path of the organized file (`inbox/web-clips/_organized/{same filename}`).

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
- Extracted tasks (if any, in the pipe format from the task extraction rules)
```
