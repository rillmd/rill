# /plugin — Plugin Management

Interactively manage plugins with a 3-state lifecycle: available → installed → enabled. Internally calls `rill plugin` via Bash, with guidance, diagnostics, and suggestions added before and after.

## Arguments

$ARGUMENTS — subcommand (omit: status display, `install <name>`, `enable <name>`, `disable <name>`, `uninstall <name>`, `search <keyword>`)

## Steps

### When no arguments (status display)

1. Run `rill plugin list` via Bash
2. Read each plugin's `plugin.md` in `plugins/` to understand the overview
3. Display the status in the following format:

```
## Plugin Status

| Plugin | State | Commands | Overview |
|---|---|---|---|
| google-meet | ✓ enabled | sync-google-meet | Import Google Meet meeting notes |
| twitter | ● installed | — | Sync tweet URLs from iPhone |
| web-clipper | available | — | Web page clip organizer |

Next actions:
- For available plugins: suggest `/plugin install <name>`
- For installed plugins: suggest `/plugin enable <name>` (or setup guidance if dependencies are missing)
- For enabled plugins with adapters: suggest `/sync`
```

### When install <name>

1. Verify that `plugins/<name>/` exists
2. Run `rill plugin install <name>` via Bash (always succeeds)
3. Read `plugins/<name>/plugin.md` to understand the overview and prerequisites
4. Interpret the dependency check output:
   - If all dependencies met: suggest `rill plugin enable <name>` as next step
   - If dependencies missing: guide the user through setup interactively
5. After setup guidance, suggest running `rill plugin enable <name>`

### When enable <name>

1. Run `rill plugin enable <name>` via Bash
2. If it fails (dependency check failed):
   - Read `plugins/<name>/plugin.md` for setup instructions
   - Guide the user through resolving each missing dependency
   - After resolution, suggest retrying `rill plugin enable <name>`
3. If it succeeds: suggest a test run (`/sync <name>` or the corresponding sync skill)

### When disable <name>

1. Explain the scope: which commands will be unlinked, `/sync` and hooks will skip this plugin
2. Run `rill plugin disable <name>` via Bash
3. Explain that the plugin remains installed and can be re-enabled with `rill plugin enable <name>`

### When uninstall <name>

1. Read `plugins/<name>/plugin.md`
2. Explain the scope of impact (disables if currently enabled, removes from installed list)
3. Confirm with AskUserQuestion
4. Run `rill plugin uninstall <name>` via Bash
5. Explain that data in `inbox/*/` will remain

### When search <keyword>

1. Grep search the `plugin.md` files in `plugins/` by keyword
2. If found, suggest installation
3. If not found, suggest creating a new plugin

## Rules

- Delegate mechanical operations (state files, symlinks) to `rill plugin`
- Value Claude adds: discovery, guidance, diagnostics, next-action suggestions
- A plugin's plugin.md is human-facing documentation. Read it to understand the content and summarize it for the user
- Plugin lifecycle: available → install → (setup) → enable → disable → uninstall
