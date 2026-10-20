# /close Distillation Sub-agent

/close Stage 2 (S2.4) sub-agent prompt. Converts **ONE knowledge candidate** into an atomic note in `knowledge/notes/` (or one justified skip), with mandatory cross-deliverable verification to catch propagated errors from `_summary.md`, and records the outcome in the CLI-owned distill record.

**IMPORTANT**: This file is a template. The parent /close skill reads this file, fills in the placeholders (candidate, deliverable MOC, invalidated list, shared context), and passes the result as the `prompt` parameter when spawning the sub-agent via the Agent tool. Each sub-agent handles exactly one candidate. The parent runs up to 5 in the foreground per batch.

## Your candidate

```json
{candidate_json}
```

Example of what this looks like filled in (`source` and `related` are relative to the workspace directory; `source_path` is the vault-relative path to use in the note's frontmatter):

```json
{"event": "candidate", "id": "L1-3", "layer": 1, "slug": "cli-vault-resolution-hybrid-pattern", "type": "insight",
 "source": "008-rill-home-resolution-design.md",
 "source_path": "workspace/2026-04-06-skill-testing/008-rill-home-resolution-design.md",
 "related": ["007-localization-tracking-report.md"],
 "rationale": "maintain quick-capture while treating multiple vaults as first-class concepts",
 "suggested_tags": ["cli-design", "pkm-tooling"], "suggested_mentions": ["projects/rill"]}
```

## Reference material

- `output_language` (optional): ISO 639-1 language code for narrative output fields (e.g. `"ja"`, `"en"`); when omitted, default to English
- `style_guide` (optional): short vocabulary-boundary rules for narrative fields (see Language section); when omitted, write narrative fields in plain English

### Workspace context

- Workspace ID: `{workspace_id}`
- Distill run: `{run}` (pass it as `--run {run}` to every record command)
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

## Language

Use the language specified by `output_language` (ISO 639-1) for the narrative output field — namely the **body of the created `knowledge/notes/{slug}.md` note, including the `# {Title}` heading**. Internal keys stay verbatim English regardless of `output_language` because the coordinator string-matches them: the `slug` itself, the `source` / `related` / `mentions` paths and entity IDs, `tags` slugs, `type` enum values (`record` / `insight` / `reference`), all frontmatter field names, the `candidate_id` value, the status labels (`created` / `updated` / `skipped`), the justification labels (`EVERGREEN_DUPLICATE` / `INTERMEDIATE_CONCLUSION` / `IMPLEMENTATION_DETAIL` / `MERGED_INTO_OTHER`), and every structural key in the return-YAML schema (`status`, `path`, `verify`, `details`, etc.) all remain English. Follow the inline `style_guide` block for vocabulary boundaries on the narrative field.

## Process — MUST follow in this exact order

### Step 1: Read the candidate's primary source

`Read` the file at `candidate.source_path` in full. This is your ground truth for the candidate's content.

### Step 2: Read related deliverables if specified

If `candidate.related` is non-empty, `Read` those files (under `workspace/{workspace_id}/`) in full. Budget: up to 2 related files.

### Step 3: Read _summary.md

`Read` `workspace/{workspace_id}/_summary.md`. This gives you the narrative judgment (which decisions were adopted, which were invalidated).

### Step 4: Cross-deliverable verification (MANDATORY)

This step exists to catch errors propagated from `_summary.md`. Do not skip it.

1. From `candidate.rationale` and your reading of the source, extract **3-5 key claims** that the note will make
2. For each key claim, run:
   ```
   Grep(pattern="{claim-keyword}", path="workspace/{workspace_id}/", glob="*.{md,html}", output_mode="files_with_matches")
   ```
   An `.html` match counts as a verification source only when it is **HTML-canonical** (no same-basename `.md` — check the deliverable MOC above, which lists them). Ignore matches from derived HTML: anything under `.view/`, and same-basename `.html` twins of an MD file (their MD side is already in scope)
3. For each deliverable that matches (excluding the source you already read), `Read` up to **2 additional** deliverables — HTML-canonical deliverables included (their HTML is their only record)
4. Classify what those deliverables say about your claim:
   - **Consistent** (supports or does not contradict) → OK, continue
   - **Not mentioned** → OK, continue
   - **Contradicted** (another deliverable says the opposite) → **STOP** and go to Step 7: record `skipped` with `INTERMEDIATE_CONCLUSION`, naming the contradicting deliverable:line in the reason
   - **Invalidated** (later deliverable invalidates the approach) → **STOP** and go to Step 7: record `skipped` with `INTERMEDIATE_CONCLUSION`, referencing the IA entry if applicable
5. Also cross-check the `Invalidated Approaches` list above. If your candidate's claims overlap with any IA → **STOP** and go to Step 7 with `INTERMEDIATE_CONCLUSION`

**Budget discipline**: The verify step should consume no more than 3-5 tool calls total (Grep + up to 2 extra Reads). Do not exhaustively read every deliverable — the Analysis sub-agent already did that; your job is targeted verification.

### Step 5: Evergreen check

Follow the procedure from `.claude/commands/_distill/knowledge-agent.md` section "Evergreen Check":

1. Extract 3-5 search terms from the key concepts
2. `Glob("knowledge/notes/*{keyword}*")` for candidate search (1-2 times)
3. `Grep(pattern, path="knowledge/notes/", output_mode="files_with_matches", head_limit=10)` (1 time)
4. If a file on the same topic is found:
   - Read only the **frontmatter** (first 10 lines) of the candidate file
   - If `type` differs → **create new**, add the existing file to `related`
   - If `type` matches and content covers the same topic → **STOP** and go to Step 7: record `skipped` with `EVERGREEN_DUPLICATE` and the existing file as `--path`
5. If no matches → proceed to Step 6
6. If related (but different topic) files found → note their paths for the `related` field in Step 6

### Step 6: Create the atomic note

Use `rill mkfile` to create the file with correct frontmatter. **Always invoke it as `bin/rill` (relative path from the vault root)**, never as bare `rill`:

```bash
bin/rill mkfile knowledge/notes --slug {candidate.slug} --type {candidate.type} \
  --field "source={candidate.source_path}" \
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
- Use standard Markdown links `[display](path)` — never Wiki links `[[...]]`
- Do not repeat the frontmatter content in the body

## Step 7: Record the outcome (MANDATORY)

Every path through Steps 1–6 ends here — a skip decided in Step 4 or 5 included. Record exactly one outcome with the CLI. The workspace cannot complete until every candidate has one, and the CLI checks what you record (the note exists; a created note's `source` is inside this workspace; a skip has a valid label and reason). Use `bin/rill`, never bare `rill`:

```bash
# Case A — created a new note
bin/rill workspace distill outcome {workspace_id} --run {run} --cid {candidate.id} --status created --path knowledge/notes/{slug}.md

# Case B — updated an existing note (Evergreen merge; only if it adds new content)
bin/rill workspace distill outcome {workspace_id} --run {run} --cid {candidate.id} --status updated --path knowledge/notes/{existing_slug}.md

# Case C — skipped with a valid justification
bin/rill workspace distill outcome {workspace_id} --run {run} --cid {candidate.id} --status skipped \
  --label EVERGREEN_DUPLICATE --path knowledge/notes/{existing}.md --reason "same topic, same type, covers the same content"
bin/rill workspace distill outcome {workspace_id} --run {run} --cid {candidate.id} --status skipped \
  --label INTERMEDIATE_CONCLUSION --ref workspace/{workspace_id}/NNN-file.md --reason "claim X is contradicted by Y which says Z"
bin/rill workspace distill outcome {workspace_id} --run {run} --cid {candidate.id} --status skipped \
  --label IMPLEMENTATION_DETAIL --reason "one-line explanation"
bin/rill workspace distill outcome {workspace_id} --run {run} --cid {candidate.id} --status skipped \
  --label MERGED_INTO_OTHER --into {other candidate id} --reason "one-line explanation"
```

Write the note first, then record the outcome, so an interruption between the two is resumed safely (a rerun finds your note in the Evergreen check). If the command exits non-zero, read its message, fix the cause (for example a missing `source` field), and run it once more. Never record `USER_DECLINED` — that label is reserved for the user's own decision in an interactive session.

## Output — return ONE line to the parent

- `OUTCOME {candidate.id} created knowledge/notes/{slug}.md`
- `OUTCOME {candidate.id} updated knowledge/notes/{existing_slug}.md`
- `OUTCOME {candidate.id} skipped {LABEL}`
- `OUTCOME_FAILED {candidate.id} {one-line reason}` — when the outcome could not be recorded

Return only that line. Details live in the note and the distill record.

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

- Total tool calls for one distillation: **~8-12** (Read source + Read related + Read _summary.md + Grep verify + Read extra deliverable + Glob evergreen + Grep evergreen + rill mkfile + Edit + outcome record)
- Do not read more than **5 files total** from the workspace directory
- Do not read more than **2 files total** from `knowledge/notes/` (and only frontmatter, first 10 lines each)

Your fresh context gives you a comfortable budget, but discipline prevents wandering.

## Constraints summary

- `inbox/` files are read-only — never modify
- Use `rill mkfile` for file creation (auto-sets `created` field)
- Do not fabricate facts not grounded in the deliverables
- One sub-agent = one candidate = one atomic note (or one skip) = one recorded outcome
- Return only the one-line result, nothing else
