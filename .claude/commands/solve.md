---
gui:
  label: "/solve"
  hint: "AI autonomously researches, analyzes, and resolves a task"
  match:
    - "tasks/*/_task.md"
  arg: path
  order: 12
  mode: live
---

# /solve — AI Autonomous Task Execution

The AI reads a task, gathers context, and autonomously runs research and analysis to produce deliverables. It carries the task forward until it is waiting on human review (status: waiting).

## Arguments

{arg} — one of the following:
- Full path to a task's `_task.md` (e.g. `tasks/research-kids-carsickness/_task.md`)
- A task slug (e.g. `research-kids-carsickness`) → resolved to `tasks/{slug}/_task.md`
- Omitted → use AskUserQuestion to ask "Which task should I run?"

Legacy flat-file paths (`tasks/{slug}.md`) are no longer accepted. If one is passed, fail with a message asking the user to run `rill migrate tasks-v1` first (ADR-076).

## Safety Boundary

The AI autonomously performs "know, think, write." Actions that "change, send, or execute" must go through human review.

| Operation | Permission |
|-----------|------------|
| Reading files, WebSearch, Grep | Autonomous |
| Creating reports / analyses (writing into workspace) | Autonomous |
| Updating the task file (status, related, history) | Autonomous |
| Appending procedural details to the task file | Autonomous |
| Code changes | **Investigation and planning only.** Implementation requires human approval |
| Sending email / external communication | **Drafting only.** Sending is performed by a human |
| File deletion, git push, external API calls | **Forbidden** |

## Procedure

### Phase 0: Load Task + Validation + Context Collection

#### 0.1 Resolve and validate arguments

1. Resolve the argument and determine the task file path
2. Read the task file
3. Validation:
   - Confirm `type: task`. If it is `type: insight` or similar, notify "This file is not a task (type: {actual_type})" and exit
   - `status: done` or `status: cancelled` → notify "This task is already completed/cancelled" and exit
   - `status: draft` → "This task is a draft (an unapproved AI-generated task). Approve and run it?" via AskUserQuestion. Approved → Edit `status` to `open` and continue. Rejected → exit
4. Check whether the `related` field contains a workspace path:
   - If yes → ask "This task already has an existing workspace ({workspace path}). Add to it, or run as a new workspace?" via AskUserQuestion
   - Add to existing → reuse that workspace in Phase 3
   - New → create a new workspace in Phase 3

#### 0.2 Context collection

To deepen understanding of the task, dynamically gather related information:

1. **Read the source**: Read the file in the task's `source` field. If a file with the same name exists under `_organized/`, prefer that
2. **Read the related items**: Read the files in the `related` field (if it is a workspace path, Read `_workspace.md`)
3. **Cross-cutting search**: Extract 2–3 keywords from the task's `tags` and `mentions` and run a single Grep:
   ```
   Grep(pattern="{keyword}", glob="{knowledge,inbox,workspace,reports,tasks}/**/*.md",
        output_mode="files_with_matches", head_limit=30)
   ```
   - pages/ is excluded from the search
   - From the results, Read a handful of the most relevant files
4. **User profile**: Read `knowledge/me.md`
5. **Person info**: If `mentions` contains `people/{id}`, Read `knowledge/people/{id}.md`
6. **Latest context**: Grep recent `inbox/journal/` for task-related keywords, and Read any related entries (prefer _organized/)

### Phase 1: Understand

Understand the task correctly and align with the user.

#### 1.1 Fact-check

Verify whether the assumptions and issues stated in the task are still accurate:

- Cross-check the situation described in the task's background and context against the current state of related files
- For code-change tasks: Read the target files and confirm the current implementation
- For business tasks: check the latest state in knowledge/people/ and knowledge/projects/
- **Surface stale assumptions explicitly**: "The task background says 'X is in state Y,' but it is currently Z."

#### 1.2 Scoping

Verify whether the task's scope is appropriate:

- Consider whether the task's goal has been missing any angles in the background or context
- If there is a request, consider whether that request is sufficient to achieve the goal
- Identify dependencies: are there other tasks or prerequisites that should be resolved first
- **Propose adjustments when scope is too narrow or too broad**: "Achieving the goal also seems to require X." "Should Y be considered out of scope for now?"

