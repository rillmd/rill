# Autonomous Execution Rules — Rill

`/solve` (and any future autonomous-execution skill) operates in one of two **lanes** depending on what the task touches. Loaded automatically via `.claude/rules/*.md`.

## 1. Two Lanes

PKM updates and Rill system development are physically separated.

| Axis | Lane A: PKM Operations | Lane B: Rill System Development |
|---|---|---|
| Purpose | Daily knowledge / tasks / journal updates | Adding / fixing Rill itself (skills, rules, CLI, GUI) |
| Target paths | `inbox/`, `knowledge/`, `workspace/`, `tasks/`, `reports/`, `pages/`, `taxonomy.md`, `activity-log.md` | `.claude/`, `bin/rill`, `~/src/rillmd/rill/**`, sibling repos, vault's `personal-*.md` / `settings.json` |
| Branch | main directly | feature branch in worktree |
| Push | Commit + push immediately (`rill push`) | PR → Codex review → auto-merge |
| Review | None (use `codex review --uncommitted` only for sensitive distills) | `codex review --base main` required |
| Worktree | None | Required (`.claude/worktrees/{slug}/`) |
| Conflict resolution | `git pull --rebase` + AI two-sided merge | PR mergeable check + rebase |

### Lane detection at Plan time

Detect from the Plan's "files to touch", first match wins:

1. **Lane B paths *and* Lane A paths** → **Mixed** (check first; the two-channel write invariant in §5 makes this safe)
2. All Lane A → **Lane A**
3. All Lane B → **Lane B**

Mixed is the default for any task updating both `_task.md` and code.

Single-file Lane B changes still get a worktree (consistency > the cost of one `git worktree add` / `remove` pair).

## 2. The Plan Gate

Phase 3 Plan approval is the **only required user gate**. Phase 4 / 5 run end-to-end with three exceptions only:

1. **External messaging** — email, Slack, anything to a human outside the user's systems (AI drafts, user sends)
2. **Real-world / physical action** — moves matter in the physical world
3. **Human-input-required knowledge gap** — see `solve.md` knowledge-gap blocker; AI asks, user answers, AI resumes

All three must be **explicitly declared in the Plan**.

### Plan-gap blocker (`status: open` exit)

When Phase 4 hits an unanticipated decision branch: write "Plan replan needed: {what}" to `## Current Position`, exit Phase 4 with `status: open`. Next `/solve {slug}` resumes from Phase 3 (Planning), not Phase 4. Distinct from the knowledge-gap blocker (missing facts, not missing decisions).

### Plan quality requirements

A Plan must contain: (1) Completion criteria (verifiable end-state), (2) Verification commands, (3) Review method (codex / none / explicit), (4) Merge policy, (5) Branch name (Lane B), (6) Files in scope (exhaustive — anything outside is a Plan-gap signal), (7) Target repositories (Lane B), (8) Lane. Missing any → Phase 3 reworks before requesting approval.

## 3. Worktree Convention (slug-identity)

**Principle**: 1 task = 1 slug = 1 worktree = 1 branch = 1 PR, identical across all target repositories.

| Element | Value |
|---|---|
| Task slug | from `tasks/{slug}/_task.md` directory name |
| Worktree | `$REPO/.claude/worktrees/{slug}` |
| Feature branch | `feature/{slug}` |
| PR title prefix | `{slug}:` (searchable) |

Cross-repo: the same slug in every target repo; branch collisions don't occur (each repo is a separate remote).

### Idempotent resume (five-case branching)

Phase 1.5 checks each target repo. Let `WT = $REPO/.claude/worktrees/{slug}`, `BR = feature/{slug}`:

| Case | Condition | Action |
|---|---|---|
| 1 | WT exists, HEAD = BR | Reuse silently |
| 2 | WT exists, HEAD ≠ BR | Halt with `[User]` breakpoint |
| 3 | WT missing, BR on remote | `git fetch origin BR && git worktree add WT BR` |
| 4 | WT missing, BR local-only | `git worktree add WT BR` |
| 5 | Neither | `git worktree add WT -b BR` |

PR check: `gh pr list --head feature/{slug} --state open --json number` — reuse if found.

### Lifecycle

Created in Phase 1.5. Reused across `/clear`. Removed in Phase 5.6 only after auto-merge succeeds (interrupted tasks keep the worktree). GC is manual.

Each sibling repository must have `.claude/worktrees/` in its `.gitignore`.

## 4. Codex Dual Usage

### 4.1 Phase 3.3 — Plan review (`codex exec`)

```bash
codex exec --skip-git-repo-check --sandbox read-only \
  --cd $RILL_HOME --color never "$PROMPT" </dev/null
```

