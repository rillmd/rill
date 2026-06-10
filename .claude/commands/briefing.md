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

**Conduct ALL conversation with the user in the language defined by `.claude/rules/personal-language.md`** (or the user's input language if absent). The English instructions below are for skill clarity, not for output style. Exceptions (only): tokens inside backticks or code blocks, proper nouns, ASCII acronyms.

Generates a Daily Note that aggregates the day's situation by reading the `knowledge/self/` snapshot (current-state.md, direction.md, interests.md, decisions.md) as the primary input and emitting a thin 4-section Daily Note (~1500 chars target). Uses internal data only, fully automated (no interaction). Aims for prose-quality readable reports. See 007 design doc in `workspace/2026-05-07-dream-system-rill-application/007-briefing-derivation-redesign.md`.

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
2. **activity-log.md** — Get entries within the activity window
3. **reports/newsletter/** — Check if today's newsletter exists (for linking)
4. **Previous briefing** — Read the most recent `reports/daily/` file (excluding today's). Skip if none exists

Detailed scans (journals, knowledge/notes/, past reports, past 2 weeks journal, pages/.pending, full workspace details) that were collected by the pre-migration briefing are now subsumed by `self/current-state.md` — do not duplicate them here.

#### Step C.0: /pulse on-demand pre-check

Before reading `knowledge/self/current-state.md` in Step C, check freshness so the briefing always reads a snapshot that is at most 5 minutes old (009 §1.4 — briefing-on-demand bypasses /pulse's 12h cooldown):

```
read .claude/state/pulse.json
if (now - last_pulse_at) > 5 min OR file missing:
  invoke /pulse with --force flag  # via the harness's Skill invocation primitive
# else: current-state.md is fresh enough, skip /pulse invocation
```

The invocation is synchronous (the harness's Skill tool blocks until /pulse returns). After /pulse completes, proceed to Step C. /pulse handles its own non-recursion contract (it never invokes /briefing back).

#### Step C: Read self/ Snapshot

Read the following self/ files. **Skip a file silently if it is not present** — `decisions.md` is a Phase 2 deliverable populated by `/retrospective`, so it may be empty or absent.

1. `knowledge/self/current-state.md` — pulse snapshot (high-velocity, updated by `/pulse`)
2. `knowledge/self/direction.md` — cross-project meta-direction (medium-velocity, monthly)
3. `knowledge/self/interests.md` — Deep Interests / Curiosity / Obligations / Career (medium-velocity, monthly)
4. `knowledge/self/decisions.md` — curated decision digest (3-month window, updated by `/retrospective`). **If absent or empty**, treat the "直近意思決定" section in Phase 2 as empty/skipped

These files are the **primary input** for Phase 2 generation:
- "Snapshot" section is rendered from `self/current-state.md` (compressed to 5 lines)
- "Today's Focus" filters from `self/current-state.md` "判断ゲート" + "進行中タスク (急ぎ)" plus the Step B task collection
- Analytical work (contradictions, longitudinal observations) is **not** regenerated here — it lives in `self/observations.md` and the `/retrospective` skill instead

#### Step C.5: Stale Workspaces detection

After Step C completes, run a separate scan for stale active workspaces and surface the count in the Notes section (015 §3.2):

```
Grep(pattern="^status: active", path="workspace/", glob="**/_workspace.md", output_mode="files_with_matches")
for each hit:
  read frontmatter, get updated (or created)
  if (now - updated) > 7 days: stale_count++

if stale_count >= 3:
  notes_extra_line = "⚠ 7 日以上停滞: {stale_count} 件 (詳細は次回 /retrospective)"
```

The check is cheap (1 Grep + frontmatter Reads of ~30 files). In Phase 2 the resulting line is appended to the Notes section (after the recommended-action nudges). If `stale_count < 3`, omit the line silently.

#### Step E: /retrospective Thursday nudge (artifact 012 §0.4 + 015 §3.1)

After Step C.5, evaluate whether to surface a `/retrospective weekly` nudge at the top of Phase 2. The logic mirrors 012 §1.2 / 015 §3.1. **All date inputs are derived from the briefing's `target_date` (Phase 0), not the wall clock**, so backfilled or re-run briefings produce the nudge correct for that date and do not mutate `retrospective.json` for an unrelated current week.

```
read .claude/state/retrospective.json (if missing, treat as { last_period: null, skipped_periods: [], nudge_state: {} })
direct_completed_week = the ISO week before the one containing target_date (Mon..Sun)
period_id = "weekly-{Monday-of-direct_completed_week as YYYY-MM-DD}"

# Lazy-init nudge state for this period_id if the key is absent (first run for this week)
if period_id not in retrospective.json.nudge_state:
    retrospective.json.nudge_state[period_id] = { "nudge_count": 0, "last_nudge_at": null }

state = retrospective.json.nudge_state[period_id]
last_nudge_date = (state.last_nudge_at && date_only_of(state.last_nudge_at)) or null
same_day_rerun = (last_nudge_date == target_date)   # do not consume strikes on same-day briefing reruns

if retrospective.json.last_period == period_id:
    nudge = OFF                      # already ran for this period
elif period_id in retrospective.json.skipped_periods:
    nudge = OFF                      # 3-strike skip already recorded
elif target_date is Thursday:
    nudge = ON
    if not same_day_rerun:
        state.nudge_count += 1
        state.last_nudge_at = target_date_with_time
elif target_date is Friday/Saturday/Sunday:
    nudge = DELAYED                  # still surface, marked "delayed"
    if not same_day_rerun:
        state.nudge_count += 1
        state.last_nudge_at = target_date_with_time
else:                                # Mon/Tue/Wed
    nudge = OFF

# 3-strike auto-skip on Sunday — dedup the append since a same-day rerun would
# otherwise re-add an already-skipped period_id every time briefing runs that Sunday
if retrospective.json.nudge_state[period_id].nudge_count >= 3 and target_date is Sunday:
    if period_id not in retrospective.json.skipped_periods:
        retrospective.json.skipped_periods.append(period_id)
    nudge = OFF

# Persist updated retrospective.json (skip persistence in --dry-run mode or when target_date != today, since dated-backfill briefings should be read-only against state). Use **merge-write semantics**: read the existing JSON, update ONLY nudge_state[period_id] and (when applicable) skipped_periods, then write back. Never touch last_run_at / last_period / pending_finalize / run_count — those four fields are owned by the /retrospective skill, and replacing the whole file would clobber them.
```

If `nudge == ON or DELAYED`, prepend a single-line nudge to the Phase 2 output (above the Snapshot section). The nudge text follows `DETECTED_LANG`; one-line, prose tone, ending with the literal command name (do not include `rill` CLI commands per the Notes-section convention; `/retrospective weekly` is a slash command, not a shell command, so it is allowed).

State file path: `.claude/state/retrospective.json`. The file is initialized lazily; the first weekly run of `/retrospective` writes it. If the file does not exist, treat all fields as empty/null and do not error.

**Failure modes**:

- `.claude/state/retrospective.json` parse error → log a one-line warning, treat as missing, do not surface a nudge
- Today is not in a valid weekday → skip silently (defensive; date library bugs)

The check is cheap (one stat + one short JSON parse + date arithmetic). Does not require external skill invocation; if you do detect `nudge_count` mutation, write the updated state back to disk before exiting Phase 1.

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

Write the report body in the language defined by `.claude/rules/personal-language.md` (English when absent), with the same exceptions as the conversation rule above. When a term has no established translation in the target language, prefer a loanword in common use; otherwise keep the English term inside backticks with a short parenthetical gloss — never invent literal calques that do not exist in the target language.

#### File Creation

First create the file with `rill mkfile` (to ensure timestamp accuracy):

```bash
rill mkfile reports/daily --type daily-note --field "journal-count=N"
# For specific date: rill mkfile reports/daily --date YYYY-MM-DD --type daily-note --field "journal-count=N"
```

Then use Edit to append the body to the output path (frontmatter is already generated by `rill mkfile`).

#### Template (4 sections, target ~1500 chars)

```markdown
# YYYY-MM-DD Daily Briefing

(If Step E set `nudge == ON or DELAYED`, prepend ONE prose line above `## Snapshot` — no heading, no list bullet. Tone: warm, conversational, ending with the literal command `/retrospective weekly`. Marker word "delayed" or equivalent in `DETECTED_LANG` if nudge state is DELAYED. Example English shape: *"Last week's retrospective is still pending — want to record it before this week's session limit resets? /retrospective weekly"*. Omit this line entirely if `nudge == OFF`.)

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

**Dependency-aware filtering (ADR-080 D80-6, depends-on/blocks recognition)**:

A task that would otherwise qualify as P0 or P1 but is **blocked** by an unmet `depends-on` is demoted:

- A task is **blocked** if its frontmatter `depends-on: [tasks/foo, tasks/bar]` lists at least one entry whose target task has `status` other than `done` / `cancelled`. Broken `depends-on` links (target task file missing) also count as blocked
- Blocked P0 candidates → demote to a `## Notes` line: `Blocked: [{title}](../../tasks/{slug}/_task.md) — waiting on [{dep-title}](../../tasks/{dep-slug}/_task.md)` (max 2 such lines in Notes; older P0 first)
- Blocked P1 candidates → omit silently (they live in `/project {slug} review`)
- Unblocked tasks pass through the P0/P1 rules unchanged

The check is cheap: for each candidate task, Read its frontmatter `depends-on`, then Read each referenced task's frontmatter `status`. Reuse the same check that `/refresh-project` performs — both skills implement the same canonical algorithm defined in the `/project` SKILL.md "Dependency Resolution Algorithm" section. If a task has no `depends-on` field at all, it is unblocked by default (the common case).

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
- If some self/ files are partially present (e.g. current-state.md exists but decisions.md is absent), proceed and treat the missing files as empty sections
