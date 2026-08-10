# Data Model Rules — Rill

Common frontmatter schema, references, links. Directory-specific rules: `rill-inbox.md` / `rill-knowledge.md` / `rill-workspace.md` / `rill-tasks.md` / `rill-outputs.md`.

## Frontmatter Schema

### Required

- `created`: ISO 8601 (e.g., `2026-04-07T18:30+09:00`). **LLMs must never write directly** — auto-assigned via `rill mkfile`.
- `type`: File type identifier (`record` / `insight` / `reference` / `task` / `workspace` / `page` / `person` / `org` / `project` / `self` / `daily-note` etc.)

### Optional

- `source`: relative path (no leading `/`). Required for knowledge/notes/.
- `tags`: AI-assigned, max 3, inline array. Topic discrimination only — entities go in `mentions`.
- `mentions`: typed entity array `[people/id, orgs/id, projects/id]` (ADR-053). Usable in all file types (ADR-066).
- `related`: array of related file paths.
- `updated`: auto-set (used in pages/).

## Tag Management

- Read `taxonomy.md` before assigning tags. Add new tags only if none match.
- Passing tag vocabulary to sub-agents: use YAML list format (name + desc). Inline `tag(description)` prohibited (ADR-046 D46-3).
- kebab-case, English.
- Entity IDs as tags are prohibited (`acme-saas` is not a tag → use `mentions: [projects/acme-saas]`).
- Deprecated tags in taxonomy.md's "Deprecated Tags" table — remove via Edit when found.

## Reference / Link Rules

- **In-body links**: standard Markdown `[text](path)`. Wiki links `[[]]` not used.
- **Backtick-only ID references prohibited**: no `` `task-xxx` `` — always `[display name](tasks/xxx/_task.md)` (ADR-064, ADR-076).
- **Frontmatter fields** (source, related, mentions): structured data — plain path strings, no Markdown links.

## File Creation

Use `rill mkfile` for new files (ADR-060) — ensures timestamp accuracy. LLMs never write `created` directly. See `rill-claude-code-integration.md`.

**HTML exception**: generated HTML files carry no frontmatter and are not created via `rill mkfile` — producing skills write them directly; derived views embed a provenance comment instead. See [rill-html-output.md](rill-html-output.md).

## `source:` Read Priority

When reading a `source:` file, prefer the same-named file in `_organized/` if present. Example: `source: inbox/meetings/2026-02-16-X.md` → if `inbox/meetings/_organized/2026-02-16-X.md` exists, Read that.

## Entity References (mentions)

- Project: `mentions: [projects/{id}]` → `projects/{id}/_project.md` (ADR-066, ADR-080 — top-level, moved from old `knowledge/projects/`). Dedicated `project` field deprecated.
- Person: `mentions: [people/{id}]` → `knowledge/people/{id}.md`
- Org: `mentions: [orgs/{id}]` → `knowledge/orgs/{id}.md`
- Multiple allowed: `mentions: [people/alex-chen, orgs/sunrise-hotel, projects/acme-saas]`

Mention text is the same across entity types; only resolution path differs.

## Note Metadata Repair (ADR-046 D46-7)

When reading knowledge/notes/ files:

**Mode A — direct fix** (no judgment, 1-2 Edits):

1. Remove deprecated tags
2. Move entity IDs from `tags` to `mentions` in typed format (`{type}/{id}`); skip if already there

**Mode B — append to `knowledge/.refresh-queue`** (detection only, dedup against existing):

- `tags` empty `[]`
- `tags` has only 1 tag and that tag is a current mega-tag: its usage count exceeds the /inspect split threshold `max(60, 2.5 x median tag usage)` (reuse the latest `eval/metrics/` tag_balance median instead of recomputing when available)
- `mentions` field missing
- `related` field missing
- `type` is not `record` / `insight` / `reference`
