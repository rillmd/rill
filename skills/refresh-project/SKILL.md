---
model: sonnet
effort: low
name: refresh-project
description: Recompute the auto-maintained sections (`## Active Tasks`, `## Related Workspaces`) of `projects/{slug}/_project.md` via mention reverse-lookup, sorted by dependency-resolved priority. Idempotent. Use when refreshing a project's surface, or as a leaf invoked internally by `/project` and `/promote`.
gui:
  label: "/refresh-project"
  hint: "Recompute Active Tasks and Related Workspaces in _project.md"
  match:
    - "projects/*/_project.md"
  arg: slug
  order: 16
  mode: auto
---

# /refresh-project — Auto-section Refresh for Projects

**Conduct all conversation with the user — and write all generated output — in the language defined by `.claude/rules/personal-language.md`** (or the user's input language if that file is absent). Follow the language rules in full — exceptions and translation quality are defined in the Language Rules of `.claude/rules/rill-core.md` and the vault's `personal-*.md` overrides, never restated per skill. The English instructions below are for skill clarity, not for output style.

> **Tool references in this skill** (`Read`, `Edit`, `Grep`, `Glob`, `shell`) describe **intent**, not Claude-specific tool calls. Each harness should map them to its native equivalent — Claude Code uses its built-in tools as named; Codex CLI uses `apply_patch` / `--search` / shell as appropriate.

Recomputes the two auto-maintained sections of a project's main file (`projects/{slug}/_project.md`):

- `## Active Tasks` — tasks whose frontmatter contains `mentions: [..., projects/{slug}, ...]`, filtered to `status: open` / `waiting`, sorted by the dependency-resolved priority defined in `/project` (see "Dependency Resolution" below for the canonical algorithm)
- `## Related Workspaces` — workspaces whose frontmatter contains `mentions: [..., projects/{slug}, ...]`. Active workspaces are listed first (sorted by `updated` desc), then up to 20 most-recently-touched completed workspaces (also sorted by `updated` desc). Each entry carries an explicit `status:` marker so live vs past surfaces stay visually distinct

Other sections (Goal, Current Focus, Watch, Key Facts, Repository, See Also) are owned by different skills (see `.claude/rules/rill-projects.md` for the section-ownership table) and **must not be touched** by this skill.

## Arguments

$ARGUMENTS — one of the following:

- `{slug}` (e.g. `rill`, `acme-saas`) → Refresh the single project at `projects/{slug}/_project.md`
- `--all` → Refresh every project under `projects/*/_project.md` (processed sequentially, each under its own per-slug lock)
- Omitted → Ask the user which project to refresh, via the harness's question primitive. If invoked internally by another skill, the caller must pass an explicit `{slug}` or `--all`

## Procedure

### Phase 0: Input validation + lock acquisition

1. Resolve `{slug}` to `projects/{slug}/_project.md`. If the file does not exist:
   - List similar slugs via `Glob(projects/*)` and propose corrections
   - Exit with a one-line error (do not auto-create a project — that is `/project new`'s job)
2. Create a per-slug lock file at `.claude/state/refresh-project-{slug}.lock` (per-slug, not global — concurrent refresh of different projects is allowed)
   - If the lock already exists, poll for up to 30 seconds (1-second intervals)
   - If still present after the wait, log a warning and exit (leave the existing data stale rather than racing)
   - Create the lock atomically (`mkdir` semantics or `set -C` + redirect)

### Phase 1: Tasks reverse-lookup

1. Find all task tickets that mention this project:
   ```
   Grep(pattern="^mentions:.*projects/{slug}\b", path="tasks/", glob="**/_task.md", output_mode="files_with_matches")
   ```
   The trailing word boundary `\b` is important to avoid matching `projects/{slug}-extension` when the target is `{slug}`.
2. For each matched file, Read the frontmatter and extract:
   - `status`, `due`, `scheduled`, `depends-on`, `blocks` (frontmatter fields)
   - Task title (the body's first `# ` heading)
3. Filter to `status: open` or `status: waiting`. Drop `done`, `cancelled`, `someday`, `draft` (drafts are unapproved AI suggestions — they are not part of the project's executable surface yet).
4. Resolve dependency state:
   - A task is **unblocked** if every entry in its `depends-on` resolves to a task with `status: done` or `status: cancelled` (or if `depends-on` is absent/empty)
   - A task is **blocked** otherwise (including the case where a referenced dependency cannot be found — emit a broken-link warning but keep the task in the blocked bucket so it surfaces in `/project review`)
   - Detect `depends-on` cycles via DFS; tasks in a cycle are treated as blocked, and the cycle is annotated for `/project review` to surface
5. Sort the unblocked tasks by the priority levels P0–P4 defined in the `/project` skill (overdue `due` first → today's `scheduled` → upcoming `due` within 7 days → upcoming `due` 8–30 days → no date, newest first). Sort blocked tasks separately, by the same rules.

### Phase 2: Workspaces reverse-lookup

1. Find all workspaces that mention this project:
   ```
   Grep(pattern="^mentions:.*projects/{slug}\b", path="workspace/", glob="**/_workspace.md", output_mode="files_with_matches")
   ```
2. For each matched file, Read the frontmatter and extract `status`, `name`, `updated` (or `created` if `updated` is absent).
3. Bucket by the workspace's own `status` (the workspace enum `active | completed | on-hold | pilot | planning` — not the project status enum `planning | active | paused | done`):
   - **Active bucket**: `status: active`
   - **Completed bucket**: `status: completed` (these are the workspaces a `/close` has already produced a `_summary.md` for — typically the surface a `/promote` has already crystallised, so they retain provenance value)
   - **Drop**: any other status — the workspace enum's remaining values (`status: on-hold`, `status: planning`, `status: pilot`) and any stray project-vocabulary value (`status: paused`, `status: done`) that has leaked into a workspace file; not live, not historical-of-record
4. Sort each bucket by `updated` descending (most recently touched first).
5. Cap the Completed bucket at the 20 most-recently-touched entries (older history lives in `See Also`, plain Grep, or `/project review`).

### Phase 3: Section rewrite (atomic)

Rewrite `## Active Tasks` and `## Related Workspaces` in `projects/{slug}/_project.md`. Preserve every other section verbatim — including any text the user has manually added inside these two sections is **not** preserved (these are auto-managed; the section-ownership doctrine says manual edits here will be overwritten).

#### Format — `## Active Tasks`

```markdown
## Active Tasks

### Unblocked

- [ ] [{title}](../../tasks/{slug}/_task.md) — status: {status}{ / due: {due}}{ / scheduled: {scheduled}}

### Blocked

- [ ] [{title}](../../tasks/{slug}/_task.md) — status: {status} / waiting on: [{dep-title}](../../tasks/{dep-slug}/_task.md)
```

- If `Unblocked` is empty, omit the heading and write `_None — see Blocked below or `/project {slug} continue` to investigate._`
- If `Blocked` is empty, omit the heading
- If both are empty, write `_No active tasks. Use `rill task` or `/promote` to create one._`
- For each blocked task, list one representative blocker (the first unmet `depends-on` entry). Cycle annotations and broken-link warnings are deferred to `/project review`.

#### Format — `## Related Workspaces`

```markdown
## Related Workspaces

### Active

- [{name}](../../workspace/{id}/_workspace.md) — status: active / last updated: {updated:YYYY-MM-DD}

### Completed (most recent 20)

- [{name}](../../workspace/{id}/_workspace.md) — status: completed / last updated: {updated:YYYY-MM-DD}
```

- If `Active` is empty, omit the heading and write `_No active workspaces. Use `/focus <theme>` to start one._` under `## Related Workspaces`
- If `Completed` is empty, omit the heading entirely (do not write an empty-case marker — completed history is optional surface)
- If both are empty, emit only the active-empty-case line (no `## Related Workspaces` body otherwise)

#### Atomicity

The two sections must be rewritten as a single operation so that observers never see a half-written state:

1. Read the entire `_project.md`
2. Locate the byte ranges of `## Active Tasks` and `## Related Workspaces` (each section runs until the next `## ` heading or EOF)
3. Build the new content in memory: prefix (everything before `## Active Tasks`) + new `## Active Tasks` + middle (everything between the end of `## Active Tasks` and the start of `## Related Workspaces`) + new `## Related Workspaces` + suffix (everything after `## Related Workspaces`)
4. Write the new content to a tempfile in the same directory, then `mv` (rename) over the original — `mv` is atomic on the same filesystem
5. If either section is missing from the file (e.g. a project created before this skill existed), insert it at the standard position defined in `.claude/rules/rill-projects.md` body structure (Goal → Current Focus → Active Tasks → Related Workspaces → Watch → Key Facts → ...)

### Phase 4: Lock release

1. Remove `.claude/state/refresh-project-{slug}.lock`
2. Exit silently on success. Print a one-line summary: `Refreshed projects/{slug}/_project.md — {N} active tasks ({M} unblocked, {K} blocked), {W} active workspaces.`

### `--all` mode

When invoked with `--all`:

1. `Glob(projects/*/_project.md)` to enumerate all projects
2. For each, run Phases 0–4 sequentially (per-slug locks prevent races with any concurrent `/refresh-project {slug}` invocation)
3. Print a one-line per-project summary, then a final aggregate count

## Dependency Resolution

The unblocked-vs-blocked judgment and the priority ordering are defined canonically in the `/project` skill (`/project` mode-shared algorithm). This skill applies the same algorithm so that `/project` can rely on the file content directly without recomputing.

- **Unblocked**: all `depends-on` entries resolve to tasks with `status: done` or `status: cancelled`
- **Broken link**: a `depends-on` entry whose target `tasks/{slug}/_task.md` does not exist → treat as blocked, warn in `/project review`
- **Cycle**: `depends-on` chain forming a cycle (A → B → A) → all members treated as blocked, surfaced in `/project review`
- **Priority** (used only to order the Unblocked list; blocked tasks are listed by the same rule but separately):
  - P0: `due` is today or overdue (oldest overdue first)
  - P1: `scheduled` is today or past
  - P2: `due` within next 7 days (closest first)
  - P3: `due` within next 8–30 days
  - P4: no `due` / no `scheduled` (newest `created` first)

## Idempotency

Running this skill twice in a row produces identical file content (modulo the side effect that the second run leaves the lock briefly held during execution). The function depends only on:

- The set of files matching the mention grep
- Each matched file's frontmatter (`status`, `due`, `scheduled`, `depends-on`, `mentions`, `updated`)
- Each task's body `# ` heading

There are no time-based or random inputs. Repeat invocations are safe and cheap.

## Error handling

| Situation | Behavior |
|---|---|
| `projects/{slug}/_project.md` does not exist | Propose similar slugs, exit with one-line error. Do not auto-create |
| Lock acquisition fails after 30 s wait | Warn and exit. Leave existing data stale (better than racing the other writer) |
| Grep returns zero matches | Write the empty-case template into the section. This is a valid state |
| A referenced `depends-on` task file is missing | Treat as broken link → blocked. Do not fail the run; defer the warning to `/project review` |
| `depends-on` cycle detected | Mark all members as blocked. Do not fail the run |
| Frontmatter parse error in a matched file | Skip that file with a one-line warning. Do not fail the entire run |
| `_project.md` has neither `## Active Tasks` nor `## Related Workspaces` | Insert both sections at the standard positions defined in `.claude/rules/rill-projects.md` |
| `_project.md` is missing required frontmatter (no `type: project`) | Warn and skip (this is a structural problem better reported than papered over) |

## Invocation

Typical callers:

- `/project {slug} status|continue|review` — calls `/refresh-project {slug}` at the start so subsequent reads see fresh data
- `/promote {workspace-id}` — calls `/refresh-project {target-slug}` after appending a workspace reference, so the project's surface reflects the promotion
- Direct user invocation: `/refresh-project rill` or `/refresh-project --all`
- Future automation (cron-style): periodic `/refresh-project --all` to keep the surface fresh without manual prompting

This skill does not invoke other skills. It is a pure read-grep-write leaf.

## Rules

- **Never modify** `## Goal` / `## Current Focus` / `## Watch` / `## Key Facts` / `## Repository` / `## See Also` (different section owners per `.claude/rules/rill-projects.md`)
- **Never modify** `inbox/` source files (read-only)
- **Always use relative Markdown links** `[display name](../../relative-path)` in the body. Backtick-only ID references are forbidden
- **Per-slug lock**, not global — concurrent refresh of different projects must be allowed
- **Atomic write** via tempfile + `mv` so partial states never become visible
- The `--all` mode is sequential (one slug at a time); a future enhancement could parallelise it but is out of scope here

## See also

- `.claude/rules/rill-projects.md` — section ownership table, body structure
- `.claude/rules/rill-tasks.md` — `depends-on` / `blocks` frontmatter schema
- `/project` skill — uses this skill as its first phase
- `/promote` skill — calls this skill after appending a workspace reference
