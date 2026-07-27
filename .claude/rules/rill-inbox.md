---
paths:
  - "inbox/**"
---

# Inbox Rules — Rill

`inbox/` is the **input layer (immutable)** — incoming information from external sources and personal journals.

```
inbox/
├── journal/      # Shallow Think: chronological journal
├── meetings/     # Meeting notes (source-type: meeting)
├── tweets/       # Tweets (source-type: tweet)
├── web-clips/    # Web Clips (source-type: web-clip)
├── think-outputs/ # Think output recirculation
└── sources/      # Other external inputs
```

Each subdirectory has `.processed` (tracking) and `_organized/` (organized versions).

## Core Principle: Immutability

**Original files in inbox/ are read-only.** No appending, no modifying. New input → new file (especially strict for journal/ — microfile strategy). Creating organized versions in `_organized/` is allowed.

Violations break Git-as-transaction-log, corrupt `.processed` tracking, and break `/distill` idempotency.

## `_organized/` Convention

Each subdirectory has `_organized/`. Organized filenames match originals. `source:` references prefer `_organized/` if a same-named file exists there.

## `.processed` Format

Tracks processed files (Git-tracked, shared state):

- `journal/`: one filename per line
- Others (`meetings/`, `tweets/`, `web-clips/`, `sources/`): `filename:status` (status: `organized` / `extracted` / `skipped`)

## Subdirectory-Specific Rules

Each subdirectory has its own `CLAUDE.md` (on-demand loaded): `journal/` (microfile strategy), `meetings/` (participants + organized format), `tweets/`, `web-clips/`, `sources/`.

## Frontmatter Basics

```yaml
---
created: YYYY-MM-DDTHH:MM+09:00
source-type: meeting | tweet | web-clip | journal | ...
original-source: "Google Meet Gemini Notes"  # optional
---
```

See `rill-data-model.md` for details.

## File Naming

- journal: `YYYY-MM-DD-HHmmss.md` (auto via `rill log`)
- meetings / tweets / web-clips: `YYYY-MM-DD-description.md` or `YYYY-MM-DD-HHmmss-slug.md`

## PII / Contact Information

**Do not write contacts (email, phone) in inbox/.** They belong only in `knowledge/people/` or `knowledge/orgs/` (ADR-047). See `rill-knowledge.md`.
