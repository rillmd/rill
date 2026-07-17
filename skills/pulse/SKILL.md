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

Aggregates active state from `workspace/`, `tasks/`, and `knowledge/self/` and writes a triaged snapshot to `knowledge/self/current-state.md`. The snapshot has a **hard cap of 80 lines / 2 screens** with each section limited to 7 entries (3 for execution gap, 5 for known contradictions).

Design essence:

- The snapshot is a **triage, not an archive**: hard-capped volume, per-section entry caps, overflow dropped or signaled — never appended. Anything needing full detail is reached through the links, not inlined
- Input collection is **Grep-first**: two bulk status Greps + frontmatter-only Reads. Full-body reads of every active workspace do not scale — at a few dozen active workspaces they cost roughly an order of magnitude more tokens per run than the Grep-first pipeline
- /pulse is **auto-chained** from the tails of `/distill` and `/close` and invoked on-demand by `/briefing`; cooldown state lives in the `.claude/state/pulse.json` sidecar, never in knowledge frontmatter (frontmatter is a search anchor, not skill telemetry)

## Arguments

$ARGUMENTS — one of the following:
- Omitted → normal run (12h cooldown applies)
- `--force` → bypass the 12h cooldown
- `--dry-run` → produce the output and print to stdout; do not write `knowledge/self/current-state.md`

## Trigger Model

Three trigger kinds:

| Trigger | Source | Cooldown |
|---|---|---|
| **Manual** | User invokes `/pulse` directly | 12h applies; `--force` bypasses |
| **Auto-chain** | Tail of `/distill` (Step 11), tail of `/close` (Phase 10) | 12h applies (no-op silently if recent) |
| **Briefing-on-demand** | `/briefing` Phase 1 Step C.0 when last_pulse_at is >5min old | Always bypasses cooldown (treated as `--force`) |

The user does **not** see this distinction at invocation time — the cooldown logic is internal.

## Cooldown / State Sidecar

State lives in **`.claude/state/pulse.json`** (sidecar, not in frontmatter). Git-tracked so cooldown survives clone.

```json
{
  "last_pulse_at": "2026-05-11T18:00+09:00",
  "pulse_run_count": 47,
  "last_force_at": "2026-05-07T08:00+09:00"
}
```

Cooldown logic:
- Read `.claude/state/pulse.json` at the start. If absent, treat as `last_pulse_at = null` (no cooldown applies)
- If `--force` (manual flag or briefing-on-demand invocation) → proceed unconditionally
- Else if `now - last_pulse_at < 12h` → **no-op skip**. Print one line: `/pulse: skipped (last run at {timestamp}, cooldown 12h)`, do not modify the snapshot, return
- Else → proceed
- After a real run, update the state file: `last_pulse_at = now`, increment `pulse_run_count`, set `last_force_at = now` if `--force`

## Non-Recursive Contract with /distill

/distill ↔ /pulse must not recurse:
- `/distill` path scoping **excludes `knowledge/self/`** (and especially `current-state.md`). The only self/ file `/distill profile-agent` touches is `self/interests.md` + `self/direction.md` (and rarely `self/profile.md`)
- `/pulse` does **not** invoke `/distill` (no back-chain)
- Chain direction: `/distill → /pulse` only

## Procedure

### Phase 0: Cooldown gate

1. Resolve `$ARGUMENTS` to flag set: `force` (true if `--force` or briefing-on-demand), `dry_run` (true if `--dry-run`)
2. Read `.claude/state/pulse.json`
3. If `force == false` and `now - last_pulse_at < 12h` → no-op skip (print 1 line, return)
4. Otherwise continue

### Phase 1: Input collection (Grep-first pipeline)

Two bulk Greps + targeted Reads (the Grep-first pipeline — see Design essence):

1. **Active workspace scan**:
   ```
   Grep(pattern="^status: active", path="workspace/", glob="**/_workspace.md", output_mode="files_with_matches")
   ```
2. **Open/waiting task scan**:
   ```
   Grep(pattern="^status: (open|waiting)", path="tasks/", glob="**/_task.md", output_mode="files_with_matches")
   ```
3. For each hit, Read the frontmatter (≤25 lines per file)
4. Read `knowledge/self/direction.md` (full)
5. Read `knowledge/self/decisions.md` if present (Phase 2 input; absent in Phase 1)
6. Read latest `reports/retrospective/*.md` if present (Phase 2 input)

### Phase 2: Per-section aggregation

Each section caps at 7 entries (3 for execution gap, 5 for contradictions). All caps are hard — overflow is signaled, not displayed (see Phase 4).

#### Section 1 — Current Direction (4-6 line prose, no triage)

Transcribe the opening prose of `self/direction.md` (the heading-less paragraph at the top, plus the bullet list of its `## Current Main Theme` section if compact enough — that heading is the canonical English structural key seeded by `/onboarding`; if absent, treat the first `## ` section as the main-theme section). If `direction.md` is >6 lines, take the first 4-6 lines verbatim and link to direction.md for the full version. No summarization — direction.md is the source of truth.