`$PROMPT` includes the Plan body + relevant verification notes + an instruction to label each evaluation point `PASS / WARN / FAIL`.

**Output interpretation** (3-valued, prompt-forced labels). `codex exec` echoes its answer twice (streaming + tail summary); truncate at the `tokens used` marker:

```bash
awk '/^tokens used$/{exit} {print}' codex-exec-output.txt \
  | grep -oE '\b(PASS|WARN|FAIL)\b' | sort | uniq -c
```

| Decision | Condition |
|---|---|
| PASS — present to user | `FAIL == 0` and `WARN <= 1` |
| Auto-fix — replan + re-review (1 loop) | `FAIL == 1` or `WARN >= 2` |
| Material — halt for Plan replan | `FAIL >= 2`, *or* a single FAIL on a core invariant (slug-identity, two-channel write, PII guard) |

Save as `tasks/{slug}/NNN-codex-plan-review.md` from the main worktree.

**Operational**: `</dev/null` required (prevents stdin hang). `--skip-git-repo-check` required when `--cd` points outside a trusted git repo. De-dup output before counting. Use loose regex (label position varies).

### 4.2 Phase 4.5 — Code review (`codex review`)

`--base main` works post-commit, pre-push:

```bash
cd $WT
codex review --base main </dev/null
```

```bash
UNIQUE_P_LINES=$(grep -E '^- \[P[123]\]' codex-review-output.txt | sort -u | wc -l)
```

| Decision | Condition |
|---|---|
| PASS — proceed to push | `UNIQUE_P_LINES == 0` |
| Trivial auto-fix — Edit + `--amend` + re-review (1 loop) | `[P2]` or `[P3]` only |
| Material — halt with `[User]` breakpoint | `[P1]` >= 1 |

Save as `tasks/{slug}/NNN-codex-review-{repo}.md` from the main worktree.

**Operational**: `--color` flag not accepted (differs from `codex exec`). `--base` and positional `[PROMPT]` are mutually exclusive. Paths in `[Pn] ... — /abs/path:line` are absolute; normalize to repo-relative for PR comments. Workdir must be a git repo (no `--skip-git-repo-check` here).

## 5. Two-Channel Write Invariant

A Lane B feature branch **must never modify** files under `tasks/`, `knowledge/`, `workspace/`, `pages/`, `reports/`, `inbox/`, `taxonomy.md`, `activity-log.md`. Those are the main worktree (Lane A) channel. The Lane B worktree only touches `.claude/`, `bin/`, `app/`, sibling repos' equivalents.

This works because squash-merge is a 3-way merge: for any file F the feature branch didn't touch, `theirs` (feature HEAD) = base ancestor, so git picks `ours` (main HEAD with Lane A updates) automatically — no conflict.

Consequences: `_task.md` Current Position / History stay current on main throughout Phase 4. Interrupted Lane B tasks show `status: open` on main, so other sessions and `/briefing` see them. PR squash carries only code.

Enforcement is procedural (`solve.md` Phase 4 forbids Lane B Edit of forbidden paths). A future pre-commit hook could enforce structurally.

## 6. Three-Tier Destructive Operations

### Tier 1 — AI autonomous

`git add` / `commit` / `push` to feature branches. `git pull` / `fetch` / `rebase` / `merge` (conflicts: AI two-sided merge). `git worktree add` / `remove` (current task only). `git checkout` / `switch` (within a worktree). `gh pr create` / `merge --(auto-)squash --delete-branch` / `comment`. `codex review` / `exec`. File `Edit` / `Write` / `Read`. `rill push` / `mkfile` / `activity-log add`.

### Tier 2 — User confirmation required (even if Plan declared)

- Bulk file deletion (3+ files, or any deletion under the personal-entities layer)
- `.claude/` config changes (`settings.json`, rules) committed via the Lane A channel — misclassification signal
- Direct `status: cancelled` transition on `_task.md` (`done` is Tier 1)
- Removal of a worktree the current task did not create
- Non-squash merge commits to main
- **Weakening a task's own verification** — editing a Plan's `## Verification` to drop / loosen a check, or deleting / hollowing out a test the Plan relies on (ADR-082 §10). Fixing the code under test is Tier 1; rewriting the gate to be trivially satisfiable is Tier 2

### Tier 3 — Deny (forbidden, enforced via settings.json)

| Pattern | Reason |
|---|---|
| `Bash(git push --force*)` / `Bash(git push -f *)` | Overwrites remote history |
| `Bash(git push * main*)` / `Bash(git push * master*)` | Direct main push (use PR) |
| `Bash(git reset --hard*)` | Discards working tree |
| `Bash(git clean -f*)` | Removes untracked files unrecoverably |
| `Bash(git branch -D *)` | Removes unmerged branch state |
| `Bash(gh pr merge --admin*)` | Bypasses branch protection |
| `rm -rf` on absolute paths | Catastrophic blast radius |

