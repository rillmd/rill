---
gui:
  label: "/solve"
  hint: "Solve a task collaboratively via a Plan with embedded breakpoints"
  match:
    - "tasks/*/_task.md"
  arg: path
  order: 12
  mode: live
---

# /solve — Plan-Embedded Breakpoint Task Execution

The default is to solve a task in a single ticket. Each step in the Plan declares **who acts** and **whether a breakpoint is required**, and Claude navigates that Plan seamlessly. There is no explicit "AI autonomous mode" → "human-in-the-loop" toggle — the Plan itself dictates when Claude proceeds and when the user is called.

If the session is cleared (`/clear`) and `/solve {slug}` is invoked again later, the `## Current Position` section at the top of `_task.md` is enough to identify the resumption point. Worst-case rework is "one step that was started but not completed".

## Arguments

{arg} — one of:
- Full path to a task's `_task.md` (e.g. `tasks/research-kids-carsickness/_task.md`)
- A task slug (e.g. `research-kids-carsickness`) → resolved to `tasks/{slug}/_task.md`
- Omitted → ask "Which task should I run?" via AskUserQuestion

Legacy flat-file paths (`tasks/{slug}.md`) are not accepted. If one is passed, ask the user to run `rill migrate tasks-v1` first (ADR-076).

## Safety Boundary

Operations are governed not by a fixed table but by what the Phase 3 Plan declares. Each step has a `[Claude]` or `[User]` tag, and any step where reversibility is low or external side effects occur is given a `⚠️ Breakpoint` so the user is consulted before it runs.

| Operation | Default placement |
|---|---|
| File reads, WebSearch, Grep | `[Claude]` (autonomous) |
| Creating / editing artifacts under `tasks/{slug}/NNN-*.md` | `[Claude]` (autonomous) |
| Updates to `_task.md` (status, Plan, Current Position, History) | `[Claude]` (autonomous) |
| Code changes in a target repository | `[Claude]` step preceded by `⚠️ Breakpoint` for user approval, OR `[User]` step |
| Email / external messaging | Draft only by Claude. Sending is a `[User]` step with `⚠️ Breakpoint` |
| File deletion, git push, external API calls | Must be declared in the Plan. Do not run without user approval, except where repository convention permits (e.g. routine push on a working branch) |

`[Claude]` vs `[User]` is not a fixed rule — it is a Plan-time decision based on the task's nature and the reversibility of each step.

## State Persistence — `## Current Position` in `_task.md`

Treat `_task.md` as a state document where the current position and next action can be read from the top. A new section `## Current Position` sits directly under the title (after the frontmatter, before `## Goal`).

### Format

```markdown
## Current Position

- Phase 3 Step 2 complete; stopped at the Step 3 breakpoint (waiting for the broker's confirmation)
- Next action: user receives the confirmation from the broker and reports the date when running /solve again
```

Two or three lines is enough. State the Phase / Step / status, and who must act next plus what they must do.

### Update Cadence (not per tool call)

| Event | Value to write |
|---|---|
| Phase 1 Intake complete | "Intake complete; judging in Phase 2 Enrichment" |
| Phase 2 judgment complete | "Phase 3 Planning in progress" |
| Right after Phase 3 Plan approval | "Step 1 in progress" + fill the `## Plan` section |
| At the start of each Step | **Write "Step N in progress" as the very first Edit of Step N** |
| Breakpoint reached | "Stopped at the Step M breakpoint ({what}); next action: {what}" |
| Plan complete | Delete this section (the frontmatter `status: done` is sufficient) |

### Critical trick — write at *step start*, not step end

Current Position is written as the **first Edit of the next Step**, not as the last Edit of the previous Step. If Claude is interrupted, what remains in the file is "the step Claude most recently opened" — which is exactly the right resume point. Do this at the top of every step in Phase 4 Execute.

State lives in this single `_task.md` file. Do not introduce a separate `_state.md`. Section order at the top of the file is fixed: `## Current Position` → `## Goal` → `## Background` → `## Context` → `## Plan` → `## Request` → `## History`.

