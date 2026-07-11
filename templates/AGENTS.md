# Rill Vault Instructions

This repository is a Markdown-based personal journal and knowledge vault.
Before changing vault content, read the applicable files under
`.claude/rules/rill-*.md`; they are shared Rill rules despite the legacy
directory name. Also read the nearest nested `AGENTS.md` for the target path.

## Critical Invariants

- Original files under `inbox/` are immutable. Only `_organized/` derivatives
  may be created or changed.
- Create vault content with `rill mkfile`; never write the `created`
  frontmatter field manually.
- Frontmatter is required and must follow `.claude/rules/rill-data-model.md`.
- Email addresses and phone numbers belong only in `knowledge/people/` or
  `knowledge/orgs/`.
- Do not edit Rill-managed files listed in `.rill/managed-files.txt`. Change
  the canonical Rill source and run `rill update` instead.
- Preserve unrelated changes in a dirty worktree.

## Container Directories

Codex only auto-loads `AGENTS.md` files on the path from the git root down
to the current working directory, and sessions here start at the vault
root — so the nested `AGENTS.md` copies below are not auto-loaded on their
own (their combined size can also exceed the default 32 KiB
`project_doc_max_bytes` project-doc budget). Before creating or editing
files under a directory below, read its `CLAUDE.md` (or `AGENTS.md` twin)
first — it is that container's schema (frontmatter, naming, invariants).

| Directory | Read first |
|---|---|
| `inbox/` | `inbox/CLAUDE.md` |
| `inbox/journal/` | `inbox/journal/CLAUDE.md` |
| `inbox/meetings/` | `inbox/meetings/CLAUDE.md` |
| `inbox/tweets/` | `inbox/tweets/CLAUDE.md` |
| `inbox/web-clips/` | `inbox/web-clips/CLAUDE.md` |
| `inbox/sources/` | `inbox/sources/CLAUDE.md` |
| `knowledge/notes/` | `knowledge/notes/CLAUDE.md` |
| `knowledge/people/` | `knowledge/people/CLAUDE.md` |
| `knowledge/orgs/` | `knowledge/orgs/CLAUDE.md` |
| `knowledge/self/` | `knowledge/self/CLAUDE.md` |
| `projects/` | `projects/CLAUDE.md` |
| `workspace/` | `workspace/CLAUDE.md` |
| `tasks/` | `tasks/CLAUDE.md` |
| `pages/` | `pages/CLAUDE.md` |
| `reports/daily/` | `reports/daily/CLAUDE.md` |
| `reports/newsletter/` | `reports/newsletter/CLAUDE.md` |

## Main Workflow

Input flows from `inbox/` into `knowledge/`, `tasks/`, `workspace/`,
`projects/`, `pages/`, and `reports/`. Reusable workflows are installed under
`.agents/skills/`. Use the matching skill whenever the request names or
clearly implies one.

## Verification

Run `rill doctor codex` after installation or updates. For data changes, use
the verification steps required by the applicable Rill rule or skill.
