# Note Refresh Agent

Sub-agent prompt for /refresh. Batch-updates frontmatter metadata of existing knowledge notes to the latest state.

## Files to Process
{file_paths}

**Read each file, understand its contents, and then update the frontmatter.**

## Update Rules

### tags
- Maximum 3. Topics only (do not include entity IDs)
- Reference each tag's desc and select tags that match the definition
- Re-select the most appropriate tags for the content, using existing tags as a reference
- **If deprecated tags are present**: Reference the "merge target" in the deprecated tags table and replace them with the appropriate successor tag
- **Prefer more specific subtags over megatags with more than 50 entries (see shared context)**
- **Creating new tags is forbidden**. Only use tags that exist in the tag vocabulary in the shared context

### mentions
- Cross-reference the people, orgs, projects entity lists with the body
- Extract IDs that are mentioned
- Format: mentions: [people/id1, orgs/id2, projects/id3] (type prefix required. ADR-053)
- IDs that exist in the entity list should go in mentions, not tags
- **If no matching entity**: Add `mentions: []` (marks as "reviewed, none applicable" to prevent re-queuing on the next /inspect)
- If the mentions field does not exist, also add `mentions: []`

### related
- **Preserve existing values. Do not change them**
- If the related field does not exist, do not add it

### type
- record (facts/data) / insight (realizations/interpretations) / reference (external citations)
- If the current type is non-standard (analysis, decision, etc.), change it to the appropriate standard type

## Notes
- **Do not modify the file body**. Only update the frontmatter
- **Do not modify the source field**
- **Do not modify the created field**
- **Do not modify the related field**
- Use the Edit tool to update frontmatter

## Shared Context
The following data is injected from the orchestrator's prompt (not included in this file):
- **Tag vocabulary**: YAML list format (name + desc). Reference desc when selecting tags
- **Deprecated tags table**: Mapping of old tag → merge target. When a deprecated tag is found, replace with the successor tag
- **Megatag list**: List of tag names with more than 50 entries. Prefer more specific subtags over these
- **People mapping**: id → name (aliases) in single-line format
- **Orgs mapping**: id → name (aliases) in single-line format
- **Projects mapping**: id → name (stage, tags) in single-line format
- **Entity ID list**: All entity IDs in type-prefixed format (`people/id`, `orgs/id`, `projects/id`). Used to decide whether entity IDs found in tags should be moved to mentions in type-prefixed format

## Output
Report each file classified into the following 3 categories:

### success (update succeeded)
- File path
- tags change (old → new) (also report current values when no change)
- mentions change (added IDs)
- type change (if any)

### skipped
- File path
- Reason (file does not exist, no frontmatter, etc.)

### failed
- File path
- Error details

Final summary line:
```
summary: success={n}, skipped={n}, failed={n}
```
