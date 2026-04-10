# knowledge/projects/ — Project Entities

Project entity files. Project hub + competitor monitoring + goal management.

## Definition

Project = an initiative the user is actively pursuing. Covers business, personal, and learning — completion criteria are not required (ADR-049).

Independent from `workspace/`. No forced 1:1 mapping (one project can have multiple workspaces, ADR-042).

## Filename

`{id}.md` (kebab-case). Must match the `id` field.

## Frontmatter

```yaml
---
created: 2026-03-14T01:00+09:00
type: project
id: acme-saas                       # Required, matches filename
name: Acme SaaS                     # Required
stage: active                       # active | idea | completed
entity: techcorp                    # Optional: operating entity → orgs/ id
relationship: own                   # own | client-work | oss | personal
tags: [acme-saas]
---
```

## Body Structure (required sections)

```markdown
{Brief introduction}

## Goals
- Goal 1
- Goal 2

## Current Focus
{Current status. Auto-updated by /distill}

## Watch

### Competitors
- **Competitor Name** — Description

### Keywords
- "keyword 1"
- "keyword 2"

## Key Facts
- Fact 1 (/distill auto-accumulates, up to 20 items)

## See Also
- [workspace/xxx/](../../workspace/xxx/) — Related workspace
```

## Writing Rules

### What to write
- **Goals**
- **Current Focus**
- **Watch** (Competitors + Keywords) — Referenced by /newsletter
- **Key Facts** (/distill auto-accumulates)
- **See Also** (links only, not aggregated results)

### What NOT to write
- **Session history** (workspace/ responsibility)
- **Task lists** (tasks/ responsibility)
- **Deliverable contents** (workspace/ responsibility)
- **Aggregated results** (dynamic aggregation is handled by Claude Code)

## See Also Nature

- Links (navigation), not aggregated results
- Auto-managed by `/distill`
- Markdown link format: `[display name](relative path)`

## Watch Section

`/newsletter` automatically references this to fetch the latest on competitors and keywords:
- Competitors: List of competitor companies
- Keywords: Search keywords (mixed languages OK)

## Creating New

```bash
rill mkfile knowledge/projects --slug {id} --type project
```
