---
gui:
  label: "/close"
  hint: "Complete workspace and generate summary"
  match:
    - "workspace/**/*.md"
  arg: workspace-id
  order: 20
  mode: auto
---

# /close — Workspace Completion

Completes an active workspace with exhaustive knowledge distillation. Uses a two-layer sub-agent architecture (ADR-073) to isolate heavy work from the parent session's context budget and to enforce multi-layer defense against error propagation.

## Arguments

$ARGUMENTS — one of the following:

- workspace/ path or id (e.g., `workspace/2026-02-13-rill-development/` or `rill-development`) → Complete the specified workspace
- Omitted → Auto-detect active workspaces
- Add `--auto-approve` to skip the Phase 3 user checkpoint (used by integration tests running under `claude -p`). When this flag is present, treat the Analysis sub-agent's output as implicitly approved and proceed directly to Phase 4 without calling AskUserQuestion.

## Architecture (why this skill is structured the way it is)

Historically /close ran all phases directly in the parent context (ADR-072). This failed on large workspaces: the parent would run out of context budget during distillation and silently skip most candidates ("Let me be pragmatic..."). ADR-073 replaces that with a two-layer structure:

1. **Parent session** (this skill): orchestration + user interaction + final phases
2. **Analysis sub-agent** (fresh context): reads all deliverables, writes `_summary.md`, enumerates distillation candidates
3. **Distillation sub-agents** (fresh context, up to 5 parallel): one candidate → one atomic note, with mandatory cross-deliverable verification

The parent session stays lightweight and never runs out of budget regardless of workspace size. Each sub-agent has a fresh context (independent budget). Narrative consistency is preserved because the Analysis sub-agent reads everything in a single fresh context, and each Distillation sub-agent cross-verifies against other deliverables before writing.

See [ADR-073](../../docs/decisions/2026-04-08-073-close-two-layer-subagent-delegation.md) for the full rationale.

## Procedure

### Phase 0: Workspace Identification

1. If argument provided: Read the metadata file in that directory (priority: `_workspace.md` > `_session.md` > `_project.md`)
2. If argument omitted:
   - Scan all directories directly under `workspace/` (exclude `daily`)
   - Search for `_workspace.md` OR `_session.md` OR `_project.md` with `status: active`
   - If multiple found, use AskUserQuestion to prompt selection
   - If no active workspaces found, display "No active workspaces" and exit
3. Verify the metadata file's `status` is `active`
   - If `completed`, display "This workspace is already completed" and exit

### Phase 1: Shared Context Preparation (parent)

Prepare context data once in the parent, so both the Analysis sub-agent and the Distillation sub-agents can use it without re-computing.

1. Read the "Topic Tags" table from `taxonomy.md` and generate **YAML list format (name + desc)** (exclude deprecated tags)
2. Read `knowledge/people/*.md`, `knowledge/orgs/*.md`, `knowledge/projects/*.md` and compress into one-line mapping format
3. Generate entity ID list (for post-processing `rill strip-entity-tags`)

This is the same preparation that /distill Step 1 performs. Hold the result in parent state for injection into sub-agent prompts.

### Phase 2: Spawn Analysis Sub-agent

Read `.claude/commands/_close/analysis-agent.md` and fill in the placeholders with actual values:

- `{workspace_id}` — resolved workspace id
- `{metadata_file_name}` — `_workspace.md` / `_session.md` / `_project.md`
- `{shared_context_placeholder}` — the tag vocabulary, people/orgs/projects mappings from Phase 1

Spawn the sub-agent via the Agent tool (`subagent_type: general-purpose`), passing the filled-in template as the `prompt` parameter.

**Wait for the sub-agent to return** before proceeding. Its output is:

- `_summary.md` has been written at `workspace/{workspace_id}/_summary.md`
- A structured YAML report containing:
  - `candidates[]` — distillation candidates (Layer 1 + Layer 2)
  - `invalidated_approaches[]` — approaches rejected within the workspace
  - counts: `decisions_count`, `candidates_total`, etc.

Parse the YAML report and hold it in parent state.

### Phase 3: User Checkpoint

Before spawning any Distillation sub-agent, present the Analysis result to the user for approval. This is the **first layer of defense against error propagation** — a human sanity-checks the narrative judgment before it fans out to parallel sub-agents.

**Non-interactive mode**: If the `--auto-approve` flag was passed in $ARGUMENTS, skip the AskUserQuestion step entirely and treat the Analysis result as approved. Still display the summary table (it will appear in the execution log for later review), but proceed directly to Phase 4 without prompting. This mode exists for integration tests that run under `claude -p` and for automated `/close` execution.

Display:

```markdown
## /close Phase 2 complete — please review

### _summary.md
Generated at `workspace/{workspace_id}/_summary.md`.

- Decisions: {N}
- Invalidated Approaches: {M}
- Open Issues: {K}

### Distillation candidates ({total})

Layer 1 (from Decisions): {NL1}
Layer 2 (from per-deliverable scan): {NL2}

| ID | Layer | Slug | Type | Source | Rationale |
|----|-------|------|------|--------|-----------|
| L1-1 | 1 | example-slug | insight | 001-example.md | ... |
| ... |

### Invalidated approaches ({M})

| ID | Slug | Proposed in | Invalidated by |
|----|------|-------------|----------------|
| IA-1 | ... | ... | ... |
```

