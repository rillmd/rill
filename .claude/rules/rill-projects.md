# Project Rules — Rill

`projects/` is the **execution hub layer** — management unit for initiatives bundling multiple tasks (ADR-080).

## Structure

```
projects/
└── {slug}/
    ├── _project.md            # meta + state + auto-generated sections
    ├── _summary.md            # generated on completion (optional)
    └── NNN-description.md     # optional artifacts (chronological)
```

Directory name: `{slug}` (kebab-case). Examples: `projects/rill/_project.md`, `projects/acme-saas/_project.md`.

## Frontmatter

```yaml
---
created: 2026-05-12T...         # auto-assigned by rill mkfile
type: project
id: rill                        # required, matches directory name
name: Rill                      # required, display name
status: active                  # required: planning | active | paused | done
goal: Personal PKM OSS release  # one-line version for GUI list (optional)
paused_until: 2026-07-01        # optional when status: paused
tags: [rill]
mentions: [orgs/rillmd]
---
```

Required: `type: project`, `id`, `name`, `status`.

### State Values

- `planning`: scope being shaped
- `active`: tasks in progress
- `paused`: temporarily paused (`paused_until` may indicate resume target)
- `done`: DoD met

## Body Structure

```markdown
# {Project Name}

{1-2 paragraph overview}

## Goal
- {Completion condition (DoD), verifiable end-state}

## Current Focus
{Free-form 1-3 paragraphs}

## Active Tasks
- [ ] [task title](../../tasks/{slug}/_task.md) — status / due / depends-on

## Related Workspaces
- [WS name](../../workspace/{id}/_workspace.md) — status / last updated

## Watch
### Competitors
### Keywords

## Key Facts
- (up to 20, overflow → knowledge/notes/)

## Repository (optional)
- `repo-name` — purpose. `~/path`

## See Also
- (manual links not captured by auto-generated sections)
```

## Section Ownership

| Section | Owner | Update timing |
|---|---|---|
| Goal | `/promote` | At creation and on scope changes |
| Current Focus | `/distill` profile-agent | Weekly |
| Active Tasks | `/refresh-project` | Before `/project` invocation |
| Related Workspaces | `/refresh-project` | Same as above |
| Watch | `/distill` knowledge-agent | Accumulated from research |
| Key Facts | `/distill` knowledge-agent | Accumulated, moveOut at 20 cap |
| Repository | bootstrap + manual | Rare |
| See Also | Manual | As needed |

Concurrent writes are guarded by skill-level locks (`.claude/state/{skill-name}.lock`). Section-level locks not required.

## Artifacts (optional)

Under `projects/{slug}/`, optional `NNN-{description}.md` artifacts may be placed when needed (snapshots, decisions, reviews, plans). When skills generate them, assign `type:` automatically.

## Completion Summary — `_summary.md`

When a project transitions to `status: done`, generate `_summary.md` (same convention as workspace's). Retrospective + distillation candidates.

## Relationship with Workspaces

One project ↔ N workspaces (ADR-042). Workspaces = divergent thinking; projects = execution. Results crystallize via `/promote`.

## Relationship with Tasks

Tasks live in `tasks/{slug}/_task.md` (ADR-076, no physical move). Linked virtually via `mentions: [projects/{id}]`. The `Active Tasks` section auto-generates by mention reverse-lookup. Task dependencies use frontmatter `depends-on` / `blocks` (see rill-tasks.md).

## Completion Criteria (DoD) Required

Every project **must have DoD**. Write a verifiable end-state in Goal — ensures the project surface meets the granularity needed for future `/solve {project}` automation (supersedes ADR-049).

## mention Namespace

`mentions: [projects/{id}]`. Resolution: `projects/{id}/_project.md` (changed from old `knowledge/projects/{id}.md`).

## Creation

```bash
rill mkfile projects --slug rill --type project
```

Or via `/promote` from a workspace.

## After Completion

Remain at `status: done`. Generate `_summary.md`. Active Tasks empties automatically. No file move on archive — directory stays with `status: done`.
