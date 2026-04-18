---
gui:
  label: "/briefing"
  hint: "Generate today's situational analysis report"
  match:
    - "reports/daily/**/*.md"
  arg: none
  order: 60
  mode: auto
---

# /briefing — Daily Note Generation

Generates a Daily Note that aggregates the day's situation. Uses internal data only, fully automated (no interaction). Aims for prose-quality readable reports.

## Arguments

$ARGUMENTS — one of the following:
- `YYYY-MM-DD` (e.g., `2026-03-11`) → Generate Daily Note for the specified date
- Omitted → Generate Daily Note for today

## Procedure

### Phase 0: Initialization

1. If argument is `YYYY-MM-DD`: Use that date as target
2. If argument omitted: Use today's date as target
3. If `reports/daily/YYYY-MM-DD.md` already exists: Overwrite without confirmation (version history is in Git)
4. Run `rill pages-pending-update --gc` to sweep pending entries pointing at deleted pages (silent when nothing to clean; never fails)

### Phase 1: Data Collection

#### Step A: Structured Data Collection (Script)

Execute the following in Bash and capture the YAML output:

```
bash .claude/commands/_lib/briefing-context.sh "$TARGET_DATE" "03:00"
```

Structured data returned by the script:
- `workspaces`: Count by status (active / completed / on_hold) + detailed list of active ones (id, days_old, last_modified, artifacts)
- `inbox`: Unprocessed count per subdirectory
- `journals_in_window`: Journal filenames within the activity window
- `knowledge_created_in_window`: knowledge/notes filenames created within the activity window
- `tag_health`: Top 5 tag counts + list of tags exceeding 50 files
- `task_tickets`: Ticket file statistics (open/waiting/overdue counts + due_soon list + all filenames)
- `activity_window`: "Yesterday" time range (based on day_boundary, default 03:00)

#### Step B: Content Collection (AI)

Collect the following data in parallel:

1. **Task collection** (from ticket files)
   - Use Grep for fast filtering of target tickets:
     `Grep(pattern="^status: (open|waiting)", path="tasks/", glob="**/_task.md", output_mode="files_with_matches")`
   - Read only matched files (skip done, draft, cancelled, someday)
   - Also reference Step A's `task_tickets` statistics (counts, due_soon list) as supplementary data
   - Collect from each ticket: title (h1), status, due, mentions (projects/{id}), background (body opening), request
   - Focus target criteria: `due` within 7 days / `status: waiting` / `projects/{id}` in mentions matches active workspace
   - Detect overdue (`due` < today), long-term waiting (7+ days since created)
