# Autonomous Execution Rules — Rill

`/solve` (and any future autonomous-execution skill) operates in one of two **lanes** depending on what the task touches. This document defines lane detection, the single Plan gate, the worktree convention, Codex output interpretation, the two-channel write invariant, and the three-tier classification of destructive operations.

Loaded automatically via `.claude/rules/*.md`. See `rill-core.md` for the index.

## 1. Two Lanes — Detection and Definition

PKM updates (knowledge / tasks / journal) and Rill system development (skills / rules / CLI / GUI) are physically separated into two lanes.

### 1.1 Lane definitions

| Axis | Lane A: PKM Operations | Lane B: Rill System Development |
|---|---|---|
| Purpose | Daily knowledge / tasks / journal updates | Adding / fixing Rill itself (skills, rules, CLI, GUI app) |
| Target paths | `inbox/`, `knowledge/`, `workspace/`, `tasks/`, `reports/`, `pages/`, `taxonomy.md`, `activity-log.md` | `.claude/`, `bin/rill`, `~/src/rillmd/rill/**`, sibling repos, vault's `personal-*.md` / `settings.json` |
| Branch | **main directly** | feature branch in worktree |
| Push | Commit + push immediately (`rill push`) | PR → Codex review → auto-merge |
| Review | None (use `codex review --uncommitted` only for sensitive distills) | **Codex `codex review --base main` required** |
| Worktree | None | **Required** (`.claude/worktrees/{slug}/`) |
| Concurrent sessions | Multiple OK, all see main | Each task gets its own worktree |
| Conflict resolution | `git pull --rebase` + AI two-sided merge | PR mergeable check + rebase |

### 1.2 Lane detection at Plan time

Detect from the Plan's "files to touch", evaluating in order (first match wins):

1. **One or more Lane B paths *and* one or more Lane A paths** → **Mixed** (must be checked first, otherwise step 3 swallows mixed tasks). Run as a Lane A path + Lane B path in parallel within the single task. The two-channel write invariant in §5 makes this safe: PKM updates run on main; code changes run in the Lane B worktree.
2. All targets in Lane A paths → **Lane A**
3. All targets in Lane B paths → **Lane B**

The Mixed case is the default for any task that updates both a `_task.md` artifact and code, which is most non-trivial Lane B work.

### 1.3 No single-file exception

Single-file Lane B changes (a one-line `.gitignore` addition, an ADR-only PR, a typo fix in a rule) still get a worktree. Bypassing worktree "for trivial changes" empirically drags unrelated working-tree state into the commit; the cost of one extra `git worktree add` / `git worktree remove` pair is small enough that the consistency is worth more.

## 2. The Plan Gate — Single Point of User Consent

Phase 3 Plan approval is the **only required user gate**. Once the Plan is approved, Phase 4 and Phase 5 run end-to-end without further user breakpoints, with three exceptions.

### 2.1 The three remaining `[User]` breakpoints

1. **External messaging** — sending an email, Slack message, or any communication to a human outside the user's own systems. The AI drafts; the user sends
2. **Real-world / physical action** — anything that moves matter in the physical world (mailing a parcel, calling a vendor outside automated channels)
3. **Human-input-required knowledge gap** — `/solve`'s knowledge-gap blocker handling (see `solve.md`) classifies a gap as outside Rill's reach. The AI asks the user; on response, it resumes

All three must be **explicitly declared in the Plan** at Phase 3. Implicit breakpoints during Phase 4 are not allowed.

### 2.2 The Plan-gap blocker (`status: open` exit)

When Phase 4 encounters a decision branch the Plan did not anticipate, the AI:

- Writes "Plan replan needed: {what}" to `## Current Position`
- Exits Phase 4 with `status: open` unchanged
- The next `/solve {slug}` resumes from Phase 3 (Planning), not Phase 4

This is distinct from the knowledge-gap blocker (which is about missing facts, not missing decisions).

### 2.3 Plan quality requirements

A Plan that passes the gate must contain (Phase 3 will not present it for approval otherwise):

1. **Completion criteria** — a verifiable end-state (mechanically checkable via diff, file existence, command exit code)
2. **Verification commands** — how to confirm Completion criteria (`npm test`, `rill validate`, `diff`, etc.) plus any required manual steps
3. **Review method** — `codex review --base main` (Lane B default) / none (Lane A default) / explicit "double review"
4. **Merge policy** — `auto-squash` / manual / draft PR
5. **Branch name** — `feature/{slug}` (Lane B). Lane A has no branch
6. **Files in scope** — exhaustive list (any file outside the list that gets touched is a Plan-gap signal)
7. **Target repositories** — for Lane B (`my-rill`, `rillmd/rill`, `rill-dev`, etc.)
8. **Lane** — A / B / mixed

If any of (1)–(8) is missing, Phase 3 reworks the draft before asking for approval.

## 3. Worktree Convention (slug-identity)

**Principle**: 1 task = 1 slug = 1 worktree = 1 branch = 1 PR, identical across all target repositories.

### 3.1 Naming

