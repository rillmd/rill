# inbox/meetings/ — Meeting Notes

Meeting note input. source-type: meeting.

## Filename

`YYYY-MM-DD-description.md` (e.g., `2026-02-16-sunrise-hotel-meeting.md`)

A note written in the Rill app is named `YYYY-MM-DD-HHmmss.md`, the time it was created, with its title in the `title` frontmatter field.

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

- **`participants`**: List of meeting attendees (required in the organized version; `/distill` keeps it from the original when present and otherwise extracts it from the text)
- **`original-source`**: Import origin (Google Meet, Zoom, handwritten notes, `Rill GUI note` for a note written in the Rill app, etc.)
- The `_organized/` version contains a structured summary, decisions, and key points
- `/distill` automatically updates key facts in knowledge/people/ and knowledge/orgs/

## Immutability Principle

Original files are read-only. Only `_organized/` creation is allowed.

A note written in the Rill app stays outside the inbox, as a draft in `.rill/state/drafts/`, until it is finished. Once it is here it follows the same rule.

## Contact Information Handling

Even if contact details (email, phone numbers) appear in meeting notes, **do not carry them over to organized versions**. Contact information belongs only in knowledge/people/ or knowledge/orgs/ (ADR-047).

## Plugin Import

May be auto-imported via plugins such as `rill sync google-meet`.
