# /sync-voice-memo — Sync Voice Memos

Automatically import iPhone voice memos (via iCloud Drive) into inbox/journal/.

## Arguments

$ARGUMENTS — none

## Steps

### 1. Check the iCloud Drive folder

1. Use Bash to verify that the following path exists:
   ```
   "$HOME/Library/Mobile Documents/com~apple~CloudDocs/Rill/voice-memos/"
   ```
2. If it does not exist, point the user to the setup instructions in `plugins/voice-memo/plugin.md` and exit

### 2. Check for unsynced files

1. Use Bash to list `*.txt` files inside the iCloud Drive folder
2. Read `plugins/voice-memo/.synced` to exclude files that have already been synced (treat as an empty list if the file does not exist)
3. If there are no unsynced files, report "Everything is already synced" and exit
4. Display the list of unsynced files (filename + preview of the first few lines)

### 3. Run the sync

1. Run `rill sync voice-memo` via Bash
2. Check the result:
   - Success: report the number of imported files
   - Failure: analyze the error and propose how to address it

### 4. Suggest follow-up

1. Report the number of imported files
2. Suggest chaining into `/distill`:
   - "Imported N voice memos into inbox/journal/. Run /distill to distill them?"

## Rules

- Delegate the mechanical sync to `rill sync voice-memo`
- Value Claude adds: folder check, preview display, result reporting, /distill chain suggestion
- Voice memos are saved to inbox/journal/, so they are processed in /distill Phase 1
