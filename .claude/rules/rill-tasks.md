# Task Rules — Rill

`tasks/` is the **action layer**. Individual tasks are managed as per-task directories (ADR-063, ADR-076).

## Structure

```
tasks/
└── {slug}/
    ├── _task.md            # Task ticket body + frontmatter
    └── NNN-description.md  # Optional per-task artifacts (time-ordered)
```

**Directory per task** (ADR-076). Each task lives in its own directory so /solve can accumulate research notes, plans, decisions, and other artifacts under it without spawning a separate workspace. Simple tasks remain a one-file directory (`_task.md` only).

- Sub-directories under a task are not allowed (flat artifact layout).
- Binary artifacts (HTML mock, image, PDF) may live at the same level as `_task.md`.

## File Names

- Directory: `{slug}/` (kebab-case). The ticket body is always `_task.md` inside it.
- **No `task-` prefix needed** on the slug (ADR-063)
- Examples: `tasks/rill-voice-task-management-skill/_task.md`, `tasks/smith-trading-followup/_task.md`

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
- `status`
- `source` — when the task has a discrete upstream (journal, meeting, note). For tasks born from live conversation with no discrete origin, omit it rather than fabricate a link to an unrelated recent file.

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
(completion condition — what must be true for this task to be done)

## Background
(why this task exists, what triggered it, what's at stake)

## Context
(optional: related notes, workspaces, sources — one link per line with a role descriptor)

## Request
(optional: creator's note to executor — approach hints, pitfalls, constraints)

## History
- 2026-04-07: Task created. (provenance — how it came into existence)
```

Scaffolded by `rill task`. See Substance below for how to fill each field.

## Substance

The task file is the primary handoff between creator and executor (human or AI). Thin fields force the executor to re-derive intent from scratch — which defeats the point of persisting a ticket.

Aim for a body the executor can work from without re-interviewing you. Write as richly as the task's actual complexity warrants: a multi-party commercial task needs real context; a one-line reminder does not. Empty fields and placeholder text are the anti-pattern, not short fields.

Per-field notes:

- **Goal**: State the completion condition — something that can be checked true/false. Not a plan. If it genuinely can't be stated at capture time, say so explicitly rather than leaving it blank.
- **Background**: Whatever the executor needs to pick this up cold — the trigger, the stakes, non-obvious prior context. The test is whether someone who wasn't in the room can work from Background alone.
- **Context**: One link per line with a short role descriptor ("why this link matters for this task"). Do not use the `Title::path,Title::path` inline format — it compresses role context to nothing.
- **Request**: Creator's note to executor — approach hints, pitfalls, constraints. Not a plan. Legacy "Action Items" headings (in any language) are deprecated: put intent in Request and concrete checkboxes under Subtasks.
- **History**: Provenance at creation; grows as the task evolves.
- **Frontmatter**: `source` must point to the actual upstream file, or be omitted — do not fill it with an unrelated recent journal. `tags` and `mentions` reflect what the task is actually about.

## Good Example

```markdown
---
created: 2026-04-17T10:00+09:00
type: task
status: open
source: inbox/meetings/_organized/2026-04-15-acme-saas-kickoff.md
tags: [onboarding, integrations]
mentions: [projects/acme-saas, people/alex-chen]
due: 2026-05-15
related:
  - knowledge/notes/acme-saas-imap-connector-design.md
  - knowledge/notes/sunrise-hotel-imap-retrospective.md
---

# Confirm IMAP connectivity for acme-saas trial inbox

## Goal
IMAP/SMTP access to the acme-saas trial mailbox is confirmed working end-to-end (outbound auth, inbound polling, TLS), with a documented setup procedure their IT team can execute without our help.

## Background
Alex Chen's team agreed to a 1–2 month trial on their customer-support mailbox during the 2026-04-15 kickoff. Their mail is hosted on an internal groupware suite, so the standard setup docs don't apply. The trial's go/no-go depends on whether the mailbox can be connected without IT policy exceptions. A prior project (sunrise-hotel) used IMAP on a different stack and hit TLS/auth issues that took a week to resolve — we want to pre-empt the same class of bugs before the trial starts. Their IT contact is available only on Thursdays, so discovery calls need to be batched.

## Context
- [Acme-saas IMAP connector design](knowledge/notes/acme-saas-imap-connector-design.md) — prior design covering TLS config and polling cadence
- [Sunrise-hotel IMAP retrospective](knowledge/notes/sunrise-hotel-imap-retrospective.md) — failure modes on a similar stack
- [Kickoff notes](inbox/meetings/_organized/2026-04-15-acme-saas-kickoff.md) — original commitment

## Request
Before the first discovery call, draft a specific yes/no checklist (IMAP enabled? external forwarding allowed? TLS version?) so we don't burn their IT window on open-ended questions.

## History
- 2026-04-17: Created from 2026-04-15 acme-saas kickoff. Connector design doc already exists from prior exploration.
```

Why this passes: Goal states a verifiable end-state; Background covers trigger, stakes, constraints, and a prior incident informing approach; Context links have role descriptors; Request is prescriptive but not a plan; History records provenance.

## Bad Example (anti-pattern)

```markdown
---
created: 2026-04-16T20:55+09:00
type: task
status: open
---

# Personalize onboarding by asking about interests upfront

## Goal

## Background
Empty journal entries come in as meaningless text. Ask interest questions at the start, generate a personal profile, then personalize the flow.

## Context
Friend test debrief::workspace/2026-04-13-X/006-debrief.md,Task brushup::workspace/2026-04-13-X/007-brushup.md

## Request

## History
```

What's wrong:

- No `source`, no `tags`, no `mentions` — executor can't locate the trigger or related entities
- Goal empty — executor has to guess what "done" means
- Background compressed to a sketch; loses the *why* (which friction? which users? how often?)
- Context uses the legacy `Title::path` inline format with no role descriptors
- Request / History empty — creator's intent and provenance are lost

## Subtasks

- Managed as checkboxes within the ticket body
- Promote to separate tickets if independent tracking is needed

## Creation Methods

1. AI suggestions during `/focus` (user approval required)
2. `rill task "title" --slug {slug}` CLI — creates `tasks/{slug}/_task.md`
3. `/distill` (interactive only)

Per-task artifacts (research notes, plans, decisions produced by /solve) are scaffolded inside the task directory with `rill mkfile tasks/{slug} --slug {description} --type {research|analysis|decision|progress|review}`.

## Duplicate Check

Check for duplicates against existing tickets before creating new ones (Evergreen principle for tasks/).

## After Completion

- Keep as `status: done`
- Move to knowledge/notes/ as `type: record` if appropriate

## In-Session Status Updates

When the user reports task completion, cancellation, or status changes during a session, **update the ticket file's frontmatter `status` immediately**.
