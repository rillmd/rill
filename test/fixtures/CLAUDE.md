# CLAUDE.md — Rill Test Vault

This is a minimal test vault for Rill skill testing.

## Repository Structure

```
test-vault/
├── inbox/journal/          # Journal
├── inbox/web-clips/        # Web Clips
├── knowledge/notes/        # Knowledge
├── knowledge/people/       # Person entities
├── knowledge/orgs/         # Organization entities
├── knowledge/projects/     # Project entities
├── workspace/              # Workspace
├── tasks/                  # Task tickets
├── reports/daily/          # Daily Note
├── taxonomy.md             # Tag vocabulary
└── CLAUDE.md               # This file
```

## Language Rules

- **Body text**: English
- **Technical terms**: Keep in English
- **File/directory names**: English kebab-case
- **Frontmatter keys**: English

## Claude Code Working Rules

1. Original files in inbox/ are **read-only**. Never modify them
2. Before creating files in knowledge/notes/, check for duplicates against existing files. Update existing files if there is overlap
3. Tasks are managed as ticket files at `tasks/{slug}/_task.md`
4. Always include frontmatter when creating files. **Use `rill mkfile` for new file creation**
5. When assigning tags, Read `taxonomy.md` to check existing tags
6. The `mentions` field can be used in all file types. An array of typed entity references with type prefix: `[people/id, orgs/id, projects/id]`
7. When referencing files in the body, use Markdown links in the format `[display name](relative-path)`
