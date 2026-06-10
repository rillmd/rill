---
name: pulse
description: Refresh knowledge/self/current-state.md — a triaged 80-line/6-section snapshot of the user's current state (direction / active workspaces / open tasks / recent decisions / open questions / known contradictions). Called manually, or auto-chained from /distill + /close, or on-demand by /briefing when the snapshot is stale. Use when the user asks for "今の状態" / "current state" / "what's going on across my workspaces", or when a higher-level skill needs a fresh self-snapshot.
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

**Conduct ALL conversation with the user in the language defined by `.claude/rules/personal-language.md`** (or the user's input language if absent). The English instructions below are for skill clarity, not for output style. Exceptions (only): tokens inside backticks or code blocks, proper nouns, ASCII acronyms.

> **Tool references in this skill** (`Bash`, `Grep`, `Read`, `Edit`, `Glob`, `Skill`) describe **intent**, not Claude-specific tool calls. Each harness should map them to its native equivalent.

Aggregates active state from `workspace/`, `tasks/`, and `knowledge/self/` and writes a triaged snapshot to `knowledge/self/current-state.md`. The snapshot has a **hard cap of 80 lines / 2 screens** with each section limited to 7 entries (5 for known contradictions).

Design references:
- `workspace/2026-05-07-dream-system-rill-application/009-pulse-skill-detail-design.md` — full spec
- `workspace/2026-05-07-dream-system-rill-application/010-pulse-token-cost-analysis.md` — Grep-first 4-stage pipeline (~30-42K tokens / run)
- `workspace/2026-05-07-dream-system-rill-application/015-execution-wiring.md` — Auto-chain trigger paths

## Arguments

$ARGUMENTS — one of the following:
- Omitted → normal run (12h cooldown applies)
- `--force` → bypass the 12h cooldown
- `--dry-run` → produce the output and print to stdout; do not write `knowledge/self/current-state.md`

## Trigger Model

Three trigger kinds (see 009 §1.1):

| Trigger | Source | Cooldown |
|---|---|---|
| **Manual** | User invokes `/pulse` directly | 12h applies; `--force` bypasses |
| **Auto-chain** | Tail of `/distill` (Step 11), tail of `/close` (Phase 10) | 12h applies (no-op silently if recent) |
| **Briefing-on-demand** | `/briefing` Phase 1 Step C.0 when last_pulse_at is >5min old | Always bypasses cooldown (treated as `--force`) |

The user does **not** see this distinction at invocation time — the cooldown logic is internal.

## Cooldown / State Sidecar

State lives in **`.claude/state/pulse.json`** (sidecar, not in frontmatter — 009 §1.2). Git-tracked so cooldown survives clone (009 §9 OQ5).

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

/distill ↔ /pulse must not recurse (009 §1.5):
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

Two bulk Greps + targeted Reads (009 §2.3, 010 v2):

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

#### Section 1 — 今の方向性 (4-6 line prose, no triage)

Transcribe the opening prose of `self/direction.md` (the heading-less paragraph at the top, plus the "現在のメインテーマ" bullet list if compact enough). If `direction.md` is >6 lines, take the first 4-6 lines verbatim and link to direction.md for the full version. No summarization — direction.md is the source of truth.

#### Section 2 — 進行中のワークスペース (cap 7)

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
- [{WS name}](workspace/{id}/_workspace.md) — {1-line summary from `## 背景` or h1}
```

Always append `→ 全 active WS は workspace/ を参照` as a trailing pointer.

#### Section 3 — 進行中のタスク (cap 7 across 3 subsections)

| Subsection | Filter |
|---|---|
| 急ぎ | `status=open` AND (`due ≤ today + 7d` OR `scheduled = today`) |
| 待機 | `status=waiting` AND `last_modified ≤ 14d` |
| Scheduled | `status=open` AND `8d ≤ scheduled ≤ 30d` |

Top-up priority: 急ぎ → 待機 → Scheduled. Sort within each by `due` / `last_modified` / `scheduled`. If total > 7, drop the lowest-priority overflow silently (do not add "+N more" line — see Phase 3 of 009 §3.3).

Omit empty subsection headings (`### 待機` absent if no waiting tasks).

```markdown
### 急ぎ
- {YYYY-MM-DD due} [{title}](tasks/{slug}/_task.md) — {1-line context}

### 待機
- [{title}](tasks/{slug}/_task.md) — 待機: {what/whom}

### Scheduled
- {YYYY-MM-DD} [{title}](tasks/{slug}/_task.md)
```

#### Section 4 — 直近の意思決定 (cap 7, 14-day window)

- If `self/decisions.md` is **absent or empty** → single line: `(retrospective 未実装。Phase 2 で埋まる)`
- Otherwise: extract entries from `decisions.md` whose date is within the 14-day window. Importance = `mentions count` + (1 if cited WS is active, 0 if completed). Top 7:

  ```markdown
  - {YYYY-MM-DD}: {decision summary} (出典 [{WS name}](workspace/{id}/_workspace.md))
  ```

#### Section 5 — 判断ゲート (cap 7, with overflow warning)

**No keyword filter** (009 §3.5 contract). Extract every unchecked checkbox (`- [ ]`) from `## 考えるべき論点` / `## Issues to Consider` / `## Next Steps` headings in active WS `_workspace.md` files. Sort by WS score (Section 2's score) descending, then by `_workspace.md` `updated` descending. Top 7.

```markdown
- [{checkbox text}](workspace/{id}/_workspace.md) — {WS name}
```

If total hits ≥ 8, append a warning line:

```markdown
⚠ 判断ゲート過剰 ({total} 件、target ≤7)。/focus 過剰の可能性、/retrospective を検討
```

If total ≥ 14 (twice target), bold the warning.

#### Section 6 — 執行ギャップ (cap 3, additive signal orthogonal to Section 2/5 scoring)

**Purpose**: Surface "decided but unexecuted, deadline-past" items that sink from Section 2 (WS score) and Section 5 (judgment gate) because `recency_factor = exp(-days_since_modified / 7)` halves the WS score at >7 days and zeroes at >14 days. This section inverts that decay — stale WSs with unchecked execution items rise to the top here.

**Source set** (stricter than Section 5):
- Active WS `_workspace.md` files only (no artifacts)
- WS frontmatter `updated` (fallback `created`) is **> 7 days ago** (skip otherwise)
- Inside such a WS, read the body and extract unchecked checkboxes (`- [ ]`) only from `## Next Steps` and `## 即時アクション` headings (decided-action sections; stop at the next `## ` heading). Do **not** include `## 考えるべき論点` / `## Issues to Consider` — those are deliberation-stage and stay in Section 5.

**Date-parse failures are defensive** — if a WS's `updated` / `created` cannot be parsed to a date, exclude it from this section (do not crash).

**Sort key**: `days_since_updated × unchecked_count_in_WS` descending. Tie-break: oldest `updated` first (older WS surfaces first within the same product score).

**Cap**: 3 in the initial iteration (intentionally tight — relax later after a sample-size week of operation per 016 §6 schedule). Items beyond cap 3 are dropped silently — no "+N more" footer.

**Empty-case**: If no candidates, omit the entire section header (do not render an empty `## 執行ギャップ`).

**Output** (each entry 1 line):

```markdown
- {N}d [{checkbox text}](workspace/{id}/_workspace.md) — {WS name}
```

Where `{N}d` = days since `updated` (integer days, e.g. `21d`). Keep `{checkbox text}` to a single line — if multi-line, take the first line only.

**Overlap with Section 5**: A given checkbox can in principle appear in both sections (Section 5 keeps `## Next Steps` in its source set). In practice, items that surface here (stale-WS bias) are unlikely to also surface in Section 5 (recent-WS bias). If a duplicate does occur, that is itself a signal — "this item is important AND stale" — and is acceptable for the first iteration. A future revision may refine the partition.

**/briefing impact**: None directly. /briefing's Step C reads `self/current-state.md` whole; the new section is additive context. /briefing may choose to surface 執行ギャップ items in its `## Today's Focus` under P0 if appropriate, but that is a follow-up design decision (out of scope here).

#### Section 7 — 既知の前提矛盾 (cap 5)

- If `reports/retrospective/*.md` does not exist → single line: `(retrospective 未実装。Phase 2 で埋まる)`
- Otherwise: Read the latest `reports/retrospective/{period}.md`, parse the `## Contradictions` section, top 5. Mark with `[aged]` if same item persisted for 4+ weeks across retrospectives.

  ```markdown
  - {summary} (出典: [{WS A}](path), [{WS B}](path))
  ```

### Phase 3: Render full file

Assemble the 7 sections under a `# Current State — {YYYY-MM-DD HH:MM JST}` heading. The frontmatter (`type: self`, etc.) is already on the existing skeleton — preserve it and overwrite only the body. Section 6 (執行ギャップ) is omitted entirely when empty (per Section 6 empty-case rule); the section numbering still reflects the canonical 7-section layout in this document for clarity.

Skeleton example for the body:

```markdown
# Current State — {YYYY-MM-DD HH:MM JST}

## 今の方向性
{direction.md prose excerpt}

## 進行中のワークスペース
- [...](...) — ...
- ...
→ 全 active WS は workspace/ を参照

## 進行中のタスク
### 急ぎ
- ...
### 待機
- ...
### Scheduled
- ...

## 直近の意思決定 (14 日)
{Phase 1: stub / Phase 2: real entries}

## 判断ゲート
- ...
{8 件以上なら警告行}

## 執行ギャップ
- {N}d [...](...) — ...
{empty case: section header omitted entirely}

## 既知の前提矛盾
{Phase 1: stub / Phase 2: real entries}
```

### Phase 4: Volume enforcement (80-line cap)

1. Generate the body
2. Count lines (`wc -l` equivalent on the rendered body, including frontmatter)
3. If `lines > 80` → **per-section shrink retry** (009 §4):
   - Measure each section's actual line count
   - Pick the **single largest** section and reduce its cap by 2 (e.g. WS 7 → 5, or judgment-gate 7 → 5)
   - Regenerate
4. Maximum **2 retries**. If still > 80 after 2 retries:
   - Emit as-is
   - Prepend an HTML comment to the file: `<!-- volume warning: {actual_lines} lines, target 80 -->`
   - Print one stdout warning line

Do **not** add a "+N omitted" footer to any section — that is noise. Use the trailing `→ 全 active WS は workspace/ を参照` pointer (Section 2) for navigation.

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
