---
gui:
  label: "/focus"
  hint: "Start a focus session from this file"
  match:
    - "**/*.md"
  arg: path
  order: 10
  mode: live
---

# /focus — Workspace Start / Resume

Starts (or resumes) a workspace from a theme or file. Automatically collects related information and builds a workspace in `workspace/`, then begins an interactive session.

## Arguments

$ARGUMENTS — one of the following:
- Theme text (e.g., `voice input optimization`) → Start a new workspace
- Journal file path (e.g., `inbox/journal/2026-02-13-1950.md`) → Start new workspace from that journal
- workspace/ path or id (e.g., `workspace/2026-02-13-rill-development/` or `rill`) → Resume existing workspace
- Omitted → Propose resuming active workspaces if any, otherwise ask for theme

**Not accepted**: task file paths (`tasks/{slug}/_task.md`, or the legacy `tasks/{slug}.md`). ADR-077 retired task-originated /focus. If the user passes a task path, return an error immediately and suggest `/solve {slug}` instead — tasks are executed in place now, not through a workspace (ADR-076).

## Procedure

### Phase 0: Workspace Identification

1. If argument is a `workspace/` path or an existing workspace id:
   - Read the metadata file in that directory (priority: `_workspace.md` > `_session.md` > `_project.md`)
   - `status: active` → Resume workspace → Go to Phase 3
   - `status: completed` → Ask "This workspace is completed. Would you like to reopen it?" via AskUserQuestion. Yes → Set status back to active, go to Phase 3
   - `status: on-hold` → Ask "This workspace is on hold. Would you like to resume it?" via AskUserQuestion
2. If argument is omitted:
   - Scan all directories directly under `workspace/` (exclude `daily`)
   - Search for `_workspace.md` OR `_session.md` OR `_project.md` with `status: active`
   - If active workspaces found, display the list and ask via AskUserQuestion whether to resume or create new
   - If no active workspaces, ask "What would you like to think about?" via AskUserQuestion
3. If argument starts with `tasks/` (either new `tasks/{slug}/_task.md` or legacy `tasks/{slug}.md`):
   - Exit immediately with: "Task-originated /focus was retired by ADR-077. Tasks execute in place now — run `/solve {slug}` to work on this task, which writes artifacts directly under `tasks/{slug}/`. If you want a standalone Deep Think surface, start `/focus <theme>` with a theme (not a task path)."
   - Do not create a workspace, do not Read the task file
4. If argument is text or a journal path:
   - Search for related existing workspaces (match on directory name, tags, _workspace.md body)
   - If related workspace found, ask "An existing workspace exists. Resume or create new?" via AskUserQuestion
   - If creating new → Phase 1

### Phase 1: Context Collection

Automatically collect information related to the theme:

1. **Bulk search**: Extract 2-3 keywords from the theme and run a single cross-cutting Grep:
   ```
   Grep(pattern="{keyword}", glob="{knowledge,inbox,workspace,reports,tasks}/**/*.md",
        output_mode="files_with_matches", head_limit=30)
   ```
   - pages/ is excluded from search targets
   - If results contain both inbox/{type}/ and inbox/{type}/_organized/ with same filename, use only the `_organized/` version
2. **Supplementary search**: Only if bulk search didn't find sufficient related files, run additional Grep on individual directories
3. Organize collection results for inclusion in Phase 2's `_workspace.md`

### Phase 2: Workspace Construction

