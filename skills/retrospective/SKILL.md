---
name: retrospective
description: Generate a weekly retrospective at reports/retrospective/weekly-{YYYY-MM-DD}.md with 5 sections (Cross-WS Themes / Contradictions / Stale Workspaces / Decision Digest / Self Observations) over the prior ISO week. Auto-appends to knowledge/self/decisions.md (3-month window); Self Observation candidates are approved interactively via --finalize (the skill asks which to adopt and handles the checkboxes). Primary habit trigger is the Thursday /briefing nudge. Use when the user runs `/retrospective`, asks for a weekly review, or the briefing nudge requests it.
gui:
  label: "/retrospective"
  hint: "Weekly retrospective generation"
  match:
    - "reports/retrospective/*.md"
  arg: "weekly | monthly | --view | --rerun | --finalize {period}"
  order: 70
  mode: auto
---

# /retrospective — Weekly Retrospective

> **Registration convention**: `skills/{name}/SKILL.md` is the canonical skill form; there is **no** `.claude/commands/retrospective.md` and one is not required. `rill update` propagates `skills/*/SKILL.md` to consumer vaults as `.claude/skills/{name}/SKILL.md`.

**Conduct all conversation with the user — and write all generated output — in the language defined by `.claude/rules/personal-language.md`** (or the user's input language if that file is absent). Follow the language rules in full — exceptions and translation quality are defined in the Language Rules of `.claude/rules/rill-core.md` and the vault's `personal-*.md` overrides, never restated per skill. The English instructions below are for skill clarity, not for output style.

> **Skill-specific language exception**: the five report section headings (`## Cross-WS Themes`, `## Contradictions`, `## Stale Workspaces`, `## Decision Digest`, `## Self Observations`) stay verbatim English regardless of the report-body language — they are a dependency contract; `/pulse` parses `## Contradictions` by name.

> **Tool references in this skill** (`Bash`, `Grep`, `Read`, `Edit`, `Glob`, `Agent`, `Skill`) describe **intent**, not Claude-specific tool calls. Each harness should map them to its native equivalent.

Aggregates the prior ISO week across `workspace/`, `tasks/`, `inbox/journal/`, and decision artifacts into a 5-section retrospective. Auto-flushes the Decision Digest into `knowledge/self/decisions.md` (3-month window). Self Observation candidates are approved through an interactive `--finalize` flow (multi-select questions; the skill writes the checkboxes). Stale Workspace detection runs deterministically (no agent fanout).

Design essence:

- The user's job-to-be-done is a **weekly high-altitude view**: "look down on last week's self, build this week's strategy" — a different time axis from `/briefing` (today) and `/pulse` (this instant). Hence contradictions across workspaces, stale-workspace triage, a curated decision digest, and self-observation patterns, not another activity summary
- The **5-section output schema is a dependency contract**: `/pulse` Section 7 parses the `## Contradictions` section of the latest retrospective, so section names and order are fixed
- **Thursday is the primary trigger**, wired as a nudge inside `/briefing` Step E (with a 3-strike auto-skip) rather than a scheduler — the weekly usage-budget reset acts as a psychological deadline
- Self Observations only ever enter `self/observations.md` through explicit user approval; decisions flush automatically, observations never do. The approval itself is collected **interactively** — the skill presents the candidates as multi-select questions and writes the `[x]` marks on the user's behalf (editing checkboxes in a report file from a terminal session proved too much friction). The checkbox in the file remains the durable record; manual `[x]` editing stays supported as a fallback

## Arguments

$ARGUMENTS — one of the following:

- Omitted → `weekly` for the prior ISO week (Monday-to-Sunday, ending before today's week)
- `weekly` → same as omitted
- `weekly YYYY-MM-DD` → weekly for the ISO week whose Monday is the given date
- `monthly` → monthly for the prior calendar month (Phase 2 deferred; emit "monthly is not implemented yet" and exit if invoked)
- `monthly YYYY-MM` → same
- `--view` → display the existing file path (if any) without regenerating
- `--rerun` → regenerate over an existing file (preserves frontmatter `created`, updates `updated`)
- `--finalize [{period}]` → collect Self Observation approval and flush approved entries into `knowledge/self/observations.md`. In an interactive session the skill presents unchecked candidates as multi-select questions and marks `[x]` on the user's behalf; pre-marked `[x]` lines are honored as-is. With `{period}` omitted, sweeps every period in the state sidecar's `pending_finalize` (oldest first). Does not regenerate the retrospective file

## Trigger Model

Four trigger kinds:

| Trigger | Source | Action |
|---|---|---|
| **Manual weekly** | User runs `/retrospective` or `/retrospective weekly` | Generate weekly retrospective |
| **Manual monthly** | User runs `/retrospective monthly` | Deferred (Phase 2); print stub message |
| **Briefing nudge** | `/briefing` Phase 1 Step E surfaces a nudge | User must still invoke `/retrospective` manually — no auto-chain |
| **/pulse Read** | `/pulse` reads the latest retrospective for "known contradictions" extraction | Read-only; never invoked from `/pulse` |

No launchd / cron. Primary path is manual + Thursday nudge.

## State Sidecar

State lives in `.claude/state/retrospective.json`. Git-tracked so weekly cadence survives clone.

```json
{
  "last_run_at": "2026-05-08T18:00+09:00",
  "last_period": "weekly-2026-04-27",
  "pending_finalize": ["weekly-2026-04-27"],
  "skipped_periods": ["weekly-2026-04-13"],
  "nudge_state": {
    "weekly-2026-05-04": { "nudge_count": 1, "last_nudge_at": "2026-05-14T07:00+09:00" }
  },
  "run_count": 8
}
```

- `last_run_at` / `last_period` updated on every successful generation
- `pending_finalize` tracks periods with un-finalized Self Observations
- `skipped_periods` tracks 3-strike nudge skips (also written by `/briefing` Step E)
- `nudge_state` is written by `/briefing` only; this skill reads it but does not mutate it
- `run_count` for instrumentation

If the file does not exist, initialize lazily on first successful run. Treat missing fields as empty.

## Idempotency

- Same period + no `--rerun` → display "weekly-{period}.md already exists. Use `--rerun` to overwrite or `--view` to display." and exit
- `--rerun` → full body replacement; `created` immutable, `updated` refreshed
- `--view` → print the file path; do not regenerate
- `self/decisions.md` append: dedup by `(source path)` key; reruns do not double-append
- `self/observations.md` (via `--finalize`): dedup by `(text + source)` key

## Period Strategy

- `weekly` is primary: period = ISO week (Monday..Sunday). Format: `weekly-{YYYY-MM-DD}` where the date is the Monday
- `monthly` is deferred (open question, not yet designed)
- `daily` is not supported — `reports/daily/` already covers that role

## Procedure

### Phase 0: Resolve period and check idempotency

1. Parse arguments. Compute `period_monday := YYYY-MM-DD` of the target ISO week's Monday (default: the prior ISO week, i.e., week before today's week)
2. **Define the canonical period id once**: `period_id := "weekly-" + period_monday` (e.g. `weekly-2026-05-04`). All later phases, state writes, and provenance strings reference `{period_id}` verbatim — do not re-prepend `weekly-` anywhere downstream
3. **`--finalize` short-circuits the rest of Phase 0 — with or without a period argument** → jump straight to Phase 6 (finalize operates only on existing files; the bare form resolves its targets from `pending_finalize` there). Do not run any existing-file or `--view` gating before it, and never fall through to weekly generation when `--finalize` is present
4. Build the output path: `reports/retrospective/{period_id}.md`
5. If `--view` → print the path and exit
6. If the file exists and neither `--rerun` nor `--view` is set → display the existing-file message and exit

### Phase 1: Input collection (Grep-first)

Collect period-bounded inputs:

| Source | Filter | Use |
|---|---|---|
| `workspace/*/_workspace.md` | `status: active` OR (`status: completed` AND `updated` in period) | Cross-WS Themes / Contradictions / Stale |
| `workspace/*/[0-9]*-*.md` | `type: decision` AND `created` in period | Decision Digest |
| `tasks/*/_task.md` | `status: done` AND `updated` in period | Decision Digest supplement |
| `inbox/journal/*.md` | filename date in period (or `_organized/` mirror) | Self Observations candidates |
| `reports/daily/*.md` | filename date in period | Cross-WS Themes supplement |
| `reports/retrospective/{prev-week}.md` | most recent prior retrospective | Continuity (carry-over observations) |

Use `Grep` (frontmatter-only) and `Glob` for enumeration. Do **not** Read full content of every workspace at this stage — only frontmatter and the headings list. Full-text reads happen inside agent fanout (Phase 2).

### Phase 2: Agent fanout for theme-extraction and observation candidates

#### Phase 2 prologue: Build language args

Before launching either batch, call `build_language_args()` to decide whether to inject narrative-language args into each sub-agent invocation. The function is intentionally trivial — distribution default is English (sub-agent prompts are written in English), so absence of a personal override means no args are injected and the sub-agent's English default takes over naturally. No fallback logic needed on either side.

The top-of-file "Conduct ALL conversation with the user in the language defined by `.claude/rules/personal-language.md`" instruction governs the orchestrator's (main session's) user-facing utterances; this prologue governs argument injection into sub-agent invocations. They share a trigger file but operate on different surfaces — the user-facing rule has no effect on sub-agent output, which is exactly what this prologue closes.

