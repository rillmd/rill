# Knowledge Rules — Rill

`knowledge/` is the **accumulation layer (Evergreen)**. Stores distilled atomic knowledge and entity information.

## Structure

```
knowledge/
├── self/         # Interest Profile + state layer (8 files; see "knowledge/self/" section below)
├── notes/        # Distilled atomic knowledge (pool, flat)
├── people/       # Person entities
├── orgs/         # Organization entities
└── projects/     # Project entities
```

Each container directory (people/orgs/projects/) has its own `CLAUDE.md` (on-demand loaded).

## knowledge/notes/ Principles

### Atomic Units
- 1 file = 1 atomic piece of knowledge
- File names: English kebab-case, reflecting content (e.g., `whisper-api-comparison.md`)
- **Evergreen**: If content overlaps with an existing file, update the existing file rather than creating a new one

### File Name Prefix Convention
- **Notes tied to a specific entity should use the entity ID as prefix (recommended)**
  - Examples: `acme-saas-pricing-model.md`, `alex-chen-contract-details.md`
- Generic knowledge uses topic only
  - Example: `saas-manual-operation-bootstrap.md`

### Required Frontmatter

```yaml
---
created: 2026-02-13T15:00+09:00  # auto-assigned by rill mkfile
type: insight | record | reference
source: inbox/meetings/_organized/2026-02-16-X.md  # required
tags: [pricing, saas]       # max 3
mentions: [projects/acme-saas]
related:
  - knowledge/notes/related-note.md
---
```

- `type`: `record` (facts/data) / `insight` (observations/interpretations) / `reference` (external citations)
- `source`: **Required**. knowledge/notes/ always has a source

### Duplicate Check

- Check for duplicates against existing files before creating new ones (Grep/Glob)
- Update existing files if overlapping (Evergreen principle)

### Keep Flat

- knowledge/notes/ has many files but **stays flat**. Do not create subdirectories (breaking change, conflicts with fluid mention/tag classification)
- Categorization is done via **filename prefix + mentions + tags**

## Entity Files (people/orgs/projects/)

### Common Principles

- **frontmatter** = search anchor + normalization hub
- **body** = distilled key facts
- File name matches the `id` field (kebab-case)
- `id` is a unique short identifier. Used in task `mentions`

### What to Write
- Key facts (/distill auto-accumulates)
- Guideline: max ~20 items
- Updated under Evergreen principle

### What NOT to Write (important)
- Interaction history
- Task lists
- Artifact links
- Aggregation results

→ These belong in `journal/`, `tasks/`, `workspace/`, `pages/` as appropriate. Dynamic aggregation is executed by Claude Code via grep/read.

### projects/ Specifics

- Project = an initiative the user is actively pursuing (business, personal, or learning)
- Independent from workspace/. No 1:1 correspondence enforced (ADR-042, ADR-049)
- What to write: Goal, Current Focus, Watch (Competitors + Keywords), Key Facts, See Also (links)
- See Also contains links, not aggregation results (/distill auto-manages)

## knowledge/self/ (Interest Profile + state layer)

- Singleton-entity directory (`type: self`), located directly under `knowledge/` alongside `notes/` / `people/` / `orgs/` / `projects/`
- **8 files**, each owned by a distinct velocity / skill (per `workspace/2026-05-07-dream-system-rill-application/006-self-knowledge-layer-design.md`):
  - `profile.md` — Core Identity (year-scale)
  - `interests.md` — Deep Interests / Curiosity / Obligations / Career (monthly)
  - `direction.md` — Active Projects + cross-project meta-direction + Career direction (monthly)
  - `current-state.md` — pulse snapshot (high-velocity, updated by `/pulse`, capped at 80 lines)
  - `decisions.md` — curated decision digest (3-month window, updated by `/retrospective`)
  - `observations.md` — longitudinal self-observations (updated by `/retrospective` with user `[x]` approval)
  - `history.md` — career / event history (manual)
  - `constraints.md` — constraints (family / financial / health, etc., manual)
- Referenced by `/briefing`, `/newsletter`, `/pulse`, `/solve`, `/eval`, `/distill profile-agent`
- **Guide, not constraint**: LLMs may suggest adjacent areas outside listed categories
- `interests.md` / `direction.md` are auto-updated by `/distill profile-agent` (with conservative rules)

## Contact Information (ADR-047, important)

**Contact information (email addresses, phone numbers) must only be written in knowledge/people/ or knowledge/orgs/.** Do not write them elsewhere (notes/, workspace/, inbox/, tasks/, etc.).

This minimizes the PII exposure surface.

## Binary Assets

The rule gates on **whether the binary embeds personal data**, not on file format.

- **PII-bearing source binaries** (business cards, scanned contracts, meeting PDFs / slides / screenshots with real names, emails, or phone numbers) must not be committed. These typically land under `inbox/sources/*.{jpg,jpeg,png,heic,pdf}` and are excluded by the default `.gitignore` per [ADR-047 D47-2](../../docs/decisions/047-git-crypt-pii-encryption.md).
- **Non-PII asset binaries** (app icons, logos, UI screenshots intended for documentation, generated figures) **may** be committed when they are reasonably small (soft cap ~2 MB per file) and the user has approved the asset. Prefer text-based formats (SVG, Markdown tables) when equivalent; fall back to PNG / JPG only when a binary format is genuinely required.

A 100 KB app icon is not PII. A screenshot of an inbox view showing real email addresses is. When in doubt, strip the PII before committing, or keep the file out of Git.
