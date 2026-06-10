---
gui:
  label: "/solve"
  hint: "Solve a task end-to-end via a Plan-gated autonomous flow"
  match:
    - "tasks/*/_task.md"
  arg: path
  order: 12
  mode: live
---

# /solve — Plan-Gated Autonomous Task Execution

**Conduct ALL conversation with the user in the language defined by `.claude/rules/personal-language.md`** (or the user's input language if absent). The English instructions below are for skill clarity, not for output style. Exceptions (only): tokens inside backticks or code blocks, proper nouns, ASCII acronyms.

> **Tool references** (`Read`, `Edit`, `Grep`, `Glob`, `WebSearch`, the harness's question primitive, `find`, `shell`) describe **intent**, not Claude-specific tool calls. Each harness maps them to its native equivalent.

The default is to solve a task end-to-end in a single ticket. **Phase 3 Plan approval is the only required user gate.** Once the Plan is approved, Phase 4 and Phase 5 run autonomously, with three narrow exceptions defined in §"Three Remaining Breakpoints" below.

If the session is cleared (`/clear`) and `/solve {slug}` is invoked again later, the `## Current Position` section at the top of `_task.md` plus the worktree state (for Lane B) are enough to identify the resumption point. Worst-case rework is "one step that was started but not completed".

This skill is governed by `rill-autonomous-execution.md` (lane detection, Plan gate, worktree convention, Codex dual usage, two-channel write invariant, three-tier destructive operations). Reading both files together gives the full picture.

## Arguments

{arg} — one of:

- Full path to a task's `_task.md` (e.g. `tasks/research-kids-carsickness/_task.md`)
- A task slug (e.g. `research-kids-carsickness`) → resolved to `tasks/{slug}/_task.md`
- Omitted → ask "Which task should I run?" via the harness's question primitive

Legacy flat-file paths (`tasks/{slug}.md`) are not accepted. If one is passed, ask the user to run `rill migrate tasks-v1` first (ADR-076).

## Safety Boundary

Two classification axes govern Phase 4 execution: **lane** (what files the task touches) and **operation tier** (reversibility).

### Lane (determines branch / push / review)

| Lane | Target paths | Branch | Push | Review |
|---|---|---|---|---|
| **A** (PKM) | `inbox/`, `knowledge/`, `workspace/`, `tasks/`, `reports/`, `pages/`, `taxonomy.md`, `activity-log.md` | main directly | `rill push` immediate | None |
| **B** (dev) | `.claude/`, `bin/`, `app/`, sibling repos | `feature/{slug}` in `.claude/worktrees/{slug}/` | PR → review → auto-merge | `codex review --base main` required |

Mixed tasks split into a Lane A path + Lane B path running concurrently within the single task. See `rill-autonomous-execution.md` §1 and §5.

### Three Remaining Breakpoints

Phase 4 may pause for the user only in these three cases, and only if the Plan declared them at Phase 3:

1. **External messaging** — sending email, Slack, or other communication to a person outside the user's automated systems. The AI drafts; the user sends
2. **Real-world / physical action** — anything that moves matter in the physical world
3. **Human-input-required knowledge gap** — see §"Phase 4 knowledge-gap blocker handling" below

Any other case where Phase 4 cannot proceed is a **Plan-gap blocker** (§"Plan-gap blocker"): exit with `status: open` and resume from Phase 3 next time.

### Operation tiers

| Tier | Examples | How |
|---|---|---|
| **1 — AI autonomous** | feature-branch push, worktree add/remove, PR create + squash-merge, `codex` invocations, file Edit/Write, `rill push` / `rill mkfile` | No user prompt; the Plan implicitly authorized these by being approved |
| **2 — User confirmation** | bulk file deletion, `.claude/` config via the Lane A channel (misclassification signal), `_task.md` → `status: cancelled`, non-squash merges to main, removing a worktree the current task did not create | Surface to the user before acting |
| **3 — Deny (enforced via settings.json)** | `git push --force`, direct push to main/master, `git reset --hard`, `git clean -f`, `git branch -D`, `gh pr merge --admin`, absolute-path `rm -rf` | Refuse and report |

See `rill-autonomous-execution.md` §6 for the full tier 3 deny matrix.

## State Persistence — `## Current Position` in `_task.md`

Treat `_task.md` as a state document where the current position and next action can be read from the top. A new section `## Current Position` sits directly under the title (after the frontmatter, before `## Goal`).

### Format

```markdown
## Current Position

- Phase 4 Step 5 complete; running Phase 4.5 Codex code review
- Next action: parse review output for [P1] hits, apply Trivial auto-fix or halt
```

Two or three lines is enough. State the Phase / Step / status, and who must act next plus what they must do.

### Update cadence (not per tool call)

| Event | Value to write |
|---|---|
| Phase 1 Intake complete | "Intake complete; judging in Phase 2 Enrichment" |
| Phase 2 judgment complete | "Phase 3 Planning in progress" |
| Right after Phase 3 Plan approval | "Phase 4 Step 1 in progress" + fill the `## Plan` section |
| At the start of each Phase 4 step | **Write "Phase 4 Step N in progress" as the very first Edit of step N** |
| Plan-gap or breakpoint reached | "Stopped at {what}; next action: {what}" |
| Plan complete | Delete this section (the frontmatter `status: done` is sufficient) |

### Critical trick — write at *step start*, not step end

Current Position is written as the **first Edit of the next step**, not as the last Edit of the previous step. If the AI is interrupted, what remains in the file is "the step the AI most recently opened" — which is exactly the right resume point.

State lives in this single `_task.md` file. Do not introduce a separate `_state.md`. Section order at the top of the file is fixed: `## Current Position` → `## Goal` → `## Background` → `## Context` → `## Plan` → `## Request` → `## History`.

### Two-channel write — always edit `_task.md` from the main worktree

Even when the Plan declares Lane B and the task has an active worktree, **`_task.md` (and every other PKM-domain file) is edited from the main worktree**. The Lane B feature branch must not contain `_task.md` changes. This is the two-channel write invariant (`rill-autonomous-execution.md` §5). Mid-task `status: open` exits stay visible on main as a result.

## Procedure

### Phase 1: Intake (read related files + transparency)

#### 1.1 Resolve and validate

1. Resolve the argument and determine the `_task.md` path
2. Read `_task.md`
3. Validation:
   - Confirm `type: task`. Otherwise: "This file is not a task (type: {actual_type})" and exit
   - `status: done` / `status: cancelled` → "This task is already completed/cancelled" and exit
   - `status: draft` → "This task is a draft (an unapproved AI-generated task). Approve and run it?" via the harness's question primitive. Approved → Edit `status` to `open` and continue. Rejected → exit
4. Check whether `_task.md` already has a `## Current Position` section:
   - **Present**: this is a resume. Read its content, announce "Resuming from {Phase X Step Y}", and jump to the corresponding Phase
   - **Absent**: this is a fresh run. Add the section at the end of Phase 1

#### 1.2 Read related files

To deepen understanding of the task, read:

1. **source**: the file in `source` (prefer the same-named file under `_organized/` if present)
2. **related**: every file listed in `related` (if it is a workspace path, read `_workspace.md`)
3. **mentions**: each `people/{id}` / `orgs/{id}` / `projects/{id}` file
4. **User profile**: `knowledge/self/profile.md` (+ `knowledge/self/constraints.md` if non-empty)
5. **Cross-cutting Grep** (single call): pick 2–3 keywords from the task's `tags` and `mentions`
   ```
   Grep(pattern="{keyword}", glob="{knowledge,inbox,workspace,reports,tasks}/**/*.md",
        output_mode="files_with_matches", head_limit=30)
   ```
   Exclude pages/. Read the most relevant handful from the result
6. **Recent context**: Grep recent `inbox/journal/` for task keywords and Read related entries (prefer `_organized/`)

#### 1.3 Transparency — list the files that were read

Output a Markdown list of every file Read in Phase 1, so the user can see the knowledge base the AI is operating from and flag gaps.

```markdown
## Phase 1 Intake — files read

- [tasks/{slug}/_task.md](tasks/{slug}/_task.md) — this task
- [{source}]({source}) — source
- [{related-1}]({related-1}) — related
- knowledge/self/profile.md — Core Identity
- knowledge/self/constraints.md — Constraints (skip if empty)
- {a few files actually Read from the Grep result}
- {related entries from recent journal}
```

#### 1.4 Update Current Position

For a fresh run, Edit `_task.md` to add `## Current Position` at the top:

```markdown
## Current Position

- Phase 1 Intake complete; judging in Phase 2 Enrichment
- Next action: AI judges whether information is sufficient
```

#### 1.5 Worktree resume check (Lane B only, idempotent)

If `_task.md` already has a `## Plan` section *and* that Plan declares Lane B (or a mixed task with Lane B components), check the worktree / branch / PR state in every target repository **before doing anything else in Phase 4**. Let `WT = $REPO/.claude/worktrees/{slug}` and `BR = feature/{slug}`.

For each target repo, branch on five cases:

| Case | Condition | Action |
|---|---|---|
| 1 | WT exists, HEAD = BR | Reuse silently (log "worktree reused: {WT}") |
| 2 | WT exists, HEAD ≠ BR (corrupted) | Halt and ask the user: "worktree {WT} is on unexpected branch {actual}. Investigate manually before re-running /solve" |
| 3 | WT missing, BR on remote | `git -C $REPO fetch origin $BR && git -C $REPO worktree add $WT $BR` |
| 4 | WT missing, BR local-only | `git -C $REPO worktree add $WT $BR` |
| 5 | Neither WT nor BR (fresh) | Defer; Phase 4 Step 1 creates them via `git -C $REPO worktree add $WT -b $BR` |

PR check (parallel): for each target repo, run `gh pr list -R {owner/name} --head feature/{slug} --state open --json number` — reuse the existing PR if found in Phase 4.7. The `-R` flag is required so the query targets the correct repository regardless of the current working directory.

This makes `/solve` **idempotent on slug**: invoking it repeatedly converges on a single worktree / branch / PR triple per task per repo.

For fresh runs without an existing Plan, this step is a no-op and is performed once the Plan exists (right after Phase 3 approval).

### Phase 2: Enrichment Judgment (conditional, one-line declaration)

The AI judges at runtime:

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

### Phase 3: Planning (required, Codex-reviewed, user approval gate)

The default is "do not split". If the Plan can state "this task is solvable as a single ticket", do not split. Only split when necessary, and then declare it as a single Plan step ("create child tasks {slug-A}, {slug-B} via `rill task`, copy parent Background / Context, add parent path to children's `related`") and **list the child slugs in the parent's Plan** (parent–child visibility holds via that listing alone — no extra tooling needed).

#### 3.1 Fact-check + scoping

- Briefly verify the task's background / context is consistent with the current state of related files
- Pick up at most 1–2 missing angles or scope clarifications
- If a fatal inconsistency exists, ask the user for a one-line correction first

#### 3.2 Drafting the Plan

The AI drafts the Plan. **The eight Plan-quality fields are required** (per `rill-autonomous-execution.md` §2.3). If any are missing, rework before presenting:

1. **Completion criteria** — verifiable end-state (mechanically checkable)
2. **Verification commands** — how to confirm Completion criteria
3. **Review method** — `codex review --base main` (Lane B default) / none (Lane A default) / explicit "double review"
4. **Merge policy** — `auto-squash` / manual / draft PR
5. **Branch name** — `feature/{slug}` (Lane B). Lane A has no branch
6. **Files in scope** — exhaustive list
7. **Target repositories** — for Lane B
8. **Lane** — A / B / mixed

```markdown
## Plan

**Completion criteria**: {a clear, verifiable end-state}

**Lane**: A | B | mixed

**Target repositories** (Lane B only): {list}

**Branch** (Lane B only): `feature/{slug}`

**Verification**: {commands or manual steps}

**Review method**: {codex review --base main | none | other}

**Merge policy**: {auto-squash | manual | draft}

**Files in scope**: {list}

**Steps**:

1. {Refine / Research / Analysis / Decision / Code / Action ...}
2. {...}
N. {Wrap-up: status: done + History}
```

#### Step kinds

`/solve` recognizes six kinds of step. Mix freely within one Plan.

| Step kind | Target | Deliverable |
|---|---|---|
| **Refine** | `_task.md` body | Edit to `_task.md` (sharpens Background / Context / Request) |
| **Research** | Web / Vault / knowledge search | `tasks/{slug}/NNN-research-*.md` (`--type research`) |
| **Analysis** | Structuring / comparison | `tasks/{slug}/NNN-analysis-*.md` (`--type analysis`) |
| **Decision** | Design / implementation plan | `tasks/{slug}/NNN-*-plan.md` (`--type decision`) |
| **Code** | Code change in a target repo | The Plan authorizes implementation; no per-step breakpoint. Lane B steps run in the worktree |
| **Action (external)** | Email / message / physical | Drafted to `tasks/{slug}/NNN-draft-*.md`. **Sending is a remaining `[User]` breakpoint** |

All artifact deliverables live under `tasks/{slug}/` (ADR-077 D77-1). `/solve` never creates a workspace. If the task genuinely needs a shared Deep Think surface, halt and suggest the user run `/focus <theme>` manually.

#### 3.3 Codex Plan review (mandatory)

After the Plan is drafted into `_task.md`, run `codex exec` to review it before user approval. This catches Plan-quality issues a same-model self-review misses.

```bash
codex exec --skip-git-repo-check --sandbox read-only \
  --cd $RILL_HOME --color never "$PROMPT" </dev/null
```

`$PROMPT` should embed: the Plan body, the relevant verification notes (under `knowledge/notes/`), and an explicit instruction to label each evaluation point `PASS / WARN / FAIL`. Useful evaluation axes:

1. Completion criteria verifiability
2. Worktree resume idempotency (cross-check against `rill-autonomous-execution.md` §3.2)
3. Two-channel write invariant compliance (Lane B steps must not touch the forbidden paths)
4. PUBLIC repo PII/JP guard (if any target repo is PUBLIC)
5. `codex review --base main` integrity (review must run after commit, before push)

Save output as `tasks/{slug}/NNN-codex-plan-review.md` (via `rill mkfile` from the main worktree; this is a Lane A artifact and follows the two-channel write rule).

**Output interpretation**: `codex exec` echoes its final answer twice (streaming + tail summary). Truncate at the `tokens used` marker before counting, then count occurrences (do **not** `sort -u`, which would collapse repeated labels):

```bash
awk '/^tokens used$/{exit} {print}' codex-exec-output.txt \
  | grep -oE '\b(PASS|WARN|FAIL)\b' \
  | sort | uniq -c
```

| Decision | Condition |
|---|---|
| PASS — present Plan to user | `FAIL == 0` and `WARN <= 1` |
| Auto-fix — replan + re-review (1 loop max) | `FAIL == 1` or `WARN >= 2` |
| Material — surface to user for manual Plan rework | `FAIL >= 2`, *or* a single FAIL on a core invariant (slug-identity, two-channel write, PII guard) |

Operational notes (see `rill-autonomous-execution.md` §4.1 for full details):

- `</dev/null` prevents stdin hang
- The codex output appears twice (streaming + final summary); de-dup before counting
- Label position relative to the evaluation point varies; use loose regex

#### 3.4 User approval

Present the Plan + Codex review summary, then ask:

```
## Execution Plan (Codex-reviewed)

{summary of the Plan, including any Codex-flagged items already auto-fixed and any remaining advisories shown to the user}

May I proceed with this Plan?
```

Approved → proceed to Phase 4. Revision requested → revise the draft, re-run §3.3 Codex review if the change is non-trivial, re-present.

Do not move on to Phase 4 without approval. After approval, update Current Position to "Phase 4 Step 1 in progress".

### Phase 4: Execute (autonomous, lane-aware)

Phase 4 navigates the approved Plan without further user gates, with the three exceptions listed under Safety Boundary. Run each step in declared order. At the start of every step, **write "Phase 4 Step N in progress" as the first Edit of the step** (the step-start trick).

#### 4.0 Lane Setup

Determine the lane from the Plan's `Lane:` field and the files in scope.

- **Lane A only**: no worktree, work proceeds in the main worktree
- **Lane B only**: ensure the Lane B worktree exists (Phase 1.5 already verified state; if Case 5 was the result, create the worktree now via `git -C $REPO worktree add $WT -b $BR`)
- **Mixed**: do both — main worktree for Lane A edits, Lane B worktree for code edits, in parallel through the rest of Phase 4

#### 4.1 Lane A execution flow

```
1. Edit/Write the in-scope Lane A files in the main worktree
2. (optional) codex review --uncommitted "{review focus}" — only for sensitive distillation work
3. rill push  (= git add -A + commit + push)
   - On push failure (someone else pushed first): git pull --rebase → AI two-sided merge → push again
```

`rill push` performs the pull-and-rebase implicitly when it detects the remote has moved; explicit `git pull --rebase` at the *start* of Phase 4 would conflict with the dirty main worktree left by Phase 3 (the `## Plan`, the Codex plan-review artifact, and the `## Current Position` update are all uncommitted edits at this point). Rebase is therefore reactive (on push failure), not proactive.

Conflicts: the AI integrates both sides whenever the change-set semantics permit, then commits with `## History` noting "merged with concurrent change from {clue}". The AI must not unilaterally drop a side; if integration is impossible, exit with `status: open` and surface to the user.

#### 4.2 Lane B execution flow

```
WT=$REPO/.claude/worktrees/{slug}

1. Inside $WT, Edit/Write the in-scope Lane B files (using absolute paths)
2. Run the verification commands declared in the Plan
   - On failure: one auto-fix loop, then Plan-gap blocker if still failing
3. git -C $WT add -A && git -C $WT commit -m "..."
   - Prefer heredoc for the commit message body (subject 50–72 chars, body wrapped at 72)
4. Proceed to Phase 4.5 (Codex code review)
5. After review passes, proceed to Phase 4.7 (push + PR + merge)
```

#### 4.3 Two-channel write — forbidden paths under a Lane B feature branch

While inside a Lane B worktree, **never Edit/Write any of**:

- `tasks/`
- `knowledge/`
- `workspace/`
- `pages/`
- `reports/`
- `inbox/`
- `taxonomy.md`
- `activity-log.md`

These belong to Lane A and are edited from the main worktree only. Their `_task.md` / artifact updates land on main throughout Phase 4, so the task's progress (Current Position / status / History) is always visible to other sessions and `/briefing` even mid-flight. See `rill-autonomous-execution.md` §5.

If a Lane B step legitimately needs to read a Lane A file (e.g. to embed workspace context into a Codex prompt), do not `cp` it into the worktree (that risks staging it on the feature branch). Instead, point Codex at the main worktree directly via `codex exec ... --cd $RILL_HOME ...`, or read the file from the main path and pass its contents inline.

#### 4.4 Producing artifacts

- **New per-task artifact**: `rill mkfile tasks/{slug} --slug {desc} --type {research|analysis|decision|progress|review}` scaffolds `tasks/{slug}/NNN-{desc}.md` with auto-incrementing NNN. Always run this from the **main worktree** (artifact paths are Lane A). Append the body via Edit. Always end with a Sources section.
- **Direct `_task.md` edit** (Refine step): sharpen `## Background` / `## Context` / `## Request` via Edit, from the main worktree.
- **Code change** (Code step): run inside the Lane B worktree only. No per-step user approval needed (the Plan-gate authorized it).

#### 4.5 Codex code review (Lane B only, mandatory)

After commit, before push:

```bash
cd $WT
codex review --base main </dev/null
```

Save output as `tasks/{slug}/NNN-codex-review-{repo}.md` (via `rill mkfile` from the main worktree).

**Output interpretation** (`grep -E '^- \[P[123]\]' | sort -u | wc -l`):

| Decision | Condition | Action |
|---|---|---|
| PASS — proceed to push | `0` unique `[Pn]` lines | Continue to Phase 4.7 |
| Trivial auto-fix + re-review | `[P2]` or `[P3]` only | Edit fixes in worktree → `git add -A && git commit --amend --no-edit` → `codex review --base main` again (one loop max). Save new output as a new artifact file. If still Trivial, halt for user |
| Material | `[P1]` >= 1 | Halt and surface to user. They may approve continuation, request a Plan replan, or override |

Operational notes (see `rill-autonomous-execution.md` §4.2 for full details):

- `--color` is not accepted (different from `codex exec`)
- `--base` and positional `[PROMPT]` are mutually exclusive
- File paths in `[Pn] ... — /abs/path:line` are absolute; normalize for PR-comment forwarding

#### 4.6 PUBLIC repository guard (Lane B, PUBLIC target only)

Before pushing to a PUBLIC repository, run three BLOCKING scans on the most-recent-commit diff (`git diff HEAD~1 HEAD` against the worktree):

1. **Non-ASCII (covers CJK / Japanese)**: `git -C $WT diff HEAD~1 HEAD | grep -E '^\+[^+]' | LC_ALL=C grep -nE '[^[:ascii:]]'` — halt on hit. BSD-portable; `grep -P` (Perl regex) is not available on macOS, so the bracketed Unicode range cannot be used directly. The `^\+[^+]` filter limits the scan to added lines, avoiding false positives from deleted lines
2. **PII mapping**: grep for entries in the vault's PII mapping table (lives in the vault's `personal-*.md`) — halt on hit
3. **Email / phone**: regex for `\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b` and `\b\d{2,4}-\d{2,4}-\d{4}\b` — halt and confirm (false-positive prone)

All three must clear before push. PRIVATE repos skip this section.

#### 4.7 Push, PR, merge (Lane B only)

```
1. git -C $WT push -u origin feature/{slug}
2. PR_NUM=$(gh pr list -R {owner/name} --head feature/{slug} --state open \
              --json number -q '.[0].number')
   if [ -z "$PR_NUM" ]; then
     gh pr create -R {owner/name} \
       --title "{slug}: {one-line summary}" \
       --body  "{Plan summary + Codex review summary + Implementation deviations (if any)}"
   else
     gh pr edit -R {owner/name} $PR_NUM \
       --body "{updated body — Plan summary + Codex review summary + Implementation deviations (if any)}"
   fi
3. gh pr checks -R {owner/name}  (read CI state)
   - No CI configured → gh pr merge -R {owner/name} --squash --delete-branch
   - CI required → gh pr merge -R {owner/name} --auto --squash --delete-branch && gh pr checks -R {owner/name} --watch
4. git -C $REPO switch main && git -C $REPO pull --ff-only
   (target the primary worktree at $REPO, not $WT — main cannot be checked out
    inside the feature worktree because the primary worktree already holds it)
5. (deferred to Phase 5.7) git -C $REPO worktree remove $WT
```

PR resume: Phase 1.5's PR check populates `PR_NUM` (or leaves it empty). Phase 4.7 Step 2 uses that to choose between `gh pr create` and `gh pr edit` so re-running `/solve` after a `/clear` does not error out with "a pull request already exists".

#### 4.8 knowledge-gap blocker handling

When a Plan step stalls because Rill's `knowledge/` is missing information the step needs, treat it as a **knowledge-gap blocker** rather than a generic fatal blocker. The goal is to **write the missing fact into `knowledge/` in-flight and resume**, so the same gap never blocks a future run.

##### Step 1: Classify the gap

The AI classifies the gap into one of two buckets at runtime:

- **Auto-recoverable** — the information exists somewhere reachable (filesystem, `knowledge/` entities, `inbox/` sources) and can be found via `find` / `Glob` / `Grep`. Typical examples: repository paths, references to existing entity files, content already captured in `inbox/`
- **Human-input-required** — the information lives outside Rill and depends on user recall or private sources. Typical examples: contract amounts, PII (names, emails, phone numbers — ADR-047 requires these to live in `knowledge/people/` or `knowledge/orgs/`), verbal commitments, private API specs

The qualitative test: **is the fact findable by grepping Rill or the filesystem?** If yes, treat as auto-recoverable.

##### Step 2: Handle by classification

**Auto-recoverable**:

1. Run the search (`find ~/src -maxdepth 4 -name '<pattern>*'`, `Glob`, `Grep`, etc.)
2. If the fact is found:
   - Edit the target `knowledge/` file (the `suggest:` location) to add the missing fact. This is a Lane A edit, done from the main worktree
   - Append to `## History`: `- YYYY-MM-DD: knowledge-gap resolved: {what} → added to {path}`
   - Resume the Plan step
3. If the fact is not found or the candidate set is ambiguous:
   - Create a draft task inline: `rill mkfile tasks/fix-knowledge-{parent-slug}-{topic} --slug _task --type task`, then Edit its frontmatter `status: draft`
   - Draft task Goal: `Add {what} to {path}`
   - Draft task Background: autopopulate from the blocker context
   - Append to the parent task's `## History`: `- YYYY-MM-DD: knowledge-gap deferred: {what} → draft task [fix-knowledge-...](../fix-knowledge-{...}/_task.md)`
   - Exit Phase 4 with the parent task `status: open`

**Human-input-required** (one of the three remaining `[User]` breakpoints):

1. Ask the user via the harness's question primitive: "I need {what}. If you give it to me, I'll add it to {suggest-path} and continue. Provide it, or skip?"
2. If the user provides the information:
   - Edit the target `knowledge/` file to add it
   - Append to `## History`: `- YYYY-MM-DD: knowledge-gap resolved: {what} → added to {path} (user-provided)`
   - Resume the Plan step
3. If the user skips:
   - Append to `## History`: `- YYYY-MM-DD: knowledge-gap unresolved: {what} (user deferred)`
   - Exit Phase 4 with `status: open`

##### Writing rules

- **Never write PII anywhere other than `knowledge/people/` or `knowledge/orgs/`** (ADR-047)
- If the target section does not exist in the destination file, add it as free text
- Use `Edit` to add a section to an existing file; use `rill mkfile` only when a wholly new file is required

##### Draft task naming

- Path: `tasks/fix-knowledge-{parent-task-slug}-{topic}/_task.md`
- Keep `{topic}` short and identifying

#### 4.9 Plan-gap blocker

When Phase 4 encounters a decision branch the Plan did not anticipate (a missing implementation choice, an unforeseen verification failure, a Codex Material that disputes the Plan's premises), exit cleanly:

1. Edit `_task.md`:
   - Leave `status: open` unchanged
   - Update `## Current Position` to "Plan replan needed: {what}; next action: re-run /solve to re-enter Phase 3"
   - Append to `## History`: `- YYYY-MM-DD: Plan-gap blocker — {what}`
2. From the main worktree, `rill push` so the blocker is visible on main
3. Worktree and feature branch (Lane B) stay in place for resume
4. Exit Phase 4

The next `/solve {slug}` resumes from Phase 3 (Planning), not Phase 4.

### Phase 5: Wrap-up (completion criteria check)

#### 5.1 Check completion criteria

Judge whether the Plan's "Completion criteria" is met:

- Met → 5.2 (`status: done`)
- Not met but the AI is no longer the actor (waiting on user execution / external response) → leave `status: open`, update Current Position to "{what} pending; Next action: {what}", exit
- Stopped by a fatal blocker → leave `status: open`, record the blocker in Current Position, append details to `## History`, exit. **If the blocker is a knowledge-gap, apply §4.8 first — it may auto-resolve or emit a draft task before reaching this branch**

#### 5.2 Transition to status: done

From the main worktree:

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
- **Evergreen check**: if a `knowledge/notes/` on the same theme exists, update it instead of creating a new one

#### 5.4 activity-log

```bash
rill activity-log add task:execute "{task title}" → {primary deliverable path or _task.md path}
```

#### 5.5 Final push (mandatory)

Run `rill push` from the main worktree to commit and push all Phase 5 main-worktree updates (`_task.md` `status: done`, `## History`, distillation notes, activity-log changes) to the remote.

Without this step, `status: done` lives only in the local main checkout and other Claude Code sessions / `/briefing` / `rill update` cannot see the task as completed.

#### 5.6 Display result paths

Print primary deliverable paths as Markdown links or in backticks. **Do not call `rill open`** — the user opens files via the GUI header search box (or `Cmd+P`).

#### 5.7 Worktree cleanup (Lane B only, on success)

For each Lane B target repo:

```bash
git -C $REPO worktree remove $WT
```

Skip this on Plan-gap exit, on Material halt, or any other interrupted exit — the worktree must persist for resume. The `--delete-branch` flag in `gh pr merge` already cleans up the remote and local branch on a successful merge; if a local branch remains (rare), remove it with `git branch -d feature/{slug}` (note: `-d`, not `-D`, since the merge is squashed and the branch is reachable from main).

If any worktree removal fails (e.g. due to local untracked files), surface to the user — do not force-remove (`git worktree remove --force` is a Tier 2 confirmation operation).

## Resume Operation

If `/solve {slug}` is invoked after a `/clear`:

1. Phase 1.1 validation detects the existing `## Current Position`
2. Read its content and announce "Resuming from {Phase X Step Y}"
3. Jump to that Phase / Step. Phase 1.5 (worktree resume) re-runs in case the worktree state needs reconciliation
4. Tolerate at most one step of rework (real SLA)

## Decomposition

- **Default**: solve in one ticket. If the Plan cannot articulate "why splitting is necessary", do not split
- **When splitting**: declare it as one Plan step — "create child tasks {slug-A}, {slug-B} via `rill task`, copy the parent's Background / Context, add parent path to each child's `related`". After execution, replace the corresponding line in the parent's `## Plan` with "Done — continued in [slug-A](../{slug-A}/_task.md), [slug-B](../{slug-B}/_task.md)"
- **Parent–child visibility**: holds via the child slugs being listed in the parent's Plan. No additional tooling needed

## Rules

- Source files under `inbox/` are **read-only**. Never modify them
- When reading files under `knowledge/notes/`, apply the ADR-046 metadata fixes:
  - **Mode A (direct fix)**: remove deprecated tags, migrate entity IDs from tags to mentions
  - **Mode B (append to `.refresh-queue`)**: detect empty `tags`, missing mentions / related, etc., and append to the queue
- If a same-named file exists under `_organized/`, prefer Reading that one
- Use `rill mkfile tasks/{slug} --slug {desc} --type {type}` for new artifact files under a task, **always from the main worktree** (Lane A path)
- Never create a workspace from /solve (ADR-077). If the task truly needs a shared Deep Think surface, halt and suggest `/focus <theme>` manually
- When assigning tags, Read `taxonomy.md` to check existing tags. Add a new tag only if none apply
- For in-body file references, use Markdown links of the form `[display name](relative path)`. Backtick-only ID references are forbidden
- Always include a Sources section at the end of any deliverable (URLs for web research, file paths for in-Rill references)
- When Reading a file referenced by `source:`, prefer the `_organized/` version if a same-named file exists there
- **Two-channel write invariant**: while inside a Lane B worktree, never Edit/Write under `tasks/`, `knowledge/`, `workspace/`, `pages/`, `reports/`, `inbox/`, `taxonomy.md`, `activity-log.md`. These are Lane A files and must be edited from the main worktree only
- **Worktree slug-identity**: 1 task = 1 slug = 1 worktree (`.claude/worktrees/{slug}`) = 1 branch (`feature/{slug}`) = 1 PR, identical across all target repos. Do not introduce per-purpose branch suffixes (no `feat/`, `chore/`, `docs/` prefixes; everything is `feature/{slug}`)
- **PUBLIC repo PII/JP scan (BLOCKING)** before any push to a PUBLIC repository — see §4.6
- **Per-step `[Claude]` / `[User]` tags are not used**. Step kind (Refine / Research / etc.) replaces the per-step actor tag. The only `[User]` actions are the three Remaining Breakpoints
