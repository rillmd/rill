---
paths:
  - "tasks/**"
---

# Task Rules — Rill

`tasks/` is the **action layer**. Tasks are managed as per-task directories (ADR-063, ADR-076).

## Structure

```
tasks/
└── {slug}/
    ├── _task.md            # Task ticket body + frontmatter
    └── NNN-description.md  # Optional per-task artifacts (time-ordered)
```

Each task is a directory so /solve can accumulate research notes, plans, decisions under it without spawning a workspace. Simple tasks remain a one-file directory.

Sub-directories under a task are not allowed (flat artifact layout), with one exception: a `.view/` sidecar directory for regenerable derived renders (gitignored, per [rill-html-output.md](rill-html-output.md) principle 5). Binary artifacts (HTML mock, image, PDF) may live at the same level as `_task.md`. HTML artifacts follow the class rules in [rill-html-output.md](rill-html-output.md) — on resume the AI reads `.md` only, except an HTML-canonical artifact that is itself the resumed work's target (principle 3).

## File Names

- Directory: `{slug}/` (kebab-case). Body is always `_task.md`.
- No `task-` prefix on the slug (ADR-063).
- Examples: `tasks/rill-voice-task-management-skill/_task.md`, `tasks/smith-trading-followup/_task.md`

## Frontmatter

```yaml
---
created: 2026-04-07T10:00+09:00   # auto-assigned by rill mkfile
type: task
status: open                       # required
source: inbox/journal/2026-04-07-X.md   # required when there's a discrete upstream
tags: [rill, crm]                  # optional
mentions: [projects/rill, people/alex-chen]  # optional
due: 2026-04-15                    # optional: deadline
scheduled: 2026-04-10              # optional: planned start date
depends-on: [tasks/rill-foundation-design]   # optional: prerequisite tasks
blocks: [tasks/rill-launch-post]             # optional: tasks this one blocks
related:                           # optional
  - workspace/2026-04-07-rill-feature/_workspace.md
---
```

`source` is required when there's a discrete upstream (journal, meeting, note); omit it for tasks born from live conversation rather than fabricating a link.

### Status Values

- `draft`: AI-generated unapproved task (approved/rejected via Electron Review mode, ADR-069)
- `open`: Awaiting start
- `waiting`: Waiting on others or events
- `someday`: Future/low priority
- `done`: Completed
- `cancelled`: Cancelled

### due vs scheduled

`due` is deadline ("by when"); `scheduled` is planned start or event date ("when to work on it"). Independent. Tasks with a future `scheduled` are excluded from urgent lists. No `priority` field — urgency is calculated from due/scheduled.

### Dependency Fields

- `depends-on: [tasks/foo, tasks/bar]` — prerequisite tasks
- `blocks: [tasks/baz]` — downstream tasks this one blocks (inverse of depends-on; either alone is sufficient)

`/project {slug} continue` resolves `depends-on` to pick an unblocked task. `/refresh-project` renders Active Tasks in dependency order.

## Project Linkage

Use `mentions: [projects/{id}]` (ADR-066). The dedicated `project` field is deprecated.

## Body Structure

```markdown
# Title

## Goal
(completion condition — what must be true for done)

## Background
(why this exists, what triggered it, what's at stake)

## Context
(optional: related notes, workspaces, sources — one link per line with role descriptor)

## Request
(optional: creator's note to executor — approach hints, pitfalls, constraints)

## History
- YYYY-MM-DD: Task created. (provenance)
```

Scaffolded by `rill task`.

### Dynamic sections (managed by /solve)

- `## Current Position` — directly under title; updated each Phase / Step transition; removed at `status: done`
- `## Plan` — between `## Context` and `## Request` after Phase 3 approval; stays even after completion (documents how solved)

## Substance

The task file is the primary handoff between creator and executor (human or AI). Thin fields force the executor to re-derive intent — defeating the point of a ticket. Write as richly as the task's complexity warrants. Empty fields and placeholder text are the anti-pattern, not short fields.

Per-field:

- **Goal**: A verifiable completion condition. Not a plan. If it can't be stated at capture, say so explicitly rather than leaving it blank.
- **Background**: What the executor needs to pick this up cold. The test: can someone who wasn't in the room work from Background alone?
- **Context**: One link per line with a short role descriptor ("why this link matters"). Do not use the legacy `Title::path,Title::path` inline format.
- **Request**: Approach hints, pitfalls, constraints — not a plan. Legacy "Action Items" headings are deprecated.
- **History**: Provenance at creation; grows as the task evolves.
- **Frontmatter**: `source` points to the real upstream or is omitted. `tags` and `mentions` reflect what the task is about.

## Good Example (abridged)

Frontmatter: `source`, `tags`, `mentions: [projects/..., people/...]`, optional `due`, optional `related: [knowledge/notes/...]`.

Body:

- **Goal** — verifiable end-state ("IMAP/SMTP access confirmed working end-to-end, with a procedure their IT can execute without our help").
- **Background** — trigger + stakes + non-obvious prior context (e.g., "prior project hit TLS/auth issues for a week; pre-empt that"). The test: someone not in the room can work from this alone.
- **Context** — one link per line with role descriptor: `[Acme-saas IMAP connector design](knowledge/notes/...) — TLS config + polling cadence`.
- **Request** — prescriptive hint, not a plan ("draft a yes/no checklist before the first discovery call so we don't burn their IT window on open-ended questions").
- **History** — provenance: `2026-04-17: Created from 2026-04-15 kickoff.`

Passes: Goal verifiable, Background covers trigger/stakes/prior incident, Context links have role descriptors, Request prescriptive but not a plan.

## Anti-patterns

- No `source`, `tags`, or `mentions` → executor can't locate trigger or entities
- Empty `Goal` → executor guesses what "done" means
- Background as a sketch without the *why* (which friction? which users? how often?)
- Context as `Title::path,Title::path` inline (loses role descriptors)
- Empty Request / History → creator's intent and provenance lost

## Subtasks

Checkboxes within the ticket body. Promote to separate tickets if independent tracking is needed.

## Creation

1. AI suggestions during `/focus` (user approval required)
2. `rill task "title" --slug {slug}` CLI
3. `/distill` (interactive only)

Per-task artifacts (research, plans, decisions from /solve): `rill mkfile tasks/{slug} --slug {description} --type {research|analysis|decision|progress|review}`.

## Duplicate Check

Check for duplicates before creating (Evergreen principle).

## After Completion

Keep as `status: done`. Move to `knowledge/notes/` as `type: record` if appropriate.

## In-Session Status Updates

When the user reports completion, cancellation, or status changes mid-session, update `_task.md` frontmatter `status` immediately.