#### 1.3 Briefing

Organize the fact-check and scoping results and present them to the user:

```
## Task Understanding Briefing

**Goal**: {summary of the task's goal}

**Current State**:
- {fact-check results}
- {flags about changed assumptions}

**Scope Confirmation**:
- {missing considerations}
- {scope boundary proposals}
```

- **If the goal is empty**: Infer the goal from the Phase 0 context (source, related, background) and propose it. If inference is not possible, ask via AskUserQuestion
- **If the goal is not empty**: Present the briefing. If the fact-check is clean and there are no scope concerns, proceed to Phase 2 without asking
- **If there are issues**: Ask any clarifying questions via AskUserQuestion, then proceed to Phase 2 after the user replies

**Phase 1 completion criteria**:
- The AI accurately understands the task's goal, background, and current state
- There is no misalignment with the user
- Scope is agreed

### Phase 2: Design

The AI proposes how to do it and decides the approach interactively with the user. **Do not move on to Phase 3 until the user has approved.**

#### 2.1 Proposing an approach

Design the execution approach using the context gathered in Phase 0 and the understanding from Phase 1.

1. Safety boundary check:
   - Code changes needed → state explicitly "I will produce an investigation and implementation plan. The implementation itself will be done by a human"
   - External communication needed → state explicitly "I will draft email text. Sending will be done by a human"
2. Decide where the deliverables go:
   - **Append to the task file (Enrich pattern)**: when the work only refines the existing task structure (goal/background) and produces no new content
   - **Separate file in a workspace (Research pattern)**: when producing new content (research results, analysis, comparison tables, design proposals, etc.), always use a workspace. Quick rule: if WebSearch/WebFetch is used → workspace
   - **Separate file in a workspace (Code pattern)**: implementation plans and code-change proposals. The code change itself is not performed

#### 2.2 Interactive design

Present the proposal to the user and get approval via AskUserQuestion:

```
## Execution Plan

**Approach**: {summary of the approach}

**Steps**:
1. {step 1}
2. {step 2}
...

**Deliverables**: {placed in workspace / appended to task file}
**Safety boundary**: {code changes: implementation plan only / external comms: draft only}

May I proceed with this approach?
```

If the user requests modifications, revise the design and present it again. Once approved, proceed to Phase 3.

### Phase 3: Execution

#### When a workspace is required

1. Create the workspace directory:
   ```bash
   mkdir -p workspace/{YYYY-MM-DD}-{task-slug}/
   ```
   `{task-slug}` is the task file name with `.md` removed

2. Get the accurate current time:
   ```bash
   date +%Y-%m-%dT%H:%M%z | sed 's/\([0-9][0-9]\)$/:\1/'
   ```

3. Create `_workspace.md` with Write:
   ```markdown
   ---
   created: {time obtained above}
   type: workspace
   id: {YYYY-MM-DD}-{task-slug}
   name: {task title}
   status: active
   origin: {task file path}
   tags: [{inherit the task's tags}]
   ---

   # {task title}

   Workspace for autonomous execution by /solve.

   ## Execution Plan
   {plan from Phase 2}

   ## Related Files (MOC)
   - [{deliverable name}]({deliverable path}) — {description}

   ## Session History
   - {YYYY-MM-DD}: /solve autonomous run. {summary}
   ```

4. Create the deliverable file:
   ```bash
   rill mkfile workspace/{workspace-id} --slug {description} --type research
   ```
   Append the body to the printed path with Edit

#### For tasks that involve code changes / implementation

**Code changes are not performed by /solve.** Limit work to investigation and producing an implementation plan; the implementation itself happens after human approval, via /focus.

1. Read the target code to understand the current state (use Grep to find related files → Read)
2. Analyze the cause of the issue and outline a direction
3. **Create the implementation plan as a workspace deliverable**:
   - Concrete description of which files to change and what the changes are
   - Reasons for the changes and their impact
   - Test methods and verification steps
4. Change the task's status to `waiting` (waiting on review of the implementation plan)
5. **Phase 3 ends here. Do not Edit or Write any code**