```bash
# build_language_args()
# Returns: inject_args string (or empty if no non-English target is detected).
# Called once per skill invocation, before agent fanout.
#
# Locale detection: presence of personal-language.md is NOT a signal — the
# onboarding skill creates the file for English vaults too, and `rill init
# --lang en` likewise. We pattern-match for any Unicode codepoint in the
# range U+3040-U+30FF, which spans the Hiragana block (U+3040-U+309F) and
# the Katakana block (U+30A0-U+30FF). Both scripts are exclusive to
# Japanese — Chinese and Korean writing systems use Han / Hangul
# respectively and contain neither Hiragana nor Katakana — so a hit here is
# a near-certain ja signal. The stock-ja personal-language.md template
# contains both Hiragana (particles, verb endings) and Katakana (loanwords)
# in its body bullets, so any user-edited derivative that retains even one
# Hiragana or Katakana glyph is detected. Pure-Kanji-only Japanese content
# is the one remaining miss case (Kanji is shared with Chinese, so we cannot
# distinguish), but that style is uncommon for personal-language.md.
# Stock-en and other Latin-script vaults have no such codepoints and fall
# through to the no-injection branch.
#
# Implementation: We use `perl -CSD` (UTF-8 decode on STDIN) with the
# codepoint range above. The earlier `LC_ALL=C grep -qE $'\xe3\x81|...'`
# form relied on bash ANSI-C byte literals, which the default zsh harness
# Claude Code launches via the Bash tool does not interpret as raw bytes —
# detection silently failed under zsh and `output_language` came back empty.
# perl is in PATH on every macOS / Linux distribution that ships Claude
# Code, and Unicode codepoint regexes carry no shell-quoting ambiguity.
#
# Multi-locale detection (mapping all 9 onboarding-supported locales correctly)
# is out of scope for this task and deferred to a separate task. Doing it right
# requires a structured marker (frontmatter or sentinel comment) that bin/rill
# would have to write — and migration of existing personal-language.md files.
# Until that lands, vaults in zh / ko / fr / de / es / pt / it / en receive
# English narrative output (the same behavior as before this skill landed).

