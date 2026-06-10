# /sync — Bulk External Source Sync

**Conduct ALL conversation with the user in the language defined by `.claude/rules/personal-language.md`** (or the user's input language if absent). The English instructions below are for skill clarity, not for output style. Exceptions (only): tokens inside backticks or code blocks, proper nouns, ASCII acronyms.

Run all plugins sequentially to bulk-sync external sources.

## Arguments

$ARGUMENTS — plugin name (omit: run all plugins sequentially)

## Procedure

### When no argument is given (run all plugins at once)

1. Read `plugins/.enabled` to get the list of enabled plugins. If the file does not exist or is empty, report "No plugins enabled. Run 'rill plugin install <name>' and 'rill plugin enable <name>' to set up plugins." and exit
2. For each enabled plugin name, resolve its directory (see "Plugin Directory Resolution" below) and Read `plugin.md` frontmatter
3. Run all enabled plugins sequentially (no selection prompt):
   - For each plugin, execute the "Single Plugin Execution" procedure below
   - Report the result for each plugin briefly
4. After all plugins complete, display a summary of total ingested files
5. If new files were ingested, propose chaining to `/distill`:
   - "A total of N files were ingested. Would you like to organize and distill them with /distill?"

### When a plugin name is specified

Run the "Single Plugin Execution" procedure for the specified plugin only.

### Plugin Directory Resolution

A plugin's directory may live under either of:

- `plugins/{name}/` — standard layout (distributed by `rill update`)
- `plugins/local/{name}/` — vault-local plugin (track: local; e.g. UI-only sidebar plugins)

Check both in this order. If neither exists, treat the plugin as missing and report it (do not abort the overall run; continue with the remaining plugins).

### Single Plugin Execution

1. Resolve the plugin directory per "Plugin Directory Resolution". If neither path exists, report "Plugin '{name}' is enabled but not installed" and skip
2. Check whether `{plugin_dir}/commands/` contains a `sync-{name}.md` skill
3. **If the skill exists**: Read its procedure and follow its instructions (AI-powered sync)
4. **If no skill**: Check whether `{plugin_dir}/adapter.sh` exists:
   - **If adapter.sh exists**: Run `rill sync {name}` via Bash. Report newly ingested files on success, or analyze the error and propose remediation on failure
   - **If neither sync skill nor adapter.sh exists**: The plugin is not a sync source (e.g. UI-only, capability provider, or passive distill handler). Skip silently and note it in the summary as "no sync source"

## Rules

- Without an argument, run all plugins automatically (do not make the user choose)
- Delegate mechanical sync execution to `rill sync`
- Value Claude adds: interpreting results, proposing chaining to /distill
- If a plugin-specific sync skill (e.g. `/sync-google-meet`) exists, prefer it
