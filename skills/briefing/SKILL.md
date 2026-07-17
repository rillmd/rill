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

**Conduct all conversation with the user — and write all generated output — in the language defined by `.claude/rules/personal-language.md`** (or the user's input language if that file is absent). Follow the language rules in full — exceptions and translation quality are defined in the Language Rules of `.claude/rules/rill-core.md` and the vault's `personal-*.md` overrides, never restated per skill. The English instructions below are for skill clarity, not for output style.

> **Tool references in this skill** (`Bash`, `Grep`, `Read`, `Edit`, `Glob`, `sub-agent`) describe **intent**, not Claude-specific tool calls. Each harness should map them to its native equivalent — Claude Code uses its built-in tools as named; Codex CLI uses `apply_patch` / shell / its own sub-agent mechanism etc. as appropriate.

Generates a Daily Note that aggregates the day's situation by reading the `knowledge/self/` snapshot (current-state.md, direction.md, interests.md, decisions.md) as the primary input and emitting a narrowed 6-section Daily Note (~2500 chars target). Uses internal data only, fully automated (no interaction). Aims for prose-quality readable reports.

Design essence (derivation, not aggregation): "where am I" awareness lives in `knowledge/self/` — maintained by `/pulse` and `/distill` — so the briefing only **derives today's actions** from that snapshot instead of rebuilding a full situation analysis from raw files every morning. This keeps the note thin and prevents the one-file-does-six-jobs bloat that the pre-derivation briefing suffered from.

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

Collect the following data in parallel:

1. **Task collection** (from ticket files)
   - Use Grep for fast filtering of target tickets:
     `Grep(pattern="^status: (open|waiting)", path="tasks/", glob="**/_task.md", output_mode="files_with_matches")`
   - Read only matched files (skip done, cancelled, someday)
   - Also reference Step A's `task_tickets` statistics (counts, due_soon list) as supplementary data
   - Collect from each ticket: title (h1), status, due, **scheduled** (v3: scheduled-only tasks such as a dated follow-up qualify for 🟠 Urgent via past `scheduled`, must be extracted), mentions (projects/{id}), background (body opening), request
   - **v3 — draft task collection** (for the 🔵 Draft-candidate slot): additionally grep `Grep(pattern="^status: draft", path="tasks/", glob="**/_task.md", output_mode="files_with_matches")`, sort by `created` descending, **Read the most recent 1 draft task body** (title, frontmatter `created` / `source` / `mentions`, Goal, Background opening) — needed for deterministic 🔵 Draft-candidate card rendering. If 0 drafts, skip the slot
2. **activity-log.md** — **v3**: get entries within the **past 5 days relative to TARGET_DATE** (not wall-clock, so backfilled `/briefing YYYY-MM-DD` runs produce the correct slice). The activity window is anchored as: `[TARGET_DATE - 5 days at day_boundary, TARGET_DATE at day_boundary]`. Three subsets are used: (a) the activity_window subset (TARGET_DATE-1 → TARGET_DATE at day_boundary) feeds v2-style summaries / detection; (b) the **recent 12h subset relative to TARGET_DATE** (TARGET_DATE-12h → TARGET_DATE) feeds the v3 "Today's Flow" section; (c) the full 5-day range feeds the v3 **untouched** axis (a project / workspace / task with no touch in this window qualifies as untouched). Implementation: read the tail of `activity-log.md`; if the file is long, restrict to entries with timestamps within `[TARGET_DATE - 5 days, TARGET_DATE]`
3. **reports/newsletter/** — Check if today's newsletter exists (for linking)
4. **Previous briefing** — Read the most recent `reports/daily/` file (excluding today's). Skip if none exists

Detailed scans (journals, knowledge/notes/, past reports, past 2 weeks journal, pages/.pending, full workspace details) that were collected by the pre-migration briefing are now subsumed by `self/current-state.md` — do not duplicate them here.

#### Step C.0: /pulse on-demand pre-check

Before reading `knowledge/self/current-state.md` in Step C, check freshness so the briefing always reads a snapshot that is at most 5 minutes old (briefing-on-demand bypasses /pulse's 12h cooldown):

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
2. `knowledge/self/direction.md` — cross-project meta-direction (medium-velocity, monthly). **v3**: this is the **primary** signal for the **important** axis for Top filtering — workspaces / tasks mentioned in Active Projects here qualify directly. Items not in Active Projects can still qualify via the **secondary** signal `constraints.md` (Step C #6 below) — both paths are valid, the "ineligible" verdict only fires when neither direction.md nor constraints.md mentions the item
3. `knowledge/self/interests.md` — Deep Interests / Curiosity / Obligations / Career (medium-velocity, monthly)
4. `knowledge/self/decisions.md` — curated decision digest (3-month window, updated by `/retrospective`). **If absent or empty**, treat decision-digest content in Phase 2 as empty/skipped

**v3 additional inputs for narrowing**:

5. `activity-log.md` — read tail entries (recent 12 hours + past 5 days). Used for two purposes: (a) the **"Today's Flow"** section in Phase 2 (recent 12h, prose summary grouped into morning / afternoon / most recent); (b) the **untouched** axis for Top filtering — a workspace / task / project mentioned in `direction.md` Active Projects but with no `activity-log` touch in the past 5 days qualifies as untouched
6. `knowledge/self/constraints.md` — family / financial / health / life-event constraints. Used as a **secondary signal** for the **important** axis when an item is not in `direction.md` Active Projects but is tied to a `constraints.md` constraint (e.g. a tax-filing deadline tied to a financial constraint, a health checkup tied to a health constraint). Skip silently if absent or empty
7. `status: draft` tasks — already collected in Step B #1 (the v3 addendum reads the most recent 1 draft task body in full). Used here only as a cross-reference for the **🔵 Draft-candidate** slot in Phase 2 (cap 1, most recent `created`, sourced from Step B's Read). If 0 matches, the slot is replaced by a second In-Progress entry or omitted entirely — the 5-count is not strict

These files are the **primary input** for Phase 2 generation. v3 narrowing logic:

- The **Main-theme 1-line** is rendered from the `## Current Main Theme` section of `self/direction.md` (compress to 1 line, dense). **Heading lookup contract**: `## Current Main Theme` is the canonical English structural key seeded by `/onboarding`; direction.md headings are lookup keys, not display strings. If the canonical heading is absent (a vault seeded before this convention may carry a localized heading), fall back to the **first `## ` section** of direction.md
- The **"Today's Flow"** 3 lines are rendered from `activity-log.md` recent 12h (group entries by time-of-day or by activity type, prose)
- The **⚠️ Today's Focus** (Top, hierarchical) is filtered by the **3-condition product**:
  1. **important**: mentioned in `direction.md` Active Projects, OR tied to a `constraints.md` constraint (the file actually read in Step C #6)
  2. **untouched**: no `activity-log` touch in past 5 days for that project / workspace / task
  3. **pull**: `due` / `scheduled` / explicit deadline / promise / doctrine
  Tie-break: explicit deadline > scheduled/due > general doctrine; longer delay first. If 0 candidates qualify, fall back to the most active project from `activity-log` past 12h (label as **"★ Today's Focus (in progress)"** instead of "⚠️")
- The **4 parallel cards** are filled in this order: 1× 🟢 In Progress (most active in `activity-log` past 12h) + 1-2× 🟠 Urgent (`due` past / `scheduled` past / `/pulse` Section 6 execution-gap entries) + 0-1× 🔵 Draft candidate (most recent `status: draft` task). **De-duplication rule**: if the Top fell back to "in progress" (i.e. no important × untouched candidate) and the 🟢 parallel slot's most-active leader is the same project, the 🟢 slot picks the **next-most-active** project instead — never spend 2 of 5 slots on the same item
- **Dependency-aware filtering (ADR-080 D80-6, depends-on/blocks recognition)**: a task that would otherwise qualify for Top or a 🟠 Urgent card but is **blocked** by an unmet `depends-on` is demoted. A task is blocked if its frontmatter `depends-on: [tasks/foo, tasks/bar]` lists at least one entry whose target task has `status` other than `done` / `cancelled`; broken `depends-on` links (target task file missing) also count as blocked. Blocked Top candidates → the next candidate takes Top, and the blocked item is listed in the "Narrowed out" section as `Blocked: [{title}](../../tasks/{slug}/_task.md) — waiting on [{dep-title}](../../tasks/{dep-slug}/_task.md)` (max 2 such lines; older candidate first). Blocked 🟠 candidates → omit silently (they live in `/project {slug} review`). A task with no `depends-on` field is unblocked by default (the common case), so the check is cheap: Read each candidate's frontmatter `depends-on`, then each referenced task's `status`. Reuse the same canonical algorithm as `/refresh-project` — both implement the "Dependency Resolution Algorithm" defined in the `/project` SKILL.md
- The **"Narrowed out"** section summarizes counts upfront (do **not** fold via `<details>` — Markdown viewer compatibility) — see Phase 2 Template
- Analytical work (contradictions, longitudinal observations) is **not** regenerated here — it lives in `self/observations.md` and the `/retrospective` skill instead

#### Step C.5: Stale Workspaces detection

After Step C completes, run a separate scan for stale active workspaces and surface the count in the Notes section:

```
Grep(pattern="^status: active", path="workspace/", glob="**/_workspace.md", output_mode="files_with_matches")
for each hit:
  read frontmatter, get updated (or created)
  if (now - updated) > 7 days: stale_count++

if stale_count >= 3:
  notes_extra_line = "⚠ Stalled 7+ days: {stale_count} workspaces (details in the next /retrospective)"
```

The check is cheap (1 Grep + frontmatter Reads of ~30 files). In Phase 2 the resulting line is appended to the Notes section (after the recommended-action nudges). If `stale_count < 3`, omit the line silently.

#### Step E: /retrospective Thursday nudge

After Step C.5, evaluate whether to surface a `/retrospective weekly` nudge at the top of Phase 2 (this is /retrospective's primary habit trigger — see that skill). **All date inputs are derived from the briefing's `target_date` (Phase 0), not the wall clock**, so backfilled or re-run briefings produce the nudge correct for that date and do not mutate `retrospective.json` for an unrelated current week.

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

# Persist updated retrospective.json (skip persistence in --dry-run mode or when target_date != today, since dated-backfill briefings should be read-only against state). Use merge-write semantics: read existing JSON, update only nudge_state[period_id] + (when applicable) skipped_periods; never touch last_run_at / last_period / pending_finalize / run_count — those are owned by the /retrospective skill.
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
   - Execute via a sub-agent (general-purpose). Pass the following context:
     - **Target date**: The date determined in Phase 0
     - **Plugin path**: `plugins/{plugin-name}/`
   - **Failures are non-fatal**: Log and skip errors during hook execution
   - Collect the complete `## Section Name` section (Markdown) returned by the hook
5. Insert collected hook sections in Phase 2

### Phase 2: Daily Note Generation

Write the report body in the language defined by `.claude/rules/personal-language.md` (English when absent). Translation quality follows the Language Rules in `.claude/rules/rill-core.md` and the vault's `personal-*.md` overrides — in particular, never invent literal calques that do not exist in the target language.

#### File Creation

First create the file with `rill mkfile` (to ensure timestamp accuracy):

```bash
rill mkfile reports/daily --type daily-note --field "journal-count=N"
# For specific date: rill mkfile reports/daily --date YYYY-MM-DD --type daily-note --field "journal-count=N"
```

Then use Edit to append the body to the output path (frontmatter is already generated by `rill mkfile`).

#### Template (v3 — 5-item narrowing + Top hierarchy + 4-element schema, target ~2500 chars)

The Phase 2 output is structured as 6 sections after the H1 + main-theme 1-line.

Design essence (v3, canonical here): v2 surfaced every active workspace in parallel (30+ items at scale) and pushed the triage back onto the user. v3 narrows the surface to **5 items** via the important × untouched × pull product, expands **only the Top item** into a hierarchical tree, and renders every card in the fixed **4-element schema** (Stuck / Next step / Resume / Source), so each surfaced item arrives with its stuck-point, one concrete ≤30-min action, a resume command, and its sources. Not-yet-ticketed work enters only through `status: draft` tasks (Review-mode approval), never as free-floating suggestions.

**Composition target** (not strict, fall back when source-set is empty):

| Slot | Count | Source / extraction |
|---|---|---|
| Top (⚠️ important × untouched, or ★ Today's Focus) | 1 | 3-condition product (Step C, v3 narrowing); fall back to most-active project if 0 candidates |
| Parallel 🟢 In Progress | 1 | `activity-log` most-active project in past 12h |
| Parallel 🟠 Urgent | 1-2 | `due` past / `scheduled` past / `/pulse` Section 6 execution-gap entries |
| Parallel 🔵 Draft candidate | 0-1 | Most recent `status: draft` task; if 0, replace with a second In Progress or omit |

Total 5 items by default; the cap is soft (3-7 is acceptable when source-set varies).

**4-element schema (single-tier cards)**:

- **Stuck** (1-2 sentences, ~80 chars) — Why stuck / where it is jammed. Pulled from `_workspace.md` Current Position / Session History tail, or `_task.md` Background tail + `due/scheduled` delay
- **Next step** (1 sentence, ~60 chars) — Concrete action ≤30min to start. Pulled in this order: (a) `/pulse` Section 6 entry / (b) `_workspace.md` `## Next Steps` first unchecked / (c) `_task.md` `## Plan` next step / (d) the decision itself if it's a judgment gate
- **Resume** (1 backtick line) — Slash command (`/focus {id}` for workspace, `/solve {slug}` for task, link-only if judgment gate, `/solve {slug}` with an "(after Review-mode approval)" suffix for draft task)
- **Source** (1-3 Markdown links) — `[name](path)` to source workspace / task / journal

**Top hierarchy (3-tier)**:

The Top item only is expanded in 3 tiers inside an ASCII tree block. Use Unicode box-drawing characters (`├ └ │`). Tiers are typically: **Strategy** (the decided means; state "not up for re-deliberation" if already decided) → **Execution ← untouched** (concrete action delayed N days, the stuck node) → **Contingency** (guardrails / fallback scenarios). If the dependency chain is shallow, collapse to 2 tiers; do not pad to 4.

```markdown
# YYYY-MM-DD Daily Briefing

(SC-01 contract: H1 must match `# YYYY-MM-DD Daily Briefing` exactly. Weekday goes into the main-theme line below, not into the H1.)

(If Step E set `nudge == ON or DELAYED`, prepend ONE prose line above the main-theme line — no heading, no list bullet. Tone: warm, conversational, ending with the literal command `/retrospective weekly`. Marker word "delayed" or equivalent in `DETECTED_LANG` if nudge state is DELAYED. Omit this line entirely if `nudge == OFF`.)

**Main theme**: {the direction.md Current Main Theme section compressed to 1 line, dense — include career or other sub-directions only when direction.md itself carries them}. **Today ({weekday})**: {time constraints, if any}.

## Today's Flow (touched in the last 12 hours)

- **Morning**: {activity-log entries grouped, prose, 1 line}
- **Afternoon**: {activity-log entries grouped, prose, 1 line}
- **Most recent**: {most recent activity, prose, 1 line}

(If no activity in past 12h, write a single line: "No activity in the last 12 hours". This section is the v3 equivalent of v2's "Yesterday's Activity" — it shifts focus from "yesterday-aggregated" to "what's already happening today".)

## ⚠️ Today's Focus — important but untouched

**[{Project}] {Top item title}**

> {1-2 sentence stuck explanation: why it qualifies as important × untouched, with specific signals — direction.md mention / activity-log gap / deadline / promise / doctrine}

```
├ Strategy: {if already decided, say so explicitly ("not up for re-deliberation") + 1 line of what was decided}
├ Execution ← untouched: {concrete action N days delayed, the stuck node — be specific about the delay and what's blocking}
└ Contingency: {guardrails / fallback scenarios — G1-Gn if applicable, otherwise 1 line naming the fallback when stalled}
```

**Resume** → `{/focus or /solve command}`
**Source** → [{name}]({path}) · [{name}]({path})

(If 0 candidates qualify for important × untouched, replace the heading with `## ★ Today's Focus (in progress)` and the meta line with "moving forward on today's momentum"; the tree may still apply if dependencies exist, otherwise output as a single-tier card.)

## In Parallel (4)

### 🟢 In Progress — [{Project}] {item title}

- **Stuck**: {what's happening today, what's left}
- **Next step**: {concrete next action}
- **Resume**: `{/focus or /solve command, or "this session" if currently active}`
- **Source**: [{name}]({path})

### 🟠 Urgent — [{Project}] {item title}

- **Stuck**: {expiry delay, blocker}
- **Next step**: {concrete action ≤30min}
- **Resume**: `/solve {slug}`
- **Source**: [task ticket]({path})

### 🟠 Urgent — [{Project}] {item title}

(Same 4-element structure; omit this card if only 1 Urgent item exists.)

### 🔵 Draft candidate — [{Project}] {item title}

- **Stuck**: {why this is surfacing now, why it's not yet a real task}
- **Next step**: approve the draft task in Review mode → `status: open` → run `/solve`
- **Resume**: `/solve {slug}` (after Review-mode approval)
- **Source**: [draft task]({path}) · {related rules / source files}

(Omit this card entirely if 0 `status: draft` tasks exist. The 5-count is not strict.)

## Narrowed out

(Do **not** fold via `<details>` — count-summaries go on the heading line in bold. Markdown viewer compatibility.)

**Active workspaces, remaining N** · not tied to today's decisions: X / stalled 15-29 days: Y (next week's `/close` candidates) / dormant 30+ days: Z (`/retrospective` Sunday auto-skip candidates) → details in [knowledge/self/current-state.md](../../knowledge/self/current-state.md)

**Waiting tasks N** · overdue: X / due this month: Y / one-off scheduled: Z (if any overdue, surface exactly 1 inline link)

**External signals** · today: critical alerts X, releases Y · prior day: critical alerts Z, releases W — latest in [newsletter]({path})

## Notes

(Bulleted prose, **5 items maximum**. Include:
- **Today's recommended action** — Two nudge cases, both must read as a request the user makes to Claude, never as a terminal command. **Never output `rill log`, `rill clip`, or any `rill *` CLI command in the Notes section.**
  1. **Journal capture nudge** (trigger: `journal-count` from frontmatter is 0, OR the past 3+ days have had journal-count=0): warm, brief nudge in `DETECTED_LANG` inviting the user to start capturing. Examples: *"When you're ready to capture a thought, click 'New Entry' in the Rill app, or open a Claude Code session in your vault and just tell me what's on your mind — I'll handle the rest. No commands needed."*
  2. **Inbox processing nudge** (trigger: any `inbox.*.unprocessed` count is non-zero): prose nudge stating counts per subdirectory and inviting the user to ask Claude to pull in the new entries. If this nudge has been appearing for several days in a row, suggest "you can also ask Claude to set this up as a daily automation."
- Other one-line observations
)

(※ Insert Plugin Hook sections collected in Phase 1.5 here, each as-is `## Section Name`.)
```

**Empty cases**:

| Case | Behavior |
|---|---|
| Top "important × untouched" 0 candidates | Switch heading to `## ★ Today's Focus (in progress)`, use most-active project from `activity-log` past 12h |
| `/pulse` Section 6 0 entries | Fill 🟠 Urgent from `due` past / `scheduled` past only; if 0, set Urgent count to 0 and add a second 🟢 In Progress |
| `status: draft` task 0 entries | Omit 🔵 Draft-candidate card entirely (4 items output is fine) |
| `activity-log` past 12h 0 entries | "Today's Flow" section: single line "No activity in the last 12 hours" |
| All active workspaces 0 | **Do not drop Top + parallel cards wholesale.** Re-source them entirely from `tasks/` instead: Top = highest-pull task (overdue, then `scheduled` past, then `due` near, then `status: draft`); parallel = remaining Urgent tasks (overdue / scheduled past / `/pulse` Section 6) + draft tasks. Top still uses the same `## ⚠️ Today's Focus` heading but the hierarchical tree degrades to 1-tier (no Strategy / Contingency sub-branches when the source is a single task). Add an explicit note "no active workspaces — surfacing urgent items from tasks/" at the top of the Top card |

**Output language (headings, labels, body)**: The template strings above are the **canonical English** forms. Render the emitted Daily Note — section headings, card labels (Stuck / Next step / Resume / Source), and body — in the language defined by `.claude/rules/personal-language.md` (English when absent), translating the canonical strings consistently (one rendering per concept per document). **Filter at generation time**, not as a post-pass, and do not import vocabulary from source material in other languages — translate it. Two stability rules: (1) the H1 `# YYYY-MM-DD Daily Briefing` and the literal `waiting` status token stay verbatim in every language (SC-01 / TK-04 contracts); (2) for cross-day consistency, reuse the heading renderings of the previous Daily Note (read in Step B #4) when its language matches the current config.

**Language for Notes nudges**: follow `DETECTED_LANG` (the user's preferred language); the journal capture / inbox processing nudges keep their warm conversational tone regardless of language.

**Character count target**: ~2500 chars (v2 was ~1500; v3 grows because density per card is higher, but visible items drop from 8-15 to 5).

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
