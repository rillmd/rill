---
name: pulse
description: Refresh knowledge/self/current-state.md — a triaged 80-line/7-section snapshot of the user's current state (direction / active workspaces / open tasks / recent decisions / open questions / execution gaps / known contradictions). Called manually, or auto-chained from /distill + /close, or on-demand by /briefing when the snapshot is stale. Use when the user asks for "current state" (in any language) / "what's going on across my workspaces", or when a higher-level skill needs a fresh self-snapshot.
gui:
  label: "/pulse"
  hint: "Refresh self/current-state.md snapshot"
  match:
    - "knowledge/self/current-state.md"
  arg: none
  order: 65
  mode: auto
---

# /pulse — Self Snapshot Refresh

**Conduct all conversation with the user — and write all generated output — in the language defined by `.claude/rules/personal-language.md`** (or the user's input language if that file is absent). Follow the language rules in full — exceptions and translation quality are defined in the Language Rules of `.claude/rules/rill-core.md` and the vault's `personal-*.md` overrides, never restated per skill. The English instructions below are for skill clarity, not for output style.

> **Tool references in this skill** (`Bash`, `Grep`, `Read`, `Edit`, `Glob`, `Skill`) describe **intent**, not Claude-specific tool calls. Each harness should map them to its native equivalent.

## Goal

Refresh `knowledge/self/current-state.md` from live vault state. The snapshot is a **triage, not an archive**: hard 80-line cap, per-section entry caps, overflow dropped or signaled — never appended. Anything needing full detail is reached through links, not inlined.

## Arguments

$ARGUMENTS — omitted → normal run (12h cooldown applies) / `--force` → bypass the cooldown / `--dry-run` → print the rendered snapshot to stdout, write nothing.

## Behavior contracts

- **Cooldown & state sidecar**: `.claude/state/pulse.json` (git-tracked; never frontmatter — frontmatter is a search anchor, not skill telemetry) holds `last_pulse_at`, `pulse_run_count`, `last_force_at`. If not forced and `now - last_pulse_at < 12h`, no-op skip with a single line: `/pulse: skipped (last run at {timestamp}, cooldown 12h)`. Invocations chained from `/distill` and `/close` respect the cooldown; briefing-on-demand invocations (from `/briefing` when `last_pulse_at` is >5min old) always count as forced. After a real run, update the sidecar (bump `last_pulse_at`, increment `pulse_run_count`, set `last_force_at` on forced runs).
- **Non-recursion with /distill**: the chain direction is `/distill → /pulse` only; /pulse never invokes /distill. (/distill's path scoping excludes `knowledge/self/`.)
- **Grep-first cost profile**: collect inputs with two bulk status Greps — `^status: active` over `workspace/**/_workspace.md` and `^status: (open|waiting)` over `tasks/**/_task.md` — plus frontmatter-only reads (≤25 lines) of the hits. Full-body reads of every active workspace do not scale. Full reads are limited to `self/direction.md`, `self/decisions.md` (if present), and the latest `reports/retrospective/*.md` (if present).

## Output contract

Target: `knowledge/self/current-state.md` — replace the body, preserve the existing frontmatter (`type: self`, `created`). H1 is `# Current State — {YYYY-MM-DD HH:MM}` with the local timezone from the system (e.g. `date +'%Y-%m-%d %H:%M %Z'`), never hardcoded.

**Output language**: section headings below are the canonical English forms. Render the body in the language defined by `personal-language.md` (English when absent), translating the canonical strings consistently (one rendering per concept). Two stability rules: the `# Current State — ` H1 prefix stays verbatim in every language, and the previous snapshot's heading renderings are reused when its language matches the config, so day-to-day diffs stay quiet.

Seven sections, in order (Section 6's header is omitted entirely when it has no entries; all caps are hard — overflow is dropped or signaled, never listed):

### 1. Current Direction (4-6 lines, no triage)

Transcribe the opening prose of `self/direction.md` (the heading-less top paragraph, plus the bullet list of its `## Current Main Theme` section if compact — that heading is the canonical structural key seeded by `/onboarding`; if absent, use the first `## ` section). No summarization — direction.md is the source of truth; when truncating to 4-6 lines, link to it for the full version.

### 2. Active Workspaces (cap 7)

Score each active WS: `exp(-days_since_modified / 7) × (1 + open_task_count_linking_to_WS) × (1 + direction_keyword_overlap)`, where `days_since_modified` comes from `_workspace.md` `updated` (fallback `created`), the task count is over `tasks/*/_task.md` whose `mentions`/`related` include the WS path, and the keyword overlap is a simple-tokenized comparison of direction.md nouns vs WS `tags + mentions + title` (auto-skip — factor 1.0 — when direction.md < 5 lines). Stale penalty: score halved at >7 days, zeroed at >14 days (excluded; `/retrospective` surfaces those). Entry: `- [{WS name}](workspace/{id}/_workspace.md) — {1-line summary}`. Always end with the pointer `→ see workspace/ for all active workspaces`.

### 3. Active Tasks (cap 7 across 3 subsections)

| Subsection | Filter |
|---|---|
| Urgent | `status=open` AND (`due ≤ today + 7d` OR `scheduled = today`) |
| Waiting | `status=waiting` AND `last_modified ≤ 14d` |
| Scheduled | `status=open` AND `8d ≤ scheduled ≤ 30d` |

Top-up priority Urgent → Waiting → Scheduled; sort within each by `due` / `last_modified` / `scheduled`; drop overflow silently. Omit empty subsection headings. Entry formats: `- {YYYY-MM-DD due} [{title}](tasks/{slug}/_task.md) — {1-line context}` (Urgent), `- [{title}](tasks/{slug}/_task.md) — waiting on: {what/whom}` (Waiting), `- {YYYY-MM-DD} [{title}](tasks/{slug}/_task.md)` (Scheduled).

### 4. Recent Decisions (cap 7, 14-day window)

If `self/decisions.md` is absent or empty, render the single stub line `(not yet populated — /retrospective fills this in)`. Otherwise take entries dated within 14 days, ranked by importance = `mentions count` + (1 if the cited WS is active). Entry: `- {YYYY-MM-DD}: {decision summary} (source: [{WS name}](workspace/{id}/_workspace.md))`.

### 5. Judgment Gates (cap 7, overflow warning)

No keyword filter (fixed contract). Every unchecked checkbox (`- [ ]`) from the deliberation and next-action sections of active WS `_workspace.md` files — canonical headings `## Issues to Consider` and `## Next Steps`, plus their vault-language equivalents. Sort by Section 2's WS score descending, then `updated` descending. Entry: `- [{checkbox text}](workspace/{id}/_workspace.md) — {WS name}`. If total hits ≥ 8, append `⚠ Judgment-gate overload ({total} entries, target ≤7). Possible /focus overuse — consider /retrospective` (bold it at ≥ 14).

### 6. Execution Gap (cap 3, additive signal)

Purpose: surface "decided but unexecuted, deadline-past" items that sink out of Sections 2/5 because the recency factor decays stale WSs. Source set (stricter than Section 5): active WS `_workspace.md` files whose `updated` (fallback `created`) is **> 7 days ago**; unchecked checkboxes from decided-action sections only — `## Next Steps` and vault-language equivalents, stopping at the next `## ` heading; never `## Issues to Consider` (deliberation stays in Section 5). Unparseable dates exclude the WS defensively. Sort by `days_since_updated × unchecked_count_in_WS` descending, tie-break oldest `updated` first. Entry: `- {N}d [{checkbox first line}](workspace/{id}/_workspace.md) — {WS name}` where `{N}d` = integer days since `updated`. Omit the whole section when empty. A checkbox appearing in both Sections 5 and 6 is acceptable — that duplication is itself an "important AND stale" signal. (/briefing reads the whole snapshot and surfaces these entries as urgent-card candidates.)

### 7. Known Contradictions (cap 5)

If no `reports/retrospective/*.md` exists, render the stub line `(not yet populated — /retrospective fills this in)`. Otherwise parse the latest retrospective's `## Contradictions` section, top 5, marking entries persisting 4+ weeks across retrospectives with `[aged]`. Entry: `- {summary} (sources: [{WS A}](path), [{WS B}](path))`.

## Volume enforcement (80-line cap)

If the rendered file (frontmatter included) exceeds 80 lines: reduce the cap of the single largest section by 2 and re-render, at most twice. If still over after 2 retries, emit as-is, prepend `<!-- volume warning: {actual_lines} lines, target 80 -->`, and print one stdout warning line. Never add "+N omitted" footers — the Section 2 trailing pointer is the navigation affordance.

## Wrap-up

Write the file (on `--dry-run`: print to stdout and write neither the snapshot nor the sidecar), update `.claude/state/pulse.json`, then log: `rill activity-log add "pulse — refresh self/current-state.md ({lines} lines, top WS: {top_ws_id})"` (skip on dry-run).

## Constraints

- **Never write to `knowledge/self/` files other than `current-state.md`** — /pulse owns only the snapshot.
- `.claude/state/pulse.json` is the source of cooldown truth, not frontmatter.
- Do not regenerate analytical content (contradictions, longitudinal observations) — that lives in `self/observations.md`, populated by `/retrospective`.
- All in-body file references use `[display name](relative path)` Markdown links — backtick-only ID refs forbidden (project rule).
