# inbox/meetings/ — Meeting Notes

Meeting note input. source-type: meeting.

## Filename

`YYYY-MM-DD-description.md` (e.g., `2026-02-16-sunrise-hotel-meeting.md`)

## Raw Frontmatter (original file)

```yaml
---
created: 2026-02-16T10:58+09:00
source-type: meeting
original-source: "Google Meet Gemini Notes"
---
```

## Organized Frontmatter (_organized/ file)

```yaml
---
created: 2026-02-16T10:58+09:00
source-type: meeting
original-file: inbox/meetings/2026-02-16-sunrise-hotel-meeting.md
original-source: "Google Meet Gemini Notes"
tags: [acme-saas, client-meeting]
participants: [Alex Chen, Takeda, Tokunaga, Kosano]
mentions: [people/alex-chen, orgs/sunrise-hotel, projects/acme-saas]
---

Structured summary, decisions, key points...
```

## Characteristics

- **`participants`**: List of meeting attendees (required)
- **`original-source`**: Import origin (Google Meet, Zoom, handwritten notes, etc.)
- The `_organized/` version contains a structured summary, decisions, and key points
- `/distill` automatically updates key facts in knowledge/people/ and knowledge/orgs/

## Immutability Principle

Original files are read-only. Only `_organized/` creation is allowed.

## Contact Information Handling

Even if contact details (email, phone numbers) appear in meeting notes, **do not carry them over to organized versions**. Contact information belongs only in knowledge/people/ or knowledge/orgs/ (ADR-047).

## Plugin Import

May be auto-imported via plugins such as `rill sync google-meet`.
