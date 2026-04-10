# /plugin — Plugin Management

Interactively check status, install, and uninstall plugins. Internally calls `rill plugin` via Bash, with guidance, diagnostics, and suggestions added before and after.

## Arguments

$ARGUMENTS — subcommand (omit: status display, `install <name>`, `uninstall <name>`, `search <keyword>`)

## Steps

### When no arguments (status display)

1. Run `rill plugin status` via Bash
2. Read each plugin's `plugin.md` in `plugins/` to understand the overview
3. Display the status in the following format:

```
## Plugin Status

| Plugin | Status | Commands | Overview |
|---|---|---|---|
| google-meet | ✓ installed | sync-meetings | Import Google Meet meeting notes |

Next actions:
- If there are uninstalled plugins, suggest `/plugin install <name>`
- If there are syncable adapters, suggest `/sync`
```

### When install <name>

1. Verify that `plugins/<name>/` exists
2. Read `plugins/<name>/plugin.md` to understand the overview and prerequisites
3. Verify that prerequisites are met:
   - Check for the existence of external tools (verify with `which`)
   - Check authentication state (verify with tool-specific commands)
4. If anything is missing, guide the user through setup interactively
5. Run `rill plugin install <name>` via Bash
6. Suggest a test run (`rill sync <name>` or the corresponding skill)

### When uninstall <name>

1. Read `plugins/<name>/plugin.md`
2. Explain the scope of impact (which skills will be removed)
3. Confirm with AskUserQuestion
4. Run `rill plugin uninstall <name>` via Bash
5. Explain that data in `inbox/*/` will remain

### When search <keyword>

1. Grep search the `plugin.md` files in `plugins/` by keyword
2. If found, suggest installation
3. If not found, suggest creating a new plugin

## Rules

- Delegate mechanical operations (creating/deleting symlinks) to `rill plugin`
- Value Claude adds: discovery, guidance, diagnostics, next-action suggestions
- A plugin's plugin.md is human-facing documentation. Read it to understand the content and summarize it for the user
