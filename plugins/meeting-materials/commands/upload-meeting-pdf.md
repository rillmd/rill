# /upload-meeting-pdf — Upload Meeting Materials to Google Drive

Upload a meeting materials PDF to Google Drive.

## Arguments

$ARGUMENTS — Path to the PDF file (relative to the repository root). If omitted, search for HTML/PDF files in recent workspace/ directories and propose candidates.

## Steps

### 1. Identify the file

1. If the argument is a PDF path, use that file
2. If the argument is an HTML path, instruct the user to "Open it in your browser, then Cmd+P → Save as PDF" and confirm the resulting PDF path with AskUserQuestion
3. If the argument is omitted:
   - Use Glob to search for recent HTML files inside `workspace/`
   - Present the candidates and confirm which file to use with AskUserQuestion

### 2. Check / create the Google Drive folder

The folder structure is `{client-name}/Meeting Materials/` (or your locale's equivalent). Determine the client name from context (workspace name, mentions, or by asking the user via AskUserQuestion).

1. Run `gog --json drive search "Meeting Materials" --max 10` via Bash (substitute your folder name if you use a different convention)
2. Look for a "Meeting Materials" folder inside the `{client-name}` folder
3. If the folder does not exist:
   - Run `gog drive mkdir "{client-name}"` to create the client folder (skip if it exists)
   - Run `gog drive mkdir "Meeting Materials" --parent <client-folder-id>` to create the subfolder
4. Record the folder ID

### 3. Upload

1. Run `gog drive upload <pdf-path> --parent <folder-id>` via Bash
2. Display the upload result (filename, Drive link)

### 4. Report

1. Report that the upload completed
2. Display the Drive link

## Rules

- Do not upload anything other than PDF files. For HTML, instruct the user to convert to PDF
- Google Drive folder structure is per-client: `{client-name}/Meeting Materials/`
- Recommended filename: `YYYY-MM-DD-{counterparty}-{summary}.pdf`
- If the `gog` command is not installed, point the user to the install instructions and exit
