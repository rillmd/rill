# /morning — Morning Routine

Runs the two user-facing daily reports in sequence: Daily Note (/briefing) and research newsletter (/newsletter). Both run inline within the current Claude Code session via the Skill tool.

Background processing (external source sync, knowledge distillation) is **not** part of /morning (ADR-075). When you want to catch up, ask inside your vault — *"pull in new entries and extract anything useful"* — and Claude will route to `/sync` then `/distill`. For unattended automation, see [docs/guides/scheduling.md](../../docs/guides/scheduling.md).

## Why sequential (not parallel)

Earlier revisions of /morning spawned `/briefing` and `/newsletter` as parallel `claude -p` sub-processes. When the parent session runs in `auto` mode (the recommended default), the classifier reliably refuses to spawn in-session sub-agents with elevated permissions — this is the classifier's intended behavior, not a bug. Inline Skill-tool invocation stays inside the user's single top-level intent ("run my morning routine"), so each underlying tool call is judged routine and no subprocess spawn is attempted. Runtime cost: roughly 2–3 minutes longer than the old parallel pipeline.

## Dependencies

```
Step 1: /briefing
Step 2: /newsletter
Step 3: Completion summary
```

Neither skill depends on the other's output. /briefing reads yesterday's activity window; /newsletter is WebSearch-based.

## Arguments

$ARGUMENTS — none

## Procedure

### Step 1: Daily Note (/briefing)

Invoke the `briefing` skill via the Skill tool and wait for it to complete. Capture the path of the generated Daily Note from the skill's summary output.

### Step 2: Newsletter (/newsletter)

Invoke the `newsletter` skill via the Skill tool and wait for it to complete. Capture the path of the generated newsletter.

If /briefing failed in Step 1, still run /newsletter — the two are independent.

### Step 3: Completion summary

Concisely summarize the execution result of each skill:
- /briefing: path of generated Daily Note + success/failure
- /newsletter: path of generated newsletter + success/failure

The Daily Note already surfaces unprocessed inbox counts and recommends `/sync` and `/distill` when there is pending work (see /briefing's Notes section). The morning summary does not need to duplicate that.

After the summary, exit (do not transition to assistant mode).

## Rules

- Both skills run in the current session via the Skill tool. Do **not** spawn `claude -p` sub-processes from this skill
- Sequential execution. Parallel was tried and abandoned because the `auto` mode classifier (correctly) refuses skill-initiated subprocess spawns with elevated permissions
- If /briefing fails, still attempt /newsletter (they are independent)
- After everything completes, display the summary and exit
- Do not call `/sync` or `/distill` from inside /morning (ADR-075)