output_language=""
if [[ -f .claude/rules/personal-language.md ]] && \
   perl -CSD -e 'while(<>){if(/[\x{3040}-\x{30ff}]/){exit 0}} exit 1' .claude/rules/personal-language.md; then
  output_language="ja"
fi

if [[ -n "$output_language" ]]; then
  # style_guide is hardcoded English. Protocol sentinels listed below MUST stay
  # English literal in sub-agent output — the coordinator string-matches them
  # later (see this skill's Phase 4 render section and theme-extraction-agent
  # failure handling). Translating them would break clustering and rendering.
  style_guide='Write narrative output fields (summary, conclusion, observation, and similar prose) in the language specified by output_language. English exceptions (only): (1) tokens inside backticks, (2) proper nouns, (3) ASCII acronyms, (4) any literal sentinel string or fixed enum value documented in this sub-agent prompt'\''s Output schema or Failure handling section — including "(in progress)", "(skipped — ...)", "(could not read _workspace.md)", and confidence levels like "high"/"medium"/"low" — which must remain verbatim English regardless of output_language because the coordinator string-matches them. Translate all other English (common nouns, adjectives, verb metaphors). When translating, prefer the established target-language term (a word actually used in documents written by native speakers); if none exists, prefer a loanword form in common use; otherwise keep the English term inside backticks with a short parenthetical gloss on first use. Never invent literal calques that do not exist in the target language, and keep one consistent rendering per concept within a document.'
  inject_args="output_language: ${output_language}
