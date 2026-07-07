---
name: project
description: Operate on a project execution hub via six modes — `status` (one-project overview), `continue` (next unblocked task → /solve), `run` (policy-gated autonomous loop that solves tasks until a stop condition), `review` (dependency-tree audit), `list` (cross-project), `new` (create). Each mode auto-runs `/refresh-project` first. Use when the user wants to check a project, pick the next task, autonomously work a whole project, or see what's actionable across projects.
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

**Conduct ALL conversation with the user in the language defined by `.claude/rules/personal-language.md`** (or the user's input language if absent). The English instructions below are for skill clarity, not for output style. Exceptions (only): tokens inside backticks or code blocks, proper nouns, ASCII acronyms.

> **Tool references in this skill** (`Read`, `Edit`, `Grep`, `Glob`, `AskUserQuestion`, `shell`) describe **intent**, not Claude-specific tool calls. Each harness should map them to its native equivalent — Claude Code uses its built-in tools as named; Codex CLI uses `apply_patch` / its own question primitive / shell as appropriate.

Operates on a Rill project — the execution-hub unit that bundles multiple tasks (see ADR-080, `.claude/rules/rill-projects.md`). Six modes:

| Mode | Purpose | Typical entry |
|---|---|---|
| `status` (default for `{slug}` alone) | One-screen overview of one project's current state | `/project rill` |
| `continue` | Pick the next unblocked task and offer to chain into `/solve` (user-steered, 1-step) | `/project rill continue` |
| `run` | **Policy-gated autonomous loop** — solve unblocked tasks one after another until a stop condition (ADR-082) | `/project rill run` |
| `review` | Structural audit of dependency tree, broken links, cycles, stale tasks | `/project rill review` |
| `list` (default when no arg) | Cross-project overview (every `status: active` project at once) | `/project` or `/project list` |
| `new` | Create a new project under `projects/{slug}/_project.md` | `/project new acme-saas` |

`continue` and `run` are siblings: `continue` is user-steered (asks before each task, recursion depth 1), `run` is policy-gated and autonomous (approve a policy once, then it loops). `run` is the project-level counterpart of `/solve`'s autonomous mode.

`/project` (execution surface, convergent) is the counterpart of `/focus` (workspace surface, divergent). The bridge between them is `/promote`.

## Arguments

```
/project                              # → list mode
/project list [--status=active|planning|paused|done]
/project {slug}                       # → status mode
/project {slug} status                # → status mode (explicit)
/project {slug} continue              # → continue mode
/project {slug} run [--max-tasks N] [--max-hours H] [--lane A|B|mixed]   # → run mode
/project {slug} review                # → review mode
/project new {slug}                   # → new mode
```

### Argument parsing rules

| Input | Mode |
|---|---|
| (empty) or `list` | `list` |
| `{slug}` only | `status` |
| `{slug} {mode-keyword}` | the named mode (`status` / `continue` / `run` / `review`) |
| `{slug} run [flags]` | `run` (flags parsed: `--max-tasks`, `--max-hours`, `--lane`) |
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
2. Otherwise read the file's frontmatter (`name`, `description`, `status`, `paused_until` if present)

### Phase 1: Refresh (`status` / `continue` / `review` / `list`)

Invoke `/refresh-project` to bring auto-sections up to date before reading them:

- Single-project modes (`status` / `continue` / `review`): invoke `/refresh-project {slug}`
- `run` mode: refresh happens inside the loop (Step 2.1) before each task; the Phase 1 refresh is still run once up front so the policy proposal (Step 1) sees current task counts
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
2. For each project, read both
   - frontmatter (`name`, `description`, `status`, `paused_until`)
   - body section `## Goal` (the first bullet under that heading is the
     canonical goal text used by the list render below). `## Goal` lives
     in the body because `goal:` was retired from the schema when
     `description` became required
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
   - **Name** — a descriptive one-line title (~30–60 chars). Not the slug
     in title case. The answer to "what is this project, in one phrase".
     Surfaces in the GUI project list and is read by task-classification
     skills (`/distill`, `/focus`, `_task:create-agent`) when picking
     which `projects/{slug}` a candidate task belongs to.
   - **Description** — 1–3 sentences (~120–300 chars) covering the
     project's context, scope, and reason. Surfaces in the GUI card
     preview row and complements `name` as classification input.
   - **Goal** — one-line completion condition (DoD), per ADR-080's
     DoD-required policy. Goes in the body, not in frontmatter.
   - **Initial status** — `planning` (default) or `active`.
3. Run `rill mkfile`. The free-text `name` / `description` answers can
   contain shell metacharacters (apostrophe, `$`, backtick) and YAML-
   reserved punctuation (colon, hash). Build the invocation so the
   string survives both layers — single-quote the `--field` args, and
   if the user's input contains a `'`, replace each one with the POSIX
   four-character sequence `'\''` before substituting:

   ```
   rill mkfile projects --slug {slug} --type project \
     --field 'name={name-with-apostrophes-escaped-as-quote-backslash-quote-quote}' \
     --field 'description={description-with-apostrophes-escaped-as-quote-backslash-quote-quote}' \
     --field 'status={chosen}'
   ```

   `rill mkfile` writes the frontmatter (now requires both `name` and
   `description` via --field; see `bin/rill`) and a body scaffold per
   `.claude/rules/rill-projects.md` (empty `## Active Tasks`,
   `## Related Workspaces`, `## Watch`, `## Key Facts`). YAML quoting of
   the values is handled inside `rill mkfile`, so no further YAML escape
   is needed at the caller. Do **not** pass a `goal` field — that schema
   entry was retired when `description` became required; Goal lives in
   the body.
