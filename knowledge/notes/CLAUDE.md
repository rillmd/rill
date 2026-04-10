# knowledge/notes/ — Atomic Knowledge Pool

Distilled atomic knowledge. **Flat pool structure**.

## Principles

- 1 file = 1 atomic piece of knowledge
- Evergreen (update existing files, don't create duplicates)
- Keep flat (no subdirectories)

## Filename

English kebab-case. Reflects the content.

**Important conventions**:
- **Entity-linked notes**: Prefix with the entity ID
  - e.g., `acme-saas-pricing-model.md`, `alex-chen-contract-details.md`
- **General knowledge**: Topic only
  - e.g., `saas-manual-operation-bootstrap.md`, `whisper-api-comparison.md`

## Frontmatter (required fields)

```yaml
---
created: 2026-02-13T15:00+09:00   # Auto-set by rill mkfile
type: insight | record | reference  # Required
source: inbox/meetings/_organized/2026-02-16-X.md  # Required
tags: [pricing, saas]              # Max 3
mentions: [projects/acme-saas]     # Typed entity references
related:
  - knowledge/notes/related-note.md
---
```

### type values
- `record`: Facts and data
- `insight`: Observations and interpretations
- `reference`: External citations

## File Creation Flow

1. **Duplicate check**: Use Glob/Grep to check for existing files
2. **If exists, update it** (Evergreen principle)
3. **If not, create new**: `rill mkfile knowledge/notes --slug {slug} --type {type}`
4. Fill in frontmatter and body with Edit (`created` is automatic, `source` must be specified)

## Contact PII Prohibited

**Do not write contact information (email, phone numbers) in knowledge/notes/**. Contacts belong only in knowledge/people/ or knowledge/orgs/ (ADR-047).

## Efficient Searching

Despite the flat structure, the combination of filename prefix + mentions + tags enables efficient search:

- Entity-related: `Glob knowledge/notes/acme-saas-*.md`
- By tag: `Grep -r "tags:.*pricing" knowledge/notes/`
- By project: `Grep -r "mentions:.*projects/acme-saas" knowledge/notes/`

## Metadata Quality Checks

When reading files, those with incomplete metadata are automatically added to `.refresh-queue` (see Mode B section in `.claude/rules/rill-data-model.md`).
