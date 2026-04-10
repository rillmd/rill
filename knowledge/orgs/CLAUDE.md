# knowledge/orgs/ — Organization Entities

Organization entity files. Search anchor + normalization hub + key fact accumulation.

## Filename

`{id}.md` (kebab-case). Must match the `id` field.

## Frontmatter

```yaml
---
created: 2026-03-14T00:00+09:00
type: org
id: sunrise-hotel                          # Required, matches filename
name: Sunrise Hotel Corp.                  # Required
aliases: [Sunrise Hotel, SHC]
industry: Hospitality
relationship: client                       # client | prospect | partner | competitor
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

## Writing Rules

Same as `knowledge/people/`:

### What to write
- Key facts (/distill auto-accumulates, up to 20 items)
- Update following the Evergreen principle

### What NOT to write
- Interaction history
- Task lists
- Deliverable links
- Aggregated results

## Relationship with knowledge/people/

- The `company` field in `knowledge/people/` references the `id` in `knowledge/orgs/`
- Multiple people can be linked to one org

## Contact Information

Organization contact details (main phone, info@ email, etc.) may be recorded here (ADR-047):

```yaml
email: info@example.com
phone: "+1-555-XXX-XXXX"
address: "Address"
```

## Creating New

```bash
rill mkfile knowledge/orgs --slug {id} --type org
```