#### Section 2 — Active Workspaces (cap 7)

Score each active WS:

```
score(WS) = recency_factor * activity_factor * mention_factor

recency_factor   = exp(-days_since_modified / 7)
activity_factor  = 1 + open_task_count_linking_to_WS
mention_factor   = 1 + direction_keyword_overlap
```

Where:
- `days_since_modified` = days between `_workspace.md` `updated` (fallback `created`) and now
- `open_task_count_linking_to_WS` = `tasks/*/_task.md` count where `mentions` or `related` includes this WS's path
- `direction_keyword_overlap` = simple-tokenized keyword overlap (5-10 noun tokens from direction.md vs WS `tags + mentions + title`). **Auto-skip if `direction.md` < 5 lines**: set `mention_factor = 1.0`. So in Phase 1 (sparse direction.md) the formula degrades to `recency × activity`, and gets sharper as direction.md grows.

Stale penalty:
- `days_since_modified > 7` → score halved
- `days_since_modified > 14` → score = 0 (excluded; surfaced separately in `/retrospective`)

Output (each entry 1-2 lines):

```markdown
- [{WS name}](workspace/{id}/_workspace.md) — {1-line summary from the workspace's background/opening section or h1}
```

Always append `→ see workspace/ for all active workspaces` as a trailing pointer.

#### Section 3 — Active Tasks (cap 7 across 3 subsections)

| Subsection | Filter |
|---|---|
| Urgent | `status=open` AND (`due ≤ today + 7d` OR `scheduled = today`) |
| Waiting | `status=waiting` AND `last_modified ≤ 14d` |
| Scheduled | `status=open` AND `8d ≤ scheduled ≤ 30d` |

Top-up priority: Urgent → Waiting → Scheduled. Sort within each by `due` / `last_modified` / `scheduled`. If total > 7, drop the lowest-priority overflow silently (do not add a "+N more" line).

Omit empty subsection headings (`### Waiting` absent if no waiting tasks).

```markdown
### Urgent
- {YYYY-MM-DD due} [{title}](tasks/{slug}/_task.md) — {1-line context}

### Waiting
- [{title}](tasks/{slug}/_task.md) — waiting on: {what/whom}

### Scheduled
- {YYYY-MM-DD} [{title}](tasks/{slug}/_task.md)
```

#### Section 4 — Recent Decisions (cap 7, 14-day window)

- If `self/decisions.md` is **absent or empty** → single line: `(not yet populated — /retrospective fills this in)`
- Otherwise: extract entries from `decisions.md` whose date is within the 14-day window. Importance = `mentions count` + (1 if cited WS is active, 0 if completed). Top 7:

  ```markdown
  - {YYYY-MM-DD}: {decision summary} (source: [{WS name}](workspace/{id}/_workspace.md))
  ```

#### Section 5 — Judgment Gates (cap 7, with overflow warning)

**No keyword filter** (fixed contract). Extract every unchecked checkbox (`- [ ]`) from deliberation and next-action sections in active WS `_workspace.md` files — canonical headings `## Issues to Consider` and `## Next Steps`; workspace bodies are written in the vault's language, so also match the vault-language equivalents of these headings. Sort by WS score (Section 2's score) descending, then by `_workspace.md` `updated` descending. Top 7.

```markdown
- [{checkbox text}](workspace/{id}/_workspace.md) — {WS name}
```

If total hits ≥ 8, append a warning line:

```markdown
⚠ Judgment-gate overload ({total} entries, target ≤7). Possible /focus overuse — consider /retrospective
```

If total ≥ 14 (twice target), bold the warning.

#### Section 6 — Execution Gap (cap 3, additive signal orthogonal to Section 2/5 scoring)

**Purpose**: Surface "decided but unexecuted, deadline-past" items that sink from Section 2 (WS score) and Section 5 (judgment gate) because `recency_factor = exp(-days_since_modified / 7)` halves the WS score at >7 days and zeroes at >14 days. This section inverts that decay — stale WSs with unchecked execution items rise to the top here.

**Source set** (stricter than Section 5):
- Active WS `_workspace.md` files only (no artifacts)
- WS frontmatter `updated` (fallback `created`) is **> 7 days ago** (skip otherwise)
- Inside such a WS, read the body and extract unchecked checkboxes (`- [ ]`) only from decided-action sections — canonical heading `## Next Steps`, plus vault-language equivalents of "next steps" / "immediate actions" headings (stop at the next `## ` heading). Do **not** include `## Issues to Consider` (or its vault-language equivalents) — those are deliberation-stage and stay in Section 5.

**Date-parse failures are defensive** — if a WS's `updated` / `created` cannot be parsed to a date, exclude it from this section (do not crash).

**Sort key**: `days_since_updated × unchecked_count_in_WS` descending. Tie-break: oldest `updated` first (older WS surfaces first within the same product score).

**Cap**: 3 in the initial iteration (intentionally tight — relax after a sample-size week of operation). Items beyond cap 3 are dropped silently — no "+N more" footer.

