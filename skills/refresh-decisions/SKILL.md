---
name: refresh-decisions
description: Recompute the `## Pending Decisions` digest section of `projects/{slug}/_project.md` by collecting line-start `[DECISION-QUEUE]` markers from the project's tasks and the project file itself (decision-loop contract v1.1, ADR-084). Deterministic grep-render-replace, no LLM judgment, idempotent. Use after an agent queues a decision, after a human resolves one, or as a leaf invoked by other skills.
gui:
  label: "/refresh-decisions"
  hint: "Recompute the Pending Decisions digest in _project.md"
  match:
    - "projects/*/_project.md"
  arg: slug
  order: 17
  mode: auto
---

# /refresh-decisions -- Pending-Decisions Digest Refresh

**Conduct ALL conversation with the user in the language defined by `.claude/rules/personal-language.md`** (or the user's input language if absent). The English instructions below are for skill clarity, not for output style. Exceptions (only): tokens inside backticks or code blocks, proper nouns, ASCII acronyms.

> **Tool references in this skill** (`Read`, `Edit`, `Grep`, `Glob`, `shell`) describe **intent**, not Claude-specific tool calls. Each harness should map them to its native equivalent.

Recomputes one auto-maintained section of a project's main file:

- `## Pending Decisions` -- a digest of every unresolved decision (`[DECISION-QUEUE]` marker at line start) that belongs to this project, collected from (a) task tickets whose frontmatter `mentions` include `projects/{slug}` and (b) project-scoped first-class entries inside `projects/{slug}/_project.md` itself (ADR-084 D84-4)

This is the **deterministic derived view** of the decision-loop contract (ADR-084 D84-5): grep, render, full-section replace. The markers in the source files remain the single source of truth; resolving happens **there** (a human rewrites `[DECISION-QUEUE id=dN]` to `[DECISION-RESOLVED id=dN ...]`), never in the digest. No LLM judgment over decision content is applied.

Every other section of `_project.md` is owned by other skills (see the section-ownership table in `.claude/rules/rill-projects.md`) and **must not be touched**.

## Arguments

$ARGUMENTS -- one of:

- `{slug}` -> refresh the single project at `projects/{slug}/_project.md`
- `--all` -> refresh every project under `projects/*/_project.md` with `status: active` or `status: planning` (sequential, per-slug locks)
- Omitted -> ask which project, via the harness's question primitive. Internal callers must pass an explicit `{slug}` or `--all`

## Procedure

### Phase 0: Input validation + lock

1. Resolve `projects/{slug}/_project.md`. If missing: propose similar slugs via `Glob(projects/*)`, exit with a one-line error (do not auto-create).
2. Acquire `.claude/state/refresh-decisions-{slug}.lock` (atomic `mkdir` semantics; poll up to 30 s; on timeout warn and exit, leaving the section stale rather than racing another writer).

### Phase 1: Collect queued decisions

1. Task-origin entries:
   ```
   Grep(pattern="^mentions:.*projects/{slug}[,\\]\\s]", path="tasks/", glob="**/_task.md", output_mode="files_with_matches")
   ```
   The closing character class (comma, bracket, whitespace) prevents prefix collisions -- a word boundary alone would let `projects/rill` match `projects/rill-dev`. For each matched file, scan for line-start markers: `grep -nE '^(- )?\[DECISION-QUEUE' {file}`.
2. Project-scoped entries: scan `projects/{slug}/_project.md` itself with the same line-start pattern, **excluding the `## Pending Decisions` section** (self-reference guard; the rendered digest never uses line-start marker syntax, but the exclusion keeps the recompute well-defined even if a future renderer changes).
3. For each hit, parse the block that follows the marker line (until the first blank line or the next line-start marker): the human-facing fields `Decision`, `Background`, `Choices` (with the recommended one), `Default`, `Blocks`, `More`, and the `id` (ADR-084 D84-7). Parse each field by its label; a field that is absent (commonly `More` on a self-contained decision) is simply omitted from the render — do not fail or emit a placeholder. Backward compatibility: an entry still using the pre-2026-07-08 labels is read by mapping `What`→`Decision` and `Options`→`Choices` (and ignoring `Why AI can't decide`), so any decision queued before the D84-7 field revision still renders.
   - Legacy entries without `id=` are included, labeled `id=?`, with a note that they cannot be consumed until an id is added (ADR-084 D84-2).
   - `[DECISION-RESOLVED]` blocks are **not** listed (they are awaiting agent consumption, not human attention). `[DECISION-DONE]` lines live in History / Decision Log and are ignored.
4. Sort deterministically: by source file path (lexicographic), then by numeric id.

### Phase 2: Section rewrite (atomic)

Replace the entire `## Pending Decisions` section body. Manual edits inside it do not survive (section-ownership doctrine).

#### Format

```markdown
## Pending Decisions

_Derived view -- recomputed by `/refresh-decisions`; do not edit here. To resolve, rewrite the `[DECISION-QUEUE id=...]` block in the source file to `[DECISION-RESOLVED ...]` (ADR-084), then re-run the task._

- **{Decision}** -- [{source title}](../../tasks/{task-slug}/_task.md), `id={dN}`
  - {Background, rendered verbatim from the marker}
  - {Choices, rendered verbatim; keep the recommended marker}
  - If left unanswered: {Default}
  - Blocked: {Blocks}
  - {More links, verbatim, when the entry has them}
```

Render every field **verbatim** from the source marker -- no summarizing, condensing, or rewording (the skill is deterministic; condensation would be LLM judgment and break idempotency). Keeping `Background` short is the writer's job at queue time (D84-7), not the digest's. Labels (`If left unanswered`, `Blocked`) render in the user's language, consequence-framed. Lead with `Decision` (the question) so the list scans as questions.

- Write entries consequence-framed (ADR-082 D82-8): user-language wording, no internal labels beyond the `id` needed for addressing.
- For project-scoped entries, the source link points to the project file itself.
- Empty case: `_No pending decisions._` (a valid, common state).
- If the file has no `## Pending Decisions` section yet, insert it directly after `## Current Focus` (before `## Active Tasks`), per the body structure in `.claude/rules/rill-projects.md`.

Atomicity: build the whole new file content in memory, write to a tempfile in the same directory, then `mv` over the original.

### Phase 3: Lock release + summary

1. Remove the lock.
2. Print one line: `Refreshed projects/{slug}/_project.md -- {N} pending decision(s) ({M} task-origin, {K} project-scoped, {L} legacy id-less).`

### `--all` mode

`Glob(projects/*/_project.md)`, filter frontmatter `status: active|planning`, run Phases 0-3 per slug sequentially, print per-project lines plus an aggregate.

## Idempotency

Two consecutive runs produce identical content. Inputs are only: the set of files matched by the mention grep, their line-start `[DECISION-QUEUE]` blocks, and the project file's own blocks. No time-based or random inputs.

## Error handling

| Situation | Behavior |
|---|---|
| `_project.md` missing | Propose similar slugs, one-line error, no auto-create |
| Lock timeout (30 s) | Warn and exit; leave section stale |
| Zero queued decisions | Write the empty-case line -- valid state |
| Malformed QUEUE block (missing fields) | Render what is parseable; append `(malformed entry -- fields missing)` so the human sees it needs repair. Do not fail the run |
| Marker inside a fenced code block | Line-start grep may false-positive; if the hit is inside a fence, skip it |
| No `## Pending Decisions` section | Insert at the standard position (after `## Current Focus`) |

## Invocation

Typical callers:

- `/solve` -- **required in autonomous mode**: immediately after writing a `[DECISION-QUEUE]` entry, run this skill for each project the task mentions, so the digest surfaces the entry before the queue-and-exit (the digest must never be stale right after a queue write)
- A human -- after resolving entries, to clear them from the digest
- `/project {slug} status` / future `/briefing` integration -- to surface pending counts
- Direct: `/refresh-decisions {slug}` or `/refresh-decisions --all`

This skill invokes no other skills. Pure read-grep-write leaf.

## Rules

- **Never modify** any section other than `## Pending Decisions`
- **Never rewrite markers in source files** -- this skill renders a view; it must not perform QUEUE -> RESOLVED transitions (that is the human's / the app's move, ADR-084 D84-1) nor consume RESOLVED blocks (that is the resuming agent's move)
- **Never modify** `inbox/` files
- Relative Markdown links `[title](../../path)` in the body; backtick-only ID references are forbidden
- Per-slug lock, atomic tempfile + `mv` write

## See also

- ADR-084 (rill-dev `docs/decisions/`) -- decision-loop contract v1.1: marker syntax, writer asymmetry, digest-as-derived-view
- `.claude/rules/rill-autonomous-execution.md` sec. 9 -- the human-decision queue this digest renders
- `.claude/rules/rill-projects.md` -- section-ownership table (this skill owns `## Pending Decisions`)
- `skills/solve/SKILL.md` -- writes QUEUE entries and consumes RESOLVED ones on resume
- `skills/refresh-project/SKILL.md` -- sibling deterministic-recompute skill (`## Active Tasks` / `## Related Workspaces`)
