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
    ├── _summary.md     # written by /close Stage 2 (analysis)
    ├── _distill.md     # distill record — written only by `rill workspace`
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
status: active              # active | distill-pending | completed (written only by `rill workspace`)
icon: "🔭"                   # one emoji, chosen at creation (GUI identity)
origin: inbox/journal/2026-02-13-1950.md
tags: [rill]
mentions: [projects/rill]
client: Client Name          # optional
---
```

### Status Values and Transitions

| Value | Meaning |
|---|---|
| `active` | Being worked on. A workspace waiting on something stays `active` with `snooze-until: YYYY-MM-DD` and `snooze-reason` (excluded from idle handling until that date) |
| `distill-pending` | Closed; knowledge distillation not yet verified. The set of these workspaces is the distill queue |
| `completed` | Closed, and the distill record (`_distill.md`) passed `rill workspace verify` |

Every change goes through a `rill workspace` subcommand, which refuses any other transition:

| Transition | From | To | Used by |
|---|---|---|---|
| `close` | `active` | `distill-pending` | `/close` Stage 1 |
| `reopen` | `distill-pending`, `completed` | `active` | `/focus` resume |
| `complete` | `distill-pending` | `completed` | `/close` Stage 2 (interactive) or the distill job wrapper — only after `verify` passes |
| `requeue` | `completed` | `distill-pending` | re-distillation, migration (`--backfill`) |
| `snooze` / `unsnooze` | `active` | `active` | waiting with a date |

- **Never write `status`, `closed`, `distilled`, `distill-*`, or `snooze-*` with an editor, and never edit `_distill.md`.** Only `rill workspace complete` writes `completed`, after it verifies that the analysis finished, every coverage file was accounted for, every candidate has exactly one outcome, the referenced notes exist, and `_summary.md` exists. A failed or interrupted distillation therefore leaves the workspace `distill-pending`, and the next run resumes it.
- Every workspace is distilled; closing never skips it. `rill workspace check` (no AI) reports violations for unattended jobs.
- Legacy `on-hold` is accepted only as the source of `close` / `reopen` until migrated; `pilot` and `planning` are retired.

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

### HTML Artifacts

Workspace HTML follows [rill-html-output.md](rill-html-output.md): mocks and diagrams are committed primary artifacts (the HTML is the deliverable, no MD twin); decision digests and completion handbooks are derived views generated into `workspace/{id}/.view/` (gitignored, regenerable). On resume the AI reads `.md` files only — derived HTML is skipped; an HTML-canonical artifact (mock, diagram) is read only when it is itself the resumed work's target (rill-html-output.md principle 3).

### Updating `_workspace.md`

At each milestone: add new artifacts to "Related Files (MOC)", update checkboxes, append "Session History", update "Next Steps".

## Handling Existing Artifacts

Once created, artifacts are generally not modified — additions / corrections go in new files. `NNN-` numbers increase chronologically.

## Backward Compatibility

Older workspaces may contain `_session.md` or `_project.md` instead of `_workspace.md`. Treat as meta files (do not rename during Phase 3).
