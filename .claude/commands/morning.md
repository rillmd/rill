# /morning — Morning Routine

**Conduct ALL conversation with the user in the language defined by `.claude/rules/personal-language.md`** (or the user's input language if absent). The English instructions below are for skill clarity, not for output style. Exceptions: code blocks, slash commands, technical terms (Markdown, frontmatter, etc.).

Runs the two user-facing daily reports concurrently: Daily Note (/briefing) and research newsletter (/newsletter). Both run as isolated sub-agents in parallel via the Agent tool.

Background processing (external source sync, knowledge distillation) is **not** part of /morning (ADR-075). When you want to catch up, ask inside your vault — *"pull in new entries and extract anything useful"* — and Claude will route to `/sync` then `/distill`. For unattended automation, see [docs/guides/scheduling.md](../../docs/guides/scheduling.md).

## Why Agent tool (not Skill tool, not `claude -p`)

Earlier revisions chained `/briefing` and `/newsletter` via the Skill tool inside /morning. That was probabilistically broken: each child skill ends with "Display a summary and finish — do not transition to assistant mode," and the LLM frequently interpreted that finish instruction as the end of /morning itself, silently skipping /newsletter.

This revision delegates each report to a separate sub-agent via the Agent tool. Sub-agents run in **isolated contexts**, so a child skill's "finish" terminates only that sub-agent — control structurally returns to /morning. The fix is harness-level, not prompt-level. As a side benefit, both reports run in parallel, cutting wall-clock time roughly in half.

An even earlier revision used `claude -p --output-format stream-json` subprocesses for the same parallelism. That hit a different wall: in `auto` mode the harness reliably refuses skill-initiated subprocess spawns with elevated permissions — by design. Agent tool sub-agents are **in-process** and do not trigger that classifier; they inherit the parent's existing permission context.

Tradeoff: each sub-agent loads the corresponding skill into its own context, so total token cost is somewhat higher than the old Skill-tool chain. Acceptable in exchange for deterministic execution.

## Arguments

$ARGUMENTS — one of the following:
- `YYYY-MM-DD` (e.g. `2026-03-11`) → both reports target the specified date
- Omitted → both reports target today

## Procedure

### Step 1: Spawn briefing and newsletter as parallel sub-agents

Issue **two Agent tool calls in a single assistant message** so they execute concurrently. Use `subagent_type: general-purpose` for both — it has Skill tool access in its toolset.

Each agent prompt must:
- Instruct the sub-agent to invoke the corresponding skill (`briefing` or `newsletter`) via the Skill tool
- Pass through any date argument received by /morning (default: today)
- Require the sub-agent to return a tight machine-readable summary of the result

Concrete agent prompts:

```
Agent 1 — description: "Run /briefing"
  subagent_type: general-purpose
  prompt: |
    Invoke the `briefing` skill via the Skill tool with argument
    "<DATE_ARG_OR_EMPTY>". Wait for it to complete. Then return
    exactly this format and nothing else:

      path: <repo-relative path to generated daily note>
      status: <success | failure>
      error: <one-line error message if failure, omit if success>

    Do not paraphrase the daily note's content; only return the
    structured summary above.

Agent 2 — description: "Run /newsletter"
  subagent_type: general-purpose
  prompt: |
    Invoke the `newsletter` skill via the Skill tool with argument
    "<DATE_ARG_OR_EMPTY>". Wait for it to complete. Then return
    exactly this format and nothing else:

      path: <repo-relative path to generated newsletter>
      status: <success | failure>
      error: <one-line error message if failure, omit if success>

    Do not paraphrase the newsletter content; only return the
    structured summary above.
```

If /morning was called with `YYYY-MM-DD`, substitute that string for `<DATE_ARG_OR_EMPTY>`. If called without an argument, pass an empty string (each child skill defaults to today).

### Step 2: Completion summary

After both sub-agents return, write a concise summary (under 5 lines):

- `/briefing`: path of the generated Daily Note + success/failure
- `/newsletter`: path of the generated newsletter + success/failure

The Daily Note already surfaces unprocessed inbox counts and recommends `/sync` and `/distill` when there is pending work (see /briefing's Notes section). The /morning summary does not need to duplicate that.

After the summary, exit (do not transition to assistant mode).

## Rules

- Both sub-agents are spawned in **one** assistant message so they execute in parallel. Do not serialize them — sequential Agent calls defeat the parallelism this revision delivers.
- Do **not** invoke `/briefing` or `/newsletter` directly via the Skill tool from /morning. That reintroduces the child-finish leak this revision exists to eliminate.
- Do **not** spawn `claude -p` sub-processes from /morning. That hits the auto-mode classifier.
- If one sub-agent fails, still report the other's result — they are independent.
- Do not call `/sync` or `/distill` from inside /morning (ADR-075).
