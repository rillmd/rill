# /sync-twitter — Sync Tweet URLs

Automatically import tweet URLs shared from iPhone (via iCloud Drive) into inbox/tweets/.

## Arguments

$ARGUMENTS — none

## Steps

### 1. Check the iCloud Drive folder

1. Use Bash to verify that the following path exists:
   ```
   "$HOME/Library/Mobile Documents/com~apple~CloudDocs/Rill/tweet-urls/"
   ```
2. If it does not exist, point the user to the setup instructions in `plugins/twitter/plugin.md` and exit

### 2. Check for unsynced files

1. Use Bash to list `*.txt` files inside the iCloud Drive folder
2. Read `plugins/twitter/.synced` to exclude files that have already been synced (treat as an empty list if the file does not exist)
3. If there are no unsynced files, report "Everything is already synced" and exit
4. Display the list of unsynced files (filename + URL preview)

### 3. Run the sync

1. Run `rill sync twitter` via Bash
2. Check the result:
   - Success: report the number of imported tweets
   - Failure: analyze the error and propose how to address it

### 4. Suggest follow-up

1. Report the number of imported tweets
2. Suggest chaining into `/distill`:
   - "Imported N tweets into inbox/tweets/. Run /distill to organize and extract knowledge?"

## Rules

- Delegate the mechanical sync to `rill sync twitter`
- Value Claude adds: folder check, URL preview, result reporting, /distill chain suggestion
- Tweets are saved to inbox/tweets/, so they are processed in /distill Phase 2
