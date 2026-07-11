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

## Main Workflow

Input flows from `inbox/` into `knowledge/`, `tasks/`, `workspace/`,
`projects/`, `pages/`, and `reports/`. Reusable workflows are installed under
`.agents/skills/`. Use the matching skill whenever the request names or
clearly implies one.

## Verification

Run `rill doctor codex` after installation or updates. For data changes, use
the verification steps required by the applicable Rill rule or skill.
