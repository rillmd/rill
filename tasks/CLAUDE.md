# tasks/ — Task Tickets

Task ticket files (ADR-063). Flat structure, individually managed.

## Filename

`{slug}.md` (kebab-case). **No `task-` prefix needed**.

## Frontmatter (required fields)

```yaml
---
created: 2026-04-07T10:00+09:00   # Auto-set by rill mkfile
type: task                         # Required
status: open                       # Required
source: inbox/journal/X.md         # Required
tags: [rill]                       # Optional
mentions: [projects/rill, people/alex-chen]  # Optional
due: 2026-04-15                    # Optional: deadline
scheduled: 2026-04-10              # Optional: planned start date
---
```

## status Values

- `draft` — AI-generated, unapproved task (approve/reject in Review mode, ADR-069)
- `open` — Ready to start
- `waiting` — Blocked on someone/something
- `someday` — Someday/maybe
- `done` — Completed
- `cancelled` — Cancelled

## due vs scheduled

- `due` — Deadline ("by when")
- `scheduled` — Planned start date or event date ("when to do it")
- They are independent
- Tasks with a future `scheduled` date are excluded from urgent (already planned)

**No `priority` field**. Urgency is computed from due/scheduled.

## Body Structure

```markdown
# Title

## Goal
(Can be filled during /solve comprehension phase. OK to leave empty at capture)

## Background
...

## Context
(Optional)

## Request
(Optional)

## History
- 2026-04-07: Task created
```

## Project Linking

Use `mentions: [projects/{id}]` (ADR-066). **Dedicated `project` field is deprecated**.

## Subtasks

Managed via checkboxes in the body. Promote to separate tickets if independent tracking is needed.

## Duplicate Check

Check for duplicates against existing tickets before creating new ones (Evergreen principle).

## Status Updates During Sessions

When the user reports "done", "no longer needed", etc., **immediately Edit the `status` in the corresponding file**.

## After Completion

- Retain as `status: done`
- Optionally move to knowledge/notes/ as `type: record`

## Creating New

```bash
rill mkfile tasks --slug compare-e-contract-services --type task
# or
rill task "Compare e-contract services"
```