`/solve` relies on these being denied in `.claude/settings.json`. Matcher syntax: space-form (`Bash(... *)`), not colon-form (`Bash(...:*)`). Rules evaluate **deny → ask → allow** (first match wins) — Tier 3 deny correctly overrides Tier 1 allow.

## 7. PUBLIC Repository Guard

PUBLIC repos (OSS core, demo vault) must clear all three BLOCKING scans before `git push`:

1. **CJK / Japanese**: `git diff HEAD~1 HEAD | LC_ALL=C grep -nP '[\x{3000}-\x{9fff}\x{ff00}-\x{ffef}]'`
2. **PII mapping**: grep for entries in the vault's local `personal-*.md` mapping table (not in this repo)
3. **Email / phone**: `\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b` and `\b\d{2,4}-\d{2,4}-\d{4}\b`

Push only when all pass. PRIVATE repos do not require these scans.

## 8. Project-Level Policy Gate (ADR-082)

`/project {slug} run` lifts the per-task Plan gate (§2) to a **once-per-project execution policy**. The user approves an envelope once when the runner starts; thereafter each task's Plan is auto-approved when it stays inside that envelope and Codex Plan review returns PASS.

The policy envelope declares:

- **Allowed lanes** — A only / B allowed / mixed
- **File & repository scope** — which paths and repos the runner may touch
- **PUBLIC-push posture** — Plans that push to a PUBLIC repo: always require a human, or auto if in-scope
- **Stop-condition trio** (§11) — max tasks/iterations, no-progress detection, time/budget ceiling
- **Tier 2 posture** — queue and skip vs halt

Auto-approval rule (in `/solve` autonomous mode):

| Condition | Action |
|---|---|
| Codex PASS (**`>=1` parsed PASS label** and `FAIL==0` and `WARN<=1`) **and** Plan inside envelope | Auto-approve → Phase 4, no prompt |
| Plan outside envelope (unauthorized repo/lane/PUBLIC push) | Human-decision queue (§9) + exit `status: open` |
| Codex `WARN>=2` or `FAIL>=1` | Per §2 / §4.1: auto-fix loop, else queue |
| **Codex output unparseable** (zero labels) **or any non-PASS verdict** (e.g. a lone WARN, no PASS) | **Do not auto-approve** — queue + exit (fail-safe) |

The fail-safe (never silently auto-approve on an unreadable verdict) is load-bearing: it prevents a broken Codex CLI from becoming a rubber stamp. Auto-approval requires a **positively-parsed PASS label**, never merely the absence of FAIL — a zero-label or WARN-only output must not pass.

### Consequence-framed approval (ADR-082 D82-8)

The policy approval is the one synchronous human gate, so it must be one the user can actually judge. **Write it by consequence, not by mechanism** — in the user's language, with concrete values (real task titles / repos / numbers), covering only: what the runner will do unattended, what it will always stop for, when it stops, and what it will work on. Do **not** surface internal labels (`Lane`, `Tier 2`, `entry filter`, `stop-condition trio`, `Codex PASS`) on the approval screen; translate each to what will happen, and keep the mechanism references (§8–§11) for the implementer. The same rule governs every human-facing surface (the human-decision queue entries, the stop summary, the future HTML digest). Rationale: an approval the user can't understand defeats the gate. See `personal-plain-communication.md` and `skills/project/SKILL.md` Step 1.

## 9. Human-Decision Queue (ADR-082)

In autonomous mode, every point that would synchronously ask the user instead writes a **`[DECISION-QUEUE]`** entry into the task's `## Current Position` and exits `status: open` (or skips, for Tier 2). No new file or schema — the queue is the set of open tasks carrying the marker.

Enumerate it deterministically (markers count at line start only; contract v1.1 extends the scope to project files — ADR-084):

```bash
grep -rlE '^(- )?\[DECISION-QUEUE' tasks/*/_task.md projects/*/_project.md
```

Each entry carries an `id=dN` (numbered per file; legacy id-less entries stay visible but cannot be consumed until an id is added) and these **human-facing fields**, written for the reader and not the AI (ADR-084 D84-7):

