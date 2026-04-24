# Rill Plugins

Rill's plugin system. Implements data ingestion from external services as swappable "plugins".

## Design Philosophy

- **Rill is the "destination"** — the transport mechanism is swappable
- **Directory = Plugin** — each plugin lives in its own `plugins/{name}/` directory
- **3-state lifecycle** — available → installed → enabled (see below)
- **2-layer management** — `rill plugin` (shell, mechanical) + `/plugin` (Claude Code, interactive)
- **plugin.md = human-readable docs, directory structure = manifest** — no AI parser needed
- **Capability-based** — plugins are defined by a combination of capabilities (source / workflow / hooks). Existing source-only plugins are fully backward compatible

## 3-State Plugin Lifecycle

Plugins have three states:

```
available ──install──→ installed ──enable──→ enabled
    ↑                      │                    │
    └────uninstall─────────┘                    │
                           ↑                    │
                           └────disable─────────┘
```

| State | Meaning | Detection |
|-------|---------|-----------|
| **available** | Plugin directory exists but user has not installed it | `plugins/{name}/` exists AND not in `.installed` |
| **installed** | User has installed it; may be setting up dependencies | Listed in `.installed` AND not in `.enabled` |
| **enabled** | Dependencies resolved; `/sync`, hooks, and skills are active | Listed in `.enabled` |

State files:
- `plugins/.installed` — one plugin name per line (git-tracked)
- `plugins/.enabled` — one plugin name per line (git-tracked)
- `rill update` does **not** overwrite these files (preserves user choices)

### Dependency Checking: `requires.sh`

Plugins declare dependencies via a `requires.sh` script that uses helpers from `_lib.sh`:

```bash
#!/usr/bin/env bash
source "$(cd "$(dirname "$0")/.." && pwd)/_lib.sh"

require_command gog "brew install steipete/tap/gogcli"
require_dir "~/Library/..." "mkdir -p ..."
require_auth "Google OAuth" "Run: gog auth add <email> --services drive"
requires_check
```

- `rill plugin install` runs `requires.sh` for **informational diagnostics** (does not block install)
- `rill plugin enable` runs `requires.sh` as a **gate** (blocks enable on failure)
- `adapter.sh` retains its own runtime checks as a final safety net (defense in depth)

## Directory Structure

```
plugins/
├── README.md           # This file
├── _lib.sh             # Shared library
├── _default-distill.md # Default distill prompt
├── .gitignore          # Ignores .synced, .config
├── .installed          # Installed plugin list (user state, git-tracked)
├── .enabled            # Enabled plugin list (user state, git-tracked)
├── {plugin-name}/      # Bundled plugin — for source plugins
│   ├── plugin.md       # Documentation (overview, setup instructions, usage)
│   ├── adapter.sh      # Transport script (executed by rill sync)
│   ├── requires.sh     # Dependency check script (optional)
│   ├── distill.md      # Source-specific distill prompt (optional)
│   ├── commands/       # Claude Code skill originals
│   │   └── *.md        # Symlinked to .claude/commands/ on enable
│   └── .gitignore      # Excludes .synced
├── {plugin-name}/      # Bundled plugin — for workflow + hooks plugins
│   ├── plugin.md       # Capabilities declaration (data-dir, search-scope, hooks)
│   ├── requires.sh     # Dependency check script (optional)
│   ├── commands/       # workflow capability: skill originals
│   ├── hooks/          # hooks capability: core skill extension prompts
│   ├── data/           # workflow capability: plugin-specific data
│   └── .gitignore
└── local/              # Optional — vault-private plugins (see "Local Track" below)
    └── {plugin-name}/
        ├── plugin.md
        ├── ui/         # ui capability: React component entry
        └── ...
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

Manages synced keys in `plugins/.state/{plugin_name}.synced` (centralized state directory).
Legacy path (`PLUGIN_DIR/.synced`) is auto-migrated on first access.

### Dependency Helpers (for requires.sh)

```bash
require_command <cmd> <install-hint>     # Check command exists on PATH
require_dir <path> <create-hint>          # Check directory exists
require_auth <description> <setup-hint>   # Display auth check (informational)
requires_check                            # Finalize: exit 0 if all met, 1 if any failed
```

## CLI Commands

```bash
rill plugin list              # List plugins with state (bundled + local)
rill plugin list --json       # Machine-readable output (see "Local Track" below)
rill plugin install <name>    # Install + dependency diagnostics
rill plugin enable <name>     # Enable (requires check → symlink commands)
rill plugin disable <name>    # Disable (remove symlinks, keep installed)
rill plugin uninstall <name>  # Full removal (disable + uninstall)
rill plugin status [name]     # Detailed status
rill plugin status <name> --json  # Machine-readable status for one plugin

