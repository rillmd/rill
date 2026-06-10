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

**Conduct ALL conversation with the user in the language defined by `.claude/rules/personal-language.md`** (or the user's input language if absent). The English instructions below are for skill clarity, not for output style. Exceptions (only): tokens inside backticks or code blocks, proper nouns, ASCII acronyms.

> **Tool references in this skill** (`Bash`, `Grep`, `Read`, `Edit`, `Glob`, `sub-agent`) describe **intent**, not Claude-specific tool calls. Each harness should map them to its native equivalent — Claude Code uses its built-in tools as named; Codex CLI uses `apply_patch` / shell / its own sub-agent mechanism etc. as appropriate.

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
   - Collect from each ticket: title (h1), status, due, **scheduled** (v3: scheduled-only tasks like IMAP follow-up qualify for 🟠 緊急 via past `scheduled`, must be extracted), mentions (projects/{id}), background (body opening), request
   - **v3 — draft task collection** (for the 🔵 起票候補 slot): additionally grep `Grep(pattern="^status: draft", path="tasks/", glob="**/_task.md", output_mode="files_with_matches")`, sort by `created` descending, **Read the most recent 1 draft task body** (title, frontmatter `created` / `source` / `mentions`, Goal, Background opening) — needed for deterministic 🔵 起票候補 card rendering. If 0 drafts, skip the slot
2. **activity-log.md** — **v3**: get entries within the **past 5 days relative to TARGET_DATE** (not wall-clock, so backfilled `/briefing YYYY-MM-DD` runs produce the correct slice). The activity window is anchored as: `[TARGET_DATE - 5 days at day_boundary, TARGET_DATE at day_boundary]`. Three subsets are used: (a) the activity_window subset (TARGET_DATE-1 → TARGET_DATE at day_boundary) feeds v2-style summaries / detection; (b) the **recent 12h subset relative to TARGET_DATE** (TARGET_DATE-12h → TARGET_DATE) feeds the v3 "今日の流れ" section; (c) the full 5-day range feeds the v3 "手つかず" axis (a project / workspace / task with no touch in this window qualifies as 手つかず). Implementation: read the tail of `activity-log.md`; if the file is long, restrict to entries with timestamps within `[TARGET_DATE - 5 days, TARGET_DATE]`
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
2. `knowledge/self/direction.md` — cross-project meta-direction (medium-velocity, monthly). **v3**: this is the **primary** signal for the **重要** axis for Top filtering — workspaces / tasks mentioned in Active Projects here qualify directly. Items not in Active Projects can still qualify via the **secondary** signal `constraints.md` (Step C #6 below) — both paths are valid, the "ineligible" verdict only fires when neither direction.md nor constraints.md mentions the item
3. `knowledge/self/interests.md` — Deep Interests / Curiosity / Obligations / Career (medium-velocity, monthly)
4. `knowledge/self/decisions.md` — curated decision digest (3-month window, updated by `/retrospective`). **If absent or empty**, treat the "直近意思決定" section in Phase 2 as empty/skipped

**v3 additional inputs for narrowing**:

5. `activity-log.md` — read tail entries (recent 12 hours + past 5 days). Used for two purposes: (a) the **「今日の流れ」** section in Phase 2 (recent 12h, prose summary grouped into 朝 / 午後 / 直近); (b) the **手つかず** axis for Top filtering — a workspace / task / project mentioned in `direction.md` Active Projects but with no `activity-log` touch in the past 5 days qualifies as 手つかず
6. `knowledge/self/constraints.md` — family / financial / health / life-event constraints. Used as a **secondary signal** for the **重要** axis when an item is not in `direction.md` Active Projects but is tied to a `constraints.md` constraint (e.g. iDeCo deadline tied to financial constraint, health checkup tied to health constraint). Skip silently if absent or empty
7. `status: draft` tasks — already collected in Step B #1 (the v3 addendum reads the most recent 1 draft task body in full). Used here only as a cross-reference for the **🔵 起票候補 (draft)** slot in Phase 2 (cap 1, most recent `created`, sourced from Step B's Read). If 0 matches, the slot is replaced by a second 進行中 entry or omitted entirely — the 5-count is not strict

These files are the **primary input** for Phase 2 generation. v3 narrowing logic:

- The **主軸 1-line** is rendered from `self/direction.md` § 現在のメインテーマ (compress to 1 line, dense)
- The **「今日の流れ」** 3 lines are rendered from `activity-log.md` recent 12h (group entries by time-of-day or by activity type, prose)
- The **⚠️ 今日の重点** (Top, hierarchical) is filtered by the **3-condition product**:
  1. **重要**: mentioned in `direction.md` Active Projects, OR tied to a `constraints.md` constraint (the file actually read in Step C #6)
  2. **手つかず**: no `activity-log` touch in past 5 days for that project / workspace / task
  3. **引力あり**: `due` / `scheduled` / explicit deadline / promise / doctrine
  Tie-break: explicit deadline > scheduled/due > general doctrine; longer delay first. If 0 candidates qualify, fall back to the most active project from `activity-log` past 12h (label as **「★ 今日の重点 (進行中)」** instead of 「⚠️」)
- The **並走 4-件 cards** are filled in this order: 1× 🟢 進行中 (most active in `activity-log` past 12h) + 1-2× 🟠 緊急 (`due` past / `scheduled` past / `/pulse` Section 6 execution-gap entries) + 0-1× 🔵 起票候補 (most recent `status: draft` task). **De-duplication rule**: if the Top fell back to "進行中" (i.e. no 重要 × 手つかず candidate) and the 🟢 並走 slot's most-active leader is the same project, the 🟢 slot picks the **next-most-active** project instead — never spend 2 of 5 slots on the same item
- The **「絞り込みから外したもの」** section summarizes counts upfront (do **not** fold via `<details>` — Markdown viewer compatibility) — see Phase 2 Template
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

Write the report body in the language defined by `.claude/rules/personal-language.md` (English when absent), with the same exceptions as the conversation rule above. When a term has no established translation in the target language, prefer a loanword in common use; otherwise keep the English term inside backticks with a short parenthetical gloss — never invent literal calques that do not exist in the target language.

#### File Creation

First create the file with `rill mkfile` (to ensure timestamp accuracy):

```bash
rill mkfile reports/daily --type daily-note --field "journal-count=N"
# For specific date: rill mkfile reports/daily --date YYYY-MM-DD --type daily-note --field "journal-count=N"
```

Then use Edit to append the body to the output path (frontmatter is already generated by `rill mkfile`).

#### Template (v3 — 5 件絞り込み + Top 階層 + 4 要素 schema, target ~2500 chars)

The Phase 2 output is structured as 6 sections after the H1 + main-axis 1-line. The 5-item narrowing rule and 4-element schema come from `tasks/rill-briefing-v3-execution-gap-redesign/002-v3-design.md` (canonical design).

**Composition target** (not strict, fall back when source-set is empty):

| Slot | Count | Source / extraction |
|---|---|---|
| Top (⚠️ 重要 × 手つかず or ★ 今日の重点) | 1 | 3-condition product (Step C, v3 narrowing); fall back to most-active project if 0 candidates |
| 並走 🟢 進行中 | 1 | `activity-log` most-active project in past 12h |
| 並走 🟠 緊急 | 1-2 | `due` past / `scheduled` past / `/pulse` Section 6 execution-gap entries |
| 並走 🔵 起票候補 | 0-1 | Most recent `status: draft` task; if 0, replace with a second 進行中 or omit |

Total 5 items by default; the cap is soft (3-7 is acceptable when source-set varies).

**4-element schema (single-tier cards)**:

- **停滞** (1-2 sentences, ~80 chars) — Why stuck / where it is jammed. Pulled from `_workspace.md` Current Position / Session History tail, or `_task.md` Background tail + `due/scheduled` delay
- **次の一手** (1 sentence, ~60 chars) — Concrete action ≤30min to start. Pulled in this order: (a) `/pulse` Section 6 entry / (b) `_workspace.md` `## Next Steps` first unchecked / (c) `_task.md` `## Plan` next step / (d) "決断そのもの" if it's a judgment gate
- **再開** (1 backtick line) — Slash command (`/focus {id}` for workspace, `/solve {slug}` for task, link-only if judgment gate, `/solve {slug}` with "(Review mode 承認後)" suffix for draft task)
- **出典** (1-3 Markdown links) — `[name](path)` to source workspace / task / journal

**Top hierarchy (3-tier)**:

The Top item only is expanded in 3 tiers inside an ASCII tree block. Use Unicode box-drawing characters (`├ └ │`). Tiers are typically: **戦略** (decided means, "悩み直す段ではない" if already decided) → **実行 ← 手つかず** (concrete action delayed N days, the stuck node) → **障害対処** (guardrails / fallback scenarios). If the dependency chain is shallow, collapse to 2 tiers; do not pad to 4.

```markdown
# YYYY-MM-DD Daily Briefing

(SC-01 contract: H1 must match `# YYYY-MM-DD Daily Briefing` exactly. Weekday goes into the main-axis line below, not into the H1.)

(If Step E set `nudge == ON or DELAYED`, prepend ONE prose line above the main-axis line — no heading, no list bullet. Tone: warm, conversational, ending with the literal command `/retrospective weekly`. Marker word "delayed" or equivalent in `DETECTED_LANG` if nudge state is DELAYED. Omit this line entirely if `nudge == OFF`.)

**主軸**: {direction.md 現在のメインテーマ を 1 行に圧縮、dense}。**求職方向**: {if applicable}。**本日 ({曜})**: {時間制約}。

## 今日の流れ (直近 12 時間で触れたもの)

- **朝**: {activity-log entries grouped, prose, 1 line}
- **午後**: {activity-log entries grouped, prose, 1 line}
- **直近**: {most recent activity, prose, 1 line}

(If no activity in past 12h, write a single line: "直近の活動なし". This section is the v3 equivalent of v2's "Yesterday's Activity" — it shifts focus from "yesterday-aggregated" to "what's already happening today".)

## ⚠️ 今日の重点 — 重要だが手つかず

**[{Project}] {Top item title}**

> {1-2 sentence stuck explanation: why it qualifies as 重要 × 手つかず, with specific signals — direction.md mention / activity-log gap / deadline / promise / doctrine}

```
├ 戦略: {決定済みなら「悩み直す段ではない」と明示 + 既に決まっている内容を 1 行}
├ 実行 ← 手つかず: {concrete action N 日 delayed, the stuck node — be specific about the delay and what's blocking}
└ 障害対処: {guardrails / fallback scenarios — G1-Gn if applicable, otherwise 1 line of "停滞時の代替"}
```

**再開** → `{/focus or /solve command}`
**出典** → [{name}]({path}) · [{name}]({path})

(If 0 candidates qualify for 重要 × 手つかず, replace the heading with `## ★ 今日の重点 (進行中)` and the meta line with "今日 momentum で前進中"; the tree may still apply if dependencies exist, otherwise output as a single-tier card.)

## 並走 4 件

### 🟢 進行中 — [{Project}] {item title}

- **停滞**: {what's happening today, what's left}
- **次の一手**: {concrete next action}
- **再開**: `{/focus or /solve command, or "本セッション内" if currently active}`
- **出典**: [{name}]({path})

### 🟠 緊急 — [{Project}] {item title}

- **停滞**: {expiry delay, blocker}
- **次の一手**: {concrete action ≤30min}
- **再開**: `/solve {slug}`
- **出典**: [task チケット]({path})

### 🟠 緊急 — [{Project}] {item title}

(Same 4-element structure; omit this card if only 1 緊急 item exists.)

### 🔵 起票候補 — [{Project}] {item title}

- **停滞**: {why this is surfacing now, why it's not yet a real task}
- **次の一手**: draft タスクを Review mode で承認 → `status: open` 遷移 → `/solve` で実行
- **再開**: `/solve {slug}` (Review mode 承認後)
- **出典**: [draft task]({path}) · {related rules / source files}

(Omit this card entirely if 0 `status: draft` tasks exist. The 5-count is not strict.)

## 絞り込みから外したもの

(Do **not** fold via `<details>` — count-summaries go on the heading line in bold. Markdown viewer compatibility.)

**進行中ワークスペース 残り N 件** ・ 今日の決断に直結しない: X 件 / 停滞 15-29 日: Y 件 (来週 `/close` 候補) / 忘却 30+ 日: Z 件 (`/retrospective` Sunday の auto-skip 候補) → 詳細は [knowledge/self/current-state.md](../../knowledge/self/current-state.md)

**待機 タスク N 件** ・ overdue: X 件 / 今月期限: Y 件 / 単発 scheduled: Z 件 (overdue があれば 1 件だけ inline link を出す)

**外部の動き** ・ 今日 critical 警告 X 件、リリース Y 件 ・ 前日 critical 警告 Z 件、リリース W 件 — 最新は [newsletter]({path})

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
| Top "重要 × 手つかず" 0 candidates | Switch heading to `## ★ 今日の重点 (進行中)`, use most-active project from `activity-log` past 12h |
| `/pulse` Section 6 0 entries | Fill 🟠 緊急 from `due` past / `scheduled` past only; if 0, set 緊急 count to 0 and add a second 🟢 進行中 |
| `status: draft` task 0 entries | Omit 🔵 起票候補 card entirely (4 items output is fine) |
| `activity-log` past 12h 0 entries | "今日の流れ" section: single line "直近の活動なし" |
| All active workspaces 0 | **Do not drop Top + 並走 wholesale.** Re-source Top + 並走 entirely from `tasks/` instead: Top = highest-引力 task (overdue, then `scheduled` past, then `due` near, then `status: draft`); 並走 = remaining 緊急 tasks (overdue / scheduled past / `/pulse` Section 6) + draft tasks. Top still uses the same `## ⚠️ 今日の重点` heading but the hierarchical tree degrades to 1-tier (no 戦略 / 障害対処 sub-branches when the source is a single task). Add an explicit note "現在 active workspace なし — tasks/ から緊急項目を surface" at the top of the Top card |

**Language for body text**: Body text follows `personal-language.md` rules (Japanese for body, English only inside backticks / proper nouns / ASCII acronyms). **Filter at generation time**, not as a post-pass — translate phrases like "Top" → 「今日の重点」, "Stuck" → 「停滞」, "Next 1" → 「次の一手」, "Source" → 「出典」 inline as they form.

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