style_guide: |
  ${style_guide}"
else
  # No detected non-English target. Sub-agent prompt is in English, so absence
  # of args naturally yields English output — no fallback logic needed here.
  # The top-of-file "use the user's input language if personal-language.md is
  # absent" rule governs the orchestrator's user-facing utterances only (the
  # disambiguation paragraph above states this explicitly). Sub-agent narrative
  # output uses the prompt-language default (English) until the user expresses
  # a persistent preference by running onboarding or `rill init --lang`.
  inject_args=""
fi
```

When `inject_args` is non-empty, append it as additional YAML lines to each sub-agent invocation's prompt, alongside the existing `entity_mapping`, `period_start`, etc. arguments. The `style_guide` string is hardcoded in English on purpose: the public `rillmd/rill` repo stays ASCII-only, and the string is itself an English instruction. The `output_language` value is the only locale-dependent runtime input; broader-locale support (`ko`, `zh`, `fr`, `de`, `es`, `pt`, `it`) extends the detection branch above (and requires a corresponding bin/rill change to mark `personal-language.md` with the chosen locale) without touching the sub-agent prompts or the `style_guide` content.

Launch **2 batches of 5 parallel agents** (hard ceiling ~175K tokens / run):

**Batch A — theme-extraction-agent** (5 agents, partitioned over active + period-completed workspaces, with `model: "sonnet"`):

- Each agent receives a subset of workspace paths
- Returns the YAML schema declared in `.claude/commands/_retrospective/theme-extraction-agent.md` — top-level `themes:` list where each entry has `{ name, workspace, summary, conclusion, anchor }`, plus an optional top-level `contradictions_signal:` list
- Coordinator clusters `themes` entries by `name` (with semantic fuzziness) across all 5 agent outputs. **Exclude any entry whose `name` starts with `"(skipped — "` from clustering** (per `theme-extraction-agent.md` failure-handling rules — these are read-failure markers, not real themes). Clusters spanning 2+ workspaces become "Cross-WS Themes". Within a cluster, if 2+ entries have different `conclusion` values (and neither is `"(in progress)"`), the cluster also becomes a "Contradictions" entry. `contradictions_signal` entries are intra-workspace hints used as a tie-breaker
- Prompt path: `.claude/commands/_retrospective/theme-extraction-agent.md`
- Per-invocation prompt arguments: `workspace_paths`, `period_start`, `period_end`, `entity_mapping`, plus `output_language` + `style_guide` from the prologue (omitted when `inject_args` is empty)

**Batch B — observation-agent** (5 agents, partitioned over journal + decision-artifact + prior retrospectives in the period, with `model: "sonnet"`):

- Returns: `{ candidates: [{observation, sources: [...]}] }`
- Coordinator clusters by semantic similarity; surfaces top 5–10 as checkbox candidates
- Prompt path: `.claude/commands/_retrospective/observation-agent.md`
- Per-invocation prompt arguments: `journal_paths`, `decision_paths`, `prior_retrospective_path`, `period_start`, `period_end`, plus `output_language` + `style_guide` from the prologue (omitted when `inject_args` is empty)

If the input set is empty (no active workspaces / no decisions / no journal in period), skip the corresponding batch and leave the section as "(no data this period)".

### Phase 3: In-skill deterministic sections

**Stale Workspaces**:

```bash
# All active workspaces, then filter by updated-age
Grep(pattern="^status: active", path="workspace/", glob="**/_workspace.md", output_mode="files_with_matches")
for each match:
  read frontmatter.updated (fall back to .created)
  age_days = (period_end - updated) / 86400
  if age_days > 7:
    classify:
      no artifact created in past 30 days → "close candidate"
      otherwise → "on-hold candidate"
