---
created: 2026-04-07T11:10+09:00
type: analysis
---

# /solve — Information Architecture Document (IAD)

Behavioral specification for /solve. Executes a task ticket end-to-end via a Plan-gated flow (ADR-081, ADR-082): Phase 3 Plan approval is the only required user gate in interactive mode; Phase 4 and Phase 5 then run autonomously, with three narrow exceptions (external messaging, physical action, human-input-required knowledge gap) that must be declared in the Plan. Delegated from `/project {slug} run`, /solve runs in autonomous mode — even Phase 3 approval is replaced by a project-level policy + Codex PASS, and every remaining decision point queues instead of asking.

**Test strategy**: A single `claude -p` turn progresses through Phase 1→2→3→4→5. Resumability, Plan-quality-field completeness, lane routing, worktree idempotency, and `status: done` on completion are structurally verified.

Post-ADR-077 (D77-1/D77-2): /solve never creates a workspace. All artifacts land under `tasks/{slug}/` alongside `_task.md`.

---

## 1. Input/Output Definitions

### Input

| ID | Input | Condition |
|----|-------|-----------|
| IO-I1 | `tasks/{slug}/_task.md` path, or a task slug | Direct invocation |
| IO-I2 | Omitted | Ask which task to run |
| IO-I3 | Delegated from `/project {slug} run` | Autonomous mode — decision points queue instead of asking (ADR-082) |
| IO-I4 | Legacy flat-file path `tasks/{slug}.md` | Rejected — ask the user to run `rill migrate tasks-v1` first (ADR-076) |

### Output

| ID | Output | Condition |
|----|--------|-----------|
| IO-O1 | `tasks/{slug}/NNN-*.md` artifacts (research / analysis / decision / progress / review) | Plan steps that produce deliverables |
| IO-O2 | Lane A: direct commits to main via `rill push` | PKM-domain files (inbox/, knowledge/, workspace/, tasks/, reports/, pages/, taxonomy.md, activity-log.md) |
| IO-O3 | Lane B: `feature/{slug}` branch in `.claude/worktrees/{slug}/`, PR, squash-merge | Dev-domain files (.claude/, bin/, app/, sibling repos) |
| IO-O4 | `_task.md` frontmatter `status: done` | On completion — /solve is a doer, not a delegator; it never leaves a finished task at `waiting` |

---

## 2. Invariants

| ID | Invariant | Verification Method | Status |
|----|-----------|-------------------|--------|
| INV-01 | inbox/ is immutable | Hash comparison | ✅ |
| INV-02 | Two-channel write: a Lane B worktree never edits tasks/, knowledge/, workspace/, pages/, reports/, inbox/, taxonomy.md, activity-log.md | Diff path check | ✅ |
| INV-03 | Do not execute if task status is done/cancelled | Output verification | ✅ |
| INV-04 | No workspace is created as a side effect of /solve (ADR-077 D77-1) | `workspace/` diff check | ✅ |
| INV-05 | Worktree / branch / PR are idempotent on slug: 1 task = 1 slug = 1 worktree = 1 branch = 1 PR | State check | ✅ |
| INV-06 | A `[DECISION-QUEUE]` → `[DECISION-RESOLVED]` transition is never originated by the agent (ADR-084 D84-1) | grep | ✅ |

---

## 3. Phase 1: Intake

| ID | Rule | Verification Method | Status |
|----|------|-------------------|--------|
| P1-01 | Read the task file, source, related files, mentions, and `knowledge/self/profile.md` | ⚠️ Log | ✅ |
| P1-02 | List every file Read in Phase 1, for transparency | grep | ✅ |
| P1-03 | Presence of `## Current Position` means this is a resume; jump to the recorded Phase / Step | Field check | ✅ |
| P1-04 | Decision-marker scan runs before any other work: consume `[DECISION-RESOLVED]` blocks, apply the outcome, move it to `## History` as `[DECISION-DONE]` | grep + Log | ✅ |
| P1-05 | Worktree resume check (Lane B only): five-case branching on worktree / branch existence, converges to one worktree per task per repo | State check | ✅ |

---

## 4. Phase 2: Enrichment Judgment

