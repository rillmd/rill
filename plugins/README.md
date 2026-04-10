# Rill Plugins

Rill's plugin system. Implements data ingestion from external services as swappable "plugins".

## Design Philosophy

- **Rill is the "destination"** — the transport mechanism is swappable
- **Directory = Plugin** — install = add directory + symlink, uninstall = remove symlink
- **2-layer management** — `rill plugin` (shell, mechanical) + `/plugin` (Claude Code, interactive)
- **plugin.md = human-readable docs, directory structure = manifest** — no AI parser needed
- **Capability-based** — plugins are defined by a combination of capabilities (source / workflow / hooks). Existing source-only plugins are fully backward compatible

## Directory Structure

```
plugins/
├── README.md           # This file
├── _lib.sh             # Shared library
├── .gitignore          # Shared gitignore
└── {plugin-name}/      # For source plugins
    ├── plugin.md       # Documentation (overview, setup instructions, usage)
    ├── adapter.sh      # Transport script (executed by rill sync)
    ├── commands/       # Claude Code skill originals
    │   └── *.md        # Symlinked to .claude/commands/ on install
    └── .gitignore      # Excludes .synced
└── {plugin-name}/      # For workflow + hooks plugins
    ├── plugin.md       # Capabilities declaration (data-dir, search-scope, hooks)
    ├── adapter.sh      # source capability (optional)
    ├── distill.md      # Source-specific distill prompt (optional)
    ├── commands/       # workflow capability: skill originals
    ├── hooks/          # hooks capability: core skill extension prompts
    ├── data/           # workflow capability: plugin-specific data
    └── .gitignore
```

## _lib.sh API

Plugin `adapter.sh` files source `_lib.sh` to use shared functions:

```bash
#!/usr/bin/env bash
PLUGIN_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$PLUGIN_DIR/../_lib.sh"
```

### create_source_file

```bash
create_source_file "$filename" "$source_type" "$created" "$extra_frontmatter" "$content"
```

- `$filename` — File name (e.g., `2026-02-18-meeting-notes.md`)
- `$source_type` — `meeting`, `article`, `note`, etc.
- `$created` — ISO 8601 timestamp
- `$extra_frontmatter` — Additional frontmatter lines (newline-separated)
- `$content` — Body text
- Returns: 0 (success), 1 (duplicate)

### is_already_synced / mark_synced

```bash
if ! is_already_synced "$sync_key"; then
    # ... fetch and create file ...
    mark_synced "$sync_key" "$filename"
fi
```

Manages synced keys in `PLUGIN_DIR/.synced`.

## CLI Commands

```bash
rill plugin list              # List plugins + status
rill plugin install <name>    # Symlink commands/*.md to .claude/commands/
rill plugin uninstall <name>  # Remove symlinks (directory is preserved)
rill plugin status            # Detailed status

rill sync                     # List available adapters
rill sync <name>              # Execute adapter.sh
```

## Creating a New Plugin

1. Create a `plugins/{name}/` directory
2. Write documentation in `plugin.md`
3. Implement transport logic in `adapter.sh` (source `_lib.sh`)
4. Place Claude Code skills in `commands/*.md` if needed
5. Add `.synced` to `.gitignore`
6. Enable skills with `rill plugin install {name}`

## Capability Model (D38)

Plugins are defined by a combination of capabilities.

| Capability | What it provides | Example |
|-----------|-----------------|---------|
| source | adapter.sh, distill.md, inbox-dir | google-meet |
| workflow | commands/, data/ | CRM |
| hooks | post-distill, briefing, etc. | CRM |

### Extended frontmatter in plugin.md

```yaml
# source only (existing pattern — no changes)
---
source-type: meeting
inbox-dir: inbox/meetings
---

# Plugin with multiple capabilities
---
source-type: sales-contact        # source capability (optional)
inbox-dir: inbox/contacts          # source capability (optional)
data-dir: data                     # workflow capability
search-scope: true                 # workflow capability: included in /ask search scope
hooks:                             # hooks capability
  post-distill: hooks/post-distill.md
  briefing: hooks/briefing.md
---
```

### Hook Execution Specification

- Control stays with the core: after /distill completes all phases, it scans `plugins/*/plugin.md` and runs hooks from plugins that have a `hooks` field as sub-agents
- Failures are non-fatal: hook execution errors are logged and processing continues (does not affect core processing results)
- Backward compatible: existing source-only plugins have no hooks field and are unaffected

## 3-Tier Classification

| Tier | Examples | Location |
|------|---------|----------|
| Tier 1: Core | `/distill`, `/ask`, `/plugin`, `/sync` | Directly in `.claude/commands/` |
| Tier 2: Built-in | `/focus`, `/close` | Directly in `.claude/commands/` |
| Tier 3: External | `/sync-meetings` | `plugins/*/commands/` via symlink |
