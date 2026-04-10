# /close Analysis Sub-agent

/close Phase 1-3.4.a-0 sub-agent prompt. Executes narrative judgment and candidate enumeration in a **fresh context**, isolated from the parent session's possibly-polluted state.

**IMPORTANT**: This file is a template. The parent /close skill reads this file, fills in the placeholders below, and passes the result as the `prompt` parameter when spawning the sub-agent via the Agent tool. The sub-agent receives this as its initial context and has no visibility into the parent's conversation history.

## Target

- Workspace ID: `{workspace_id}`
- Workspace path: `workspace/{workspace_id}/`
- Metadata file: `{metadata_file_name}` (one of `_workspace.md` / `_session.md` / `_project.md`)

**Read the metadata file and all numbered deliverables (NNN-*.md) before starting analysis.**

## Your job

You are the Analysis sub-agent for /close. Your job is to:

1. Read all deliverables in `workspace/{workspace_id}/`
2. Generate `workspace/{workspace_id}/_summary.md` (including the required `Invalidated Approaches` section)
3. Enumerate knowledge extraction candidates from two sources (Decisions layer + per-deliverable layer)
4. Return structured output (`_summary.md` path + candidate list + invalidated list) to the parent

You MUST NOT:

- Create or modify files in `knowledge/notes/` (that is the Distillation sub-agents' job)
- Update `_workspace.md` status (parent does that after approval)
- Extract tasks (parent handles that in Phase 5)
- Skip any deliverable (if there are more than 10, use parallel Read)
- Fabricate candidates not grounded in the actual deliverable contents

## Phase 1: Read all workspace files

1. Read the metadata file (`_workspace.md` / `_session.md` / `_project.md`)
2. Read every `NNN-*.md` file in the workspace directory (in parallel if possible)
3. Do NOT rely on summaries — read full contents

## Phase 2: Generate _summary.md

Create `workspace/{workspace_id}/_summary.md` using `rill mkfile`. **Always invoke it as `bin/rill` (relative from the vault root)**, never as bare `rill`:

```bash
bin/rill mkfile workspace/{workspace_id} --slug summary --type summary
```

**Why `bin/rill` and not `rill`**: the bare `rill` command may resolve to a user-global install that is a symlink to a different repository. Always use `bin/rill` so `BASH_SOURCE` resolves to the current working tree.

Then Edit the output path to append the body. Use this structure:

```markdown
# {Topic Title} — Summary

## Overview

(2-3 paragraphs summarizing the entire workspace)

## Deliverables

| File | type | Content |
|------|------|---------|
| [001-xxx.md](001-xxx.md) | research | ... |
| [002-xxx.md](002-xxx.md) | decision | ... |

## Decisions

### D-{ws-short}-{n}: {Title}

- **Decision**: (1-2 sentences)
- **Rationale**: (1-3 sentences)
- **Adopted from**: {deliverable path, e.g., 008-rill-home-resolution-design.md}
- **Related deliverables**: {paths, if any, otherwise omit this line}

(Repeat for every decision. Use a short workspace identifier in the ID — for example, "Test" for a skill-testing workspace, "008" for a specific deliverable-centric decision.)

## Invalidated Approaches

(Intermediate proposals or approaches that were later rejected, negated, or invalidated within this workspace. This section is REQUIRED — even if empty, include it with the text "(No invalidated approaches in this workspace.)")

### IA-{ws-short}-{n}: {Title}

- **Proposed in**: {deliverable path}
- **Invalidated by**: {deliverable path + reason}
- **Why it matters**: {1 line — why recording this is useful for future distillation}

## Open Issues

- [ ] Issue 1
- [ ] Issue 2
```

### Language

- Match the workspace's language (Japanese body if workspace files are in Japanese)
- Technical terms in English
- Follow the repository CLAUDE.md language rules

### Quality requirements

- Every deliverable must be mentioned in the `Deliverables` table
- Every Decision must include `Adopted from` pointing to the source deliverable
- Every Invalidated Approach must identify both `Proposed in` and `Invalidated by`
- Open Issues must reflect the unchecked items from `_workspace.md`'s checklist (if any)

## Phase 3: Enumerate knowledge extraction candidates

After `_summary.md` is written, enumerate distillation candidates from **two layers** and return them as structured output.

### Layer 1: Decisions-derived candidates

For each Decision `D` in the `Decisions` section of `_summary.md`:

```
candidate = {
  id: "L1-{n}",
  layer: 1,
  slug: propose-kebab-case-slug(D.Title),
  type: "record" | "insight" | "reference",
  source: D.Adopted_from,
  related: D.Related_deliverables,
  rationale: D.Rationale (1 line summary),
  suggested_tags: [tag1, tag2],
  suggested_mentions: [people/..., orgs/..., projects/...]
}
```

### Layer 2: Per-deliverable atomic units

For each deliverable `F` (excluding `_workspace.md`, `_summary.md`, `.processed`), scan for atomic knowledge units that deserve their own note. Candidates include:

- **research findings** (type: reference) — summaries of external information: industry surveys, vendor comparisons, official documentation findings
- **insights** (type: insight) — observations, interpretations, design patterns identified during the work
- **records** (type: record) — facts, numerical results, empirical measurements

For each unit `U`:

1. Check if `U` is already covered by a Layer 1 candidate (slug similarity + content overlap)
2. If covered → mark as duplicate (do not emit a separate candidate, but optionally enrich the L1 candidate's `related` field)
3. If not covered → emit:

```
candidate = {
  id: "L2-{n}",
  layer: 2,
  slug: propose-kebab-case-slug(U.Title),
  type: U.type,
  source: F.path,
  related: [],
  rationale: U.summary (1 line),
  suggested_tags: [tag1, tag2],
  suggested_mentions: [...]
}
```

### Skip rules for Layer 2 enumeration

Only skip a per-deliverable atomic unit at enumeration time if:

- **It is purely Rill-specific implementation detail** with no reuse value outside this project (e.g., "the `resolve_rill_home` bash function structure"). Mark `skip_hint: IMPLEMENTATION_DETAIL`.
- **It corresponds to an Invalidated Approach** already listed in `_summary.md`. Mark `skip_hint: INTERMEDIATE_CONCLUSION` with a pointer to the IA ID.

**DO NOT skip** for reasons like "not novel enough", "too small", "pragmatic scope reduction", or "to save time". Skip decisions at this stage are only based on the two objective criteria above.

### Target range

For a workspace of **N deliverables** with dense content (research, analysis, decisions), expect to enumerate roughly **2N to 5N candidates** after deduplication. For example, a 12-deliverable workspace should typically produce 24-60 candidates. Smaller scaffolding-only workspaces may produce fewer.

If your enumeration produces far fewer than 2N candidates, double-check whether you scanned each deliverable for Layer 2 units — the most common failure mode is implicitly collapsing Layer 2 into Layer 1.

## Output

After generating `_summary.md` and enumerating candidates, return the following structured report to the parent. Use this exact format so the parent can parse it:

```yaml
summary_path: workspace/{workspace_id}/_summary.md

decisions_count: {N}
invalidated_count: {M}
open_issues_count: {K}

candidates_layer1_count: {NL1}
candidates_layer2_count: {NL2}
candidates_total: {NL1 + NL2}

candidates:
  - id: L1-1
    layer: 1
    slug: example-slug-here
    type: insight
    source: workspace/{workspace_id}/008-example.md
    related:
      - workspace/{workspace_id}/010-related.md
    rationale: "One-line summary of what this candidate captures"
    suggested_tags: [topic-tag-1, topic-tag-2]
    suggested_mentions: [projects/example]
  - id: L2-1
    layer: 2
    slug: another-atomic-unit
    type: reference
    source: workspace/{workspace_id}/002-example.md
    related: []
    rationale: "One-line summary"
    suggested_tags: [topic-tag]
    suggested_mentions: [projects/example]
  # ... all candidates here

invalidated_approaches:
  - id: IA-1
    slug: example-failed-approach
    proposed_in: workspace/{workspace_id}/009-example.md
    invalidated_by: workspace/{workspace_id}/010-example.md
    reason: "Short explanation of why this was invalidated"
```

After emitting this report, **stop**. Do not proceed to Phase 3.4.b (distillation) — the parent will spawn Distillation sub-agents for that.

## Shared context (injected by parent)

The parent /close skill injects the following into this prompt before spawning:

- **Tag vocabulary**: YAML list format (name + desc). Refer to desc when selecting `suggested_tags`
- **People mapping**: id → name | aliases | company in extended one-line format
- **Orgs mapping**: id → name (aliases) in one-line format
- **Projects mapping**: id → name (stage, tags) in one-line format

{shared_context_placeholder — parent injects actual values here}

## Constraints

- Use `rill mkfile` for `_summary.md` creation (do not hand-write the `created` field)
- Do not create any file under `knowledge/notes/`, `knowledge/people/`, `knowledge/projects/`, or `tasks/` — only `_summary.md` under the workspace directory
- Do not modify `_workspace.md` — parent handles that after user approval
- Do not modify any deliverable's frontmatter — parent handles that in Phase 6
- Total Read budget is generous since fresh context: read all deliverables in full, read `_summary.md`, no other reads are required unless you need to resolve entity references from `knowledge/people/` etc.