**Empty-case**: If no candidates, omit the entire section header (do not render an empty Execution Gap heading).

**Output** (each entry 1 line):

```markdown
- {N}d [{checkbox text}](workspace/{id}/_workspace.md) — {WS name}
```

Where `{N}d` = days since `updated` (integer days, e.g. `21d`). Keep `{checkbox text}` to a single line — if multi-line, take the first line only.

**Overlap with Section 5**: A given checkbox can in principle appear in both sections (Section 5 keeps `## Next Steps` in its source set). In practice, items that surface here (stale-WS bias) are unlikely to also surface in Section 5 (recent-WS bias). If a duplicate does occur, that is itself a signal — "this item is important AND stale" — and is acceptable for the first iteration. A future revision may refine the partition.

**/briefing impact**: None directly. /briefing's Step C reads `self/current-state.md` whole; the new section is additive context. /briefing surfaces Section 6 entries as 🟠 Urgent card candidates (see the /briefing composition table).

#### Section 7 — Known Contradictions (cap 5)

- If `reports/retrospective/*.md` does not exist → single line: `(not yet populated — /retrospective fills this in)`
- Otherwise: Read the latest `reports/retrospective/{period}.md`, parse the `## Contradictions` section, top 5. Mark with `[aged]` if same item persisted for 4+ weeks across retrospectives.

  ```markdown
  - {summary} (sources: [{WS A}](path), [{WS B}](path))
  ```

### Phase 3: Render full file

Assemble the 7 sections under a `# Current State — {YYYY-MM-DD HH:MM}` heading (local time; append the vault's local timezone abbreviation or UTC offset, e.g. from `date +'%Y-%m-%d %H:%M %Z'` — never hardcode a timezone). The frontmatter (`type: self`, etc.) is already on the existing skeleton — preserve it and overwrite only the body. Section 6 (Execution Gap) is omitted entirely when empty (per Section 6 empty-case rule); the section numbering still reflects the canonical 7-section layout in this document for clarity.

**Output language**: The section headings and fixed strings in this document are the **canonical English** forms. Render the snapshot body in the language defined by `.claude/rules/personal-language.md` (English when absent), translating the canonical strings consistently (one rendering per concept). Two stability rules: (1) the `# Current State — ` H1 prefix stays verbatim in every language; (2) reuse the previous snapshot's heading renderings when its language matches the config, so day-to-day diffs stay quiet.

Skeleton example for the body:

```markdown
# Current State — {YYYY-MM-DD HH:MM (local timezone)}

## Current Direction
{direction.md prose excerpt}

## Active Workspaces
- [...](...) — ...
- ...
→ see workspace/ for all active workspaces

## Active Tasks
### Urgent
- ...
### Waiting
- ...
### Scheduled
- ...

## Recent Decisions (14 days)
{Phase 1: stub / Phase 2: real entries}

## Judgment Gates
- ...
{warning line if 8+ entries}

## Execution Gap
- {N}d [...](...) — ...
{empty case: section header omitted entirely}

## Known Contradictions
{Phase 1: stub / Phase 2: real entries}
```

### Phase 4: Volume enforcement (80-line cap)

1. Generate the body
2. Count lines (`wc -l` equivalent on the rendered body, including frontmatter)
3. If `lines > 80` → **per-section shrink retry**:
   - Measure each section's actual line count
   - Pick the **single largest** section and reduce its cap by 2 (e.g. WS 7 → 5, or judgment-gate 7 → 5)
   - Regenerate
4. Maximum **2 retries**. If still > 80 after 2 retries:
   - Emit as-is
   - Prepend an HTML comment to the file: `<!-- volume warning: {actual_lines} lines, target 80 -->`
   - Print one stdout warning line

Do **not** add a "+N omitted" footer to any section — that is noise. Use the trailing `→ see workspace/ for all active workspaces` pointer (Section 2) for navigation.

### Phase 5: Write + state update

- If `dry_run == false`: write the rendered body to `knowledge/self/current-state.md` (replace body, keep frontmatter `type: self` and `created`)
- Update `.claude/state/pulse.json`: bump `last_pulse_at`, increment `pulse_run_count`, set `last_force_at` if `force == true`
- If `dry_run == true`: print the rendered body to stdout, do not write either file

### Phase 6: Activity log

```bash
rill activity-log add "pulse — refresh self/current-state.md ({lines} lines, top WS: {top_ws_id})"
```

Skip activity-log on `--dry-run`.

## Rules

- **Source files under `inbox/` are read-only** (not relevant here — /pulse only reads workspace/ and tasks/)
- **Never write to `knowledge/self/` files other than `current-state.md`** — /pulse owns only the snapshot
- **`.claude/state/pulse.json` is the source of cooldown truth**, not frontmatter
- Do not regenerate analytical content (contradictions, longitudinal observations); that lives in `self/observations.md` (populated by `/retrospective`)
- Mode decision happens at the start of Phase 0 (cooldown gate); after that the body generation is deterministic given inputs
- All in-body file references use `[display name](relative path)` Markdown links — backtick-only ID refs forbidden (project rule)