1. Create directory:
   - `workspace/{YYYY-MM-DD}-{topic-name}/` (today's date + kebab-case topic name)
2. Generate `_workspace.md`. First get the exact current time:
   ```bash
   date +%Y-%m-%dT%H:%M%z | sed 's/\([0-9][0-9]\)$/:\1/'
   ```
   Use the obtained value for `created`:

```markdown
---
created: {time obtained above}
type: workspace
id: {YYYY-MM-DD}-{topic-name}
name: {Topic title}
status: active
origin: (path of origin journal. Omit for theme-specified starts)
tags: [related-tags]
---

# {Topic Title}

(Theme overview. Why think about this, context)

## Issues to Consider
- [ ] Issue 1
- [ ] Issue 2
- [ ] Issue 3

## Related Files (MOC)
- [Filename](path) — Brief description
- [Filename](path) — Brief description

## Session History
- {YYYY-MM-DD}: Session started. (overview)

## Next Steps
- [ ] First action
```

3. The first deliverable file (`001-{description}.md`) is generated naturally during the conversation (not auto-created at session start)

### Phase 3: Interactive Phase

After session start (or resume), interact with the following flow:

1. Display the metadata file (`_workspace.md` / `_session.md` / `_project.md`) contents to user (overview, issues, next steps)
2. On resume, collect additional context:
   - Read deliverables within the workspace
   - Related information from knowledge/notes/ based on tags
   - Recent relevant entries from inbox/journal/
   - Related reports from reports/ (newsletters, dailies, etc.) (ADR-061)
3. Proceed with interactive deep-dive with user
4. **File-first principle** for deliverables:
   - **Use `rill mkfile` for file creation** (ensures timestamp accuracy):
     ```bash
     rill mkfile workspace/{workspace-id} --slug {description} --type {type}
     ```
     Then use Edit to append body to the output path (frontmatter is pre-generated)
   - type: `progress` | `research` | `analysis` | `decision` | `review`
   - **Write to file** (if any of the following apply):
     - Analysis, research, investigation results
     - Reports, surveys, comparison tables
     - Decisions and their rationale
     - Frameworks, design proposals, recommendations
     - Structured output of 3+ paragraphs
   - **Keep as text output** (don't create a file):
     - Confirmations, questions, short suggestions (1-2 paragraph conversational exchanges)
     - Direction discussions or brainstorming in progress
     - Summary previews before file save (when getting user confirmation)
   - When in doubt, write to file. The workspace's purpose is to leave traces of thinking for knowledge reuse
5. Update `_workspace.md` (or `_session.md`) at each conversation milestone:
   - Add new deliverables to "Related Files (MOC)"
   - Update checkboxes for completed issues
   - Append progress to "Session History"
   - Update "Next Steps"
   - **Do NOT change `status`** — never transition the workspace to `completed` from /focus. See the Rules section below for the completion protocol

## Deliverable File Frontmatter

```yaml
---
created: 2026-02-16T17:30+09:00
topic: {topic-name}
type: research
---
```

## Rules

- **Never transition `status` to `completed` in /focus**. Workspace completion is exclusively performed by `/close`, which runs the mandatory knowledge distillation via sub-agents (ADR-073). Setting `status: completed` from /focus bypasses distillation and silently loses the session's knowledge. If the user signals that the session is done, or you judge the workspace has reached its completion conditions, **propose running `/close`** via AskUserQuestion (e.g., "This workspace looks ready to complete. Shall I hand off to /close to run distillation?") rather than editing the status directly. The only status transitions /focus may perform are the reopen/resume paths already specified in Phase 0 (`completed` → `active` on reopen, `on-hold` → `active` on resume)
- **File-first principle**: Save analytical/report-type output to files. Leave them as workspace files, not Claude Code text output. The workspace's value lies in accumulated deliverables
- **Never modify inbox/journal/ and inbox/*/ original files** (read-only)
- Workspace files use numbered `NNN-description.md` naming
- `_workspace.md` (or `_session.md`) is continuously updated as the session progresses
- Once created, deliverable files are generally not modified (additions/corrections go in new files)
- When active workspaces exist, prioritize proposing resume
- Include frontmatter in all files
- Prefer `_organized/` version when same-named file exists
- **Note metadata correction (ADR-046 D46-7)**: When reading knowledge/notes/ files, handle in two modes:
  **Mode A — Direct fix** (no AI judgment needed, 1-2 Edits per fix, < 100ms):
  1. If frontmatter `tags` contain deprecated tags (tags in taxonomy.md's "Deprecated Tags" table), remove via Edit
  2. If frontmatter `tags` contain entity IDs (values matching filenames in knowledge/{people,orgs,projects}/), remove from `tags` and add to `mentions` in typed format (`{type}/{id}`) (skip if already in mentions. ADR-053)
  **Mode B — Append to .refresh-queue** (no AI judgment, detection only. < 10ms):
  Append file paths matching any of the following to `knowledge/.refresh-queue` (only if not already present):
  - `tags` is empty array `[]`
  - `tags` has only 1 tag and that tag has 50+ uses (generic tag only)
  - `mentions` field does not exist
  - `related` field does not exist
  - `type` is not one of `record` / `insight` / `reference`
  ※ Mode A + Mode B combined have virtually no impact on main task accuracy/speed. Mode B targets are refreshed in the next /distill Phase 0.5
- **Backward compatibility**: Properly read workspaces that only have `_session.md` or `_project.md`. Do not rename during Phase 3 interaction
- **Body link rule**: When referencing files in workspace deliverables or _workspace.md, use `[display name](relative-path)` Markdown links. Backtick-only ID references are prohibited

## Compaction Resilience

Long /focus sessions may trigger automatic context compression (compaction). Handle with:

- **Immediate persistence**: Don't leave analytical output in conversation text — immediately write to workspace files (File-first principle reinforcement)
- **Regular _workspace.md updates**: Update session history and "Next Steps" every 2-3 conversation exchanges
- **Context loss recovery**: If previous conversation content feels vague, re-read `_workspace.md` and latest deliverables before continuing
