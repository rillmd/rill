---
name: close
description: "Close a Rill workspace in two stages. Stage 1 (default, interactive, about a minute) records how it ended and the conclusion, turns open items into tasks, and moves it to distill-pending with `rill workspace close`. Stage 2 (`--distill <id>`, interactive or `--unattended` for the night distill job) runs the analysis and distillation sub-agents, records every candidate and outcome in the CLI-owned distill record, and reaches completed only through `rill workspace complete`, which verifies the record. Use when the user asks to close, complete, or wrap up a workspace, or when /focus proposes completion."
gui:
  label: "/close"
  hint: "Close workspace (distillation follows)"
  match:
    - "workspace/**/*.md"
  arg: workspace-id
  order: 20
  mode: auto
---

# /close — Workspace Close and Distillation

**Conduct all conversation with the user — and write all generated output — in the language defined by `.claude/rules/personal-language.md`** (or the user's input language if that file is absent). Follow the language rules in full — exceptions and translation quality are defined in the Language Rules of `.claude/rules/rill-core.md` and the vault's `personal-*.md` overrides, never restated per skill. The English instructions below are for skill clarity, not for output style.

> **Tool references in this skill** (`Read`, `Edit`, `Grep`, `AskUserQuestion`, the `Agent` tool's `subagent_type`, `model: "sonnet"`) describe **intent**, not Claude-specific tool calls. Each harness should map them to its native equivalent. On Codex CLI: sub-agent fan-out (`Agent` / `subagent_type`, including the parallel Distillation sub-agents below) maps to Codex's own sub-agent mechanism where one is available, or runs sequentially in the current session when it isn't; a named `model` is a preference for an equivalent lighter/faster model, falling back to the session default. `AskUserQuestion` maps to a plain free-text question in an interactive session; in an unattended run it must not block — write a `[DECISION-QUEUE]` entry instead, per the decision-loop contract (ADR-084, `.claude/rules/rill-autonomous-execution.md` §9).

Closes a workspace in two stages so that closing is cheap and distillation is never skipped. Stage 1 runs in the conversation and takes about a minute. Stage 2 — the knowledge distillation — runs later, usually unattended in the night distill job, and the workspace reaches `completed` only when the distill record verifies.

## State model (read first)

`_workspace.md` `status` takes three values (`rill-workspace.md`):

| Value | Meaning |
|---|---|
| `active` | being worked on (a waiting workspace stays `active` with `snooze-until` + `snooze-reason`) |
| `distill-pending` | closed; knowledge distillation not yet verified. The set of these workspaces is the distill queue |
| `completed` | closed, and the distill record passed `rill workspace verify` |

**Never write `status` (or `closed`, `distilled`, `distill-*`, `snooze-*`) with Edit, and never edit `_distill.md`.** Every transition goes through `rill workspace` (`close`, `reopen`, `requeue`, `complete`, `snooze`), and only `rill workspace complete` writes `completed` — after it verifies the record mechanically. Legacy `on-hold` workspaces are accepted as the source of Stage 1 during the migration.

## Arguments

$ARGUMENTS — one of the following:

- workspace/ path or id (e.g., `workspace/2026-02-13-rill-development/` or `rill-development`) → **Stage 1**: close the workspace
- Omitted → Stage 1 with auto-detection (`active` workspaces)
- `--distill <id>` → **Stage 2** in this session (interactive): distill a `distill-pending` workspace now and complete it if the record verifies
- `--distill <id> --unattended` → **Stage 2** as run by the night distill job under `claude -p`. The job wrapper owns `rill workspace distill begin`, `rill workspace complete`, and `rill workspace distill end`; the skill only records the analysis and outcomes, never prompts, and never calls `complete`. The wrapper exports `RILL_DISTILL_RUN` (the run number `begin` printed) and `RILL_DISTILL_UNATTENDED=1`; the record commands read them, so a worker of a run that was taken over cannot write into its successor
- Add `--auto-approve` to suppress approval / confirmation prompts in an interactive run (integration tests under `claude -p`): Stage 1 infers the close kind, conclusion, and hint and leaves related task statuses unchanged; Stage 2 behaves as interactive without prompts (it still owns begin / complete / end)

## Architecture (why this skill is structured the way it is)

Earlier versions did everything in one pass and set `status: completed` in the parent at the end, with the coverage self-check held only in the parent's context. Two problems followed: closing a small workspace cost a full distillation, so workspaces were left open; and nothing on disk showed whether a `completed` workspace had really been distilled.

The two-stage design fixes both:

1. **Stage 1** records how the workspace ended and moves it to `distill-pending` — the queue.
2. **Stage 2** keeps the ADR-073 two-layer structure — an **Analysis sub-agent** (fresh context, reads every coverage file, writes `_summary.md`, enumerates candidates) and one **Distillation sub-agent** per candidate (fresh context, cross-deliverable verification, one atomic note or one justified skip) — but every result goes to the CLI-owned distill record (`_distill.md`) instead of the parent's memory.
3. **`rill workspace complete`** is the only path to `completed`. It recounts the record and refuses unless the analysis finished, every coverage file was accounted for, every candidate has exactly one outcome, every referenced note exists, and `_summary.md` exists. A crashed, interrupted, or partial run therefore leaves the workspace `distill-pending`, and the next run resumes from the candidates without outcomes.

Sub-agents run in the foreground (the parent waits in the same response) and return one line each; details live in files. This keeps the parent's context flat regardless of workspace size.

## Stage 1 — close (interactive, about a minute)

### S1.0 Identify the workspace

1. If an argument is given, read the metadata file in `workspace/{id}/` (priority: `_workspace.md` > `_session.md` > `_project.md`; `rill workspace` resolves the same order and never renames legacy files)
2. If omitted, list workspaces with `status: active`; if several, ask which one (AskUserQuestion); if none, say so and exit
3. Check `status`:
   - `active` (or legacy `on-hold`) → continue
   - `distill-pending` → say it is already closed and queued; offer `/close --distill {id}` to distill now; exit
   - `completed` → say it is already completed; exit

### S1.1 Ask how it ended (one question)

Read `_workspace.md` (completion conditions, Next Steps, latest Session History) and propose defaults, then confirm with one AskUserQuestion carrying three choices:

- **Close kind** (`--kind`): `done` (completion conditions met), `concluded` (a conclusion was reached, even if loose), `abandoned` (stopped; record why), `superseded` (moved to another workspace or project; record where)
- **Conclusion**: 1–3 sentences in the user's language stating what was decided or learned, drafted by you for the user to accept or edit
- **Distill hint** (`--hint`): `full`, `partial`, or `none` — your estimate of how much reusable knowledge the workspace holds. It is a hint passed to the Analysis sub-agent, **never a reason to skip distillation**: every workspace is distilled

Under `--auto-approve`, use the proposed defaults without asking.

### S1.2 Record the close in `_workspace.md`

Edit the body (not the frontmatter):

- Add or replace a `## Closing` section: close kind, the conclusion, today's date, and for `superseded` a link to the successor
- Append a line to `## Session History`

### S1.3 Task extraction from unchecked items

- All checklist items `[x]` → skip
- Unchecked items → Read `.claude/commands/_distill/task-extraction.md`, extract task candidates, check duplicates against existing tickets, and create them with `rill task` (ADR-069: as draft)

### S1.4 Related task sync

1. `Grep(pattern="{workspace id}", path="tasks/", glob="**/_task.md", output_mode="files_with_matches")` for tasks referencing the workspace in `source:` or `related:`
2. Keep tasks with `status` `open` / `waiting` / `draft`
3. Judge from `_workspace.md` and the conclusion whether each was completed within the workspace
4. Show the judgment table and confirm via AskUserQuestion; approved → `status: done` via Edit and a History line "Transitioned to done upon closing workspace {id}". Under `--auto-approve`, show the table and change nothing

### S1.5 Move to the queue

```bash
rill workspace close {id} --kind {kind} --hint {hint}
```

This writes `status: distill-pending` and `closed:`, clears `snooze-*`, and starts a new round in `_distill.md`. If it refuses (for example exit 3: a distill run holds the lock), report the message and stop.

### S1.6 /pulse refresh

Invoke `/pulse` via the Skill mechanism (synchronous; it has its own cooldown). Failure is non-fatal: log one line and continue.

### S1.7 Report

Tell the user, in their language: the workspace is closed and waiting for distillation; its position from `rill workspace queue`; that a scheduled distill job (if the vault runs one) will distill it, and `/close --distill {id}` does it now; the tasks created or synced. Until distillation completes the workspace stays `distill-pending` — it is not `completed` yet. If the workspace had actionable items, mention that `/promote {id}` is available after distillation (it needs `_summary.md`).

## Stage 2 — distill (`--distill {id}`)

### S2.0 Preconditions and the run lock

1. `rill workspace distill show {id} --json` and read `status`, `analysis_complete`, `pending`, `open_run`, `coverage`, `hint`
2. `status` must be `distill-pending`; otherwise stop (`active` → it must be closed first; `completed` → nothing to do)
3. Lock ownership:
   - **Interactive** (no `--unattended`): run `rill workspace distill begin {id}` and keep the run number it prints. Exit 3 means another run holds the lock — stop and report it
   - **Unattended**: the wrapper already ran `begin`. If `open_run` is null, stop with an error line — do not call `begin` yourself

### S2.1 Shared context (once, in the parent)

1. Read the "Topic Tags" table from `taxonomy.md` and generate **YAML list format (name + desc)** (exclude deprecated tags)
2. **Run `rill context-map` once** and capture its output (deterministic, 0 LLM tokens, sub-second — frontmatter only). Its `### People mapping` / `### Orgs mapping` / `### Projects mapping` sections are the one-line entity mappings, and `### Entity IDs` is the entity-ID list for post-processing `rill strip-entity-tags`. Do not read the entity files in the parent. (`### Tier dict` is not used here.)

### S2.2 Build language args

Before launching the Analysis sub-agent (S2.3) or the Distillation sub-agents (S2.4), call `build_language_args()` to decide whether to inject narrative-language args into each sub-agent invocation. Distribution default is English (sub-agent prompts are written in English), so absence of a personal override means no args are injected.

The top-of-file language instruction governs the orchestrator's user-facing utterances; this prologue governs argument injection into sub-agent invocations.

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
  # later (see analysis-agent.md Language section and distillation-agent.md
  # Language section). Translating them would break clustering, rendering, and
  # the parent's self-check / aggregation logic.
  style_guide='Write narrative output fields (summary, rationale, observation, note body prose, and similar free text) in the language specified by output_language. English exceptions (only): (1) tokens inside backticks, (2) proper nouns, (3) ASCII acronyms, (4) any literal sentinel string or fixed enum value documented in this sub-agent prompt'\''s Output schema or Language section — including structured IDs (`D-{ws-short}-{n}`, `IA-{ws-short}-{n}`, `L1-{n}`, `L2-{n}`), slugs, paths, type enum values (`record`/`insight`/`reference`), priority labels (`HIGH`/`LOW`), status labels (`created`/`updated`/`skipped`), justification labels (`EVERGREEN_DUPLICATE`/`INTERMEDIATE_CONCLUSION`/`IMPLEMENTATION_DETAIL`/`MERGED_INTO_OTHER`), and the section-empty sentinel `"(No invalidated approaches in this workspace.)"` — which must remain verbatim English regardless of output_language because the coordinator string-matches them. Translate all other English (common nouns, adjectives, verb metaphors). When translating, prefer the established target-language term (a word actually used in documents written by native speakers); if none exists, prefer a loanword form in common use; otherwise keep the English term inside backticks with a short parenthetical gloss on first use. Never invent literal calques that do not exist in the target language, and keep one consistent rendering per concept within a document.'
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

When `inject_args` is non-empty, append it as additional YAML lines to **each** sub-agent prompt in S2.3 and S2.4, alongside the placeholder substitutions.

### S2.3 Analysis (skip when `analysis_complete` is true)

A resumed run whose round already has a complete analysis skips straight to S2.4 — the candidates are in the record.

Read `.claude/commands/_close/analysis-agent.md` and fill in:

- `{workspace_id}` — the id
- `{coverage_files}` — the `coverage` list from `distill show --json`, one path per line (relative to the workspace directory)
- `{distill_hint}` — the `hint` value (or `full` when absent)
- `{analysis_file}` — `.rill/state/distill/{id}-analysis.json`
- `{shared_context_placeholder}` — tag vocabulary and entity mappings from S2.1

Append `inject_args` when non-empty. Spawn one sub-agent (Agent tool, `subagent_type: general-purpose`) in the **foreground** and wait. It writes `_summary.md`, records the analysis with `rill workspace distill analysis`, and returns one line:

- `ANALYSIS_RECORDED files={N} candidates={M}` → re-run `rill workspace distill show {id} --json` and take `pending` (each entry has `source_path`) and `invalidated`
- anything else → the analysis is not recorded; go to S2.7 with the run failed (reason `analysis`)

### S2.4 Distillation (one sub-agent per pending candidate)

Read `.claude/commands/_close/distillation-agent.md` once. For each pending candidate fill in:

- `{candidate_json}` — the candidate object from `pending` (includes `source_path`)
- `{workspace_id}` — the id
- `{deliverable_moc}` — every coverage file with a one-line description (build it from `_summary.md`'s Deliverables table)
- `{invalidated_list}` — the `invalidated` entries
- `{shared_context}` — from S2.1

Append `inject_args` when non-empty. Dispatch with **`model: "sonnet"`** (Tier 2 LLM-as-judge eval, 2026-04-19: 3/3 EQUIVALENT vs Opus on this workload at about half the cost), **in the foreground, in batches of up to 5 Agent calls per response**; wait for the batch to return before sending the next. Never use `run_in_background` — an unattended run must not end its turn while sub-agents are still writing.

Each sub-agent writes its note (or decides a skip) and records its own outcome with `rill workspace distill outcome`, then returns one line: `OUTCOME {cid} {status} {path-or-label}` or `OUTCOME_FAILED {cid} {reason}`. Keep only these lines in the parent.

After all batches, re-run `distill show --json`. Retry each candidate still in `pending` once (same template). Candidates still pending after the retry:

- interactive → list them and ask: retry again, record a skip the user approves (`--label USER_DECLINED --reason "{user's reason}"`), or stop. Never record `USER_DECLINED` without the user's explicit answer
- unattended / `--auto-approve` → leave them pending; go to S2.7 with the run failed (reason `pending candidates`). The next run resumes them

### S2.5 Duplicate notes created in the same run

If two `created` outcomes in this run produced notes with near-identical slugs or overlapping content: merge the content into the richer note, delete the other note, and amend the deleted note's outcome so the record stays true:

```bash
rill workspace distill outcome {id} --cid {loser} --status skipped --label MERGED_INTO_OTHER --into {winner} --reason "duplicate created in the same run" --amend
```

### S2.6 Post-processing

- For each `NNN-*` deliverable without `mentions` / `tags`, add them from the shared context (frontmatter Edit; deliverables are otherwise immutable)
- `rill strip-entity-tags` on the created notes
- Append new tags (if any) to `taxonomy.md`
- Entity detection: new entities in the created notes' `mentions` → create the entity files if missing
- Pages pending update: write the workspace metadata path plus every **created** note path (not updated ones) to a tmp file, one per line, and run `rill pages-pending-update --sources-file "$tmp" --origin close`. Do not pass `--force` on a `⚠ bulk update detected` warning — report it instead

### S2.7 Verify, complete, end

- **Interactive**:
  1. `rill workspace complete {id}` — it runs every verify check and writes `completed` only if all pass. On refusal it prints the failed checks; the workspace stays `distill-pending`
  2. `rill workspace distill end {id} --run {run} --result completed` when `complete` succeeded; otherwise `--result failed --reason "{first failed check}"` (`{run}` is the number `begin` printed)
- **Unattended**: do **not** call `complete` or `end`. Finish the turn; the wrapper runs `complete` only if `claude -p` exits 0 and then records the run end. If you stopped early (analysis not recorded, candidates left pending), say so in the final line so the log shows why

### S2.8 Report

From `rill workspace verify {id} --json` (totals) and the one-line returns:

```markdown
## /close --distill complete — {workspace_id}

- Status: completed | still distill-pending ({failed checks})
- Candidates: {N} — created {X}, updated {Y}, skipped {Z} (by label), without outcome {W}
- Created notes: knowledge/notes/... (one per line)
- _summary.md: workspace/{id}/_summary.md
```

## Rules

- **Never write workspace `status` by hand** and never edit `_distill.md`; use `rill workspace` subcommands. Only `rill workspace complete` writes `completed`
- **Every workspace is distilled.** The distill hint and the close kind never skip Stage 2
- Knowledge distillation runs in sub-agents (ADR-073), not in the parent. Sub-agents run in the foreground and return one line
- **Forbidden justifications**: `pragmatic scope reduction`, `to save time`, `not novel enough`, `context budget running low`, `already sufficient coverage`, and any unlabeled reason. The CLI refuses them too. See `.claude/commands/_close/distillation-agent.md`
- `USER_DECLINED` only with the user's explicit answer in an interactive run (the CLI refuses it when `RILL_DISTILL_UNATTENDED=1`)
- Never modify `inbox/journal/` and `inbox/*/` original files (read-only)
- Include frontmatter in all files (generated HTML excepted — `rill-html-output.md`)
- No workspace handbook and no `/promote` chain in /close: the handbook is generated only on explicit request, and `/promote` runs after Stage 2 when the user wants it

## Related files

- `.claude/commands/_close/analysis-agent.md` — Stage 2 Analysis sub-agent prompt template
- `.claude/commands/_close/distillation-agent.md` — Stage 2 Distillation sub-agent prompt template
- `.claude/commands/_close/handbook-agent.md` — handbook template (not invoked by /close; explicit request only)
- `.claude/commands/_distill/knowledge-agent.md` — Evergreen check procedure used by distillation-agent.md
- `.claude/commands/_distill/task-extraction.md` — task extraction rules (S1.3)
- `lib/workspace/rill_workspace.py` — `rill workspace`: transitions, distill record, verify, queue, check
- ADR-073 (private, rill-dev `docs/decisions/`) — two-layer sub-agent delegation rationale
- `docs/skill-specs/close.md` — IAD (rule table for testing)