| ID | Rule | Verification Method | Status |
|----|------|-------------------|--------|
| P2-01 | AI states in one line whether the task's information is sufficient or WebSearch / Vault Search will run | ⚠️ LLM judgment | ✅ |
| P2-02 | No artifact file is created in Phase 2 itself — findings feed directly into the Phase 3 Plan | File existence check | ✅ |

---

## 5. Phase 3: Planning

| ID | Rule | Verification Method | Status |
|----|------|-------------------|--------|
| P3-01 | The Plan declares all 8 required fields: completion criteria, verification commands, review method, merge policy, branch name, files in scope, target repositories, lane | Field check | ✅ |
| P3-02 | Codex Plan review (`codex exec --sandbox read-only`) runs before user approval | Log verification | ✅ |
| P3-03 | Codex verdict: PASS requires `>= 1` parsed PASS label and `FAIL == 0` and `WARN <= 1`; zero parsed labels or any other verdict never auto-approves (fail closed) | grep | ✅ |
| P3-04 | Interactive: the user approves the Plan explicitly. Autonomous: policy + Codex PASS substitute for the ask; Material / out-of-policy / unparseable Codex output → `[DECISION-QUEUE]` + exit `status: open` | ⚠️ Interactive / Log | ✅ |
| P3-05 | Default is one ticket, no split, unless the Plan states why splitting is necessary | ⚠️ LLM judgment | ✅ |

---

## 6. Phase 4: Execute

Lane-aware; no per-step user approval (the Plan gate already authorized execution). Three exceptions only, and only if the Plan declared them: external messaging, physical action, human-input-required knowledge gap.

| ID | Rule | Verification Method | Status |
|----|------|-------------------|--------|
| P4-01 | Lane A: Edit/Write in the main worktree, then `rill push` (pull `--rebase` + two-sided merge on push failure) | Diff check | ✅ |
| P4-02 | Lane B: Edit/Write inside `$REPO/.claude/worktrees/{slug}`, run the Plan's verification commands, then commit | File existence + diff | ✅ |
| P4-03 | Lane B code review: `codex review --base main` runs after commit, before push | Log verification | ✅ |
| P4-04 | Codex review verdict: 0 unique `[Pn]` lines → proceed to push; `[P2]`/`[P3]` only → one trivial auto-fix + re-review loop; `[P1] >= 1` → Material, halt (interactive) or `[DECISION-QUEUE]` + exit (autonomous) | grep | ✅ |
| P4-05 | PUBLIC repository guard (PUBLIC targets only): non-ASCII scan, PII-mapping scan, email/phone scan — all three block push on any hit | grep | ✅ |
| P4-06 | Push, PR create-or-edit (idempotent via the Phase 1.5 PR check), merge per the Plan's declared merge policy | Log verification | ✅ |
| P4-07 | Knowledge-gap blocker: auto-recoverable gaps are resolved in-flight (fact written to `knowledge/`, step resumes); human-input-required gaps ask (interactive) or `[DECISION-QUEUE]` + exit (autonomous); PII is never written outside `knowledge/people/` or `knowledge/orgs/` | ⚠️ Log | ✅ |
| P4-08 | Plan-gap blocker: an unanticipated decision branch exits with `status: open` and a resume note; the next `/solve` re-enters Phase 3, not Phase 4 | Field check | ✅ |

---

## 7. Phase 5: Wrap-up

| ID | Rule | Verification Method | Status |
|----|------|-------------------|--------|
| P5-01 | Completion criteria met → frontmatter `status: done` (never `waiting`); `## Current Position` is deleted | fm_get | ✅ |
| P5-02 | Not met, but the AI is no longer the actor (waiting on user / external response) → `status: open`, Current Position states what's pending | fm_get | ✅ |
| P5-03 | Task `## History` section gains an execution record line | grep | ✅ |
| P5-04 | New artifacts are added to `## Context` with a role descriptor | grep | ✅ |
| P5-05 | Knowledge distillation to `knowledge/notes/` when the task carries decision / insight / reference value; pure actions are not distilled | ⚠️ LLM judgment | ✅ |
| P5-06 | `activity-log.md` gains an entry for the /solve run | grep | ✅ |
| P5-07 | A final `rill push` runs from the main worktree — without it, `status: done` stays local-only and invisible to other sessions | Log verification | ✅ |
| P5-08 | The Lane B worktree is removed only after a successful completion (post squash-merge); it is kept on any interrupted exit for resume | State check | ✅ |
