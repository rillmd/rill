# workspace/ — Active Workspaces

The active layer (stateful). Projects, Deep Think sessions, and ongoing work areas.

## Directory Naming

- **Date-prefixed**: `workspace/{YYYY-MM-DD}-{topic}/` — Standard for new workspaces
- **ID only**: `workspace/{id}/` — Long-running projects (e.g., `workspace/rill/`, `workspace/acme-saas/`)

kebab-case.

## Required Files

```
workspace/{id}/
├── _workspace.md   # MOC + state management (required)
├── _summary.md     # Generated on completion
├── _log.md         # Optional, session history
└── NNN-description.md  # Numbered deliverables
```

## `_workspace.md` Frontmatter

```yaml
---
created: 2026-02-16T17:00+09:00
type: workspace
id: rill-development
name: Rill Development
status: active                  # active | completed | on-hold | pilot | planning
origin: inbox/journal/X.md      # Origin file
tags: [rill]
mentions: [projects/rill]
---
```

## Deliverable File Frontmatter

```yaml
---
created: 2026-02-16T17:30+09:00
topic: rill-development
type: research | progress | analysis | decision | review
tags: [rill]                  # Optional
mentions: [projects/rill]     # Optional
---
```

## Deliverable Types

- `progress` — Progress records
- `research` — Research and investigation
- `analysis` — Analysis
- `decision` — Decision records
- `review` — Reviews and critiques

## Completion Criteria Required (ADR-029)

**Every workspace must have completion criteria.** Areas (responsibility domains without end conditions) should not be workspaces. If an area is needed, break it down into concrete projects.

## Relationship with Tasks

- No required 1:1 mapping with workspaces (ADR-029)
- Create workspaces only when deliverable accumulation or deep exploration is needed
- Tasks are managed independently (tasks/)
- Project linking via `mentions: [projects/{id}]`

## File-First Principle

Save deliverables to files. See `.claude/rules/rill-workspace.md` for details.

## Legacy Meta-File Compatibility

Older workspaces may have `_session.md` or `_project.md` files. Treat them as meta-files (do not rename).

## Creating New

```bash
rill mkfile workspace --slug 2026-04-07-topic-name --type workspace
```
