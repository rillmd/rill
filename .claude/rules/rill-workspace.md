# Workspace Rules — Rill

`workspace/` is the **working layer (stateful)**. Manages projects, areas, and Deep Think sessions in a unified structure.

## Structure

```
workspace/
└── {id}/
    ├── _workspace.md   # MOC + state management (unified file)
    ├── _summary.md     # Summary generated on completion
    ├── _log.md         # Session/decision history (optional)
    └── NNN-description.md  # Numbered artifacts
```

Directory name: `{id}/` (kebab-case). Date-prefixed `{YYYY-MM-DD}-{topic}/` or ID only `acme-saas/`.

## Creation Rules

1. **Create the date-prefixed topic directory first**: `workspace/{YYYY-MM-DD}-{topic}/`
2. Generate `_workspace.md` with `rill mkfile workspace --slug {id} --type workspace`
3. Artifacts emerge naturally during conversation (separate files from `_workspace.md`)

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

### Status Transition Boundary (important)

- **Only `/close` may set `status: completed`.** This transition is the trigger for knowledge distillation via the two-layer sub-agent architecture (ADR-073). Any other skill or ad-hoc edit that writes `completed` bypasses distillation and silently loses the session's knowledge
- `/focus` and other interactive skills must **never** set `status: completed` directly. When a session feels done, propose `/close` to the user via AskUserQuestion instead
- Allowed non-`/close` transitions: `completed` → `active` (reopen), `on-hold` → `active` (resume), `active` → `on-hold` (when the user explicitly pauses). These do not trigger distillation and are safe

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

### Artifact Types

- `progress`: Progress records
- `research`: Research/investigation
- `analysis`: Analysis
- `decision`: Decision records
- `review`: Review/critique

## Completion Conditions Are Required

- **Every workspace must have completion conditions**
- Do not use workspaces for areas (responsibility zones with no end condition)
- If an area is needed, decompose it into concrete projects (ADR-029 D29)

## Relationship with Tasks

- **1:1 correspondence with workspaces is not required**
- Only create workspaces when artifact accumulation or deep exploration is needed
- Tasks are independently managed as tickets in `tasks/`
- Multiple workspaces may link to one project (`mentions: [projects/xxx]`)

## Session Flow

### File-First Principle

Save artifacts to files whenever possible:
- Analysis, research, investigation results
- Reports, surveys, comparison tables
- Decisions and rationale
- Frameworks, design proposals
- Structured output of 3+ paragraphs

**Text output alone is fine for**:
- Confirmations, questions, brief suggestions (1-2 paragraphs of conversational exchange)
- Directional discussion, brainstorming
- Summary preview before saving to file

When in doubt, write it to a file. A workspace's value lives in its accumulated artifacts.

### Updating `_workspace.md`

Update `_workspace.md` at each conversation milestone:
- Add new artifacts to "Related Files (MOC)"
- Update checkboxes for completed issues
- Append progress to "Session History"
- Update "Next Steps"

## Handling Existing Artifacts

- Once created, artifact files are **generally not modified**
- Additions and corrections go in new files
- `NNN-` numbers increase chronologically

## Backward Compatibility

In addition to `_workspace.md`, older workspaces may contain `_session.md` or `_project.md`. Treat these as meta files as well (do not rename during Phase 3).