Then use AskUserQuestion to get approval:

- **Approve** → proceed to Phase 4
- **Approve with edits** → apply specified additions / removals / slug changes to the candidate list in parent state, then proceed
- **Re-analyze** → re-spawn the Analysis sub-agent with supplementary instructions (e.g., "also enumerate reference-type units from 002")
- **Abort** → keep `_summary.md` in place, exit without distillation (the workspace remains `status: active`)

### Phase 4: Spawn Distillation Sub-agents (parallel, up to 5)

Read `.claude/commands/_close/distillation-agent.md` once. For each approved candidate, fill in the placeholders:

- `{candidate_yaml}` — the candidate's full YAML block
- `{workspace_id}` — workspace id
- `{deliverable_moc}` — list of all deliverables with 1-line descriptions (parent builds this from the Analysis sub-agent's report + deliverable frontmatter)
- `{invalidated_list}` — the invalidated approaches from the Analysis report
- `{shared_context}` — tag vocabulary + entity mappings from Phase 1

**Dispatch strategy**:

- Spawn each sub-agent via the Agent tool with **`model: "sonnet"`** (Tier 2 LLM-as-judge eval, 2026-04-19: 3/3 EQUIVALENT vs Opus baseline across evergreen-duplicate, novel-verified, and verification-contradicted fixtures; both models caught the planted cross-deliverable contradiction; verification rigor equivalent; 0/3 DEGRADED; cost reduced ~50% vs Opus on this workload). Monitor the `related:` field usage in production — Sonnet occasionally mixes workspace deliverable paths into `related` where the spec calls for knowledge/notes/ paths only; roll back if this appears systematically
- If total candidates ≤ 5: spawn all in parallel in a single message (multiple Agent tool calls in one response)
- If total candidates > 5: process in batches of 5. Spawn 5 in parallel, wait for all to return, then spawn the next 5, and so on

**Collect results**: each sub-agent returns one of `created` / `updated` / `skipped`. Parent maintains a result table:

```
candidate_id | status | path_or_justification
```

### Phase 5: Parent-side Aggregation

#### 5.1 Validate justifications

For each `skipped` result:

- Check that the `justification` field is one of the four valid labels: `EVERGREEN_DUPLICATE`, `INTERMEDIATE_CONCLUSION`, `IMPLEMENTATION_DETAIL`, `MERGED_INTO_OTHER`
- Check that required `details` fields are present (e.g., `existing_file` for EVERGREEN_DUPLICATE)
- If a sub-agent returned an invalid justification (vague reason, missing details), re-spawn that sub-agent once with instructions to provide a valid justification. If it fails again, mark as `rejected` and surface to the user in Phase 9

#### 5.2 Evergreen race resolution

If two sub-agents happened to `create` notes with similar slugs or overlapping content:

1. Detect candidate pairs with slug edit-distance ≤ 3 or high content overlap
2. For each detected pair:
   - Read both notes
   - If truly duplicate → Edit one to merge the content (prefer the file with richer body), `related` field gets both candidate sources
   - Delete the loser note via direct file removal
   - Record the merge in parent state

#### 5.3 Self-check

Compute coverage:

```
enumerated = candidates_total (from Analysis sub-agent)
created    = count(status == "created")
updated    = count(status == "updated")
skipped    = count(status == "skipped" AND valid justification)
rejected   = count(status == "skipped" AND invalid justification, even after re-spawn)
uncovered  = enumerated - (created + updated + skipped + rejected)
```

**If `uncovered > 0`**: STOP. Display an error listing the uncovered candidates:

```markdown
## ⚠ Distillation incomplete

{uncovered} candidates were enumerated but never processed:
- {candidate_id}: {slug} (source: {source})
- ...

Possible causes: sub-agent timeout, invalid return, race resolution error.
Not proceeding to Phase 6+. Please investigate.
```

**If `rejected > 0`**: display the rejected candidates and their invalid justifications, ask the user whether to retry, skip them, or abort.

Only when `uncovered == 0` AND `rejected == 0`, proceed to Phase 6.

### Phase 6: Deliverable Frontmatter Update (parent)

For each numbered deliverable (`NNN-*.md`):

- If `mentions` / `tags` are not set in frontmatter, match against the shared context from Phase 1 and add them
- Use Edit to update the frontmatter

### Phase 7: Workspace Status Update + .processed (parent)

1. Change the metadata file's (`_workspace.md` / `_session.md` / `_project.md`) `status` to `completed`
2. Append a completion record to the workspace's `## Session History` section
3. Append all deliverable filenames to `workspace/{id}/.processed`

### Phase 8: Task Extraction and Related Task Sync (parent)

#### 8.1 Task extraction from unchecked items

- Check the checklist completion status in `_workspace.md`
- All items `[x]` → skip task extraction
- Unchecked items exist → Read `.claude/commands/_distill/task-extraction.md` and follow its rules to extract task candidates
- After duplicate check against existing tickets, create tickets with `rill task` (ADR-069: create as draft)

#### 8.2 Related task sync

1. `Grep(pattern=..., path="tasks/", glob="**/_task.md", output_mode="files_with_matches")` to find tasks referencing the workspace id (directory name) in `source:` or `related:`
2. Read each detected task, target those with `status` of `open` / `waiting` / `draft` (skip `done` / `cancelled`)
3. Compare each target task's goal against the `_summary.md` generated in Phase 2, with AI judging whether it was completed within the workspace
4. Present judgment results to user in a list and request confirmation via AskUserQuestion:
   ```
   ## Related Task Sync

   | Task | Current status | Judgment |
   |------|---------------|----------|
   | [Task name](tasks/xxx/_task.md) | open | ✅ Completed (reason: ...) |
   | [Task name](tasks/yyy/_task.md) | waiting | ❓ Cannot determine (reason: ...) |

   May I update the status of the above tasks?
   ```
   - Approved → Change to `status: done` via Edit. Append "Transitioned to done upon completion of workspace {id}" to "## History"
   - Selective → Update only specified tasks
   - Rejected → No changes
5. If 0 related tasks found → skip (no display)

**Non-interactive mode**: If `--auto-approve` was passed, skip the AskUserQuestion and leave related task statuses unchanged (do not auto-update statuses). Display the judgment table in the log but make no modifications. The user can sync related tasks manually after reviewing the log.

### Phase 9: Post-processing and Completion Report (parent)

#### 9.1 Post-processing

- Run `rill strip-entity-tags` on created `knowledge/notes/` files
- Append new tags (if any) to `taxonomy.md`
- Entity detection: detect new entities from `mentions` in created notes → auto-create entity files if missing
- **Pages pending update** (Phase 2 of pages-wiki-redesign — "new candidates" push):
  1. Build a sources list containing:
     - The workspace metadata file path: `workspace/{workspace_id}/_workspace.md` (or `_session.md` / `_project.md` for legacy workspaces)
     - Every newly-created `knowledge/notes/*.md` path from Phase 4 (paths where Distillation sub-agent status == `created`). Exclude `updated` notes — those are Evergreen updates already covered by /page Session Start Layer 1
  2. Write the list to a tmp file (one path per line) and invoke:
     ```bash
     rill pages-pending-update --sources-file "$tmp" --origin close
     ```
  3. The CLI matches each source's `mentions` (Layer 2) or `tags` (Layer 3 fallback, pages without mentions only) against `pages/*.md` and upserts entries into `pages/.pending`
  4. Do NOT pass `--force` if the CLI prints `⚠ bulk update detected` — investigate first (Phase 4 likely produced an unusually large batch; decide manually whether to push all into pending)

Design reference: `workspace/2026-04-15-pages-wiki-redesign/006-matching-strategy-revision.md`

#### 9.2 Completion summary display

Display the following to the user as the final output of /close:

```markdown
## /close complete — {workspace_id}

### _summary.md
workspace/{id}/_summary.md

### Distillation self-check
- Candidates enumerated: {N}
- Atomic notes created: {X}
- Existing notes updated (Evergreen merge): {Y}
- Skipped with justification: {Z}
  - EVERGREEN_DUPLICATE: {count}
  - INTERMEDIATE_CONCLUSION: {count}
  - IMPLEMENTATION_DETAIL: {count}
  - MERGED_INTO_OTHER: {count}
- Uncovered: 0 ✓

### Created notes
- knowledge/notes/xxx.md
- ...

### Extracted tasks (if any)
- tasks/xxx/_task.md (status: draft)
- ...

### Synced related tasks (if any)
- tasks/xxx/_task.md: open → done
- ...

### Open issues (carried forward)
- [ ] Issue 1 (from _summary.md)
```

## Rules

- **Never modify `inbox/journal/` and `inbox/*/` original files** (read-only)
- Knowledge distillation runs in Distillation sub-agents (ADR-073), NOT in parent context. The parent only orchestrates
- Include frontmatter in all files
- **Backward compatibility**: also handle workspaces that only have `_session.md` or `_project.md` (treat as metadata file)
- **Forbidden justifications**: parent MUST reject `pragmatic scope reduction`, `to save time`, `not novel enough`, `context budget running low`, `already sufficient coverage`, and any unlabeled reason. See `.claude/commands/_close/distillation-agent.md` for the authoritative list
- **Self-check is mandatory**: `uncovered > 0` must trigger a STOP, not a warning. Do not proceed to Phase 6+ with uncovered candidates

## Related files

- `.claude/commands/_close/analysis-agent.md` — Phase 2 Analysis sub-agent prompt template
- `.claude/commands/_close/distillation-agent.md` — Phase 4 Distillation sub-agent prompt template
- `.claude/commands/_distill/knowledge-agent.md` — referenced by distillation-agent.md for Evergreen check procedure
- `.claude/commands/_distill/task-extraction.md` — referenced by Phase 8.1 for task extraction rules
- `docs/decisions/2026-04-08-073-close-two-layer-subagent-delegation.md` — ADR-073 rationale
- `docs/skill-specs/close.md` — IAD (rule table for testing)
