---
paths:
  - "workspace/**"
---

# Workspace Rules — Rill

`workspace/` is the **working layer (stateful)** — projects, areas, and Deep Think sessions in a unified structure.

## Structure

```
workspace/
└── {id}/
    ├── _workspace.md   # MOC + state management
    ├── _summary.md     # generated on completion
    ├── _log.md         # session / decision history (optional)
    └── NNN-description.md  # numbered artifacts
```

Directory name: `{id}/` (kebab-case). Date-prefixed `{YYYY-MM-DD}-{topic}/` or ID only.

## Creation

1. Create the date-prefixed topic directory first
2. Generate `_workspace.md` via `rill mkfile workspace --slug {id} --type workspace`
3. Artifacts emerge naturally as separate files

## `_workspace.md` Frontmatter

```yaml
---
created: 2026-02-16T17:00+09:00
type: workspace
id: rill-development
name: Rill Development
status: active              # active | completed | on-hold | pilot | planning
origin: inbox/journal/2026-02-13-1950.md
tags: [rill]
mentions: [projects/rill]
client: Client Name          # optional
---
```

### Status Transition Boundary

- **Only `/close` may set `status: completed`.** This triggers knowledge distillation via the two-layer sub-agent architecture (ADR-073). Any other skill or ad-hoc edit that writes `completed` bypasses distillation and silently loses session knowledge.
- `/focus` and other interactive skills must never set `completed` directly — propose `/close` via AskUserQuestion instead.
- Allowed non-`/close` transitions: `completed` → `active` (reopen), `on-hold` ↔ `active`. Safe — no distillation.

## Artifact File Frontmatter

```yaml
---
created: 2026-02-16T17:30+09:00
topic: rill-development
type: research | progress | analysis | decision | review
tags: [rill]                # optional
mentions: [projects/rill]   # optional
---
```

Types: `progress`, `research`, `analysis`, `decision`, `review`.

## Completion Conditions Required

Every workspace must have completion conditions. Don't use workspaces for areas (no end condition); decompose into concrete projects (ADR-029).

## Relationship with Tasks

1:1 correspondence with tasks is not required. Create workspaces only when artifact accumulation or deep exploration is needed. Tasks are independent tickets in `tasks/`. Multiple workspaces may link to one project via `mentions: [projects/xxx]`.

## Session Flow

### File-First Principle

Save artifacts to files: analyses, research, comparison tables, decisions, frameworks, design proposals, structured output of 3+ paragraphs.

Text-only is fine for: brief confirmations / suggestions (1-2 paragraphs), directional discussion, brainstorming, summary preview before saving. When in doubt, write a file — a workspace's value lives in its accumulated artifacts.

### Updating `_workspace.md`

At each milestone: add new artifacts to "Related Files (MOC)", update checkboxes, append "Session History", update "Next Steps".

## Handling Existing Artifacts

Once created, artifacts are generally not modified — additions / corrections go in new files. `NNN-` numbers increase chronologically.

## Backward Compatibility

Older workspaces may contain `_session.md` or `_project.md` instead of `_workspace.md`. Treat as meta files (do not rename during Phase 3).
