---
name: briefing
description: Daily briefing in two parts. `/briefing --handoff` (unattended, run by the morning job) writes the morning handoff — what needs the user today, deadlines ahead with the arithmetic of the time left, what needs nothing now and why, and what arrived since yesterday — at the top of reports/daily/YYYY-MM-DD.md. `/briefing` with no flag is the morning standup — the user talks freely about the day, and the skill organizes it against the handoff and the records into today's commitments. Use when the user wants to plan the day, asks for a daily briefing, or starts talking through what they have to do today.
gui:
  label: "/briefing"
  hint: "Talk through your day; get today's commitments"
  match:
    - "reports/daily/**/*.md"
  arg: none
  order: 60
  mode: live
---

# /briefing — Morning Handoff and Standup

**Conduct all conversation with the user — and write all generated output — in the language defined by `.claude/rules/personal-language.md`** (or the user's input language if that file is absent). Follow the language rules in full — exceptions and translation quality are defined in the Language Rules of `.claude/rules/rill-core.md` and the vault's `personal-*.md` overrides, never restated per skill. The English instructions below are for skill clarity, not for output style.

> **Tool references in this skill** (`Bash`, `Grep`, `Read`, `Edit`, `Glob`, `sub-agent`) describe **intent**, not Claude-specific tool calls. Each harness should map them to its native equivalent.

## Goal

The morning has two jobs, done by two entry points that share one file per day, `reports/daily/{DATE}.md`.

| | Handoff (`--handoff`) | Standup (default) |
|---|---|---|
| Who starts it | The morning job, unattended (or the user) | The user, when they want to plan the day |
| What the user does | Reads it (the vault's morning mail may carry it) | Talks freely, one way, about the day |
| Answers | What needs me today? Is everything else really fine? | Is what I have in mind complete and doable today? |
| Writes | The handoff block at the top of the daily note | A standup section appended below it |

Design history (2026-10): the earlier version derived five cards from a self-snapshot with a 2500-character cap and no primary sources; it went unused for a month. The user chose this split after comparing five patterns on one real morning: the handoff because it arrives without being asked for, the standup because a plan built from the user's own words is more accurate and gets used.

## Arguments

$ARGUMENTS

- `--handoff` → handoff for today. `--handoff YYYY-MM-DD` → handoff for that date.
- A bare `YYYY-MM-DD` → handoff for that date (non-interactive; kept for backfills and the test harness).
- Anything else, or nothing → standup. Text given with the command is the start of the user's monologue.

`TARGET_DATE` is the given date or today (wall-clock date with the 03:00 day boundary: before 03:00 counts as the previous day).

## Shared inputs

Read what exists; skip absent sources silently, but record each skipped or failed source for the coverage line (see "Unverified is not safe").

1. **Freshness**: read `.claude/state/pulse.json`; if `last_pulse_at` is more than 12 hours old or missing, invoke `/pulse --force` first. Then read `knowledge/self/current-state.md`, `direction.md`, `constraints.md` (absent = empty).
2. **Tasks**: `Grep(pattern="^status: (open|waiting)", path="tasks/", glob="**/_task.md", output_mode="files_with_matches")`; read the hits. Per ticket: title, status, `due`, `scheduled`, `depends-on`, the Current Position or Background tail, the request.
3. **Workspaces**: active workspaces' `_workspace.md` "Next Steps" unchecked items and deadlines, for those touched in the last 14 days or named in `current-state.md`. Do not read every artifact; open an artifact only when a deadline or a promise depends on it.
4. **Structured counts**: `bash .claude/commands/_lib/briefing-context.sh "$TARGET_DATE" "03:00"` (activity window, journals, inbox counts, task counts).
5. **Primary sources**: if the vault declares tools for mail and calendar (look for a `personal-*` rule describing them, e.g. a CLI and its accounts), read the calendar from TARGET_DATE to TARGET_DATE + 14 days and the mail of the last 2 days (both directions) on every declared account. These catch what the records have not caught up with: an unread request with a deadline, an appointment the user has not mentioned, a reply still owed.
6. **Yesterday's daily note**: the most recent `reports/daily/*.md` before TARGET_DATE. If it has a standup section, take its commitments: each one is either done (evidence in activity-log, tasks, or mail), not done, or unknown.
7. **Today's prepared items**: if the vault has a proactive run directory for TARGET_DATE (e.g. `reports/anticipation/{DATE}/`), list its item titles, so new arrivals already covered there can say so instead of repeating it.

### Unverified is not safe

Every source that failed or was skipped (a mail account whose login expired, a calendar that could not be read, a tool not declared) is named in one coverage line at the end of the handoff. When a source that would affect an item could not be read, that item never goes under "Nothing needed now"; it goes under "Needs you today" as a check, or the coverage line says what could not be confirmed. Do not present stale records as confirmed state.

## Handoff mode

Unattended: never ask a question, never wait. Finish in one turn.

### Content

Four sections, in this order. The reader skims on a phone, so every item has two layers: a **headline line** that can be understood alone, and at most two sentences of **detail** below it. Reading only the headlines of all four sections must tell the reader what to do today and what is coming. Absolute dates with weekdays. No vault-internal labels (artifact numbers, stage names, coined terms). No links that require the vault (the text may be mailed); plain file links are fine in the detail but the sentence must stand without them.

Item format (a mail builder parses it; keep it exact):

```markdown
- **{lead}** {rest of the headline}
  {detail: one or two sentences, indented two spaces}
```

1. **Needs you today** (0–4 items). Only actions with a reason to be done today: a deadline today or tomorrow, an unread request from another person, something that blocks other work, a reply owed, a decision to make today. Lead = the action in a few words ("Decide whether to go to SCAJ"). Rest = the estimated minutes and the end point ("(half a day; done when decided)"). Detail = why today and what is already done. If nothing qualifies, write one plain sentence instead of items.
2. **Deadlines ahead** (0–6 items, within roughly 6 weeks; further ones only if preparation must start now), sorted by date. Lead = the date with weekday, plus the time for appointments ("Oct 23 (Fri) 11:20"). Rest = what it is, in a few words ("OpenAI interviews, three rounds"). Detail = what remains, with the arithmetic of the time left when an estimate exists ("9 hours of preparation, none done, 6 days left: about 1.5 hours a day"); mark estimates as estimates.
3. **Nothing needed now** (0–5 items). Things the user might worry about that need no action today. Lead = the thing ("MTI first invoice"). Rest = when it next needs attention ("check the deposit on Nov 2 (Mon)"). Detail = the reason, in one sentence. Only items whose state was verified (see "Unverified is not safe").
4. **New since yesterday** (0–4 items). Mail, invitations, and records that arrived since the previous handoff and matter. Lead = what arrived. Rest = the action, or "no action needed". Detail = one sentence; if a prepared item covers it, say that the detail is in today's prepared items.

If yesterday's standup left commitments, the opening sentence says how many were done and which were not; carry an undone one into section 1 only if it still has a reason to be done today.

### Showing only what changed

A handoff read every morning loses attention when the same items repeat in the same words: repeated identical warnings are habituated to, and attention returns when something visibly changes (security-warning habituation studies; tiered clinical alerts; alert repeat intervals). So each handoff is compared with the previous one, and unchanged items are kept but made quiet.

1. **Find the previous handoff**: the most recent daily note before TARGET_DATE (up to 7 days back) that has a handoff block. If there is none, every item is new and nothing below applies.
2. **Classify each item** of sections 2 and 3 against it. Match items by what they are (the same task, appointment, or obligation), never by date, so a moved deadline is found as the same item. Then classify: *new* (not in the previous handoff), *changed* (the date, the state, the remaining effort, or the action changed; a moved date is stated as old and new date in the detail), or *unchanged*. If the previous handoff listed the item only on its unchanged line, compare with the most recent handoff (up to 30 days back) where it was shown in full, together with its current sources (task, workspace, mail); if no full showing is found, treat the item as new. Write the leads (and, for deadlines, the what-it-is part) in the same words as before when the thing is the same, so the comparison stays stable; a deadline's date always shows the current date.
3. **Mark** new and changed items by ending their headline line with `<!-- new -->` or `<!-- changed -->`. The detail of a changed item says what changed, first ("Preparation went from 0 to 1.5 hours; 5 days left").
4. **Deadlines ahead** shows an item in full only on its milestone days: when it is new or changed, on the day preparation must start to finish in time (when an estimate exists), and 7 days, 3 days, 1 day before and on the day. On other days it is unchanged.
5. **Nothing needed now** shows every item in full on the first handoff of the week (Monday, or the first one after a gap of 3 days or more). On other days only new and changed items are full.
6. **Unchanged items** of a section are not dropped. They go, after the section's full items, on one line that starts with `<!-- unchanged -->` and then one plain sentence naming each by its lead (for deadlines, the date and what it is), for example `<!-- unchanged --> Unchanged since the last handoff are Oct 31 (Sat) director pay and Oct 31 (Sat) PTA survey.` (a sentence, not a label followed by a colon) Omit the line when there are none.
7. Sections 1 and 4 are always shown in full: section 1 is what to do today, section 4 is new by definition. If a section 1 item was also there yesterday, its rest says so ("second day").
8. The opening sentence counts the full items and the unchanged ones separately.

### Thursday retrospective nudge (state contract)

Runs in handoff mode only (never in standup, so a strike is not counted twice). All dates derive from TARGET_DATE. State: `.claude/state/retrospective.json` (missing file = all fields empty; parse error = one-line warning, no nudge).

```
period_id = "weekly-{Monday of the ISO week before the one containing target_date}"
init nudge_state[period_id] to { nudge_count: 0, last_nudge_at: null } if absent
same_day_rerun = (date of last_nudge_at == target_date)   # reruns never consume strikes

if last_period == period_id or period_id in skipped_periods:
    nudge = OFF
elif Thursday:  nudge = ON
elif Fri/Sat/Sun:  nudge = DELAYED
else:  nudge = OFF
on ON/DELAYED and not same_day_rerun: nudge_count += 1, last_nudge_at = now

3-strike auto-skip: if nudge_count >= 3 and target_date is Sunday →
  append period_id to skipped_periods (dedup), nudge = OFF
```

Persist with merge-write semantics: update only `nudge_state[period_id]` and (when applicable) `skipped_periods`; never touch `last_run_at` / `last_period` / `pending_finalize` / `run_count` (owned by `/retrospective`). Skip persistence when TARGET_DATE is not today. When ON/DELAYED, add one warm sentence ending with the literal `/retrospective weekly` as the last item of "New since yesterday" (or as its own sentence when that section is empty).

### Plugin hooks

For each plugin in `plugins/.enabled` whose `plugin.md` frontmatter has `hooks.briefing`, run its hook prompt via a sub-agent in the foreground. Each returns a `## Section` block. Put all returned blocks, in plugin order, between `<!-- briefing-hooks:start -->` and `<!-- briefing-hooks:end -->` right after the handoff end marker; on a same-day rerun, replace what is between these markers (omit the pair when no hook returns anything). Failures are non-fatal: log and skip.

### Writing the file

The daily note keeps one file per day. If `reports/daily/{TARGET_DATE}.md` does not exist, create it first (ADR-060 — never write `created` by hand):

```bash
rill mkfile reports/daily --date YYYY-MM-DD --type daily-note --field "journal-count=N"
```

The handoff is the text between two marker lines, so a same-day rerun replaces only the handoff (and the plugin-hook block, which has its own markers) and leaves any standup section intact. If the markers exist, replace what is between them; otherwise insert the block right after the H1.

```markdown
# YYYY-MM-DD Daily Briefing

<!-- handoff:start -->
<!-- gathered-at: {ISO 8601 time when reading the shared inputs began} -->
## Morning Handoff

{One opening sentence: what this is, which sources were read, and the counts of the first three sections.}

### Needs you today
### Deadlines ahead
### Nothing needed now
### New since yesterday

{Coverage line: sources read, and sources that could not be read and what that leaves unconfirmed.}
<!-- handoff:end -->
```

The H1 stays verbatim in every language (SC-01). Section headings are rendered in the vault language, one consistent rendering per concept; reuse the previous daily note's renderings when its language matches. Keep the four `###` sections in this order even when empty (write one sentence saying it is empty), so that a mail builder can rely on them. Inside sections use only the item format above; no tables, no code blocks, no emoji. Keep the opening to the sources read, the counts, and (when yesterday's standup left commitments) one sentence on which were done and which were not.

Finish with a 2–3 line summary of counts. Do not chain to other skills.

## Standup mode

The user talks; the skill listens, then organizes once. It is not an interview.

1. **If the user has not said anything about the day yet** (no text with the command), reply with one short line inviting them to talk freely about today (what they plan, what is on their mind, anything that came up), and end the turn. Do not read sources before they talk, and do not summarize the handoff at them.
2. **While they talk**, do not interrupt. If the message ends mid-thought or says there is more, reply with one short acknowledgement and wait.
3. **When they are done**, read the shared inputs. (An item on a handoff's unchanged line carries no detail: read its source, or its last full showing in an earlier handoff, when the standup needs it.) If today's handoff block exists, use it as the starting state instead of re-reading every source, then check what changed since its gathering started (the `gathered-at` comment at the top of the block; if absent, the daily note's `created`): mail and calendar since then, `activity-log.md` entries since then, and task tickets and `_workspace.md` files modified since then (status changes, new tickets with `due` or `scheduled`, completed Next Steps). Prefer the newer state wherever the two disagree. For any source the handoff's coverage line reports as failed or skipped, read it over the full shared-input range instead of the difference. If no handoff exists, gather the shared inputs yourself.
4. **Reply once**, in this order:
   - What they said, organized by topic in their own terms (short; this shows it was heard). Keep their intent: if they said "today", it stays a today candidate unless something rules it out, and then say what.
   - What they did not mention but should know today: deadlines, appointments, unread requests, yesterday's undone commitments — only those that change today's choices.
   - At most two questions, only when the answer changes today's order or scope (for example, whether a research request means re-checking yesterday's results or a new question). Ask them inline; do not use a question tool.
   - **Today's commitments**: a numbered list of 3–5 actions in the order to do them. Each has estimated minutes and an end point. Start with one sentence naming the fixed appointments that bound the day and the hours left around them. Do not allocate time slots and do not write to a calendar.
   - **Not today**: the remaining things they mentioned or that are pending, each with the reason and when it comes back (a date or a condition).
5. If they answer the questions or correct the plan, update the commitments in a short reply.
6. **Write it down**: append (or, on a later standup the same day, replace) a `## Standup` section below the handoff block in `reports/daily/{TARGET_DATE}.md`, creating the file with `rill mkfile` if it does not exist. Record: the time, a short summary of what the user said, the commitments with minutes and end points, Not today with reasons and return dates, and open questions. Mark it as the plan agreed with the user. Tomorrow's handoff reads this.

Progress itself stays in the source records (tasks, workspaces). The daily note records the state as of that morning and the day's choices. Never rewrite task statuses from the standup unless the user asks.

## Constraints

- Never modify `inbox/` originals. Prefer `_organized/` versions.
- Create `reports/daily/` if missing.
- Contacts (email addresses, phone numbers) of other people are never written into the daily note.
- Do not invent estimates without saying they are estimates. Do not present inference as fact.
- File references in the note as `[display name](../../relative-path)`; backtick-only ID references are prohibited.
