# /close Distillation Sub-agent

/close Phase 3.4.b sub-agent prompt. Converts **ONE knowledge candidate** into an atomic note in `knowledge/notes/`, with mandatory cross-deliverable verification to catch propagated errors from `_summary.md`.

**IMPORTANT**: This file is a template. The parent /close skill reads this file, fills in the placeholders (candidate, _summary.md path, deliverable MOC, invalidated list, shared context), and passes the result as the `prompt` parameter when spawning the sub-agent via the Agent tool. Each sub-agent handles exactly one candidate. Parent spawns up to 5 in parallel.

## Your candidate

```yaml
{candidate_yaml}
```

Example of what this looks like filled in:

```yaml
id: L1-3
layer: 1
slug: cli-vault-resolution-hybrid-pattern
type: insight
source: workspace/2026-04-06-skill-testing/008-rill-home-resolution-design.md
related:
  - workspace/2026-04-06-skill-testing/007-localization-tracking-report.md
rationale: "maintain quick-capture while treating multiple vaults as first-class concepts"
suggested_tags: [cli-design, pkm-tooling]
suggested_mentions: [projects/rill]
```

## Reference material

### Workspace context

- Workspace ID: `{workspace_id}`
- `_summary.md` path: `workspace/{workspace_id}/_summary.md`
- All deliverables in this workspace:

```
{deliverable_moc}
```

Example of what this looks like filled in:

```
001-skill-test-design-research.md — Skill test design research; 3-layer test structure proposed
002-skill-testing-landscape-report.md — Industry landscape report; 25+ sources surveyed
008-rill-home-resolution-design.md — RILL_HOME resolution + multi-vault + skill distribution design
...
```

### Invalidated Approaches (consult BEFORE writing)

Intermediate proposals from this workspace that were later rejected. If your candidate's claims overlap with any of these, you MUST skip with `INTERMEDIATE_CONCLUSION`:

```
{invalidated_list}
```

Example:

```
IA-1: html-comment-marker-for-claude-md
  Proposed in: 009-claude-md-genericization-plan.md
  Invalidated by: 010-claude-md-multifile-research.md
  Reason: Claude Code strips HTML comments from CLAUDE.md before injection
```

### Shared context

```
{shared_context}
```

(Contains: tag vocabulary in YAML list format, people/orgs/projects mappings)

## Process — MUST follow in this exact order

### Step 1: Read the candidate's primary source

`Read` the file at `candidate.source` in full. This is your ground truth for the candidate's content.

### Step 2: Read related deliverables if specified

If `candidate.related` is non-empty, `Read` those files in full. Budget: up to 2 related files.

### Step 3: Read _summary.md

`Read` `workspace/{workspace_id}/_summary.md`. This gives you the narrative judgment (which decisions were adopted, which were invalidated).

### Step 4: Cross-deliverable verification (MANDATORY)

This step exists to catch errors propagated from `_summary.md`. Do not skip it.

1. From `candidate.rationale` and your reading of the source, extract **3-5 key claims** that the note will make
2. For each key claim, run:
   ```
   Grep(pattern="{claim-keyword}", path="workspace/{workspace_id}/", glob="*.md", output_mode="files_with_matches")
   ```
3. For each deliverable that matches (excluding the source you already read), `Read` up to **2 additional** deliverables
4. Classify what those deliverables say about your claim:
   - **Consistent** (supports or does not contradict) → OK, continue
   - **Not mentioned** → OK, continue
   - **Contradicted** (another deliverable says the opposite) → **STOP**. Return `skipped` with `INTERMEDIATE_CONCLUSION`, include the contradicting deliverable:line
   - **Invalidated** (later deliverable invalidates the approach) → **STOP**. Return `skipped` with `INTERMEDIATE_CONCLUSION`, reference the IA entry if applicable
5. Also cross-check the `Invalidated Approaches` list above. If your candidate's claims overlap with any IA → **STOP** with `INTERMEDIATE_CONCLUSION`

**Budget discipline**: The verify step should consume no more than 3-5 tool calls total (Grep + up to 2 extra Reads). Do not exhaustively read every deliverable — the Analysis sub-agent already did that; your job is targeted verification.

### Step 5: Evergreen check

Follow the procedure from `.claude/commands/_distill/knowledge-agent.md` section "Evergreen Check":

1. Extract 3-5 search terms from the key concepts
2. `Glob("knowledge/notes/*{keyword}*")` for candidate search (1-2 times)
3. `Grep(pattern, path="knowledge/notes/", output_mode="files_with_matches", head_limit=10)` (1 time)
4. If a file on the same topic is found:
   - Read only the **frontmatter** (first 10 lines) of the candidate file
   - If `type` differs → **create new**, add the existing file to `related`
   - If `type` matches and content covers the same topic → **STOP**. Return `skipped` with `EVERGREEN_DUPLICATE`, name the existing file
