# pages/ — Materialized View Pages

Human-facing aggregated documents for repeated reference (wiki page metaphor, ADR-062).

## Structure

**Flat directory**. Each page has a **recipe pair**:

```
pages/
├── rill-roadmap.md
├── rill-roadmap.recipe.md   ← Always paired
├── body-recomposition.md
└── body-recomposition.recipe.md
```

## Filename

`{id}.md` (kebab-case, **no date prefix**)

## Frontmatter (required fields)

```yaml
---
created: 2026-03-24T10:00+09:00
type: page                         # Required
id: body-recomposition             # Required, matches filename
name: Body Recomposition Strategy  # Required
description: Aggregation of training strategy, diet plan, and weekly log  # Required
updated: 2026-03-24T08:00+09:00    # Auto-set
tags: [fitness]                    # Optional
sources:                           # Optional, structural sources
  - knowledge/notes/body-recomp-basics.md
---
```

## Excluded from AI Search

**`/distill`, `/briefing`, `/eval` do not Grep pages/**. Pages are "user-only Materialized Views" and are not targets for automated AI processing.

Reason: Pages are re-aggregated content, so AI reading them would create information loops.

## `{id}.recipe.md` (Important)

A separate file describing the page's purpose, source hints, and fixed sections:

```yaml
---
created: 2026-03-24T10:00+09:00
type: recipe
---

# Body Recomposition Strategy — Recipe

## Purpose
(What this page is for)

## Source Hints
- knowledge/notes/body-recomp-*.md
- Deliverables from workspace/2026-03-21-body-recomposition/

## Sections
1. Training strategy
2. Diet plan
3. Weekly log
```

**Structure is not prescribed — the AI infers it from the purpose.**

## Required Rule When Updating Pages (ADR-062)

**When updating a file in pages/, you must first Read the corresponding `.recipe.md` to understand the page's purpose.** The recipe describes purpose and source hints, not rigid structure.

Update flow:
1. Read `{id}.recipe.md` first
2. Understand the Purpose and Source Hints from the recipe
3. Gather necessary information from canonical sources (inbox/, knowledge/, workspace/)
4. Edit `{id}.md`
5. Update the `updated` field in frontmatter

## No Direct Editing Principle (D62-5)

**Direct data additions to Pages are prohibited.** Write new facts to canonical sources (knowledge/, inbox/) first, then reflect them in Pages. Pages are views only.

## Writing Style

- **Prose-based**
- **Tables only for comparisons**
- **Maintain chronological axis**

## Creating and Updating

```bash
/page create {id}    # Create new
/page update {id}    # Update existing
```

Or scaffold manually with `rill mkfile pages --slug {id} --type page`.