| Element | Value | Example |
|---|---|---|
| Task slug | from `tasks/{slug}/_task.md` directory name | `add-codex-plan-review` |
| Worktree directory | `.claude/worktrees/{slug}` (inside each target repo) | `~/src/rillmd/rill/.claude/worktrees/add-codex-plan-review` |
| Feature branch | `feature/{slug}` | `feature/add-codex-plan-review` |
| PR title prefix | `{slug}:` (searchable) | `add-codex-plan-review: ...` |
| PR head | `feature/{slug}` | — |

Cross-repo: the **same slug** is used in every target repo's worktree and branch names. Branch name collisions across repos do not occur because each repo is a separate remote.

### 3.2 Idempotent resume (five-case branching)

Phase 1.5 of `/solve` checks each target repo before doing anything. Let `WT = $REPO/.claude/worktrees/{slug}` and `BR = feature/{slug}`:

| Case | Condition | Action |
|---|---|---|
| 1 | WT exists, HEAD = BR | Reuse silently |
| 2 | WT exists, HEAD ≠ BR (corrupted state) | Halt with `[User]` breakpoint: "worktree {WT} is on unexpected branch {actual}" |
| 3 | WT missing, BR on remote | `git fetch origin BR && git worktree add WT BR` |
| 4 | WT missing, BR local-only | `git worktree add WT BR` |
| 5 | Neither WT nor BR (fresh task) | `git worktree add WT -b BR` |

PR check is parallel: `gh pr list --head feature/{slug} --state open --json number` — reuse the existing PR if found; do not create a duplicate.

### 3.3 Lifecycle

- **Created** in Phase 1.5 (or Phase 4 if the Plan deferred creation)
- **Reused** across `/clear` and resume — surviving the entire task lifetime
- **Removed** in Phase 5.6 *only* after auto-merge succeeds. Interrupted tasks keep the worktree (for resume)
- **GC**: not automated. Stale worktrees from cancelled tasks accumulate; clean them by hand when noticed

### 3.4 Sibling repo prerequisites

Each sibling repository must have `.claude/worktrees/` in its `.gitignore`.

## 4. Codex Dual Usage — Plan Review and Code Review

`/solve` calls Codex CLI twice in the lifecycle.

### 4.1 Phase 3.3 — Plan review (`codex exec`)

Verify the Plan's quality before user approval. Run after Phase 3.2 drafts the Plan into `_task.md`:

```bash
codex exec --skip-git-repo-check --sandbox read-only \
  --cd $RILL_HOME --color never "$PROMPT" </dev/null
```

`$PROMPT` includes the Plan body, relevant verification notes, and design references. End the prompt with an explicit instruction to label each evaluation point `PASS / WARN / FAIL`.

**Output interpretation** (3-valued, prompt-forced labels with position variance): `codex exec` echoes its final answer twice (streaming + tail summary). Truncate at the `tokens used` marker before counting:

```bash
awk '/^tokens used$/{exit} {print}' codex-exec-output.txt \
  | grep -oE '\b(PASS|WARN|FAIL)\b' \
  | sort | uniq -c
```

| Decision | Condition |
|---|---|
| PASS — present to user | `FAIL == 0` and `WARN <= 1` |
| Auto-fix — replan + re-review (1 loop) | `FAIL == 1` or `WARN >= 2` |
| Material — halt for Plan replan | `FAIL >= 2`, *or* a single FAIL on a core invariant (slug-identity, two-channel write, PII guard) |

Save output as `tasks/{slug}/NNN-codex-plan-review.md` from the main worktree.

**Operational notes**:

- `</dev/null` is required to prevent `stdin` hang
- `--skip-git-repo-check` is required when `--cd` points outside a trusted git repo
- Output appears twice (streaming + final summary) — de-dup before counting
- Label position relative to the evaluation point varies; use loose regex

### 4.2 Phase 4.5 — Code review (`codex review`)

Verify the worktree's code changes after commit. `--base main` works post-commit, pre-push:

```bash
cd $WT
codex review --base main </dev/null
```

**Output interpretation** (sharp 3-valued signal, no prompt instruction needed):

```bash
UNIQUE_P_LINES=$(grep -E '^- \[P[123]\]' codex-review-output.txt | sort -u | wc -l)
```

| Decision | Condition |
|---|---|
| PASS — proceed to push | `UNIQUE_P_LINES == 0` |
| Trivial auto-fix — Edit + `--amend` + re-review (1 loop) | `[P2]` or `[P3]` only |
| Material — halt with `[User]` breakpoint | `[P1]` >= 1 |

Save output as `tasks/{slug}/NNN-codex-review-{repo}.md` from the main worktree.

**Operational notes**:

- `--color` flag is not accepted (different from `codex exec`)
- `--base` and positional `[PROMPT]` are mutually exclusive — review uses the built-in prompt
- File paths in `[Pn] ... — /abs/path:line` are absolute; normalize to repo-relative before forwarding to PR comments
- Workdir must be a git repo (no `--skip-git-repo-check` flag here)

