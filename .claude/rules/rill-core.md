# Rill Core Rules

Entry point for working in a Rill-managed vault. Detailed rules are split into `.claude/rules/rill-*.md` files, auto-loaded each turn.

## What is Rill

Personal voice journal + knowledge management system. Core flow: **voice / text → Markdown → GitHub → Claude Code → knowledge / tasks**. All data is plain Markdown; GitHub is the single source of truth.

## Directory Map

```
<vault>/
├── inbox/          # Input layer (immutable): journal, meetings, tweets, web-clips, sources
├── knowledge/      # Accumulation layer: self/, notes/, people/, orgs/
├── projects/       # Execution hub layer (ADR-080)
├── workspace/{id}/ # Working layer (stateful)
├── tasks/{slug}/   # Per-task directory (_task.md + optional artifacts, ADR-076)
├── reports/        # Claude Code outputs: daily/, newsletter/, eval/, distill/, retrospective/
├── pages/          # Human-facing aggregated Materialized Views
├── taxonomy.md     # Tag vocabulary management
└── .claude/
    ├── skills/     # Claude Code skills (canonical form: {name}/SKILL.md)
    ├── commands/   # Internal templates, plugin symlinks, personal skills
    └── rules/      # Split rules (including this file)
```

## Critical Invariants

1. Original files in `inbox/` are read-only (no appending). Organized versions in `_organized/` are allowed.
2. Use `rill mkfile` for new files — LLMs must never write `created` directly.
3. Frontmatter required. See `rill-data-model.md`.
4. Claude Code integration boundary: Agent SDK / OAuth tokens / `--bare` mode / API Key default auth are prohibited. Use `claude -p --output-format stream-json` for automation.
5. Contacts (email, phone) only in `knowledge/people/` or `knowledge/orgs/`.

## Detailed Rules (index)

- **Data model**: [rill-data-model.md](rill-data-model.md) — frontmatter, tags, links, mentions
- **inbox/**: [rill-inbox.md](rill-inbox.md) — immutability, `_organized/`, `.processed`
- **knowledge/**: [rill-knowledge.md](rill-knowledge.md) — notes pool, entities, contact rules
- **workspace/**: [rill-workspace.md](rill-workspace.md) — completion conditions, file-first
- **tasks/**: [rill-tasks.md](rill-tasks.md) — status, due/scheduled, subtasks
- **projects/**: [rill-projects.md](rill-projects.md) — execution hub layer (ADR-080)
- **reports/ + pages/**: [rill-outputs.md](rill-outputs.md) — Daily Note, Newsletter, recipe pairs
- **Claude Code integration**: [rill-claude-code-integration.md](rill-claude-code-integration.md)
- **Autonomous execution**: [rill-autonomous-execution.md](rill-autonomous-execution.md) — lanes, Plan gate, worktrees, Codex usage, two-channel write, three-tier destructive ops

Container `CLAUDE.md` files (e.g., `inbox/meetings/`, `knowledge/people/`) load on-demand for type-specific rules.

## Language Rules

- **Body text**: user's preferred language (distribution default: English; personal vaults override via `.claude/rules/personal-*.md`)
- **English exceptions** (only): tokens inside backticks, proper nouns, ASCII acronyms
- **File/directory names, frontmatter keys, commit messages**: English

## Customization

- `.claude/rules/personal-*.md` — personal rules (auto-loaded)
- Root `CLAUDE.md` — project-specific (untouched by `rill update`)

Rill-managed `rill-*.md` files may be overwritten by `rill update` — do not edit directly.