## Procedure

### Phase 1: Intake (read related files + transparency)

#### 1.1 Resolve and validate

1. Resolve the argument and determine the `_task.md` path
2. Read `_task.md`
3. Validation:
   - Confirm `type: task`. Otherwise: "This file is not a task (type: {actual_type})" and exit
   - `status: done` / `status: cancelled` → "This task is already completed/cancelled" and exit
   - `status: draft` → "This task is a draft (an unapproved AI-generated task). Approve and run it?" via AskUserQuestion. Approved → Edit `status` to `open` and continue. Rejected → exit
4. Check whether `_task.md` already has a `## Current Position` section:
   - **Present**: this is a resume. Read its content, announce "Resuming from {Phase X Step Y}", and jump to the corresponding Phase
   - **Absent**: this is a fresh run. Add the section at the end of Phase 1

#### 1.2 Read related files

To deepen understanding of the task, read:

1. **source**: the file in `source` (prefer the same-named file under `_organized/` if present)
2. **related**: every file listed in `related` (if it is a workspace path, read `_workspace.md`)
3. **mentions**: each `people/{id}` / `orgs/{id}` / `projects/{id}` file
4. **User profile**: `knowledge/me.md`
5. **Cross-cutting Grep** (single call): pick 2–3 keywords from the task's `tags` and `mentions`
   ```
   Grep(pattern="{keyword}", glob="{knowledge,inbox,workspace,reports,tasks}/**/*.md",
        output_mode="files_with_matches", head_limit=30)
   ```
   Exclude pages/. Read the most relevant handful from the result
6. **Recent context**: Grep recent `inbox/journal/` for task keywords and Read related entries (prefer `_organized/`)

#### 1.3 Transparency — list the files that were read

Output a Markdown list of every file Read in Phase 1, so the user can see the knowledge base Claude is operating from and flag gaps.

```markdown
## Phase 1 Intake — files read

- [tasks/{slug}/_task.md](tasks/{slug}/_task.md) — this task
- [{source}]({source}) — source
- [{related-1}]({related-1}) — related
- knowledge/me.md — Interest Profile
- {a few files actually Read from the Grep result}
- {related entries from recent journal}
```

#### 1.4 Update Current Position

For a fresh run, Edit `_task.md` to add `## Current Position` at the top:

```markdown
## Current Position

- Phase 1 Intake complete; judging in Phase 2 Enrichment
- Next action: Claude judges whether information is sufficient
```

### Phase 2: Enrichment Judgment (conditional, one-line declaration)

Claude judges at runtime:

- Is the information sufficient?
- Is best practice known? If not, it is a search candidate
- Would WebSearch / Vault Search add value?

Tell the user the judgment in one line:

```
> Information looks sufficient. Skipping Enrichment and moving to Planning.
```

Or:

```
> The latest {procedure / API / fact} for {topic} is not in _task.md, so I'll WebSearch.
```

Leave room for the user to interject ("no, look up X first") before Phase 3 starts.

If Enrichment runs, summarise the result in 1–2 paragraphs and use it as material for the Plan. Do not create a new artifact file here — Phase 3 decides what gets written and where.

When done, update Current Position to "Phase 3 Planning in progress".

### Phase 3: Planning (required, Plan-Embedded Breakpoint, user approval gate)

The default is "do not split". If the Plan can state "this task is solvable as a single ticket", do not split. Only split when necessary, and then declare it as a single Plan step ("create child tasks {slug-A}, {slug-B} via `rill task`, copy parent Background / Context, add parent path to children's `related`") and **list the child slugs in the parent's Plan** (parent–child visibility holds via that listing alone — no extra tooling needed).

#### 3.1 Fact-check + scoping

- Briefly verify the task's background / context is consistent with the current state of related files
- Pick up at most 1–2 missing angles or scope clarifications
- If a fatal inconsistency exists, ask the user for a one-line correction first

#### 3.2 Drafting the Plan

Claude drafts the Plan. **`[Claude]` / `[User]` tags and `⚠️ Breakpoint` markers are required.**

