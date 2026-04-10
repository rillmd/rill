# Task Rules — Rill

`tasks/` is the **action layer**. Individual tasks are managed as task ticket files (ADR-063).

## Structure

```
tasks/
├── {slug}.md      # Task ticket file
```

**Flat structure**. No subdirectories.

## File Names

- `{slug}.md` (kebab-case)
- **No `task-` prefix needed** (ADR-063)
- Examples: `rill-voice-task-management-skill.md`, `smith-trading-followup.md`

## Frontmatter

```yaml
---
created: 2026-04-07T10:00+09:00   # auto-assigned by rill mkfile
type: task
status: open                       # required
source: inbox/journal/2026-04-07-X.md   # required
tags: [rill, crm]                  # optional
mentions: [projects/rill, people/alex-chen]  # optional
due: 2026-04-15                    # optional: deadline
scheduled: 2026-04-10              # optional: planned start date
related:                           # optional
  - workspace/2026-04-07-rill-feature/_workspace.md
---
```

### Required Fields
- `type: task`
- `source`
- `status`

### Status Values
- `draft`: AI-generated unapproved task (approved/rejected via Electron app Review mode, ADR-069)
- `open`: Awaiting start
- `waiting`: Waiting on others or events
- `someday`: Future/low priority
- `done`: Completed
- `cancelled`: Cancelled

### Difference Between due and scheduled
- `due`: Deadline ("by when")
- `scheduled`: Planned start date or event date ("when to work on it")
- They are independent. Tasks with a future `scheduled` are excluded from urgent lists (already planned)
- **No `priority` field** (urgency is calculated from due/scheduled)

## Project Linkage

- Use `mentions: [projects/{id}]` (ADR-066)
- **The dedicated `project` field is deprecated**

## Body Structure

```markdown
# Title

## Goal
(can be filled during /solve understanding phase)

## Background
...

## Context
(optional)

## Request
(optional)

## History
- 2026-04-07: Task created
```

- Scaffolded by the `rill task` command
- Goal can be empty at capture time

## Subtasks

- Managed as checkboxes within the ticket body
- Promote to separate tickets if independent tracking is needed

## Creation Methods

1. AI suggestions during `/focus` (user approval required)
2. `rill task "title"` CLI
3. `/distill` (interactive only)

## Duplicate Check

Check for duplicates against existing tickets before creating new ones (Evergreen principle for tasks/).

## After Completion

- Keep as `status: done`
- Move to knowledge/notes/ as `type: record` if appropriate

## In-Session Status Updates

When the user reports task completion, cancellation, or status changes during a session, **update the ticket file's frontmatter `status` immediately**.
