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

## 8. Cross-Reference

- `solve.md` — procedural skill implementing this rule
- `rill-tasks.md` — `## Plan` section format
- `rill-claude-code-integration.md` — `rill push` behavior, hook semantics
- vault's `personal-dev.md` (per-vault) — cross-repo routing + PII mapping