```markdown
## Plan

**Completion criteria**: {a clear end state under which this task is "solved"}

**Steps**:
1. [Claude] {autonomous work}
2. [Claude] {autonomous work — produces an intermediate `tasks/{slug}/NNN-*.md`}
   - ⚠️ **Breakpoint**: user reviews {what} and approves or requests changes
3. [User] {an action the user performs by hand}
   - ⚠️ **Breakpoint**: wait for {completion notice / result report}
4. [Claude] {autonomous work after resume}
5. [Claude] Edit `_task.md` to `status: done` and append History
```

#### Step kinds (successors of the old Enrich / Research / Code patterns)

`[Claude]` steps in Phase 3 typically take one of these "kinds". **Kind is per-step, not per-Phase** — a single Plan can mix Research + Code-plan + Refine steps freely.

| Step kind | Target | Deliverable |
|---|---|---|
| **Refine** (old "Enrich" — renamed to avoid clashing with Phase 2 "Enrichment") | `_task.md` body | Edit to `_task.md` (sharpens Background / Context / Request) |
| **Research** | Web / Vault / knowledge search | `tasks/{slug}/NNN-research-*.md` (`--type research`) |
| **Analysis** | Structuring / comparison | `tasks/{slug}/NNN-analysis-*.md` (`--type analysis`) |
| **Decision** | Design / implementation plan | `tasks/{slug}/NNN-*-plan.md` (`--type decision`) |
| **Code (plan)** | Code-change plan for a target repo | `tasks/{slug}/NNN-plan.md`. The implementation step itself is a separate step — typically `[Claude]` after a `⚠️ Breakpoint` for user approval, or `[User]` |
| **Action** | External submission / send | `[User]` step with `⚠️ Breakpoint`. Claude drafts to `tasks/{slug}/NNN-draft-*.md`; the user sends |

All deliverables live under `tasks/{slug}/` (ADR-077 D77-1). /solve never creates a workspace. If the task genuinely needs a shared Deep Think surface, halt and suggest the user run `/focus <theme>` manually.

#### 3.3 Write the Plan into `_task.md` and gate on user approval

1. Edit `_task.md` to write the drafted Plan into a `## Plan` section (replace any prior Plan)
2. Ask for approval via AskUserQuestion:
   ```
   ## Execution Plan

   {summary of the Plan}

   May I proceed with this Plan?
   ```
3. Approved → proceed to Phase 4. Revision requested → revise the draft and re-present

Do not move on to Phase 4 without approval. After approval, update Current Position to "Step 1 in progress".

### Phase 4: Execute (seamless navigation)

Navigate the approved Plan step-by-step.

#### Per-step loop

```
for step in Plan.steps:
    Edit `_task.md` Current Position to "Step {N} in progress"   # step-start trick
    if step.tag == "[Claude]":
        Execute (Research / Code plan / Refine / Action draft / etc.)
        Save deliverables to tasks/{slug}/NNN-*.md as applicable
    elif step.tag == "[User]":
        Tell the user in one line what to do, and confirm completion via AskUserQuestion
    if step.has_breakpoint:
        - Review request → wait via AskUserQuestion for approval / change request
        - User-execution wait → wait for completion report
        - External-response wait → update Current Position to a stopped state
          (status unchanged) and exit Phase 4. The next /solve {slug} resumes here
```

#### Producing deliverables

- **New artifact**: `rill mkfile tasks/{slug} --slug {desc} --type {research|analysis|decision|progress|review}` scaffolds `tasks/{slug}/NNN-{desc}.md` (numbering auto). Append the body via Edit. Always add a Sources section at the end.
- **Direct `_task.md` edit** (Refine step): sharpen `## Background` / `## Context` / `## Request` via Edit.
- **Code change in a target repo** (Code step): only run when the Plan tag is `[Claude]` and the preceding `⚠️ Breakpoint` was approved. Pre-approval implementation is forbidden. After implementation, append "date / files changed / outcome" to the corresponding `tasks/{slug}/NNN-plan.md`.

#### After a step

