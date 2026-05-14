# Knowledge Rules — Rill

`knowledge/` is the **accumulation layer (Evergreen)** — distilled atomic knowledge and entity information.

## Structure

```
knowledge/
├── self/         # Interest Profile + state layer (8 files; see below)
├── notes/        # Distilled atomic knowledge (pool, flat)
├── people/       # Person entities
└── orgs/         # Organization entities
```

Each container (people/orgs/self/) has its own `CLAUDE.md` (on-demand loaded). Projects (execution hubs) live under top-level `projects/` (ADR-080) — see `rill-projects.md`.

## knowledge/notes/

- 1 file = 1 atomic piece of knowledge. English kebab-case filename.
- **Evergreen**: if content overlaps an existing file, update it rather than creating a new one.
- **Filename prefix convention**: entity-tied notes prefix with entity ID (`acme-saas-pricing-model.md`); generic knowledge uses topic only (`saas-manual-operation-bootstrap.md`).
- **Stays flat** — no subdirectories. Categorization via filename prefix + `mentions` + `tags`.

### Frontmatter

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

- `type`: `record` (facts/data) / `insight` (observations) / `reference` (external citations)
- `source`: required — knowledge/notes/ always has one

Duplicate-check before creating (Grep/Glob); update existing on overlap.

## Entity Files (people/orgs/)

- **frontmatter** = search anchor + normalization hub
- **body** = distilled key facts (~20 max, Evergreen)
- Filename matches `id` (kebab-case); `id` is the short identifier used in task `mentions`

**Do NOT write**: interaction history, task lists, artifact links, aggregation results. Those belong in `journal/`, `tasks/`, `workspace/`, `pages/`. Dynamic aggregation runs via grep/read.

## knowledge/self/ (Interest Profile + state layer)

Singleton entity (`type: self`). **8 files**, each owned by a distinct velocity / skill:

- `profile.md` — Core Identity (year-scale)
- `interests.md` — Deep Interests / Curiosity / Obligations / Career (monthly)
- `direction.md` — Active Projects + cross-project meta-direction + Career direction (monthly)
- `current-state.md` — pulse snapshot (high-velocity, by `/pulse`, capped at 80 lines)
- `decisions.md` — curated decision digest (3-month window, by `/retrospective`)
- `observations.md` — longitudinal self-observations (by `/retrospective` with user `[x]` approval)
- `history.md` — career / event history (manual)
- `constraints.md` — constraints (family / financial / health, manual)

Referenced by `/briefing`, `/newsletter`, `/pulse`, `/solve`, `/eval`, `/distill profile-agent`. **Guide, not constraint** — LLMs may suggest adjacent areas. `interests.md` / `direction.md` auto-update via `/distill profile-agent` (conservative rules). Design rationale: `workspace/2026-05-07-dream-system-rill-application/006-self-knowledge-layer-design.md`.

## Contact Information (ADR-047)

**Email addresses and phone numbers may only live in `knowledge/people/` or `knowledge/orgs/`** — nowhere else (notes/, workspace/, inbox/, tasks/, etc.). Minimizes PII exposure surface.

## Binary Assets

The rule gates on **PII content**, not file format.

- **PII-bearing source binaries** (business cards, scanned contracts, meeting PDFs/slides/screenshots with real names/emails/phones): do not commit. Typically `inbox/sources/*.{jpg,jpeg,png,heic,pdf}`, excluded by default `.gitignore` per ADR-047 D47-2.
- **Non-PII asset binaries** (app icons, logos, doc UI screenshots, generated figures): may be committed when small (~2 MB soft cap) and user-approved. Prefer SVG / Markdown when equivalent.

A 100 KB app icon is fine; a screenshot leaking real email addresses is not. Strip PII or keep out of Git.