#### For task file enrichment

- Append directly to the task file with Edit
- Make the goal, background, and context more concrete and detailed
- Add new sections as needed (e.g. "## Detailed Procedure")

#### Execution content (for research / analysis)

- **Research**: Gather information with WebSearch + WebFetch. Integrate information across multiple sources
- **In-Rill analysis**: Use Grep to consult related knowledge and integrate it with existing insights
- **Structuring**: Structure the gathered information into readable Markdown
- **Additional research**: If the AI judges that "this direction is also worth investigating," it may autonomously run additional research
- **Sources**: Always list the referenced URLs / file paths at the end of the deliverable

### Phase 4: Wrap-up

1. **Update the task file**:
   - If the AI completed the work: Edit `status` to `waiting`
   - For tasks that require a physical action by a human (the AI only enriched the procedure): leave `status` as `open`
   - If a workspace was created: add the path to the workspace's `_workspace.md` (the file path, not the directory path) to `related`
   - **Append an execution record to the task's history section**: record the execution plan, what was done, and the outcome. The current state and Next Action should be obvious just from looking at the task
   - If the task has a "## Context" section, add new related file links discovered during execution
   - Append an execution record to the "## History" section:
     ```markdown
     - YYYY-MM-DD: /solve autonomous run. {one-line summary of the deliverable}
     ```

2. **Update the workspace** (only when a workspace was created):
   - Add deliverable links to "## Related Files (MOC)" in _workspace.md (not needed if already added in Phase 3)
   - Update "## Session History" in _workspace.md (not needed if already added in Phase 3)

3. **Knowledge distillation** (only when marking the task done):
   If the task contains information with knowledge value, extract it as a knowledge note under knowledge/notes/.
   - **What to distill**: records of decisions (why a choice was made) → `type: record`; design insights or patterns → `type: insight`; summaries of external information → `type: reference`
   - **Not to distill**: pure actions (e.g. bring the umbrella home), tasks that are only procedural checklists
   - **How**: create with `rill mkfile knowledge/notes --slug {slug} --type {record|insight|reference} --field "source=tasks/{task-slug}/_task.md"`. `source` points to the task file
   - **Backlink to the task**: add the path of the created knowledge note to the task's `related`
   - **Evergreen check**: confirm there is no existing knowledge/notes/ file on the same topic. If there is, update it instead of creating a new one

4. **Record in activity-log**:
   ```bash
   rill activity-log add task:execute "{task title}" → {deliverable path or task file path}
   ```

5. **Record blockers** (when the work could not be fully completed):
   - Record concretely in the task's "## History" what caused work to stop:
     ```markdown
     - YYYY-MM-DD: /solve run. {what was accomplished}. **Blocker: {what was missing}** (e.g. could not verify directly because the repository path is not recorded under knowledge/projects/)
     ```
   - When the blocker stems from missing knowledge in Rill (paths, credentials, external service specs, etc.), describe the missing information concretely so that a future /solve run or a human can fill it in

6. **Show in the GUI**:
   ```bash
   rill open {deliverable path}
   ```
   For workspaces, show the main deliverable file; for enrichment, show the task file

## Rules

- Source files under inbox/ are **read-only**. Never modify them
- When Reading files under knowledge/notes/, apply the ADR-046 metadata fixes:
  - **Mode A (direct fix)**: remove deprecated tags, migrate entity IDs from tags → mentions
  - **Mode B (append to .refresh-queue)**: detect empty `tags` arrays, missing mentions/related, etc., and append to the queue
- If a file with the same name exists under `_organized/`, Read that one in preference
- Use `rill mkfile` to create deliverable files (exception: _workspace.md is created directly with Write)
- When assigning tags, Read `taxonomy.md` to check existing tags. If none apply, add a new tag
- When referring to files in body text, use Markdown links of the form `[display name](relative path)`. Backtick references with the ID alone are forbidden
- Always include a Sources section at the end of the deliverable (URLs for web research, file paths for in-Rill references)
- When Reading a file referenced by `source:`, prefer the `_organized/` version if a same-named file exists there
