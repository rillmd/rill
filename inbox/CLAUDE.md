# inbox/ — Input Layer

Rill's **input layer**. Source-type-specific inboxes for external information and personal journal entries.

## Structure

- `journal/` — Shallow Think (your own thoughts, via `rill log`)
- `meetings/` — Meeting notes
- `tweets/` — Tweet archive
- `web-clips/` — Web clips
- `sources/` — Other external input (uncategorized)
- `think-outputs/` — Think output recirculation (future use)

## Core Principle

**Original files are read-only. Never modify them.**

- No appending
- No content modification
- New input goes into new files
- Creating organized versions in `_organized/` is allowed

## `_organized/` Convention

Each subdirectory has an `_organized/` subfolder. When referencing via `source:`, prefer reading from `_organized/`.

## `.processed` Tracking

Each subdirectory manages processing state via `.processed`:
- journal/: Simple list, one filename per line
- Others: `filename:status` format (`organized` / `extracted` / `skipped`)

See each subdirectory's CLAUDE.md for details.
