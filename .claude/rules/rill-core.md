# Rill Core Rules

**Entry point** rules for working in a Rill-managed vault. Detailed rules are split into `.claude/rules/rill-*.md` files, auto-loaded each turn by Claude Code.

## What is Rill

Rill is a personal voice journal + knowledge management system.

Core flow: **voice / text → Markdown → GitHub → Claude Code → knowledge / tasks**

All data is plain Markdown files. GitHub is the single source of truth.

## Directory Map (standard vault structure)

```
<vault>/
├── inbox/          # Input layer (immutable): journal, meetings, tweets, web-clips, sources
├── knowledge/      # Accumulation layer: me.md, notes/, people/, orgs/, projects/
├── workspace/{id}/ # Working layer (stateful)
├── tasks/{slug}/   # Per-task directory (_task.md + optional artifacts, ADR-076)
├── reports/        # Claude Code outputs: daily/, newsletter/
├── pages/          # Human-facing aggregated Materialized Views
├── taxonomy.md     # Tag vocabulary management
└── .claude/
    ├── commands/   # Claude Code skills
    └── rules/      # Split rules (including this file, auto-loaded)
```

## Critical Invariants (must be guaranteed every turn)

1. **Original files in inbox/ are read-only**. Never modify them (no appending either). Creating organized versions in `_organized/` is allowed
2. **Use `rill mkfile` for new file creation**. LLMs must never write `created` values directly (for timestamp accuracy)
3. **Frontmatter is required**. See `rill-data-model.md` for schema
4. **Claude Code integration boundary**: Agent SDK / OAuth token management / `--bare` mode / API Key default auth are **prohibited**. Use `claude -p --output-format stream-json` for automation
5. **Contact information (email, phone) must only be written to `knowledge/people/` or `knowledge/orgs/`**

## Detailed Rules (index to split files)

Each area's detailed rules are in the following split files. All auto-loaded from `.claude/rules/*.md`:

- **Data model**: [rill-data-model.md](rill-data-model.md) — frontmatter schema, tag management, link conventions, mentions
- **inbox/ input layer**: [rill-inbox.md](rill-inbox.md) — immutability principle, `_organized/`, `.processed`
- **knowledge/ accumulation layer**: [rill-knowledge.md](rill-knowledge.md) — notes pool, entity principles, contact rules
- **workspace/ working layer**: [rill-workspace.md](rill-workspace.md) — completion conditions, artifact numbering, file-first principle
- **tasks/ tickets**: [rill-tasks.md](rill-tasks.md) — status values, due/scheduled, subtasks
- **reports/ + pages/**: [rill-outputs.md](rill-outputs.md) — Daily Note, Newsletter, pages recipe pairs
- **Claude Code integration**: [rill-claude-code-integration.md](rill-claude-code-integration.md) — `rill mkfile`, GUI path-display convention, zsh compatibility

Additionally, container directory `CLAUDE.md` files (e.g., `inbox/meetings/`, `knowledge/people/`) are loaded on-demand, providing type-specific rules.

## Language Rules

- **Body text**: User's preferred language
- **Technical terms**: Keep in English (Markdown, API, frontmatter, etc.)
- **File/directory names**: English kebab-case
- **Frontmatter keys**: English
- **Commit messages**: English

## Customization

Users can add their own rules via:

- `.claude/rules/personal-*.md` — Personal rules in separate files (auto-loaded)
- Root `CLAUDE.md` — Project-specific instructions (`rill update` does not touch it)

Rill-managed `rill-*.md` files may be overwritten by `rill update`. Do not edit them directly.
