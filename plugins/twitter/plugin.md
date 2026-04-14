---
source-type: tweet
inbox-dir: inbox/tweets
---

# Twitter/X Plugin

Tweet import and organization plugin. Uses the FixTweet API to fetch tweet text and metadata.

## Pipeline

```
Method 1 (directly from Mac):
  rill clip <tweet-url> → inbox/tweets/

Method 2 (from iPhone via iCloud Drive):
  iPhone Share Sheet → iOS Shortcut → iCloud Drive/Rill/tweet-urls/*.txt
  → rill sync twitter → rill clip → inbox/tweets/

Common:
  → /distill Phase 2 → FixTweet API → inbox/tweets/_organized/ (structured Markdown)
```

## Provides

- **Source Adapter**: `adapter.sh` — Import tweet URLs from iCloud Drive
- **Distill Handler**: `distill.md` — Tweet organization prompt for /distill Phase 2
- **Skill**: `/sync-twitter` — Interactive sync (Claude Code)
- **Skill**: `/clip-tweet` — Individual tweet import (separate `.claude/commands/clip-tweet.md`)

## Setup (iPhone pipeline)

### 1. iCloud Drive Folder

Create on your Mac:
```bash
mkdir -p ~/Library/Mobile\ Documents/com~apple~CloudDocs/Rill/tweet-urls/
```

On iPhone, this appears as `iCloud Drive/Rill/tweet-urls/` in the Files app.

### 2. Create an iPhone Shortcut

In the Shortcuts app, create a new shortcut named "Save Tweet to Rill":

#### Step 1: Configure the Share Sheet

1. Tap the **v** next to the shortcut name to open details
2. Turn **"Show in Share Sheet"** ON (default is OFF; the shortcut won't appear in X's Share Sheet if this is off)
3. Accepted types: enable **"Text"** and **"URL"** only

> **Note**: If you only enable "URL", the shortcut may not appear in X's Share Sheet. X shares tweets as mixed text (body + URL string), so "Text" must also be accepted.

#### Step 2: Add Actions

Add the following 4 actions in order:

**1. "Get URLs from Input"**
- Search for "URL" → select "Get URLs from Input"
- Input: "Shortcut Input" (set automatically)

**2. "Text"**
- Search for "Text" → select the "Text" action
- Tap to place the **URL** variable from the previous step into the text field

**3. "Save File"**
- Search for "File" → select "Save File"
- Settings:
  - Destination: Select the `tweet-urls` folder (open `iCloud Drive/Rill/tweet-urls/` in the Files app first to make it easier to find)
  - **"Ask Where to Save"** → OFF
  - **"Sub Path"**: Place the "Current Date" variable, change format to `yyyy-MM-dd-HHmmss`, then type `.txt` at the end
  - **"If a file already exists, overwrite"** → OFF

> **Note**: If you selected the `tweet-urls` folder directly as the destination, the sub-path only needs the filename (date + `.txt`), not the folder path.

**4. "Show Notification"**
- Search for "Notification" → select "Show Notification"
- Body: "Tweet saved to Rill"
- Title: "Rill"

### 3. Usage

1. Tap the share button on a tweet in the X app
2. Select **"Save Tweet to Rill"** from the Share Sheet
3. A "Tweet saved to Rill" notification confirms success
4. Run `rill sync twitter` on your Mac (or `/sync-twitter`)
5. Run `/distill` to fetch content via FixTweet API and organize

### 4. Install the Plugin

```bash
rill plugin install twitter
rill plugin enable twitter
```

### 5. Sync

```bash
rill sync twitter
```

### Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| Shortcut not visible in Share Sheet | "Show in Share Sheet" is OFF | Turn it ON in shortcut details |
| Shortcut not visible in Share Sheet | Accepted types set to "URL" only | Enable both "Text" and "URL" |
| .txt file is empty (0 bytes) | "Text" not in accepted types | Same as above — X sends data as text format |
| Folder not visible in iCloud Drive | Not created on Mac | Run the `mkdir -p` command to create it |
| `rill sync twitter` errors | Plugin not installed | Run `rill plugin install twitter` |

## Direct Import from Mac

Import tweets directly from the Mac terminal without going through iCloud Drive:

```bash
rill clip https://x.com/user/status/123456789
```

## File Format

`.txt` file saved to iCloud Drive (single line):

```
https://x.com/user/status/123456789
```

`.md` file generated in `inbox/tweets/` after `rill sync twitter`:

```markdown
---
created: 2026-03-22T10:00+09:00
source-type: tweet
url: "https://x.com/user/status/123456789"
tweet-id: "123456789"
---

<!-- Content will be fetched by /distill Phase 2 via FixTweet API -->
```
