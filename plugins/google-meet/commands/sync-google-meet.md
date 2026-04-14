# /sync-google-meet — Import Google Meet Notes

Automatically import Google Meet meeting notes (Gemini notes). The AI understands the content and generates high-quality frontmatter.

## Arguments

$ARGUMENTS — optional. A keyword if you want to target a specific document

## Steps

### 1. Check prerequisites

1. Run `which gog` via Bash to confirm gogcli is installed
2. If not installed, point the user to the install instructions and exit

### 2. Search for Gemini notes

1. Run `gog --json drive search "Notes by Gemini" --max 100` via Bash
   - **Note**: This query matches English-locale Google accounts. For Japanese-locale accounts, use `"Gemini によるメモ"` instead
2. Parse the resulting JSON to get the list of documents (id, name, createdTime)
3. Read `plugins/google-meet/.synced` to exclude already-synced documents
4. List the unsynced documents

### 3. Import documents

1. If there are no unsynced documents, report "Everything is already synced" and exit
2. For every unsynced document, do the following:

1. Run `gog docs text <doc_id>` via Bash to fetch the text
2. Analyze the content and extract:
   - Participant names (participants)
   - Agenda / topics
   - Appropriate tags (refer to taxonomy.md)
3. Generate a filename: `YYYY-MM-DD-meeting-description.md`
4. Write to `inbox/*/` with high-quality frontmatter:

```yaml
---
created: {createdTime}
source-type: meeting
original-source: "Google Meet Gemini Notes"
google-doc-id: "{doc_id}"
participants: [{extracted participants}]
tags: [{appropriate tags}]
---
```

5. Append to `plugins/google-meet/.synced` (TSV format: `doc_id\tfilename\ttimestamp`)

### 4. Suggest follow-up

1. Report the number of imported files
2. Suggest chaining into `/distill`:
   - "Imported N meeting notes into inbox/*/. Run /distill to organize and distill?"

## Rules

- Read taxonomy.md to check tags before applying them
- Extract participants from the actual text. Do not add guesses
- Cross-reference with knowledge/people/ and use the normalized name for known people
- Save imported files to inbox/*/, not inbox/journal/