## 5. Two-Channel Write Invariant

In a mixed task (Lane A + Lane B), both lanes write concurrently into the **same `_task.md`** without conflict, because each lane writes through a different channel that touches disjoint file sets.

### 5.1 The invariant

A Lane B feature branch must **never** modify files under any of:

- `tasks/`
- `knowledge/`
- `workspace/`
- `pages/`
- `reports/`
- `inbox/`
- `taxonomy.md`
- `activity-log.md`

These files are reserved for the **main worktree** (Lane A channel). The Lane B worktree only touches:

- `.claude/`
- `bin/`
- `app/`
- sibling repos' equivalent locations

### 5.2 Why this works

Squash-merge is a 3-way merge. For any file `F` that the feature branch did not touch:

- base ancestor = `F` at branch-off
- ours (main HEAD) = `F` with all Lane A updates since branch-off
- theirs (feature HEAD) = `F` at branch-off (unchanged)

→ git automatically picks ours; no conflict.

### 5.3 Consequences

- A task's `_task.md` status / Current Position / History stay current on main throughout Phase 4, even mid-task
- Interrupted Lane B tasks show as `status: open` on main, so other Claude Code sessions and `/briefing` see them
- PR squash-merge of the Lane B branch carries only code; `_task.md` updates were already on main

### 5.4 Enforcement

- `solve.md` Phase 4 forbids Lane B Edit of forbidden paths (procedural enforcement)
- The PostToolUse hook (`rill activity-log on-write` / `rill touch`) is structurally no-op for worktree-resident paths — Lane B writes to forbidden paths produce no hook side-effect, but the *commit* on the feature branch is still a violation that this rule disallows
- A future guard could add a pre-commit hook that fails when a Lane B branch stages a forbidden path; the procedural rule is currently sufficient

## 6. Three-Tier Destructive Operations

Operations are classified by reversibility and blast radius.

### 6.1 Tier 1 — AI autonomous (no user confirmation)

- `git add` / `git commit` / `git push` to feature branches
- `git pull` / `git fetch` / `git rebase` / `git merge` (conflicts: AI two-sided merge)
- `git worktree add` / `git worktree remove` (only for worktrees owned by the current task)
- `git checkout` / `git switch` (within a worktree)
- `gh pr create` / `gh pr merge --(auto-)squash --delete-branch` / `gh pr comment`
- `codex review` / `codex exec`
- File `Edit` / `Write` / `Read`
- `rill push` / `rill mkfile` / `rill activity-log add`

### 6.2 Tier 2 — User confirmation required (even if Plan declared)

- Bulk file deletion (3+ files, or any deletion under the personal-entities layer)
- `.claude/` config changes (`settings.json`, rules) committed via the Lane A channel — this is a misclassification signal
- Direct `status: cancelled` transition on `_task.md` (whereas `done` is autonomous)
- Removal of a worktree the current task did not create
- Non-squash merge commits to main

### 6.3 Tier 3 — Deny (absolutely forbidden, enforced via settings.json)

| Pattern | Reason |
|---|---|
| `Bash(git push --force*)` | Overwrites remote history |
| `Bash(git push -f *)` | Same |
| `Bash(git push * main*)` | Direct main push (use PR) |
| `Bash(git push * master*)` | Same |
| `Bash(git reset --hard*)` | Discards working tree |
| `Bash(git clean -f*)` | Removes untracked files unrecoverably |
| `Bash(git branch -D *)` | Removes unmerged branch state |
| `Bash(gh pr merge --admin*)` | Bypasses branch protection |
| `rm -rf` on absolute paths | Catastrophic blast radius |

`/solve` relies on these being denied in `.claude/settings.json`. The matcher syntax must follow space-form (`Bash(... *)`); colon-form (`Bash(...:*)`) is not documented for Bash and should not be used.

Settings rules are evaluated in order **deny → ask → allow** (first match wins), so a Tier 3 deny correctly overrides a Tier 1 allow.

## 7. PUBLIC Repository Guard

Repositories that are PUBLIC (the OSS core repo and the demo vault) must clear the following BLOCKING scans before `git push`:

1. **CJK / Japanese scan**: `git diff HEAD~1 HEAD | LC_ALL=C grep -nP '[\x{3000}-\x{9fff}\x{ff00}-\x{ffef}]'` — halt on hit
2. **PII mapping scan**: grep for the entries listed in the vault's local PII mapping table (held in the vault's `personal-*.md`, not in this repo) — halt on hit
3. **Email / phone scan**: regex for `\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b` and `\b\d{2,4}-\d{2,4}-\d{4}\b` — halt and confirm (false-positive prone)

All three are BLOCKING — push proceeds only if all pass.

PRIVATE repos do not require these scans.

## 8. Cross-Reference

- `solve.md` — the procedural skill that implements this rule
- `rill-tasks.md` — `## Plan` section format
- `rill-claude-code-integration.md` — `rill push` behavior, hook semantics
- the vault's `personal-dev.md` (per-vault) — cross-repo routing + PII mapping
