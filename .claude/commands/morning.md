# /morning — Morning Routine

Runs the two user-facing daily reports in parallel: Daily Note (/briefing) and research newsletter (/newsletter). Each runs as an independent process (`claude -p`) to isolate context and bypass nesting limits (ADR-058).

Background processing (external source sync, knowledge distillation) is **not** part of /morning (ADR-075). Run `/sync` and `/distill` manually when you want to catch up, or see `docs/guides/scheduling.md` for ways to automate them.

## Dependencies

```
Step 1: /briefing + /newsletter  (parallel)
Step 2: Completion summary
```

/briefing reads an activity window covering yesterday's data, so it does not depend on today's /sync or /distill output. /newsletter is WebSearch-based and equally independent. This lets both run in parallel with no ordering constraint.

## Arguments

$ARGUMENTS — none

## Procedure

### Step 1: Daily Note + Newsletter (parallel)

Run the following with Bash:

```bash
claude -p "/briefing" --permission-mode bypassPermissions --model sonnet > /tmp/rill-morning-briefing.log 2>&1 &
BRIEFING_PID=$!

claude -p "/newsletter" --permission-mode bypassPermissions --model sonnet > /tmp/rill-morning-newsletter.log 2>&1 &
NEWSLETTER_PID=$!

BRIEFING_EXIT=0
NEWSLETTER_EXIT=0
wait $BRIEFING_PID || BRIEFING_EXIT=$?
wait $NEWSLETTER_PID || NEWSLETTER_EXIT=$?

echo "=== /briefing (exit: $BRIEFING_EXIT) ==="
tail -20 /tmp/rill-morning-briefing.log
echo ""
echo "=== /newsletter (exit: $NEWSLETTER_EXIT) ==="
tail -20 /tmp/rill-morning-newsletter.log
```

### Step 2: Completion summary

Concisely summarize the execution result of each skill:
- /briefing: path of generated Daily Note + success/failure
- /newsletter: path of generated newsletter + success/failure

The Daily Note already surfaces unprocessed inbox counts and recommends `/sync` and `/distill` when there is pending work (see /briefing's Notes section). The morning summary does not need to duplicate that — the user reads the Daily Note for actionable next steps.

After the summary, exit (do not transition to assistant mode).

## Rules

- The output of each `claude -p` returns to /morning's context as the Bash result
- If one skill fails, the other is unaffected (parallel isolation)
- `--model sonnet` is for cost efficiency. Adjust the flag if Opus is needed
- After everything completes, display the summary and exit
- Do not call `/sync` or `/distill` from inside /morning. They are separate skills invoked manually or via the user's external scheduler (ADR-075)