4. Edit the body to:
   - Add the user-provided Goal as the first bullet under `## Goal`
   - Leave Active Tasks / Related Workspaces sections empty (they will be filled by `/refresh-project` once tasks/workspaces mention the new project)
5. Report:
   ```
   Project [{name}](../../projects/{slug}/_project.md) created.
   - Name: {name}
   - Description: {description}
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

## Mode 6 — `run` (policy-gated autonomous loop)

### Goal

Solve a project's unblocked tasks one after another, autonomously, under a policy the user approves **once** — the project-level lift of `/solve`'s per-task Plan gate (ADR-082 §8). The loop stops on a declared stop condition, then reports what was done and what needs the user's decision.

This is the realization of "the human assigns tasks to a project; Claude works the project down." Governed by `.claude/rules/rill-autonomous-execution.md` §8–§11.

### Procedure

#### Step 0 — Acquire the GLOBAL runner lock (one runner total, not one per project)

All Lane A work — every project's tasks — shares the **one** main worktree, where `rill push` can swallow a concurrent session's uncommitted changes (`rill-autonomous-execution.md` §11). A per-*project* lock would not protect this: two runners on *different* projects still race on the same main worktree. So until explicit-path staging lands, the first implementation allows **one runner across all projects** — a single global lock, not slug-scoped.

Acquire it **atomically** — a separate "check then create" lets two near-simultaneous runs both observe no lock and both proceed. Use `mkdir` (atomic create-or-fail on POSIX), not existence-check + write:

```bash
LOCK=.claude/state/project-run.lock                   # GLOBAL — no slug; one runner across all projects
mkdir -p "$(dirname "$LOCK")"                          # ensure .claude/state/ exists (the lock dir itself stays a bare mkdir)
# Self-protect: ensure the lock is git-ignored so `rill push` (which stages with
# `git add -A`) cannot commit it. Independent of the vault's own .gitignore.
grep -qxF '*.lock' .claude/state/.gitignore 2>/dev/null || printf '%s\n' '*.lock' >> .claude/state/.gitignore
acquire() { mkdir "$LOCK" 2>/dev/null; }              # atomic create-or-fail
if ! acquire; then
  # held — reclaim only if stale, then retry exactly once
  if [ -d "$LOCK" ] && [ "$(( $(date +%s) - $(sed -n 1p "$LOCK/owner" 2>/dev/null || echo 0) ))" -gt "{stale-seconds}" ]; then
    rm -f "$LOCK/owner"; rmdir "$LOCK" 2>/dev/null    # owner is a regular file → rm, not rmdir
    acquire || { echo "Lock contended after stale reclaim — another runner just took it. Exit."; exit 0; }
  else
    echo "A project runner is already active (project {held-slug}, started {ts}). One runner at a time — refusing to start a second."; exit 0
  fi