2. **Step A's journals_in_window** — Read each file (prefer `_organized/` version if same-named file exists)
3. **Step A's knowledge_created_in_window** — Read up to 10 files (grasp overview via title and type)
4. **activity-log.md** — Get entries within the activity window
5. **reports/newsletter/** — Check if today's newsletter exists (for linking)
6. **reports/** — Reference reports within the activity window (newsletters, etc.) and incorporate their content into briefing analysis (ADR-061)
7. **Previous briefing** — Read the most recent reports/daily/ file
   (Excluding today's; the latest daily note. Skip if none exists)
8. **Past 2 weeks journal overview** — Get filename list from inbox/journal/ for the past 2 weeks.
   For understanding theme repetition and frequency trends.
   Content: Read only what AI judges necessary (no need to read all)
9. **Pages with pending updates** — Read `pages/.pending`. Skip comment lines (`^#`) and empty lines. Parse TAB-separated columns: `page_id`, `source_path`, `detected_at`, `origin_skill`. Group by `page_id` and count entries. For each `page_id`, read `pages/{id}.md` frontmatter to resolve `name` and most recent `detected_at`. Skip groups whose `source_path` appears in that page's `frontmatter.sources` (stale entries — they will be cleaned on the next /page session's implicit ack).

10. **Workspace details** — Use Step A's active_details. To detect additional active workspaces:
     `Grep(pattern="^status: active", path="workspace/", glob="**/_workspace.md", output_mode="files_with_matches")`
   Read only matched workspaces' `_workspace.md`
   - Completion candidates: All checklist items checked + related ADR exists in docs/decisions/
   - Long-term active warning: No updates for 7+ days (determinable from Step A's days_old / last_modified)

### Phase 1.5: Plugin Hook Data Collection

Collect data from plugin briefing hooks.

1. Read `plugins/.enabled` to get the list of enabled plugins. If the file does not exist or is empty, skip this phase
2. For each enabled plugin name, Read `plugins/{name}/plugin.md` frontmatter. Identify plugins with `hooks.briefing` field
3. If no matching plugins, skip (no message needed)
4. For each matching plugin:
   - Read the hook prompt file (`plugins/{plugin-name}/{hooks.briefing path}`)
   - Execute with Agent tool (`subagent_type: general-purpose`). Pass the following context:
     - **Target date**: The date determined in Phase 0
     - **Plugin path**: `plugins/{plugin-name}/`
   - **Failures are non-fatal**: Log and skip errors during hook execution
   - Collect the complete `## Section Name` section (Markdown) returned by the hook
5. Insert collected hook sections in Phase 2

### Phase 2: Daily Note Generation

#### File Creation

First create the file with `rill mkfile` (to ensure timestamp accuracy):

```bash
rill mkfile reports/daily --type daily-note --field "journal-count=N"
# For specific date: rill mkfile reports/daily --date YYYY-MM-DD --type daily-note --field "journal-count=N"
```

Then use Edit to append the body to the output path (frontmatter is already generated by `rill mkfile`).

#### Template

Writing rules for each section:
- **Use prose as the default**. Write with context and recommended actions, not just bullet point lists
- "Today's Focus" collects tasks from ticket files (`tasks/{slug}/_task.md`)
- Sections with no information may be omitted
- Workspace review results are integrated into "Situation Analysis"

```markdown
# YYYY-MM-DD Daily Briefing

## Yesterday's Activity

(Prose summary of what was done yesterday. Organized by project/topic based on
activity-log.md, journals, and knowledge/notes/ creation records.
Write in readable form: "what progressed and what was decided." Include journal count.
**Time boundary**: Only cover the range defined by activity_window. Do not include
items generated by today's /distill etc. Do not include data outside the window.)

## Today's Focus

(Analysis of tasks to work on today. Collect tasks from ticket files,
organize by project/theme, and describe in prose.
Target tasks: due within 7 days / status: waiting / projects/{id} in mentions matches active workspace)

[Prose explaining task group context]

- **[Task title](../../tasks/{slug}/_task.md)** — 1-sentence summary from background. due: YYYY-MM-DD
- **[Task title](../../tasks/{slug}/_task.md)** `waiting` — Explanation of waiting status

(Title: Use the h1 from the ticket. Background: Summarize to 1 sentence from ticket body.
Link: Use relative path `../../tasks/{slug}/_task.md`.
due: Display if frontmatter `due` exists.
status: Display `waiting` in backticks for waiting tickets)

## Pages with pending updates

(Only include this section if Phase 1 Step B #9 yielded at least one page with non-stale pending entries. Omit the entire section otherwise.

List each page ordered by most recent `detected_at` desc. Cap at 8 rows; if more exist, append `_and {N} more_` at the end.

- **[Page name](../../pages/{id}.md)**: {count} new related candidate(s) (most recent: YYYY-MM-DD, origin: distill/close)
  → Run `/page {id}` to review

When count is 1, say "1 new related candidate"; when >1, pluralize.)

## Situation Analysis

(Based on all collected data, candidly analyze what you judge most important.
Not a superficial activity report, but read the relationship between
thoughts/emotions/intentions appearing in journals and actual behavior patterns,
and point out patterns or structural issues the user may not be aware of.

Include tracking of items mentioned in the previous briefing and how they changed.
Include workspace review results (completion candidates, long-term inactive) in this section.

Start from facts, add original analysis beyond mere data summarization.
Neither overly positive nor negative — be candid.
Include specific options/choices as a conclusion to the analysis.

Write a narrative where the reader can grasp the "big picture" and "what to think about next")

## Notes

(Write specific notes in prose:
- **Today's recommended action** — If any `inbox.*.unprocessed` count is non-zero, write a prose nudge that states the counts per subdirectory and invites the user to **ask Claude to pull in the new entries and extract knowledge from them** (Claude will route this to `/sync` and `/distill` internally — do not quote the slash commands as a user instruction). If this nudge has been appearing for several days in a row, suggest "you can also ask Claude to set this up as a daily automation" rather than linking to `docs/guides/scheduling.md` directly. This section is the primary actionable handoff from the morning report to the user and must read as a request the user makes to Claude, never as a terminal command
- Tasks approaching deadlines
- Items left unattended for long periods
- Other observations)

(※ Insert Plugin Hook sections collected in Phase 1.5 here.
Place each hook's `## Section Name` as-is.
If no hook sections, insert nothing)

## Related

- [Newsletter](../newsletter/YYYY-MM-DD.md) (include only if exists)
```

### Post-output

Display a summary (3-5 lines) and finish. Do not transition to assistant mode.

## Task Display Rules

Tasks from ticket files are written in rich display format.

- Title: Use the h1 (`# Title`) from the ticket as-is
- Background: Summarize to 1 sentence from ticket body
- Link: Relative path `../../tasks/{slug}/_task.md`
- due: Display if frontmatter `due` exists
- status: Display in backticks for `waiting`

**Display example**:
```
- **[Submit Q4 expense report](../../tasks/submit-expense-report/_task.md)** — Reimbursement deadline approaching. due: 2026-04-15
- **[Schedule design review with Jane](../../tasks/phoenix-design-review/_task.md)** `waiting` — Awaiting Jane's availability for the proposal review
```

## Rules

- **Never modify inbox/journal/ and inbox/*/ original files** (read-only)
- Each section should be prose-based with context and recommended actions
- If `_organized/` has a same-named file, prefer reading that one
- Create reports/daily/ directory if it doesn't exist
- **When referencing tasks or knowledge files in the body, always use `[display name](../../relative-path)` Markdown links. Backtick-only ID references (e.g., `` `task-xxx` ``) are prohibited**. Same applies in prose sections