1. **Decision** — the one question to the human, plain language
2. **Background** — zero-context orientation: what effort this is part of (one sentence), why this decision is needed now, what answering advances
3. **Choices** — the options, each with its plain-language consequence; the AI's recommendation marked
4. **Default** — what happens while it stays unanswered (descriptive, not executive — ADR-084 D84-3)
5. **Blocks** — what stays stuck until it is resolved
6. **More** — links to full sources; include whenever Background leans on them (the reader's verification escape hatch)

Two absolute rules on the content (ADR-084 D84-7): **no internal labels** in any field (translate `Tier 2` and the like to its consequence), and **the reader is assumed to have zero context** (Background starts from the top-level effort; deep sources go in `More`, not inline). Field labels are English (stable parse tokens); content is in the user's language; the app card localizes the labels. This is the D82-8 "consequence-framed" rule made concrete for the queue.

Resolution and consumption follow the three-state contract `[DECISION-QUEUE]` → `[DECISION-RESOLVED]` → `[DECISION-DONE]` (ADR-084): the RESOLVED transition is written by the human or the app only — an agent never originates it. The next resume consumes RESOLVED without re-asking and logs DONE to `## History`. The `## Pending Decisions` digest in project files is a deterministic derived view recomputed by `refresh-decisions` (ADR-084 D84-5).

Resolution is **non-destructive** (ADR-084 D84-8): a decision is resolved by a marker/status transition, never by deleting the file or entry (git history = audit). RESOLVED carries `Chosen: N` (accepted an option) **or** `Declined: true` (deliberately none — an explicit "no", distinct from an unanswered QUEUE's silence). The correlation / resume key is the stable file path plus the decision `id` (the file-native `elicitationId` / `thread_id`); `[DECISION-DONE]` is the explicit completion signal.

**Every queue writer emits this v1.1 format** — `/solve`, `/project run`, and any future runner — and refreshes the affected projects' digests via `refresh-decisions` before exiting. Project-scoped RESOLVED blocks are consumed by the next agent operating under that project (a `/solve` of a task mentioning it, or a `/project` invocation); their DONE audit lines append to the project file's `## Decision Log` section (append-only, created on first use — ADR-084 D84-4).

Points that route here (see `solve.md` §Autonomous Mode): draft-task approval, Codex Material (Plan or code), human-input-required knowledge gap, Tier 2 operations, out-of-envelope Plans. External messaging and physical actions **always** queue in autonomous mode regardless of policy.

## 10. Verification Immutability (ADR-082)

A long-running autonomous loop must not be able to pass by **weakening its own gate** (the reward-hacking failure mode). Editing a Plan's `## Verification` to remove / loosen a check, or deleting / hollowing out a test the Plan relies on, is **Tier 2** (§6) — user confirmation in interactive mode, queue-and-skip in autonomous mode. Fixing the code under test is always Tier 1; rewriting the check so it is trivially satisfiable is not.

## 11. Runner Economics & Concurrency (ADR-082)

**Execution paths** (the 2026-06-15 billing change moved `claude -p` / Agent SDK off the subscription pool into a separate monthly credit — Pro $20 / Max 5x $100 / Max 20x $200; interactive Claude Code is unchanged):

| Path | Mechanism | Billing | Use |
|---|---|---|---|
| **Primary** | Interactive terminal session running `/project {slug} run` | Subscription pool | Daytime; 1 project = 1 terminal session |
| **Secondary** (opt-in) | `claude -p "/project {slug} run --max-tasks 1"` via launchd / cron | Agent SDK credit | Overnight "once-a-night + small merges" |

This supersedes the assumption in ADR-068 D68-3 that `claude -p` automation draws on the flat subscription. The CLI-companion model (D68-1) and Agent-SDK-not-adopted (D68-2) are unchanged.

**Stop-condition trio** (required runner parameters): (1) max tasks / iterations; (2) no-progress detection — a task that returns to Plan-gap twice is isolated and the runner moves on; all-isolated → stop; (3) time / budget ceiling.

**Concurrency**: Lane B is worktree-isolated, but Lane A work for *every* project shares the one main worktree, where `git add -A` (or `rill push`) can swallow another session's uncommitted changes. A per-project lock would not protect this — two runners on different projects still collide on the shared main worktree. So until `rill push` stages explicit paths, **run one runner total** — a single **global** lock (`.claude/state/project-run.lock`, no slug; `.claude/state/` must be git-ignored). Acquire atomically (`mkdir`), reclaim only when stale, release on every exit. Parallel runners — even across different projects — are a follow-up gated on explicit-path staging.

## 12. Cross-Reference

- `solve.md` — procedural skill implementing this rule (interactive + autonomous modes)
- `project.md` (`skills/project/SKILL.md`) — the `run` mode that drives the §8 policy gate and §9 queue
- `rill-tasks.md` — `## Plan` section format
- `rill-claude-code-integration.md` — `rill push` behavior, hook semantics
- vault's `personal-dev.md` (per-vault) — cross-repo routing + PII mapping
