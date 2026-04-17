# Data Model Rules — Rill

Common frontmatter schema, reference conventions, and link rules for all Rill files. Directory-specific rules are in `inbox.md` / `knowledge.md` / `workspace.md` / `tasks.md` / `outputs.md`.

## Common Frontmatter Schema

### Required Fields
- `created`: Required. ISO 8601 format (e.g., `2026-04-07T18:30+09:00`). **LLMs must never write this directly** (auto-assigned via `rill mkfile`)
- `type`: Required. File type identifier (`record` / `insight` / `reference` / `task` / `workspace` / `page` / `person` / `org` / `project` / `daily-note` / `interest-profile`, etc.)

### Optional Fields
- `source`: Source file path (relative to repo root, no leading `/`). Required for knowledge/notes/
- `tags`: AI-assigned. Max 3. Inline array. Topic discrimination only (entities go in `mentions`)
- `mentions`: Typed entity reference array. Format `[people/id, orgs/id, projects/id]` (ADR-053). Usable in all file types (ADR-066)
- `related`: Array of related file paths
- `updated`: Auto-set (used in pages/)

## Tag Management

- When assigning tags, Read `taxonomy.md` to check existing tags. Add new tags if none match
- When passing tag vocabulary to sub-agents, use **YAML list format (name + desc)**. Inline format like `tag(description)` is prohibited (ADR-046 D46-3)
- Tags are kebab-case, English
- Using entity IDs as tags is prohibited (`acme-saas` is not a tag — use `mentions: [projects/acme-saas]`)
- Deprecated tags are listed in taxonomy.md's "Deprecated Tags" table. If found, remove via Edit

## Reference / Link Rules

- **In-body links**: Use standard Markdown `[text](path)`. Wiki links `[[]]` are not used
- **Backtick-only ID references are prohibited**: No `` `task-xxx` `` style references — always use `[display name](tasks/xxx/_task.md)` links (ADR-064, ADR-076)
- **Frontmatter fields** (source, related, mentions, etc.) are structured data — do not use Markdown links. Keep as plain path strings

## File Creation Rules

- **Use `rill mkfile` for new file creation** (ADR-060). Ensures timestamp accuracy
- LLMs must never write `created` values directly
- See `claude-code-integration.md` for details

## `source:` Read Priority Rule

- When reading a `source:` file, if an identically-named file exists in `_organized/`, prefer reading that one
- Example: `source: inbox/meetings/2026-02-16-X.md` → if `inbox/meetings/_organized/2026-02-16-X.md` exists, Read that instead

## Entity References (mentions)

- Project linkage: `mentions: [projects/{id}]` (ADR-066). The dedicated `project` field is deprecated
- Person linkage: `mentions: [people/{id}]`
- Organization linkage: `mentions: [orgs/{id}]`
- Multiple allowed: `mentions: [people/alex-chen, orgs/sunrise-hotel, projects/acme-saas]`

## Note Metadata Repair (ADR-046 D46-7)

When reading knowledge/notes/ files, perform the following auto-repairs:

**Mode A — Direct fix (no AI judgment needed, 1-2 Edits)**:
1. If deprecated tags are found, remove via Edit
2. If entity IDs are found in tags, move to `mentions` in typed format (`{type}/{id}`) (skip if already in mentions)

**Mode B — .refresh-queue addition (detection only)**:
Append file paths matching any of the following to `knowledge/.refresh-queue` (check for existing entries):
- `tags` is empty `[]`
- `tags` has only 1 tag and that tag has 50+ uses (generic tag only)
- `mentions` field does not exist
- `related` field does not exist
- `type` is not one of `record` / `insight` / `reference`
