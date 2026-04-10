# inbox/sources/ — Miscellaneous External Input

Other external input (uncategorized). source-type: varies.

## Filename

`YYYY-MM-DD-description.md`

## Frontmatter

```yaml
---
created: 2026-04-07T10:00+09:00
source-type: source   # Change to a specific type once determined
original-source: "description of origin"
---
```

## Use Cases

- External information that doesn't fit existing source-types (meeting, tweet, web-clip)
- Handwritten notes, text transcribed from screenshots, etc.
- `/distill` may reclassify to a more appropriate source-type later

## Binary Files

Binary files containing PII (images, PDFs, etc.) must not be committed to Git. Verify they are excluded via `.gitignore` (ADR-047):

```
inbox/sources/*.jpg
inbox/sources/*.jpeg
inbox/sources/*.png
inbox/sources/*.heic
inbox/sources/*.pdf
```

To ingest binary content into Rill, the recommended approach is to create a **Markdown wrapper** containing the transcribed/extracted text.

## Immutability Principle

Original files are read-only. Only `_organized/` creation is allowed.
