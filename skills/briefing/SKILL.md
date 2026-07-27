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

## Goal

Generate a prose-quality Daily Note at `reports/daily/{TARGET_DATE}.md` (~2500 chars), fully automated, no interaction. **Derivation, not aggregation**: "where am I" awareness lives in `knowledge/self/` (maintained by `/pulse` and `/distill`); the briefing derives *today's actions* from that snapshot instead of rebuilding a situation analysis from raw files. Do not re-scan raw journals, knowledge/notes/, past reports, or full workspace bodies — `self/current-state.md` subsumes them.

## Arguments

$ARGUMENTS — `YYYY-MM-DD` → generate for that date / omitted → today. If `reports/daily/{TARGET_DATE}.md` exists, overwrite without confirmation (Git holds history). At start, run `rill pages-pending-update --gc` (silent, never fails).

## Inputs

- **Structured data**: `bash .claude/commands/_lib/briefing-context.sh "$TARGET_DATE" "03:00"` → YAML with `workspaces` (status counts + active detail), `inbox` (unprocessed counts), `journals_in_window`, `knowledge_created_in_window`, `tag_health` (top-5 + split threshold), `task_tickets` (open/waiting/overdue counts + due_soon + filenames), `activity_window`.
- **Task tickets**: `Grep(pattern="^status: (open|waiting)", path="tasks/", glob="**/_task.md", output_mode="files_with_matches")`, read the hits only. Per ticket: title (h1), status, due, **scheduled** (a past `scheduled` alone qualifies for 🟠 Urgent), mentions, background opening, request. Also grep `^status: draft`, sort by `created` desc, and read the **most recent 1** draft body — it feeds the 🔵 Draft-candidate card. 0 drafts → skip the slot.
- **activity-log.md**: entries in `[TARGET_DATE - 5d at day_boundary, TARGET_DATE at day_boundary]`, anchored to TARGET_DATE (never wall clock, so backfilled runs slice correctly). Three subsets: the 1-day window (v2-style summaries), the **recent 12h** (Today's Flow section), the full 5 days (the **untouched** axis — no touch in this window = untouched).
- **Freshness pre-check**: read `.claude/state/pulse.json`; if `last_pulse_at` is >5 min old or missing, synchronously invoke `/pulse --force` before reading the snapshot (briefing-on-demand bypasses /pulse's cooldown; /pulse never calls back).
- **self/ snapshot** (skip any absent file silently): `current-state.md`, `direction.md`, `interests.md`, `decisions.md` (may be absent until `/retrospective` populates it — treat as empty), `constraints.md` (secondary importance signal).
- **Stale-workspace count**: among active workspaces, count those with `updated` (fallback `created`) >7 days old; if ≥3, append to Notes: `⚠ Stalled 7+ days: {n} workspaces (details in the next /retrospective)`.
- **Previous Daily Note** (most recent in `reports/daily/`, for heading-language continuity) and today's `reports/newsletter/` file if present (for linking).
- **Plugin hooks**: for each plugin in `plugins/.enabled` whose `plugin.md` frontmatter has `hooks.briefing`, run the hook prompt file via a general-purpose sub-agent (context: target date + plugin path). Failures are non-fatal — log and skip. Each hook returns a complete `## Section Name` block, inserted as-is at the end of the note.

## Selection logic (v3 narrowing)

v2 surfaced every active workspace and pushed triage onto the user; v3 narrows to **5 items** (soft cap; 3-7 acceptable), expands only the Top item hierarchically, and renders every card in the fixed 4-element schema.

- **Main-theme line**: compress the `## Current Main Theme` section of `direction.md` to 1 dense line. Heading lookup contract: that heading is the canonical English structural key seeded by `/onboarding`; if absent, fall back to the first `## ` section. Headings are lookup keys, not display strings.
- **Top (⚠️ Today's Focus)** — the 3-condition product:
  1. **important**: mentioned in `direction.md` Active Projects, OR tied to a `constraints.md` constraint (either path is valid; "ineligible" only when neither mentions it)
  2. **untouched**: no activity-log touch in the past 5 days
  3. **pull**: `due` / `scheduled` / explicit deadline / promise / doctrine
  Tie-break: explicit deadline > scheduled/due > general doctrine; longer delay first. 0 candidates → fall back to the most active project of the past 12h, heading `## ★ Today's Focus (in progress)`.
- **Parallel cards**: 1× 🟢 In Progress (most active project, past 12h) + 1-2× 🟠 Urgent (past `due` / past `scheduled` / `/pulse` Section 6 execution-gap entries) + 0-1× 🔵 Draft candidate (most recent draft task). **De-dup**: if the Top fell back to "in progress" and the 🟢 leader is the same project, the 🟢 slot takes the next-most-active project — never spend 2 of 5 slots on one item.
- **Dependency-aware demotion (ADR-080 D80-6)**: a Top/🟠 candidate blocked by an unmet `depends-on` (any listed dependency not `done`/`cancelled`, or a broken link) is demoted — the next candidate takes Top, and the blocked item goes to "Narrowed out" as `Blocked: [{title}](../../tasks/{slug}/_task.md) — waiting on [{dep-title}](../../tasks/{dep-slug}/_task.md)` (max 2 lines, older first); blocked 🟠 candidates are omitted silently. No `depends-on` field = unblocked (the cheap common case). Use the same canonical Dependency Resolution Algorithm as `/refresh-project` (defined in the `/project` SKILL.md).
- Analytical content (contradictions, longitudinal observations) is never regenerated here — it belongs to `self/observations.md` and `/retrospective`.

## /retrospective Thursday nudge (state contract)

All dates derive from TARGET_DATE, not the wall clock. State: `.claude/state/retrospective.json` (lazily initialized; missing file = all fields empty, no error; parse error = one-line warning, no nudge).

```
period_id = "weekly-{Monday of the ISO week before the one containing target_date}"
init nudge_state[period_id] to { nudge_count: 0, last_nudge_at: null } if absent
same_day_rerun = (date of last_nudge_at == target_date)   # reruns never consume strikes

nudge = OFF  if last_period == period_id or period_id in skipped_periods or Mon/Tue/Wed
nudge = ON   if Thursday;  nudge = DELAYED  if Fri/Sat/Sun
on ON/DELAYED and not same_day_rerun: nudge_count += 1, last_nudge_at = now

3-strike auto-skip: if nudge_count >= 3 and target_date is Sunday →
  append period_id to skipped_periods (dedup), nudge = OFF
```

Persist with **merge-write semantics** — update only `nudge_state[period_id]` and (when applicable) `skipped_periods`; never touch `last_run_at` / `last_period` / `pending_finalize` / `run_count` (owned by `/retrospective`). Skip persistence when `target_date != today` (backfills are read-only against state). If nudge is ON/DELAYED, prepend one warm prose line above the main-theme line, ending with the literal `/retrospective weekly` (a slash command, so allowed despite the no-CLI-commands rule for Notes; mark "delayed" when DELAYED).

## Output contract

Create the file first (timestamp accuracy, ADR-060 — never write `created` by hand):

```bash
rill mkfile reports/daily --type daily-note --field "journal-count=N"
# dated: rill mkfile reports/daily --date YYYY-MM-DD --type daily-note --field "journal-count=N"
```

then Edit the body in. Template (canonical English forms; 6 sections after the H1 + main-theme line):

```markdown
# YYYY-MM-DD Daily Briefing

(SC-01 contract: the H1 must match `# YYYY-MM-DD Daily Briefing` exactly; the weekday goes in the main-theme line.)

(Nudge line here when ON/DELAYED — one prose line, no heading, no bullet.)

**Main theme**: {direction.md main theme in 1 dense line}. **Today ({weekday})**: {time constraints, if any}.

## Today's Flow (touched in the last 12 hours)

- **Morning**: {activity-log entries grouped, prose, 1 line}
- **Afternoon**: {…}
- **Most recent**: {…}

(0 entries in 12h → single line "No activity in the last 12 hours".)

## ⚠️ Today's Focus — important but untouched

**[{Project}] {Top item title}**

> {1-2 sentences: why important × untouched — direction.md mention / activity gap / deadline / promise}

```
├ Strategy: {decided means; say "not up for re-deliberation" if decided}
├ Execution ← untouched: {concrete action N days delayed — the stuck node}
└ Contingency: {guardrails / fallback when stalled}
```

**Resume** → `{/focus or /solve command}`
**Source** → [{name}]({path}) · [{name}]({path})

(3-tier tree with Unicode box-drawing; collapse to 2 tiers when the chain is shallow, never pad to 4. Fallback-Top renders as a single-tier card unless dependencies exist.)

## In Parallel (4)

### 🟢 In Progress — [{Project}] {title}
### 🟠 Urgent — [{Project}] {title}
### 🟠 Urgent — (omit if only 1)
### 🔵 Draft candidate — [{Project}] {title}

(Every card uses the fixed 4-element schema:
- **Stuck** (1-2 sentences, ~80 chars) — from `_workspace.md` Current Position / Session History tail, or `_task.md` Background tail + due/scheduled delay
- **Next step** (1 sentence, ~60 chars, ≤30-min action) — source order: /pulse Section 6 entry → `## Next Steps` first unchecked → `_task.md` Plan next step → the decision itself for judgment gates
- **Resume** (1 backtick line) — `/focus {id}` for workspaces, `/solve {slug}` for tasks, link-only for judgment gates, `/solve {slug}` + "(after Review-mode approval)" for drafts
- **Source** (1-3 Markdown links))

## Narrowed out

(No `<details>` folding — count summaries go on bold heading lines. Markdown viewer compatibility.)

**Active workspaces, remaining N** · not tied to today's decisions: X / stalled 15-29 days: Y (next week's `/close` candidates) / dormant 30+ days: Z → details in [knowledge/self/current-state.md](../../knowledge/self/current-state.md)

**Waiting tasks N** · overdue: X / due this month: Y / one-off scheduled: Z (if any overdue, surface exactly 1 inline link)

**External signals** · today: critical alerts X, releases Y · prior day: … — latest in [newsletter]({path})

## Notes

(Bulleted prose, max 5 items. Recommended-action nudges must read as requests the user makes to Claude — **never output `rill log`, `rill clip`, or any `rill *` CLI command here**. Journal-capture nudge when journal-count is 0 (or 3+ days of 0); inbox-processing nudge when any unprocessed count is non-zero, suggesting daily automation if it has recurred for days. Stale-workspace warning line goes here. Plugin hook sections follow, each as-is.)
```

**Empty cases**:

| Case | Behavior |
|---|---|
| 0 important × untouched candidates | `## ★ Today's Focus (in progress)` + most-active project |
| /pulse Section 6 empty | 🟠 from past due/scheduled only; if 0, add a second 🟢 instead |
| 0 draft tasks | Omit 🔵 card (4 items is fine) |
| No activity in 12h | Today's Flow = single line |
| 0 active workspaces | Do **not** drop the cards — re-source Top + parallels entirely from `tasks/` (Top = highest-pull task: overdue → past scheduled → near due → draft; tree degrades to 1 tier). Note "no active workspaces — surfacing urgent items from tasks/" atop the Top card |

**Output language**: template strings above are canonical English. Render headings, card labels, and body in the `personal-language.md` language (English when absent), one consistent rendering per concept, translated at generation time (never import source-material vocabulary untranslated). Verbatim in every language: the H1 `# YYYY-MM-DD Daily Briefing` (SC-01) and the literal `waiting` status token (TK-04). Reuse the previous Daily Note's heading renderings when its language matches. Notes nudges keep a warm conversational tone in the user's language.

**Task display**: title = ticket h1 as-is; 1-sentence background; link `../../tasks/{slug}/_task.md`; show `due` when present; show `` `waiting` `` in backticks. Example: `- **[Submit Q4 expense report](../../tasks/submit-expense-report/_task.md)** — Reimbursement deadline approaching. due: 2026-04-15`

**Post-output**: display a 3-5 line summary and finish. Do not transition to assistant mode.

## Constraints

- **Never modify inbox/journal/ and inbox/*/ originals** (read-only). Prefer `_organized/` versions when present.
- Create `reports/daily/` if missing.
- Prose-based sections with context and recommended actions.
- File references always as `[display name](../../relative-path)` links; backtick-only ID references prohibited.
- Partially-present self/ files: proceed, treat missing ones as empty.