```

**Decision Digest**:

1. Collect from two input sources (Phase 1 already gathered both, so the digest matches the declared inputs and weeks captured primarily as task completions are not dropped):
   - **Workspace decisions**: Glob `workspace/*/[0-9]*-*.md`; filter to `type: decision` AND `created` in period
   - **Completed tasks**: From the `tasks/*/_task.md` set already filtered in Phase 1 (`status: done` AND `updated` in period)
2. Extract the digest line per source:
   - For workspace decisions: Read the leading bullet section under the first `## ` heading that appears after the frontmatter (the artifact's primary "Decision" section in the user's vault language). The frontmatter `type: decision` is the canonical filter; the heading text is locale-specific and not pattern-matched
   - For completed tasks: use the task title (H1 or frontmatter-derived) plus its `## Goal` first line as the digest summary
3. Score:
   - Workspace decisions: `(WS status weight 1.0 active / 0.8 completed-in-period) × (count of mentions in decision body)`
   - Completed tasks: `(0.9) × (count of mentions in _task.md body)` — slightly below active-WS decisions but above completed-WS decisions, reflecting that finished tasks usually represent settled, lower-volatility outcomes
4. Merge both source lists, sort by score, take top 7. Tag each entry with its source kind (`decision` / `task`) so the rendered digest can hint at provenance for the reader

### Phase 4: Render the retrospective file

Generate `reports/retrospective/{period_id}.md`. Handle the fresh-run vs `--rerun` cases differently so the original `created` frontmatter is preserved across reruns (idempotency contract from the "Idempotency" section above):

```bash
target="reports/retrospective/{period_id}.md"

if [[ -e "$target" && "${RERUN:-}" ]]; then
    # --rerun: keep frontmatter `created` immutable, only refresh `updated`. Do NOT
    # call rill mkfile here — it would generate a new file with today's timestamp
    # and overwrite the historical `created`. Instead, Edit the frontmatter
    # `updated:` field in place (or insert it if missing) and clear the body below
    # the frontmatter so Phase 4 can re-render the 5 sections.
    edit_frontmatter_field "$target" updated "$(date_iso_now)"
    truncate_body_below_frontmatter "$target"
else
    # Fresh run: rill mkfile reports/* ignores --slug and writes {today}.md
    # (bin/rill cmd_mkfile branch for reports/*). Use mkfile to get the correct
    # `created` frontmatter (ADR-060), then rename to {period_id}.md so the rest
    # of this skill, /pulse latest-retrospective read, and --finalize / --view
    # paths all resolve against the canonical weekly-* filename.
    mkfile_out="$(rill mkfile reports/retrospective --type retrospective \
      --field "period={period_id}")"
    mv "$mkfile_out" "$target"
fi
```

Then Edit the body to fill the 5 sections in this exact order (dependency contract — do not reorder; `/pulse` parses `## Contradictions` by name):

```markdown
# Retrospective — {period}

## Cross-WS Themes

### Theme: {short name}

{1-2 line summary}

Multi-WS:
- [{WS A name}](../../workspace/{id}/_workspace.md): {1-line excerpt}
- [{WS B name}](../../workspace/{id}/_workspace.md): {1-line excerpt}

(Up to 5 themes. If empty, write "(no cross-WS themes detected this period)")

## Contradictions

### Contradiction 1: {theme}

- **WS A**: {conclusion X} — [source]({path})
- **WS B**: {conclusion Y} — [source]({path})
- **Proposed action**: {integrate / prefer one / defer to next /focus}

(Up to 5 entries. **If empty, keep the heading and write "(no contradictions this period)"** — `/pulse` reads this section to populate self/current-state.md "known contradictions", so the heading must always be present for downstream parsing.)

## Stale Workspaces

| WS | Last updated | Days stale | Suggestion |
|---|---|---|---|
| [{name}](../../workspace/{id}/_workspace.md) | YYYY-MM-DD | Nd | close / on-hold |

(If no stale workspaces, write "(no stale workspaces)")

## Decision Digest

- YYYY-MM-DD: {1-line decision summary} (source [{name}](../../path))

(Up to 7 entries. If empty, write "(no decisions recorded this period)")

## Self Observations

Candidates below. Run `/retrospective --finalize {period}` to review them interactively — the assistant asks which to adopt and handles the checkboxes. (Manual fallback: mark `[x]` yourself, then run the same command.) Unmarked items are dropped at finalize.

- [ ] {observation text} (sources: [{name1}]({path1}); [{name2}]({path2}); …)

Each candidate carries the **full** sources list returned by the observation-agent (typically 2–3 entries; see `_retrospective/observation-agent.md` "Output schema requirements" — recurrence requires ≥2 sources). Always emit the parenthetical in the plural form (`sources:` with `;`-separated entries), even when there happens to be only one source — keeps `--finalize`'s parser regex single-shape.

(Up to 10 candidates. If empty, omit the section body but keep the heading.)
```

