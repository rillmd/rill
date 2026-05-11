---
name: briefing
description: Generate today's Daily Note (or one for a specified date) at reports/daily/YYYY-MM-DD.md by aggregating the day's situation across journals, tasks, workspaces, knowledge, activity-log, and any plugin briefing hooks. Fully automated, no interaction. Use when the user asks for a daily briefing, situational analysis, or "what's going on today/yesterday".
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

**Conduct ALL conversation with the user in the language defined by `.claude/rules/personal-language.md`** (or the user's input language if absent). The English instructions below are for skill clarity, not for output style. Exceptions: code blocks, slash commands, technical terms (Markdown, frontmatter, etc.).

> **Tool references in this skill** (`Bash`, `Grep`, `Read`, `Edit`, `Glob`, `sub-agent`) describe **intent**, not Claude-specific tool calls. Each harness should map them to its native equivalent — Claude Code uses its built-in tools as named; Codex CLI uses `apply_patch` / shell / its own sub-agent mechanism etc. as appropriate.

Generates a Daily Note that aggregates the day's situation. Uses internal data only, fully automated (no interaction). Aims for prose-quality readable reports.

The skill operates in two modes:

- **new mode** — `knowledge/self/current-state.md` is present (the Dream-system Phase 1 migration is live). Read the self/ snapshot as the primary input and emit a thin 4-section Daily Note (~1500 chars target). See 007 design doc in `workspace/2026-05-07-dream-system-rill-application/007-briefing-derivation-redesign.md`
- **legacy mode** — `knowledge/self/current-state.md` is **not** present. Fall back to the original 6-section behavior (Yesterday's Activity / Today's Focus / Pages with pending updates / Situation Analysis / Notes / Related). This branch keeps PUBLIC vaults compatible during the migration window

The mode is decided at the start of Phase 1 by attempting to Read `knowledge/self/current-state.md`. If the Read succeeds, run new mode; otherwise run legacy mode. After the Phase 1 fallback removal commit (see migration plan), legacy mode and this decision will be removed.

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

Execute the following in a shell and capture the YAML output:

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

The content collection is split by mode.

**Both modes** collect (execute in parallel):

1. **Task collection** (from ticket files)
   - Use Grep for fast filtering of target tickets:
     `Grep(pattern="^status: (open|waiting)", path="tasks/", glob="**/_task.md", output_mode="files_with_matches")`
   - Read only matched files (skip done, draft, cancelled, someday)
   - Also reference Step A's `task_tickets` statistics (counts, due_soon list) as supplementary data
   - Collect from each ticket: title (h1), status, due, mentions (projects/{id}), background (body opening), request
2. **activity-log.md** — Get entries within the activity window
3. **reports/newsletter/** — Check if today's newsletter exists (for linking)
4. **Previous briefing** — Read the most recent `reports/daily/` file (excluding today's). Skip if none exists

**Legacy mode only** also collects (these are subsumed by `self/current-state.md` in new mode):

5. **Step A's journals_in_window** — Read each file (prefer `_organized/` version if same-named file exists)
6. **Step A's knowledge_created_in_window** — Read up to 10 files (grasp overview via title and type)
7. **reports/** — Reference reports within the activity window (newsletters, etc.) and incorporate their content into briefing analysis (ADR-061)
8. **Past 2 weeks journal overview** — Get filename list from inbox/journal/ for the past 2 weeks. For understanding theme repetition and frequency trends. Read only what the AI judges necessary
9. **Pages with pending updates** — Read `pages/.pending`. Skip comment lines (`^#`) and empty lines. Parse TAB-separated columns: `page_id`, `source_path`, `detected_at`, `origin_skill`. Group by `page_id` and count entries. For each `page_id`, read `pages/{id}.md` frontmatter to resolve `name` and most recent `detected_at`. Skip groups whose `source_path` appears in that page's `frontmatter.sources`
10. **Workspace details** — Use Step A's active_details. To detect additional active workspaces:
    `Grep(pattern="^status: active", path="workspace/", glob="**/_workspace.md", output_mode="files_with_matches")`
    Read only matched workspaces' `_workspace.md`
    - Completion candidates: All checklist items checked + related ADR exists in docs/decisions/
    - Long-term active warning: No updates for 7+ days (determinable from Step A's days_old / last_modified)

#### Step C (NEW, new mode only): Read self/ Snapshot

When new mode is active, read the following self/ files. **Skip a file silently if it is not present** — the migration plan keeps `decisions.md` etc. as Phase 2 deliverables, so they may be empty skeletons or absent during Phase 1.

1. `knowledge/self/current-state.md` — pulse snapshot (high-velocity, updated by `/pulse`). This file's existence is what triggered new mode
2. `knowledge/self/direction.md` — cross-project meta-direction (medium-velocity, monthly)
3. `knowledge/self/interests.md` — Deep Interests / Curiosity / Obligations / Career (medium-velocity, monthly)
4. `knowledge/self/decisions.md` — curated decision digest (3-month window, updated by `/retrospective`). **If absent or empty**, treat the "直近意思決定" section in Phase 2 as empty/skipped

These files are the **primary input** for Phase 2 generation in new mode:
- "Snapshot" section is rendered from `self/current-state.md` (compressed to 5 lines)
- "Today's Focus" filters from `self/current-state.md` "判断ゲート" + "進行中タスク (急ぎ)" plus the Step B task collection
- Analytical work (contradictions, longitudinal observations) is **not** regenerated here — it lives in `self/observations.md` and the `/retrospective` skill instead

### Phase 1.5: Plugin Hook Data Collection

Collect data from plugin briefing hooks. (Runs in both modes.)

1. Read `plugins/.enabled` to get the list of enabled plugins. If the file does not exist or is empty, skip this phase
2. For each enabled plugin name, Read `plugins/{name}/plugin.md` frontmatter. Identify plugins with `hooks.briefing` field
3. If no matching plugins, skip (no message needed)
4. For each matching plugin:
   - Read the hook prompt file (`plugins/{plugin-name}/{hooks.briefing path}`)
   - Execute via a sub-agent (general-purpose). Pass the following context:
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

#### Template — new mode (4 sections, target ~1500 chars)

```markdown
# YYYY-MM-DD Daily Briefing

## Snapshot

(Render from `self/current-state.md` "今の方向性" + "判断ゲート" + "進行中タスク (急ぎ)". Compress to **5 lines or fewer**. Also read `self/direction.md` to tighten priority ordering. Prose-style, dense.)

## Yesterday's Activity (短)

(Activity-window facts in **3 lines or fewer**, prose. One line each for: journal count, /distill output count, closed workspaces, newsletter link. Detail lives in `self/decisions.md` / activity-log.md — compress aggressively here.)

## Today's Focus

(Show **P0 and P1 only**. P2 and below are reachable via `self/current-state.md`'s 進行中タスク section — do not duplicate. Put 判断ゲート first.)

- **判断ゲート**: [WS name](../../workspace/{id}/_workspace.md) — what is being asked
- **P0**: [Task](../../tasks/{slug}/_task.md) — due / scheduled (one-line context from background)
- **P1**: [Task](../../tasks/{slug}/_task.md) — one-line comment

P0/P1 selection rules (007 §3):
- **P0** = `due` is today/overdue, OR `scheduled` is today, OR appears in self/current-state.md "判断ゲート"
- **P1** = `due` within 7 days + `status: open`, OR a stale active WS in self/current-state.md "進行中の WS" (last update 3+ days ago), OR a recent decision in self/decisions.md (past 7 days) with unfinalized follow-up
- **P2 and below** = `due` 14+ days out, `status: waiting`, monthly/weekly routines → omit entirely from briefing

## Notes

(Bulleted prose, **5 items maximum**. Include:
- **Today's recommended action** — Two nudge cases, both must read as a request the user makes to Claude, never as a terminal command. **Never output `rill log`, `rill clip`, or any `rill *` CLI command in the Notes section.**
  1. **Journal capture nudge** (trigger: `journal-count` from frontmatter is 0, OR the past 3+ days have had journal-count=0): warm, brief nudge in `DETECTED_LANG` inviting the user to start capturing. Examples: *"When you're ready to capture a thought, click 'New Entry' in the Rill app, or open a Claude Code session in your vault and just tell me what's on your mind — I'll handle the rest. No commands needed."*
  2. **Inbox processing nudge** (trigger: any `inbox.*.unprocessed` count is non-zero): prose nudge stating counts per subdirectory and inviting the user to ask Claude to pull in the new entries. If this nudge has been appearing for several days in a row, suggest "you can also ask Claude to set this up as a daily automation."
- Tasks with deadlines in the next 7 days that haven't yet shown up as P0/P1 (at most 2)
- Other one-line observations
)

(※ Insert Plugin Hook sections collected in Phase 1.5 here, each as-is `## Section Name`.)
```

#### Template — legacy mode (6 sections, original behavior)

Writing rules for each section in legacy mode:
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
- **Today's recommended action** — Two nudge cases, both must read as a request the user makes to Claude, never as a terminal command. **Never output `rill log`, `rill clip`, or any `rill *` CLI command in the Notes section.**
  1. **Journal capture nudge** (trigger: `journal-count` from frontmatter is 0, OR the past 3+ days have had journal-count=0): Write a warm, brief nudge in `DETECTED_LANG` inviting the user to start capturing — e.g. *"When you're ready to capture a thought, click 'New Entry' in the Rill app, or open a Claude Code session in your vault and just tell me what's on your mind — I'll handle the rest. No commands needed."* Do not suggest a specific number of entries (e.g., "create 3 journals").
  2. **Inbox processing nudge** (trigger: any `inbox.*.unprocessed` count is non-zero): Write a prose nudge stating the counts per subdirectory and inviting the user to **ask Claude to pull in the new entries and extract knowledge from them** (Claude will route this to `/sync` and `/distill` internally — do not quote the slash commands as a user instruction). If this nudge has been appearing for several days in a row, suggest "you can also ask Claude to set this up as a daily automation."
  Both nudges may appear together if both conditions apply. If neither applies, omit this item.
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

Tasks from ticket files are written in rich display format (applies to both modes).

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
- The mode decision is made by attempting to Read `knowledge/self/current-state.md`. Do not heuristically guess. If new mode files are partially present (e.g. current-state.md exists but decisions.md is absent), still run new mode and treat the missing files as empty sections