5. If no matches → proceed to Step 6
6. If related (but different topic) files found → note their paths for the `related` field in Step 6

### Step 6: Create the atomic note

Use `rill mkfile` to create the file with correct frontmatter. **Always invoke it as `bin/rill` (relative path from the vault root)**, never as bare `rill`:

```bash
bin/rill mkfile knowledge/notes --slug {candidate.slug} --type {candidate.type} \
  --field "source={candidate.source}" \
  --field "tags=[{suggested_tags}]" \
  --field "mentions=[{suggested_mentions}]" \
  --field "related=[{related_paths_if_any}]"
```

**Why `bin/rill` and not `rill`**: the bare `rill` command may resolve to a user-global install (e.g., `~/.local/bin/rill`) that is a symlink to a different repository. That would cause the file to be created in the wrong repository and the relative path in stdout would not exist in your cwd. Always use `bin/rill` so `BASH_SOURCE` resolves to the current working tree.

After running `bin/rill mkfile`, **verify the file was actually created** before proceeding:

```bash
# Verify the created path exists in cwd — this catches RILL_HOME mismatch bugs
[[ -f "$CREATED_PATH" ]] && echo CREATED || echo MISSING
```

If the verification reports `MISSING`, stop and return `status: error` with a clear message — do NOT fall back to `Write`, because the issue is likely a real bug that needs investigation. Falling back silently hides the root cause.

Then `Edit` the created file to append the body. Body requirements:

- Start with `# {Title}` (concise title describing the content)
- 200-800 characters (not too terse, not padded)
- Match the workspace's language (Japanese body if source is Japanese)
- Technical terms in English
- Use standard Markdown links `[display](path)` — never Wiki links `[[...]]`
- Do not repeat the frontmatter content in the body

### Step 7: Verify your work

After writing, Read the file you just created to confirm:

- Frontmatter is well-formed
- `source` matches `candidate.source`
- `type` is one of `record` / `insight` / `reference`
- Body has a `# Title` heading and 200-800 chars of substance

## Output — return to parent

Return ONE of the following structured reports. Use this exact format:

### Case A: Created a new note

```yaml
status: created
candidate_id: {candidate.id}
path: knowledge/notes/{slug}.md
type: {candidate.type}
verify:
  claims_checked: {N}
  contradictions_found: 0
  evergreen_matches: {existing_files_referenced_in_related, if any}
```

### Case B: Updated existing note (Evergreen merge — rare, only if merging adds new content)

```yaml
status: updated
candidate_id: {candidate.id}
path: knowledge/notes/{existing_slug}.md
reason: "Merged {specific new content} into existing note"
```

### Case C: Skipped with valid justification

```yaml
status: skipped
candidate_id: {candidate.id}
justification: EVERGREEN_DUPLICATE | INTERMEDIATE_CONCLUSION | IMPLEMENTATION_DETAIL | MERGED_INTO_OTHER
details:
  # Depending on justification, include:
  # For EVERGREEN_DUPLICATE:
  existing_file: knowledge/notes/xxx.md
  reason: "Same topic, same type, covers same content"
  # For INTERMEDIATE_CONCLUSION:
  contradicted_by: workspace/{id}/NNN-file.md
  reason: "Claim X is contradicted by deliverable Y which says Z"
  # For IMPLEMENTATION_DETAIL:
  reason: "Rill-specific implementation (one-line explanation)"
  # For MERGED_INTO_OTHER:
  merged_into: {other candidate id}
```

## Forbidden justifications

These are NOT valid skip reasons and will be rejected by the parent:

- `pragmatic scope reduction`
- `to save time`
- `not novel enough`
- `context budget running low`
- `already sufficient coverage`
- Any unlabeled reason

If you find yourself wanting to skip for one of these reasons, re-examine the candidate — the issue is likely one of:
- Evergreen duplicate (use that label + name the file)
- Genuinely implementation-specific (use `IMPLEMENTATION_DETAIL`)
- Or it should actually be distilled (do not skip)

## Budget discipline

- Total tool calls for one distillation: **~8-12** (Read source + Read related + Read _summary.md + Grep verify + Read extra deliverable + Glob evergreen + Grep evergreen + rill mkfile + Edit + final Read verify)
- Do not read more than **5 files total** from the workspace directory
- Do not read more than **2 files total** from `knowledge/notes/` (and only frontmatter, first 10 lines each)

Your fresh context gives you a comfortable budget, but discipline prevents wandering.

## Constraints summary

- `inbox/` files are read-only — never modify
- Use `rill mkfile` for file creation (auto-sets `created` field)
- Do not fabricate facts not grounded in the deliverables
- One sub-agent = one candidate = one atomic note (or one skip)
- Return only the structured YAML report, nothing else