### Phase 5: Auto-flush to self/decisions.md

After the file is written, append the Decision Digest entries to `knowledge/self/decisions.md`:

- Format: `- {YYYY-MM-DD}: {decision} (source [{name}]({path})) [retrospective: {period_id}]`
- 3-month (90-day) window: before appending, drop any existing entries whose date is older than 90 days
- Dedup: skip entries whose `(source path)` is already present

Update the state sidecar using **merge-write semantics** (do not replace the whole file): read the existing JSON object, mutate only the four fields owned by `/retrospective`, then write the merged object back. Fields owned by `/briefing` (`nudge_state`, `skipped_periods`) and any future writer must be preserved untouched.

```bash
mkdir -p .claude/state

# 1. Read current state (treat missing file or parse error as an empty object {})
existing="$(read_json_or_empty .claude/state/retrospective.json)"

# 2. Merge: only the four fields below belong to this skill. All other top-level
#    fields (notably nudge_state and skipped_periods, written by /briefing Step E)
#    must round-trip unchanged.
merged="$(jq_merge "$existing" '{
  last_run_at: <now ISO 8601>,
  last_period: ( . // "" | max_iso( "{period_id}" ) ),   # string-compare two weekly-YYYY-MM-DD values; ASCII order == ISO date order because the "weekly-" prefix is identical. --rerun of an older period must NOT rewind last_period (the briefing nudge gate keys on the latest completed period)
  pending_finalize: ( . // [] | unique_append( "{period_id}" ) ),  # dedup against existing entries
  run_count: ( . // 0 | + 1 )
}')"

# 3. Write back atomically
write_atomic .claude/state/retrospective.json "$merged"
```

`{period_id}` here is the canonical `weekly-YYYY-MM-DD` string defined in Phase 0 step 2 — do not re-prepend `weekly-`. The pseudocode helpers (`read_json_or_empty`, `jq_merge`, `write_atomic`) are stand-ins for whatever JSON read-modify-write the harness has on hand; what matters is the **field-level merge semantic**, not the specific implementation.

### Phase 6: --finalize path (separate invocation, or offered right after Phase 4)

When invoked with `--finalize [{period_arg}]`:

1. Resolve the target periods:
   - `{period_arg}` given → normalize into the canonical `period_id`: if it already starts with `weekly-` or `monthly-` (the form stored in `last_period` / `pending_finalize`), use it verbatim; otherwise prepend `weekly-` (e.g. `2026-04-27` → `weekly-2026-04-27`). Targets = that one period. Final path: `reports/retrospective/{period_id}.md`. Error if missing
   - `{period_arg}` omitted → targets = every period in the state sidecar's `pending_finalize`, oldest first (the backlog sweep). If the list is empty, report "no periods pending finalize" and exit
