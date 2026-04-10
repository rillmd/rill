# knowledge/people/ — Person Entities

Person entity files. Search anchor + normalization hub + key fact accumulation.

## Filename

`{id}.md` (kebab-case). Must match the `id` field.

## Frontmatter

```yaml
---
created: 2026-02-18T10:00+09:00
type: person
id: alex-chen                         # Required, matches filename
name: Alex Chen                       # Required
aliases: [A. Chen, Chen]              # Normalization hub for name variants
company: sunrise-hotel                # References id in orgs/
role: IT Manager
relationship: client                  # client | prospect | advisor | team
email: alex.chen@example.com          # PII: write here, nowhere else
phone: "+1-555-XXX-XXXX"              # Optional
tags: [acme-saas]
---
```

## Body Structure

```markdown
{Brief introduction, 1-2 lines}

## Key Facts
- Fact 1
- Fact 2
- ...
```

## Writing Rules (Important)

### What to write
- **Key facts** (/distill auto-accumulates)
- Up to **20 items** guideline
- Update following the Evergreen principle

### What NOT to write
- **Interaction history** ("talked with X today", etc.)
- Task lists
- Deliverable links
- Aggregated results

These belong in journal/, tasks/, workspace/ respectively. Dynamic aggregation is performed by Claude Code via grep/read.

## Contact Information Hub

**Contact information (email, phone numbers) must only be recorded in knowledge/people/ or knowledge/orgs/** (ADR-047). Writing to other locations (notes/, workspace/, inbox/, tasks/) is prohibited.

## aliases Field Purpose

- Normalization hub for name variants
- Used by /distill and mentions resolution
- e.g., `[A. Chen, Chen, alex-chen]`

## company Field

- References the `id` in `knowledge/orgs/`
- Expresses the relationship between person and organization

## Creating New

```bash
rill mkfile knowledge/people --slug {id} --type person
```
