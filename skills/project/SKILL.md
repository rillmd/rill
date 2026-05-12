---
name: project
description: Operate on a project execution hub via five modes — `status` (one-project overview), `continue` (next unblocked task → /solve), `review` (dependency-tree audit), `list` (cross-project), `new` (create). Each mode auto-runs `/refresh-project` first. Use when the user wants to check a project, pick the next task, or see what's actionable across projects.
gui:
  label: "/project"
  hint: "Open project status, continue, review, or list"
  match:
    - "projects/*/_project.md"
  arg: slug
  order: 15
  mode: live
---

# /project — Project Execution Hub

**Conduct ALL conversation with the user in the language defined by `.claude/rules/personal-language.md`** (or the user's input language if absent). The English instructions below are for skill clarity, not for output style. Exceptions: code blocks, slash commands, technical terms (Markdown, frontmatter, etc.).

> **Tool references in this skill** (`Read`, `Edit`, `Grep`, `Glob`, `AskUserQuestion`, `shell`) describe **intent**, not Claude-specific tool calls. Each harness should map them to its native equivalent — Claude Code uses its built-in tools as named; Codex CLI uses `apply_patch` / its own question primitive / shell as appropriate.

Operates on a Rill project — the execution-hub unit that bundles multiple tasks (see ADR-080, `.claude/rules/rill-projects.md`). Five modes:

| Mode | Purpose | Typical entry |
|---|---|---|
| `status` (default for `{slug}` alone) | One-screen overview of one project's current state | `/project rill` |
| `continue` | Pick the next unblocked task and offer to chain into `/solve` | `/project rill continue` |
| `review` | Structural audit of dependency tree, broken links, cycles, stale tasks | `/project rill review` |
| `list` (default when no arg) | Cross-project overview (every `status: active` project at once) | `/project` or `/project list` |
| `new` | Create a new project under `projects/{slug}/_project.md` | `/project new acme-saas` |

`/project` (execution surface, convergent) is the counterpart of `/focus` (workspace surface, divergent). The bridge between them is `/promote`.

## Arguments

```
/project                              # → list mode
/project list [--status=active|planning|paused|done]
/project {slug}                       # → status mode
/project {slug} status                # → status mode (explicit)
/project {slug} continue              # → continue mode
/project {slug} review                # → review mode
/project new {slug}                   # → new mode
```

### Argument parsing rules

| Input | Mode |
|---|---|
| (empty) or `list` | `list` |
| `{slug}` only | `status` |
| `{slug} {mode-keyword}` | the named mode |
| `new {slug}` | `new` |
| `{slug}/_project.md` or a path ending in `_project.md` | extract `{slug}` from the path → `status` |

`{slug}` is the directory name under `projects/`. The corresponding file is `projects/{slug}/_project.md`.

## Procedure

### Phase 0: Project resolution (all modes except `list` and `new`)

1. If `projects/{slug}/_project.md` does not exist:
   - `Glob(projects/*)` to enumerate existing slugs, suggest the closest matches (Levenshtein or simple substring)
   - Ask via the harness's question primitive: "No project named `{slug}`. Did you mean `{candidate1}` / `{candidate2}` / create a new one?"
   - On "create new", branch to `new` mode
   - On "no", exit
2. Otherwise read the file's frontmatter (`name`, `status`, `goal`, `paused_until` if present)

### Phase 1: Refresh (`status` / `continue` / `review` / `list`)

Invoke `/refresh-project` to bring auto-sections up to date before reading them:

- Single-project modes (`status` / `continue` / `review`): invoke `/refresh-project {slug}`
- Cross-project mode (`list`): invoke `/refresh-project --all`

Use the harness's skill-invocation mechanism. Wait for completion (refresh writes synchronously into `_project.md` and the next steps read those sections).

`new` mode skips refresh — the project does not exist yet.

### Phase 2: Mode-specific procedure

The mode-specific procedure runs after Phase 1 completes.

## Mode 1 — `status` (default)

### Goal

Render one project's current state in one screen.

### Procedure

1. Read the freshly-refreshed `projects/{slug}/_project.md`
2. Extract:
   - `name` and `status` (frontmatter) — show `paused_until` if `status: paused`
   - `## Goal` (body — keep the bullet list)
   - `## Current Focus` (body — show as-is, typically 1–3 paragraphs)
   - `## Active Tasks → ### Unblocked` (the auto-section) — take the top 3 in priority order
   - `## Active Tasks → ### Blocked` — count only (full list belongs in `review`)
   - `## Related Workspaces` — top 3 by `updated` descending
   - `## Key Facts` — last 5 only (full list is for `review`)
3. Render in this template:

   ```markdown
   # Project: {name} (status: {status}{ — paused until {paused_until}})

   ## Goal
   {body bullets}

   ## Current state
   - Active tasks: {N} total ({U} unblocked, {B} blocked)
   - Active workspaces: {W}
   - Last refreshed: {now in ISO}

   ## Next actionable tasks (top 3 by priority)
   1. [{title}](../../tasks/{slug}/_task.md) — {due/scheduled annotation}{ ★ if overdue}
   2. ...
   3. ...

   ## Related workspaces
   - [{name}](../../workspace/{id}/_workspace.md) — status: {s}, last updated {YYYY-MM-DD}
   - ...

   ## Recent Key Facts (latest 5)
   - {fact 1}
   - ...

   _Full Key Facts in [_project.md](./_project.md)._
   ```

4. Offer a follow-up choice via the harness's question primitive:
   - "Solve task 1 with /solve" → chain into `/solve {top-1-slug}`
   - "Open `review` mode" → run mode 3
   - "Back to `list`" → run mode 4
   - "Exit"

### Exit

Run the user's chosen follow-up (chain, mode change, or exit).

## Mode 2 — `continue`

### Goal

Pick the single highest-priority unblocked task and offer to chain into `/solve`. Optionally loop (next task after the first finishes).

### Procedure

1. Read the freshly-refreshed `_project.md`'s `## Active Tasks → ### Unblocked`
2. If the list is empty:
   - Read `### Blocked` and list the unmet blockers (each blocked task with its first unmet `depends-on`)
   - Report: "No unblocked tasks. Blocked on: ... Use `/project {slug} review` to inspect or `rill task` to add a new task."
   - Exit
3. Pick the first entry (already sorted P0→P4 by `/refresh-project`)
4. Display:
   ```
   Next task: [{title}](../../tasks/{top-slug}/_task.md) — {priority annotation}
   ```
   Then via the harness's question primitive, offer:
   - "Yes, run /solve" → chain into `/solve {top-slug}`
   - "Pick a different task" → list the next 3 candidates and ask which one
   - "Cancel"
5. After `/solve` returns:
   - If `/solve` completed (`status: done` written), re-enter `/project {slug} continue` once (loop). Recursion depth is 1; subsequent loops require the user to invoke `/project {slug} continue` again. This keeps the conversation interactive rather than runaway-autonomous
   - If `/solve` stopped at a breakpoint or returned with `status: open`, report the stopping reason and exit without re-entering

### Safety

- Always ask before chaining `/solve` — there is no auto-pilot mode
- The 1-step recursion lets the user clear several tasks in a session without re-typing; deeper autonomy belongs to a future `/solve --autonomous` if introduced

## Mode 3 — `review`

### Goal

Structural audit of all tasks under this project — dependency tree, broken links, cycles, stale items, candidates for archive.

### Procedure

1. Find every task with `mentions: [..., projects/{slug}, ...]`, including all statuses (`open`, `waiting`, `someday`, `draft`, `done`, `cancelled`). The auto-section in `_project.md` is filtered to open/waiting; for `review` we need the broader set
2. Build the dependency DAG from `depends-on` edges
3. Detect:
   - **Cycles** (DFS): a `depends-on` chain forming a cycle is a structural error. Surface every member
   - **Broken `depends-on`**: a target `tasks/{slug}/_task.md` that does not exist on disk
   - **Stale `someday`**: tasks with `status: someday` whose `created` is more than 90 days old
   - **Done in past 30 days**: archive-candidate context
4. Group by status and render:

   ```markdown
   # Project: {name} — Review

   ## Dependency tree (open/waiting)
   - [{title}](../../tasks/{slug}/_task.md) — done ✓
     - [{title}](../../tasks/{slug}/_task.md) — open ★ unblocked
       - [{title}](../../tasks/{slug}/_task.md) — waiting (depends on the above)

   ## By status

   ### Open (unblocked) — {N}
   - ...

   ### Open (blocked) — {M}
   - [{title}](../../tasks/{slug}/_task.md) — waiting on: [{dep-title}](../../tasks/{dep-slug}/_task.md)

   ### Waiting (external) — {K}

   ### Someday — {L}

   ### Done (past 30 days) — {P}

   ## Inconsistencies
   - [{title}](../../tasks/{slug}/_task.md) — `depends-on: [tasks/foo]` but that task is `status: cancelled` (dependency satisfied — treat as unblocked, just noting)
   - [{title}](../../tasks/{slug}/_task.md) — `depends-on: [tasks/bar]` but `tasks/bar/_task.md` does not exist (broken link)
   - Cycle: [{a}] → [{b}] → [{a}]

   ## Suggested actions
   - Update broken `depends-on` links?
   - Break the cycle between [{a}] and [{b}]?
   - Archive stale `someday` items (90+ days old)?
   ```

5. Offer follow-ups via the harness's question primitive: edit a `depends-on`, archive someday items, return to `status`, or exit

### Exit

Run the user's chosen follow-up (edit, archive, mode change, exit).

## Mode 4 — `list`

### Goal

Cross-project overview — every `status: active` project at once (with optional filter for other statuses).

### Procedure

1. `Glob(projects/*/_project.md)` to enumerate all projects
2. Read each one's frontmatter (`name`, `status`, `paused_until`, `goal`)
3. After Phase 1 refresh (`--all`), each `_project.md` already has fresh `## Active Tasks → ### Unblocked`; read the top entry from each
4. Apply the filter:
   - Default: `--status=active`
   - `--status=planning|paused|done` to override
   - `--status=all` to list everything
5. Render:

   ```markdown
   # Active Projects ({N})

   ## {name 1}
   - Goal: {first goal bullet}
   - Next: [{top-unblocked-title}](../../tasks/{slug}/_task.md) — {due/scheduled annotation}
   - Active tasks: {total} ({unblocked} unblocked)
   - → `/project {slug}` for details

   ## {name 2}
   ...

   ## Paused ({P}) (only if --status=paused or --status=all)
   - [{name}](../../projects/{slug}/_project.md) — paused until {date}
   ```

6. Offer a follow-up via the harness's question primitive: pick a project to enter `status` mode, or exit

### Exit

Branch to `status` mode for the chosen project, or exit.

## Mode 5 — `new`

### Goal

Create a new `projects/{slug}/_project.md` interactively.

### Procedure

1. Validate the slug:
   - Reject if not kebab-case
   - Reject if `projects/{slug}/` already exists
2. Ask the user (via the harness's question primitive) for the project's:
   - Goal (one-line completion condition — required, per ADR-080's DoD-required policy)
   - Initial status: `planning` (default) or `active`
3. Run:
   ```
   rill mkfile projects --slug {slug} --type project \
     --field 'name={slug-as-title-case}' \
     --field 'status={chosen}' \
     --field 'goal={goal}'
   ```
   `rill mkfile` writes the frontmatter and a body scaffold per `.claude/rules/rill-projects.md` (empty `## Active Tasks`, `## Related Workspaces`, `## Watch`, `## Key Facts`).
4. Edit the body to:
   - Add the user-provided Goal as the first bullet under `## Goal`
   - Leave Active Tasks / Related Workspaces sections empty (they will be filled by `/refresh-project` once tasks/workspaces mention the new project)
5. Report:
   ```
   Project [{name}](../../projects/{slug}/_project.md) created.
   - Goal: {goal}
   - Status: {status}
   - Path: projects/{slug}/_project.md

   Next:
   - Create a task with `rill task` and tag it `mentions: [projects/{slug}]`
   - Crystallise from a closed workspace with `/promote {workspace-id}`
   - Run `/project {slug}` to view status (will be empty until tasks/workspaces are linked)
   ```

### Exit

Done. Do not auto-chain.

## Dependency Resolution Algorithm

This algorithm is the canonical definition for both this skill and `/refresh-project` (which references it).

### Unblocked judgment

A task is **unblocked** iff every entry in its frontmatter `depends-on` resolves to a task with `status: done` or `status: cancelled` (or `depends-on` is absent/empty).

```
def is_unblocked(task):
    for dep_slug in task.frontmatter.get("depends-on", []):
        dep = read_task(dep_slug)
        if dep is None:                    # broken link
            return False                   # treat as blocked, surface in review
        if dep.status not in {"done", "cancelled"}:
            return False
    return True
```

### Priority order (for the Unblocked list)

```
P0: due is today OR overdue   → oldest overdue first
P1: scheduled is today OR past → oldest first
P2: due within next 7 days     → soonest first
P3: due within 8–30 days       → soonest first
P4: no due / no scheduled      → newest created first
```

Apply P0 first; ties within a tier fall through to the tie-breaker (oldest / soonest / newest as labelled).

### Cycle detection

DFS over the `depends-on` edge set. Tasks participating in any cycle are treated as blocked. The cycle members are recorded for `review` mode to surface explicitly.

### Broken-link handling

A `depends-on` entry whose target `tasks/{slug}/_task.md` is not on disk → the depending task is treated as blocked. The broken link is recorded for `review` mode.

## Coordination with other skills

### `/refresh-project`

Called at the top of every mode except `new` (single-slug or `--all` depending on mode). Synchronous wait. See the `/refresh-project` SKILL.md for behaviour.

### `/solve`

`continue` mode chains into `/solve {top-slug}`. Recursion depth is 1 after `/solve` returns successfully — the loop is intentionally finite to keep the conversation steered by the user.

### `/promote`

`/promote` may invoke `/project new {slug}` when crystallising a workspace into a project that does not yet exist. Otherwise `/project` does not call `/promote`.

### `/close`

No direct invocation. `/close` may chain to `/promote` (see `/close` Phase 0); `/promote` then enters `/project new` if needed.

### `/briefing`

Reads `knowledge/self/current-state.md` and may include project-level next-actionable tasks. Information overlap with `/project list` is fine — different surfaces (briefing = daily, project list = on-demand).

## Error handling

| Situation | Behavior |
|---|---|
| Slug does not exist (any mode) | Propose similar slugs + offer `new` mode |
| `_project.md` frontmatter is malformed | Print a warning, fall back to filename slug, continue with empty status |
| Active Tasks section is empty (project has zero tasks) | Display "No tasks yet. Use `rill task` or `/promote` to link tasks to this project." |
| All tasks are `done` | Display "All tasks complete." Offer `/project {slug} complete` (future) to generate `_summary.md` |
| Cycle detected | `status` / `continue` mode skip cycle members; `review` mode surfaces them |
| `/refresh-project` lock cannot be acquired (timeout) | Continue with the existing stale data — print a one-line warning so the user knows |
| `new` mode collides with an existing slug | Reject and exit; do not overwrite |

## Rules

- **Always invoke `/refresh-project` first** (except `new` mode). The auto-section trust contract depends on this
- **Never modify** `## Goal` / `## Current Focus` / `## Watch` / `## Key Facts` / `## See Also` from this skill — those have separate owners (see `.claude/rules/rill-projects.md`)
- Always use Markdown links `[display name](relative-path)` for in-body file references. Backtick-only ID references are forbidden
- The recursion in `continue` mode is bounded at depth 1; do not auto-loop further
- `new` mode requires a Goal (ADR-080 DoD-required policy); reject silent creation of empty projects

## See also

- `.claude/rules/rill-projects.md` — body structure, section ownership, state values
- `.claude/rules/rill-tasks.md` — `depends-on` / `blocks` schema
- `/refresh-project` skill — auto-section computation
- `/promote` skill — workspace → project crystallisation
- `/solve` skill — task execution (chain target of `continue` mode)
- `/focus` skill — workspace counterpart (divergent surface)
