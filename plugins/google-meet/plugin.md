---
source-type: meeting
inbox-dir: inbox/meetings
---

# Google Meet Adapter

Plugin that automatically imports Google Meet meeting notes (Gemini notes) into Rill's `inbox/meetings/`.

## Provides

- **Adapter**: `adapter.sh` — Searches Google Drive for Gemini notes and saves them to `inbox/meetings/`
- **Skill**: `commands/sync-google-meet.md` — Interactive import via Claude Code (generates high-quality frontmatter)
- **Distill Handler**: `distill.md` — Meeting notes organization prompt for /distill Phase 2

## Requires

- [gogcli](https://github.com/steipete/gogcli) — Google Workspace CLI tool

## Setup

### 1. Install gogcli

```bash
brew install steipete/tap/gogcli
```

### 2. Google Cloud Authentication

You need an OAuth client credentials JSON:

```bash
gog auth credentials /path/to/client_secret.json
```

### 3. Add Account

```bash
gog auth add your-email@gmail.com --services drive,docs
```

A browser window will open for Google account authentication.

### 4. Install the Plugin

```bash
rill plugin install google-meet
rill plugin enable google-meet
```

## Usage

### Shell (mechanical sync)

```bash
rill sync google-meet
```

Searches Google Drive for "Notes by Gemini" and imports unsynced documents to `inbox/meetings/`. Can be automated via cron.

### Claude Code (interactive sync)

```
/sync-google-meet
```

Claude Code understands the content and generates high-quality frontmatter (participants, tags, etc.).

## Imported File Format

```yaml
# inbox/meetings/YYYY-MM-DD-meeting-title.md
---
created: 2026-02-18T10:00+09:00
source-type: meeting
original-source: "Google Meet Gemini Notes"
google-doc-id: "1abc..."
---

Meeting notes content...
```

## Troubleshooting

- `gog: command not found` — Run `brew install steipete/tap/gogcli`
- `authentication required` — Run `gog auth add <email> --services drive,docs`
- `no documents found` — Verify that Gemini notes are saved in Google Drive