fi
# acquired — record holder (slug + start time + session) for the stale check + reporting
printf '%s\n%s\n%s\n' "$(date +%s)" "project:{slug}" "session:{session-marker}" > "$LOCK/owner"
```

`.claude/state/` must be git-ignored (the lock is runtime state, never committed). Stale threshold: comfortably above `--max-hours` (e.g. max-hours + 1h). Release the lock on **every** exit path — normal stop, error, user abort — with `rm -f "$LOCK/owner"; rmdir "$LOCK"` (the owner metadata is a regular file, so `rmdir` alone cannot empty the directory). If the harness offers `flock`/`ln -s` that is equally atomic; the invariant is "create-or-fail in one step", never check-then-create.

#### Step 1 — Approve the run (once), in plain language

This is the **only** synchronous human gate, so it has to be one the user can actually judge. **Write it by consequence, not by mechanism.** The reader has not read the ADR. Do **not** put internal labels in what the user sees — no "Lane A/B", "Tier 2", "entry filter", "stop-condition trio", "human-decision queue", "Codex PASS", "Completion criteria mechanically verifiable". Translate each into what will actually happen. Use the **user's language**. Fill in **concrete values** — the real task titles, the real repositories, the real numbers — never `{placeholder}` text.

Cover exactly these four things, in this order:

1. **What I'll work on** — the actual unblocked tasks I'll take, in order, by their real titles. Add one line: tasks too thin to run, or whose "done" I can't check, I'll set aside for you rather than guess at.
2. **What I'll do without asking** — in plain terms, e.g. "write research and design notes; make code changes on a branch, run an automated review of them, and merge once it's clean." Name the **real repositories** involved.
3. **What I'll always stop for** — and set aside in a list for you instead of doing: sending anything to another person (email/chat), anything that affects the real world, publishing to a public repository, a design fork I can't decide on my own, or needing a fact only you have.
4. **When I'll stop** — after the real N tasks or H hours, whichever comes first. On stopping I hand you one summary: what I did / what needs your decision / what's left.

End by offering concrete edits in the user's terms: "say the word to change the task count or time limit, or to have me stop before merging any code rather than merging on my own."

Approved → this is the standing authorization for the whole run; do not ask again per task. Edited → apply and re-present. Declined → release the lock and exit.

**Rendering example** (project `rill-autonomous-execution`; render it in the user's language) — a model for the implementer, not a fixed template:

```
I'll work through this project on my own. OK to start?

What I'll take on (tasks that can move now, in order):
  1. Fix the failing every-morning automation (launchd)
  2. Design the unattended-run mode
  3. Pre-provision the permissions
  Note: tasks too thin for me to judge "done" I'll set aside in a list for you instead of guessing.

What I'll do without asking: write research and design notes / put code changes on a branch, run an automated review, and merge once it's clean (repositories: the Rill core repo and the dev repo)

What I'll always stop for and set aside in a list (never do on my own): sending anything to another person, anything that affects the real world, publishing to a public repository, a design fork I can't decide myself, or needing a fact only you have

When I'll stop: after 3 tasks or 1 hour, whichever comes first. On stopping I'll hand you one page: what I did / what needs your decision / what's left.

Say the word to change the task count or time limit, or to have me stop before merging any code instead of merging on my own.
```

The mechanism behind these choices — the lanes, the human-decision queue, the stop-condition trio, the entry filter — is defined in `rill-autonomous-execution.md` §8–§11. That is for you (the implementer) to apply; it does not belong on the approval screen.

#### Step 2 — The loop

Repeat until a stop condition fires:

```
  (maintain an in-memory `isolated` set of slugs across iterations — tasks that queued
   a decision or exhausted their Plan-gap budget this run; they still appear in ### Unblocked
   because isolation is a run-local decision, not a task-status change)
