---
data-dir: null
search-scope: false
---

# Google Workspace Plugin

General-purpose plugin providing read/write access to Google Workspace (Calendar, Gmail, Slides, Drive).

## Capabilities

- **Google Slides**: Template cloning, text replacement, PDF export
- **Google Calendar**: Read events (via gogcli)
- **Gmail**: Email search and thread reading (via gogcli)
- **Google Drive**: File search and reading (via gogcli)

## Requires

- [gogcli](https://github.com/steipete/gogcli) — Google Workspace CLI tool
- OAuth authenticated (`gog auth add <email> --services drive,docs,calendar,gmail`)
- Google Cloud project with Slides API / Calendar API / Gmail API enabled

## Provides

- **Lib**: `lib/gw-auth.sh` — OAuth token retrieval helper
- **Lib**: `lib/gw-slides.sh` — Google Slides API operations

## Architecture

Calendar / Gmail / Drive reads use `gogcli` directly.
Slides writes (text replacement, element operations) use `lib/gw-auth.sh` to obtain a token, then call the Slides API directly via curl, since `gogcli` does not have Slides write commands.

## Installation

```bash
rill plugin install google-workspace
rill plugin enable google-workspace
```
