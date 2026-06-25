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

**Conduct ALL conversation with the user in the language defined by `.claude/rules/personal-language.md`** (or the user's input language if absent). The English instructions below are for skill clarity, not for output style. Exceptions (only): tokens inside backticks or code blocks, proper nouns, ASCII acronyms.

Completes an active workspace with exhaustive knowledge distillation. Uses a two-layer sub-agent architecture (ADR-073) to isolate heavy work from the parent session's context budget and to enforce multi-layer defense against error propagation.

## Arguments

$ARGUMENTS — one of the following:

- workspace/ path or id (e.g., `workspace/2026-02-13-rill-development/` or `rill-development`) → Complete the specified workspace
- Omitted → Auto-detect active workspaces
- Add `--auto-approve` to suppress the skill's approval / confirmation prompts (used by integration tests running under `claude -p`). When present: the Phase 0.5 /promote predeclare is skipped, the Phase 5.3 rejected-candidate decision is reported instead of prompted and does not block (see Phase 5.3), and the Phase 8.2 related-task-sync confirmation is skipped (statuses left unchanged). Phase 3 is informational in every mode (no approval gate — see Phase 3). Pass an explicit workspace argument when running non-interactively, so Phase 0 has no multi-workspace selection to prompt for.

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

### Phase 0.5: /promote predeclare (ADR-080 D80-7)

Decide up-front whether this `/close` should chain into `/promote` at the end. The decision is made *now* (before Phase 1) because users want to know the full plan before the long-running distillation begins, but the actual `/promote` invocation must happen *after* Phase 9 (because `/promote` requires `_summary.md`, which is produced by Phase 2's analysis sub-agent).

1. Read the workspace metadata file's frontmatter `mentions`. Extract `projects/{id}` entries
2. Branch:
   - **Workspace has actionable items** (`- [ ] ...`), with or without a `projects/{id}` mention → ask via AskUserQuestion: "After this /close completes, should I chain /promote {id} to crystallise this workspace into a project? You'll pick new-project vs an existing one (when eligible) during /promote." Store the answer (yes / no) in parent state. Do not name a specific mentioned project in the prompt — `/promote` defaults to new-project creation regardless of `mentions`, and naming an existing project here mis-sets the user's expectation
   - **No actionable items** → skip the predeclare (no promotion candidates)
3. The stored answer is applied in Phase 9.5 (new). Non-interactive `--auto-approve` mode skips this predeclare entirely (the user can run `/promote` manually after `/close` returns)

### Phase 1: Shared Context Preparation (parent)

Prepare context data once in the parent, so both the Analysis sub-agent and the Distillation sub-agents can use it without re-computing.

1. Read the "Topic Tags" table from `taxonomy.md` and generate **YAML list format (name + desc)** (exclude deprecated tags)
2. Read `knowledge/people/*.md`, `knowledge/orgs/*.md`, `projects/*/_project.md` and compress into one-line mapping format. (ADR-080: projects moved from `knowledge/projects/*.md` flat layout to top-level `projects/{slug}/_project.md` per-directory layout)
3. Generate entity ID list (for post-processing `rill strip-entity-tags`)

This is the same preparation that /distill Step 1 performs. Hold the result in parent state for injection into sub-agent prompts.

### Phase 1.5: Build language args

Before launching either the Analysis sub-agent (Phase 2) or the Distillation sub-agents (Phase 4), call `build_language_args()` to decide whether to inject narrative-language args into each sub-agent invocation. The function is intentionally trivial — distribution default is English (sub-agent prompts are written in English), so absence of a personal override means no args are injected and the sub-agent's English default takes over naturally. No fallback logic needed on either side.

The top-of-file "Conduct ALL conversation with the user in the language defined by `.claude/rules/personal-language.md`" instruction governs the orchestrator's (main session's) user-facing utterances; this prologue governs argument injection into sub-agent invocations. They share a trigger file but operate on different surfaces — the user-facing rule has no effect on sub-agent output, which is exactly what this prologue closes.

```bash
# build_language_args()
# Returns: inject_args string (or empty if no non-English target is detected).
# Called once per skill invocation, before agent fanout.
#
# Locale detection: presence of personal-language.md is NOT a signal — the
# onboarding skill creates the file for English vaults too, and `rill init
# --lang en` likewise. We pattern-match for any Unicode codepoint in the
# range U+3040-U+30FF, which spans the Hiragana block (U+3040-U+309F) and
# the Katakana block (U+30A0-U+30FF). Both scripts are exclusive to
# Japanese — Chinese and Korean writing systems use Han / Hangul
# respectively and contain neither Hiragana nor Katakana — so a hit here is
# a near-certain ja signal. The stock-ja personal-language.md template
# contains both Hiragana (particles, verb endings) and Katakana (loanwords)
# in its body bullets, so any user-edited derivative that retains even one
# Hiragana or Katakana glyph is detected. Pure-Kanji-only Japanese content
# is the one remaining miss case (Kanji is shared with Chinese, so we cannot
# distinguish), but that style is uncommon for personal-language.md.
# Stock-en and other Latin-script vaults have no such codepoints and fall
# through to the no-injection branch.
#
# Implementation: We use `perl -CSD` (UTF-8 decode on STDIN) with the
# codepoint range above. The earlier `LC_ALL=C grep -qE $'\xe3\x81|...'`
# form relied on bash ANSI-C byte literals, which the default zsh harness
# Claude Code launches via the Bash tool does not interpret as raw bytes —
# detection silently failed under zsh and `output_language` came back empty.
# perl is in PATH on every macOS / Linux distribution that ships Claude
# Code, and Unicode codepoint regexes carry no shell-quoting ambiguity.
#
# Multi-locale detection (mapping all 9 onboarding-supported locales correctly)
# is out of scope for this task and deferred to a separate task. Doing it right
# requires a structured marker (frontmatter or sentinel comment) that bin/rill
# would have to write — and migration of existing personal-language.md files.
# Until that lands, vaults in zh / ko / fr / de / es / pt / it / en receive
# English narrative output (the same behavior as before this skill landed).

output_language=""
if [[ -f .claude/rules/personal-language.md ]] && \
   perl -CSD -e 'while(<>){if(/[\x{3040}-\x{30ff}]/){exit 0}} exit 1' .claude/rules/personal-language.md; then
  output_language="ja"
fi

if [[ -n "$output_language" ]]; then
  # style_guide is hardcoded English. Protocol sentinels listed below MUST stay
  # English literal in sub-agent output — the coordinator string-matches them
  # later (see analysis-agent.md Language section and distillation-agent.md
  # Language section). Translating them would break clustering, rendering, and
  # the parent's self-check / aggregation logic.
  style_guide='Write narrative output fields (summary, rationale, observation, note body prose, and similar free text) in the language specified by output_language. English exceptions (only): (1) tokens inside backticks, (2) proper nouns, (3) ASCII acronyms, (4) any literal sentinel string or fixed enum value documented in this sub-agent prompt'\''s Output schema or Language section — including structured IDs (`D-{ws-short}-{n}`, `IA-{ws-short}-{n}`, `L1-{n}`, `L2-{n}`), slugs, paths, type enum values (`record`/`insight`/`reference`), priority labels (`HIGH`/`LOW`), status labels (`created`/`updated`/`skipped`), justification labels (`EVERGREEN_DUPLICATE`/`INTERMEDIATE_CONCLUSION`/`IMPLEMENTATION_DETAIL`/`MERGED_INTO_OTHER`), and the section-empty sentinel `"(No invalidated approaches in this workspace.)"` — which must remain verbatim English regardless of output_language because the coordinator string-matches them. Translate all other English (common nouns, adjectives, verb metaphors). When translating, prefer the established target-language term (a word actually used in documents written by native speakers); if none exists, prefer a loanword form in common use; otherwise keep the English term inside backticks with a short parenthetical gloss on first use. Never invent literal calques that do not exist in the target language, and keep one consistent rendering per concept within a document.'
  inject_args="output_language: ${output_language}
style_guide: |
  ${style_guide}"
else
  # No detected non-English target. Sub-agent prompt is in English, so absence
  # of args naturally yields English output — no fallback logic needed here.
  # The top-of-file "use the user's input language if personal-language.md is
  # absent" rule governs the orchestrator's user-facing utterances only (the
  # disambiguation paragraph above states this explicitly). Sub-agent narrative
  # output uses the prompt-language default (English) until the user expresses
  # a persistent preference by running onboarding or `rill init --lang`.
  inject_args=""
fi
```

When `inject_args` is non-empty, append it as additional YAML lines to **each** sub-agent invocation's prompt in Phase 2 and Phase 4, alongside the existing placeholder substitutions (`{workspace_id}`, `{shared_context_placeholder}`, `{candidate_yaml}`, etc.). The `style_guide` string is hardcoded in English on purpose: the public `rillmd/rill` repo stays ASCII-only, and the string is itself an English instruction. The `output_language` value is the only locale-dependent runtime input; broader-locale support (`ko`, `zh`, `fr`, `de`, `es`, `pt`, `it`) extends the detection branch above (and requires a corresponding bin/rill change to mark `personal-language.md` with the chosen locale) without touching the sub-agent prompts or the `style_guide` content.

### Phase 2: Spawn Analysis Sub-agent

Read `.claude/commands/_close/analysis-agent.md` and fill in the placeholders with actual values:

- `{workspace_id}` — resolved workspace id
- `{metadata_file_name}` — `_workspace.md` / `_session.md` / `_project.md`
- `{shared_context_placeholder}` — the tag vocabulary, people/orgs/projects mappings from Phase 1

After substituting placeholders, append `inject_args` (from Phase 1.5) to the bottom of the rendered prompt when non-empty. Skip the append when `inject_args` is empty (English-default vault) — the sub-agent prompt is written in English so absence of args naturally yields English output.

Spawn the sub-agent via the Agent tool (`subagent_type: general-purpose`), passing the filled-in template as the `prompt` parameter.

**Wait for the sub-agent to return** before proceeding. Its output is:

- `_summary.md` has been written at `workspace/{workspace_id}/_summary.md`
- A structured YAML report containing:
  - `candidates[]` — distillation candidates (Layer 1 + Layer 2)
  - `invalidated_approaches[]` — approaches rejected within the workspace
  - counts: `decisions_count`, `candidates_total`, etc.

Parse the YAML report and hold it in parent state.

### Phase 3: Display Analysis Result

Display the Analysis result so it lands in the execution log, then proceed **directly to Phase 4**. There is no approval gate here.

Earlier versions paused for a user Approve / Re-analyze / Abort decision — ADR-073's "first layer of defense against error propagation." In practice the candidate list (2N to 5N entries for N deliverables) is too large to verify item-by-item, and the parent gives the user no per-candidate evidence to judge from, so the gate degraded into a rubber stamp. A gate the user cannot act on meaningfully is worse than none, so it was removed (ADR-083). Distillation is reversible via git, and completeness is still defended downstream without a human in the loop: the Analysis sub-agent reads every deliverable in one fresh context (Phase 2), each Distillation sub-agent cross-verifies its claims against other deliverables before writing (Phase 4, CV-rules), and the parent runs a mandatory self-check that STOPs on any uncovered candidate (Phase 5).

Display (informational — for the log, not a prompt):

```markdown
## /close Phase 2 complete — analysis result

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

Then proceed directly to Phase 4 with the full candidate list from the Analysis report — do not call AskUserQuestion. If the result looks wrong, the user fixes it after the run by editing or `git`-reverting the generated `knowledge/notes/` (distillation is reversible). To re-run the analysis from scratch, reopen the workspace (set its metadata `status` from `completed` back to `active` — an allowed transition) and re-invoke `/close`.

### Phase 4: Spawn Distillation Sub-agents (parallel, up to 5)

Read `.claude/commands/_close/distillation-agent.md` once. For each candidate from the Analysis report, fill in the placeholders:

- `{candidate_yaml}` — the candidate's full YAML block
- `{workspace_id}` — workspace id
- `{deliverable_moc}` — list of all deliverables with 1-line descriptions (parent builds this from the Analysis sub-agent's report + deliverable frontmatter)
- `{invalidated_list}` — the invalidated approaches from the Analysis report
- `{shared_context}` — tag vocabulary + entity mappings from Phase 1

After substituting placeholders, append `inject_args` (from Phase 1.5) to the bottom of each rendered prompt when non-empty. Skip the append when `inject_args` is empty (English-default vault). The same `inject_args` value computed in Phase 1.5 is reused across all parallel Distillation sub-agent invocations.

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

**Non-interactive mode** (`--auto-approve`): do not prompt and do not STOP. Leave the rejected candidates undistilled, keep them counted in the `rejected` bucket (the SC-01 equation still balances), surface them in the Phase 9 completion report, and proceed to Phase 6. Their content remains in the workspace deliverables and `_summary.md`, so nothing is lost — they are simply not auto-distilled into notes this run.

`uncovered > 0` always STOPs (both modes). `rejected > 0` STOPs for a user decision in interactive mode; under `--auto-approve` it is reported and does not block. Otherwise (`uncovered == 0` and no blocking `rejected`), proceed to Phase 6.

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
- Rejected (invalid justification, not distilled): {R}
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

### Rejected candidates (not distilled, if any)
- {candidate_id}: {slug} — {invalid justification} (content remains in the workspace deliverables and `_summary.md`)
- ...

### Open issues (carried forward)
- [ ] Issue 1 (from _summary.md)
```

### Phase 9.5: /promote chain (if predeclared in Phase 0.5)

If Phase 0.5 stored a `yes` answer, chain into `/promote {workspace-id}` now. By this point `_summary.md` exists (written in Phase 2) and `/promote`'s prerequisite is satisfied.

1. Invoke `/promote {workspace-id}` via the harness's Skill mechanism. Synchronous wait
2. `/promote` runs its own AskUserQuestion flow for candidate review — `/close` does not need to relay anything
3. After `/promote` returns, continue to Phase 10

If Phase 0.5 stored `no` (or was skipped), continue directly to Phase 10 without chaining.

### Phase 10: /pulse refresh (NEW)

After Phase 9 (Post-processing and Completion Report) completes, invoke `/pulse` via the harness's Skill tool to refresh `knowledge/self/current-state.md`. The just-closed workspace will drop out of the "進行中" section in the new snapshot (015 §2.2):

```
Skill(name: "pulse", args: "")
```

The invocation is synchronous. /pulse handles its own 12h cooldown — if a recent /close or /distill already ran /pulse within the window, this is a silent no-op. Do **not** display /pulse's output as part of the close report.

**Non-recursion guarantee**: /pulse only reads from `workspace/` + `tasks/` + `knowledge/self/` (and writes only to `current-state.md`), and never invokes /close back. The chain is structurally one-way.

If the /pulse invocation fails, log a 1-line warning to stdout and treat the /close run as successful — /pulse refresh failure is not fatal.

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
- `docs/decisions/2026-06-25-083-close-remove-candidate-approval-gate.md` — ADR-083 (Phase 3 user checkpoint removed; downstream defenses retained)
- `docs/skill-specs/close.md` — IAD (rule table for testing)