1. /refresh-project {slug}                         (synchronous; recompute Unblocked)
1b. Consume project-scoped decisions (ADR-084 D84-4): scan projects/{slug}/_project.md
    for line-start [DECISION-RESOLVED] blocks; apply each per the solve SKILL.md
    decision-marker scan (append DONE audit line to ## Decision Log, delete block).
    Never rewrite QUEUE -> RESOLVED (human-only transition)
2. next = first task in ## Active Tasks → ### Unblocked WHOSE SLUG IS NOT IN `isolated`
   - none such → STOP (reason: "no actionable unblocked tasks" — either none exist,
     or every remaining unblocked task is isolated and awaiting a human decision)
3. Entry filter on `next`:
   - Completion criteria mechanically verifiable?  AND
   - Goal + Background substantial enough to execute? (rill-tasks.md)
   - either No → write a contract-v1.1 [DECISION-QUEUE id=dN] entry (line-start, 5 fields --
     ADR-084; format in solve SKILL.md) to next's Current Position
     (What: needs sharper Goal/criteria; Why: too thin to execute autonomously;
      Options: user sharpens then re-queues / drop; Default: task stays open, skipped
      as isolated on every runner pass; Blocks: this task) → add slug to `isolated`,
     run /refresh-decisions for each project in next's mentions (at minimum {slug};
     best-effort digest refresh), continue loop (do NOT /solve it)
4. Delegate to a sub-agent (one task = one fresh context — ADR-082 §8, context-rot guard):
   - Sub-agent runs `/solve {next-slug}` in AUTONOMOUS mode
   - Sub-agent returns ONLY a distilled result: { status, deliverable paths, [DECISION-QUEUE] additions, one-line outcome }
   - The orchestrator does NOT inherit the sub-agent's full working context
5. Interpret the distilled result:
   - status: done            → record, continue loop
   - status: open + queue     → record the queue entry, add slug to `isolated`, continue loop
   - status: open + Plan-gap (no queue) → increment that task's gap counter;
     if it has hit Plan-gap twice → add slug to `isolated`; else leave for a later pass
     (a non-isolated Plan-gap task may become unblocked-and-actionable after another task lands)
6. Stop-condition check (after each task):
   - tasks solved >= max-tasks → STOP ("max-tasks reached")
   - elapsed >= max-hours → STOP ("time ceiling")
   - every task in ### Unblocked is in `isolated` → STOP ("all remaining tasks blocked on human decision")
```

Notes:
- **Sub-agent delegation** keeps the orchestrator's context clean across many tasks. If the harness cannot spawn sub-agents, fall back to running `/solve` inline but `/clear`-equivalent between tasks is not available — in that case cap `--max-tasks` low (≤3) and note the degradation.
- **Lane A `git add -A`**: the sub-agent's `/solve` does Lane A pushes via `rill push`. With one runner (Step 0) this is safe; do not start a second runner.
- The runner never performs external messaging or physical actions — those always queue (`rill-autonomous-execution.md` §9).

#### Step 3 — On stop: DoD evaluation + summary

1. **DoD evaluation via a separate sub-agent** (evaluator ≠ executor, to avoid self-grading bias — ADR-082, Anthropic harness-design):
   - Input: the project's `## Goal` (DoD) + the list of tasks solved this run + their deliverable paths
   - Output: per-DoD-bullet met / not-met / partial, with a one-line justification each, and an overall "DoD satisfied? yes/no/partial"
   - The runner does **not** set `status: done` on the project — that stays a human call (the digest surfaces the evaluation).
