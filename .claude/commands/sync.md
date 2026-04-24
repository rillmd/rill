# /sync — Bulk External Source Sync

**Conduct ALL conversation with the user in the language defined by `.claude/rules/personal-language.md`** (or the user's input language if absent). The English instructions below are for skill clarity, not for output style. Exceptions: code blocks, slash commands, technical terms (Markdown, frontmatter, etc.).

Run all plugins sequentially to bulk-sync external sources.

## Arguments

$ARGUMENTS — plugin name (omit: run all plugins sequentially)

## Procedure

### When no argument is given (run all plugins at once)

1. Read `plugins/.enabled` to get the list of enabled plugins. If the file does not exist or is empty, report "No plugins enabled. Run 'rill plugin install <name>' and 'rill plugin enable <name>' to set up plugins." and exit
2. For each enabled plugin name, Read `plugins/{name}/plugin.md` frontmatter
3. Run all enabled plugins sequentially (no selection prompt):
   - For each plugin, execute the "Single Plugin Execution" procedure below
   - Report the result for each plugin briefly
4. After all plugins complete, display a summary of total ingested files
5. If new files were ingested, propose chaining to `/distill`:
   - "A total of N files were ingested. Would you like to organize and distill them with /distill?"

### When a plugin name is specified

Run the "Single Plugin Execution" procedure for the specified plugin only.

### Single Plugin Execution

1. Verify that `plugins/{name}/` exists (error if it does not)
2. Check whether `plugins/{name}/commands/` contains a `sync-{name}.md` skill
3. **If the skill exists**: Read its procedure and follow its instructions (AI-powered sync)
4. **If no skill**: Fall back to the following:
   a. Verify the existence of `plugins/{name}/adapter.sh`
   b. Run `rill sync {name}` via Bash
   c. Check the result:
      - Success: Report the number of newly ingested files
      - Failure: Analyze the error and propose remediation

## Rules

- Without an argument, run all plugins automatically (do not make the user choose)
- Delegate mechanical sync execution to `rill sync`
- Value Claude adds: interpreting results, proposing chaining to /distill
- If a plugin-specific sync skill (e.g. `/sync-google-meet`) exists, prefer it
