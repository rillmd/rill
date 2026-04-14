---
source-type: voice-memo
inbox-dir: inbox/journal
---

# Voice Memo Plugin

Plugin for importing iPhone voice memos as Rill journal entries.

## Pipeline

```
iPhone Voice Memo → iPhone Shortcut (transcription) → iCloud Drive/Rill/voice-memos/*.md → rill sync voice-memo → inbox/journal/
```

## Setup

### 1. iCloud Drive Folder

Auto-created on Mac:
```
~/Library/Mobile Documents/com~apple~CloudDocs/Rill/voice-memos/
```

On iPhone, this appears as `iCloud Drive/Rill/voice-memos/` in the Files app.

### 2. Create an iPhone Shortcut

In the Shortcuts app, create a new shortcut:

1. **"Dictate Text"** action
   - "Stop Listening": "After Pause"
   - Language: your preferred language
2. **"Text"** action — frontmatter template:
   ```
   ---
   created: [Current Date (ISO 8601)]
   source-type: voice-memo
   ---

   [Dictated Text result]
   ```
3. **"Save File"** action
   - Destination: `iCloud Drive/Rill/voice-memos/`
   - Filename: `[Current Date (yyyy-MM-dd-HHmmss)].md`
   - "Ask Where to Save": OFF

### 3. How to Run the Shortcut

- Add to Widgets / Home Screen
- Assign to Action Button (iPhone 15 Pro and later)
- Assign to Back Tap (Settings > Accessibility > Touch > Back Tap)

### 4. Install the Plugin

```bash
rill plugin install voice-memo
rill plugin enable voice-memo
```

### 5. Sync

```bash
rill sync voice-memo
```

Distilled by `/distill` just like regular journal entries.

## Importing Existing Voice Memos

If you have existing recordings in the Voice Memos app:

1. Select the memo in the Voice Memos app
2. Share button → "Shortcuts" → run the above shortcut
   - Or: Share → "Save to Files" to save the .m4a to iCloud Drive (requires separate transcription)

## File Format

File saved to iCloud Drive:

```markdown
---
created: 2026-03-09T10:30+09:00
source-type: voice-memo
---

Transcribed text goes here...
```