2. **Run summary** (Phase 1 = markdown; the HTML digest is a separate skill, ADR-082 Phase 2):

   ```markdown
   # Run summary: {name} ({stop reason})

   ## Did this run
   - [{task title}](../../tasks/{slug}/_task.md) — done — {one-line outcome} — {deliverable / PR link}
   - ...

   ## Needs your decision ({K})         ← the human-decision queue, surfaced first
   - [{task}](../../tasks/{slug}/_task.md): {What} — recommendation: {…} — blocks: {…}
   - ...

   ## DoD evaluation
   - {Goal bullet 1}: met ✓ — {why}
   - {Goal bullet 2}: partial — {why}
   - Overall: {satisfied? yes/no/partial}

   ## Still open / isolated
   - [{task}](../../tasks/{slug}/_task.md) — {reason isolated}

   _Resolve queued items via the linked tasks, then re-run `/project {slug} run`._
   ```

3. **Persist before releasing**: ensure every `_task.md` the orchestrator itself wrote a `[DECISION-QUEUE]` entry into (the entry-filter isolations of Step 3 — sub-agent `/solve` runs push their own via `rill push`) has been committed with `rill push` from the main worktree. Otherwise those queue entries live only in the local checkout and are invisible to the next run / `/briefing`. Then release the runner lock (`rm -f "$LOCK/owner"; rmdir "$LOCK"`) — on this normal exit and on every error / abort path.

### Safety

- One runner total across all projects (Step 0 global lock) — because all Lane A work shares the one main worktree. Parallel runners (even on different projects) are a follow-up gated on explicit-path `rill push` staging (`rill-autonomous-execution.md` §11).
- The policy (Step 1) is the only synchronous user gate. Everything inside the loop that would otherwise ask the user is routed to the human-decision queue.
- Stop conditions are mandatory (defaults applied if flags omitted). The loop cannot run unbounded.
- `status: done` on the **project** is never set by the runner — DoD judgment stays with the user.

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

`continue` mode chains into `/solve {top-slug}` interactively. Recursion depth is 1 after `/solve` returns successfully — the loop is intentionally finite to keep the conversation steered by the user.

`run` mode delegates each task to `/solve` in **autonomous mode** (via a sub-agent, one task per fresh context). There, the per-task Plan gate is replaced by the run's approved policy + Codex PASS, and `/solve`'s interactive decision points route to the human-decision queue instead of asking. See `solve.md` §Autonomous Mode and `rill-autonomous-execution.md` §8–§11.

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
| `run` mode: the global runner lock is already held | Refuse to start a second runner; report the holder (project + start time) and exit (one runner total, §11) |
| `run` mode: sub-agent spawning unavailable in the harness | Fall back to inline `/solve`, cap `--max-tasks` ≤3, and warn that context isolation is degraded |
| `new` mode collides with an existing slug | Reject and exit; do not overwrite |

## Rules

- **Always invoke `/refresh-project` first** (except `new` mode). The auto-section trust contract depends on this
- **Never modify** `## Goal` / `## Current Focus` / `## Watch` / `## Key Facts` / `## See Also` from this skill — those have separate owners (see `.claude/rules/rill-projects.md`)
- Always use Markdown links `[display name](relative-path)` for in-body file references. Backtick-only ID references are forbidden
- The recursion in `continue` mode is bounded at depth 1; do not auto-loop further. `run` mode is the autonomous loop, and it is bounded by the mandatory stop-condition trio, not by recursion depth
- `run` mode: acquire the one-runner lock before the loop, release it on every exit; approve the policy once (the only synchronous gate); never set the **project** `status: done` (DoD stays a human call)
- `new` mode requires a Goal (ADR-080 DoD-required policy); reject silent creation of empty projects

## See also

- `.claude/rules/rill-projects.md` — body structure, section ownership, state values
- `.claude/rules/rill-tasks.md` — `depends-on` / `blocks` schema
- `.claude/rules/rill-autonomous-execution.md` — §8 policy gate, §9 human-decision queue, §10 verification immutability, §11 runner economics (the rules `run` mode implements)
- `/refresh-project` skill — auto-section computation
- `/promote` skill — workspace → project crystallisation
- `/solve` skill — task execution (chain target of `continue`; autonomous-mode delegate of `run`)
- `/focus` skill — workspace counterpart (divergent surface)