2. Collect candidates: for each target period, Read the file's `## Self Observations` section; extract both `- [ ]` and `- [x]` lines of the form `{marker} {text} (sources: {source1}; {source2}; …)` — `{text}` plus the **full** semicolon-separated `sources` list (each entry is itself a Markdown link). Phase 4 always emits the plural `sources:` form (even single-source candidates), so a single regex shape is sufficient
3. Collect approval — **interactive by default**:
   - In an interactive session, never tell the user to go edit checkboxes in the file. Present the unchecked candidates through the harness's question primitive as **multi-select** questions: group candidates thematically, up to 4 options per question, and run as many question batches as needed to cover every candidate. Each option carries a short label plus the full observation text and its period as the description, written in plain language (no internal IDs)
   - When targets span multiple periods, first cluster near-duplicate candidates across periods (the same pattern re-observed in consecutive weeks): present the most refined / most recent wording once, noting it subsumes the earlier variant. On adoption, mark only the presented line `[x]`; the subsumed older variants stay unchecked and are dropped
   - **Fallback when the harness's question primitive cannot express multi-select or 4-option questions** (e.g. Codex CLI's mutually-exclusive single-choice prompt): do not abandon the interactive path. Fall back to either (a) one yes/no question per candidate, or (b) a single free-text prompt that lists the candidates as a numbered list and asks the user to reply with the numbers to adopt (e.g. "1, 3, 5" or "all" / "none"). Parse the reply and proceed identically
   - Lines the user already marked `[x]` by hand count as approved — exclude them from the questions
   - After the answers, the skill writes `[x]` into the file(s) on the user's behalf for every adopted candidate. The checkbox in the file stays the durable record; the question flow is merely how approval is collected
   - **Unattended runs** (`claude -p`, cron, autonomous mode): never block on a question. Process only pre-marked `[x]` lines; if there are none, report the pending candidate count and exit without modifying anything
4. For each approved `[x]` line, append to `knowledge/self/observations.md`:
   - Format: `- {YYYY-MM-DD finalize date}: {observation text} (sources: {source1}; {source2}; …, retrospective: {period_id})`
   - The provenance carries `{period_id}` verbatim (e.g. `retrospective: weekly-2026-04-27`), regardless of whether the user passed the prefixed or bare form
   - All sources extracted in step 2 are preserved in the appended line (no truncation to a single source)
   - Dedup by `(observation text + sorted sources tuple)` key; skip duplicates silently
5. Update each processed retrospective file: change `[x]` → `[X]` (uppercase) so re-finalize is idempotent
6. Update state sidecar: remove every processed `period_id` from `pending_finalize`

Do not regenerate any other section.

**Chaining from Phase 4**: in an interactive session, after a weekly file is generated (Phase 4/5 complete), offer to run this phase for the fresh period immediately — approval is cheapest while the week is still in the user's head. Declining leaves the period in `pending_finalize` for a later `--finalize` sweep.

### Phase 7: Reporting

Print to stdout:

- Path to the generated file (as a Markdown link) so the user can paste it into the Rill GUI header search
- Decision Digest line count, Self Observations candidate count, Stale Workspaces count
- If `--finalize`: periods processed, observations adopted (appended to `self/observations.md`), and candidates dropped

Do **not** invoke `rill open`. The user opens files via the GUI header search box (`Cmd+P`).

## Token budget

| Step | Tokens |
|---|---|
| Phase 1 frontmatter / headings collection | ~15K |
| Phase 2 agent fanout (5 + 5 = 10 agents × ~30K cap) | ≤ 150K |
| Phase 3 in-skill deterministic | ~10K |
| User session inflow (summary only) | ~30-40K |
| Hard ceiling per /retrospective invocation | ~175K |

Weekly cadence makes this affordable. If active workspaces exceed 60, raise agent count from 5 to 8 in each batch or partition more aggressively.

## Failure modes

- `inbox/journal/` empty for the period → Self Observations section becomes "(no journal data this period)"
- All active workspaces are stale → Stale Workspaces section will dominate; that is itself a signal
- One or more agent invocations time out / fail → log the failure, continue with reduced data, mark the affected section "(partial — N agents failed)"
- `.claude/state/retrospective.json` parse error → log a warning, proceed as if state is empty
- `/retrospective --finalize` invoked before any retrospective exists → error out cleanly

## Rules

- Source files under `inbox/` are read-only — never modify them
- `self/observations.md` only ever grows from `--finalize` user-approved entries — never auto-append observations
- `self/decisions.md` is the only auto-append target for this skill, and only within the 3-month window
- Use Markdown links `[display name](relative-path)` for in-body references; backtick-only ID references are forbidden
- Always end any reports section with a brief sources list when the section cites external work
- Never call `/distill` or any chain target from this skill; /retrospective is a leaf (the /pulse read direction is one-way)

## See also

- `skills/pulse/SKILL.md` — sister skill (Self Snapshot Refresh); its Section 7 parses this skill's `## Contradictions` output
- `skills/briefing/SKILL.md` — Step E hosts the Thursday nudge that triggers this skill