- If the step ended without a breakpoint, move to the next step (Current Position is overwritten at the next step's start, not here)
- Do not append per-step entries to `## History` (too granular). Phase 5 Wrap-up logs the run as a single entry

### Phase 5: Wrap-up (completion criteria check)

#### 5.1 Check completion criteria

Judge whether the Plan's "Completion criteria" is met:

- Met → 5.2 (`status: done`)
- Not met but Claude is no longer the actor (waiting on user execution / external response) → leave `status: open`, update Current Position to "{what} pending; Next action: {what}", exit
- Stopped by a fatal blocker → leave `status: open`, record the blocker in Current Position, append details to `## History`, exit

#### 5.2 Transition to status: done

1. Edit frontmatter `status` to `done`
2. Delete the `## Current Position` section (a finished task does not need it)
3. Append an execution record to `## History`:
   ```markdown
   - YYYY-MM-DD: /solve completed. Ran {N} Plan steps; produced {primary deliverable}
   ```
4. If new artifacts were created, add them to `## Context` with a short role descriptor (Markdown links)

#### 5.3 Knowledge distillation (only when status: done)

If the task has knowledge value, extract it as `knowledge/notes/`:

- **Distill**: decision records (why a choice was made) → `type: record`; design insights / patterns → `type: insight`; external-information summaries → `type: reference`
- **Do not distill**: pure actions (e.g. bring the umbrella home), procedural-only checklists
- **How**: `rill mkfile knowledge/notes --slug {slug} --type {record|insight|reference} --field "source=tasks/{task-slug}/_task.md"`
- **Backlink**: add the new note's path to the task's `related`
- **Evergreen check**: if a knowledge/notes/ on the same theme exists, update it instead of creating a new one

#### 5.4 activity-log

```bash
rill activity-log add task:execute "{task title}" → {primary deliverable path or _task.md path}
```

#### 5.5 Display result paths

Print primary deliverable paths as Markdown links or in backticks. **Do not call `rill open`** — the user opens files via the GUI header search box (or `Cmd+P`).

## Resume Operation

If `/solve {slug}` is invoked after a `/clear`:

1. Phase 1.1 validation detects the existing `## Current Position`
2. Read its content and announce "Resuming from {Phase X Step Y}"
3. Jump to that Phase / Step (Phase 1 file reads are re-run for cache, which is acceptable)
4. Tolerate at most one step of rework (real SLA)

## Decomposition

- **Default**: solve in one ticket. If the Plan cannot articulate "why splitting is necessary", do not split
- **When splitting**: declare it as one Plan step — "[Claude] create child tasks {slug-A}, {slug-B} via `rill task`, copy the parent's Background / Context, add parent path to each child's `related`". After execution, replace the corresponding line in the parent's `## Plan` with "Done — continued in [slug-A](../{slug-A}/_task.md), [slug-B](../{slug-B}/_task.md)"
- **Parent–child visibility**: holds via the child slugs being listed in the parent's Plan. No additional tooling needed

## Rules

- Source files under `inbox/` are **read-only**. Never modify them
- When reading files under `knowledge/notes/`, apply the ADR-046 metadata fixes:
  - **Mode A (direct fix)**: remove deprecated tags, migrate entity IDs from tags to mentions
  - **Mode B (append to `.refresh-queue`)**: detect empty `tags`, missing mentions / related, etc., and append to the queue
- If a same-named file exists under `_organized/`, prefer Reading that one
- Use `rill mkfile tasks/{slug} --slug {desc} --type {type}` for new artifact files under a task
- Never create a workspace from /solve (ADR-077). If the task truly needs a shared Deep Think surface, halt and suggest `/focus <theme>` manually
- When assigning tags, Read `taxonomy.md` to check existing tags. Add a new tag only if none apply
- For in-body file references, use Markdown links of the form `[display name](relative path)`. Backtick-only ID references are forbidden
- Always include a Sources section at the end of any deliverable (URLs for web research, file paths for in-Rill references)
- When Reading a file referenced by `source:`, prefer the `_organized/` version if a same-named file exists there