rill sync                     # List enabled adapters
rill sync <name>              # Execute adapter.sh (no enable check for explicit calls)
```

## Creating a New Plugin

1. Create a `plugins/{name}/` directory
2. Write documentation in `plugin.md`
3. Implement transport logic in `adapter.sh` (source `_lib.sh`)
4. Add dependency checks in `requires.sh` (optional)
5. Place Claude Code skills in `commands/*.md` if needed
6. Add `.synced` to `.gitignore`
7. Test: `rill plugin install {name} && rill plugin enable {name}`

## Capability Model (D38)

Plugins are defined by a combination of capabilities.

| Capability | What it provides | Example |
|-----------|-----------------|---------|
| source | adapter.sh, distill.md, inbox-dir | google-meet |
| workflow | commands/, data/ | CRM |
| hooks | post-distill, briefing, etc. | CRM |
| ui | Rill GUI sidebar entry + scope-bound filesystem access | english-practice |

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

# Plugin with ui capability (GUI extension)
---
ui:                                # ui capability
  sidebar:
    label: "English Practice"
    icon: GraduationCap            # lucide-react icon name
    order: 50                      # sort order within Plugins section
  route: english-practice          # internal route id (kebab-case)
  entry: ui/EnglishPracticeView.tsx  # relative path to React component (default export)
scope:                             # ui capability: filesystem scope (required alongside ui)
  rw:                              # read/write allowlist (vault-relative paths)
    - english-practice
  read:                            # read-only allowlist (optional)
    - knowledge/people
---
```

The `ui` capability declares a GUI sidebar entry whose React component is loaded
by the Rill GUI's Vite-based plugin loader. Declared `scope.rw` / `scope.read`
paths bound the filesystem access exposed to the plugin through
`window.rill.plugin.fs.*`. Writes to Rill-managed directories (`knowledge/`,
`inbox/`, `tasks/`, `workspace/`) are rejected by the loader even if declared.
See Rill's internal GUI extension ADR (rill-dev) for the full mechanism.

### Hook Execution Specification

- Control stays with the core: after /distill completes all phases, it reads `plugins/.enabled` and runs hooks from enabled plugins that have a `hooks` field as sub-agents
- Failures are non-fatal: hook execution errors are logged and processing continues (does not affect core processing results)
- Backward compatible: existing source-only plugins have no hooks field and are unaffected

## Local Track (vault-private plugins)

Plugins ship on one of two **tracks**:

| Track | Location | Distribution | Typical use |
|-------|----------|--------------|-------------|
| **bundled** | `plugins/{name}/` | Distributed to every vault via `rill update` | Public plugins: google-meet, twitter, etc. |
| **local** | `plugins/local/{name}/` | Never distributed — owned by the vault directly | Vault-private plugins the user authors for themselves |

### Properties of the local track

- `plugins/local/` is **excluded from `rill update`**: files inside it are never
  created, overwritten, or removed by `rill update`. Vault owners manage the
  contents directly.
- Each local plugin is a regular plugin directory — same `plugin.md` + `ui/` +
  `commands/` + `adapter.sh` layout as bundled plugins, same capability model.
  Anything expressible in a bundled plugin is expressible in a local plugin.
- The CLI treats bundled and local plugins as a single flat namespace keyed by
  plugin name. `.installed` and `.enabled` store plain names (no `local/`
  prefix); track is inferred from where the plugin directory is found.

### Name conflicts

If the same name exists in both tracks (e.g. `plugins/google-meet/` and
`plugins/local/google-meet/`), the CLI **prefers the local copy** and emits a
one-line warning to stderr on every invocation of `rill plugin list`, `status`,
`install`, `enable`, `disable`, and `uninstall`. This lets a vault owner shadow
a bundled plugin with a locally modified version while staying aware of the
override.

`rill plugin list --json` reports any such overlap in the top-level
`conflicts: []` array (see JSON output section below).

### Version-control recommendations

- **Private vaults**: committing `plugins/local/*` is fine — the plugin stays
  with your vault and is not exposed elsewhere.
- **Public vaults (OSS, demo)**: add `plugins/local/` to the vault's
  `.gitignore` so individual contributors' private plugins do not leak through
  the public repository.

### JSON output for tool integration

Two commands emit machine-readable output for GUI / editor integrations that
want to inspect plugin state without parsing human-facing text:

```bash
rill plugin list --json
# → { "available": [...], "installed": [...], "enabled": [...], "conflicts": [...] }

rill plugin status <name> --json
# → { "name", "state", "track", "capabilities": { source, workflow, hooks, ui },
#     "requires": { "status": "met" | "unmet" | "none" },
#     "ui":    { sidebar: {...}, route, entry } | null,
#     "scope": { rw: [...], read: [...] }         | null }
```

Names in `list --json` are track-less plain strings; use `status --json` to
discover which track a given plugin lives on. The output is built with `printf`
alone (no `jq` / `yq` dependency).

## 3-Tier Classification

| Tier | Examples | Location |
|------|---------|----------|
| Tier 1: Core | `/distill`, `/ask`, `/plugin`, `/sync` | Directly in `.claude/commands/` |
| Tier 2: Built-in | `/focus`, `/close` | Directly in `.claude/commands/` |
| Tier 3: External | `/sync-meetings` | `plugins/*/commands/` via symlink |
