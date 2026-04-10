# /morning — Morning Routine

Run user-feedback skills (Daily Note + Newsletter) first, then background processing (sync + distillation).
Each skill runs as an independent process (`claude -p`) to isolate context and bypass nesting limits (ADR-058).

## Dependencies

```
Step 1: /briefing + /newsletter  (parallel)  ← User feedback first
Step 2: /sync                                ← External sync
Step 3: /distill                             ← Distillation (heavy processing)
Step 4: Completion summary
```

/briefing only uses the previous day's data (activity window basis) → does not need /distill results.
/newsletter is WebSearch-based → independent of /distill.
The results of /sync + /distill are reflected in the next day's briefing.

## Arguments

$ARGUMENTS — none

## Procedure

### Step 1: Daily Note + Newsletter (parallel)

/briefing and /newsletter do not depend on each other, so **run them in parallel as background processes**.

Run the following with Bash:

```bash
claude -p "/briefing" --permission-mode bypassPermissions --model sonnet > /tmp/rill-morning-briefing.log 2>&1 &
BRIEFING_PID=$!

claude -p "/newsletter" --permission-mode bypassPermissions --model sonnet > /tmp/rill-morning-newsletter.log 2>&1 &
NEWSLETTER_PID=$!

# Wait for both to complete
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

### Step 2: External sync

Run `/sync` via the Skill tool.

/sync only runs adapter.sh and displays results, so it is lightweight (context consumption ~5K tokens).
Keeping the ingested file count in /morning's context allows it to be included in the summary.

### Step 3: Distillation

Run the following with Bash:

```
claude -p "/distill" --permission-mode bypassPermissions --model sonnet
```

/distill internally launches up to 5 parallel Agent subagents, so run it via `claude -p` (independent process) instead of the Skill tool. Reasons:
- Skill tool: context bloat (50K-100K+ tokens) degrades quality
- Agent tool: hits the 2-layer nesting limit (/morning → Agent(/distill) → Agent(journal-agent) is not allowed)
- `claude -p`: complete process isolation. /distill can freely launch Agent subagents

### Step 4: Completion summary

Concisely summarize the execution result of each step:
- /briefing: path of generated Daily Note + success/failure
- /newsletter: path of generated newsletter + success/failure
- /sync: number of ingested files
- /distill: number of processed items (extracted from claude -p output)

## Rules

- The output of each `claude -p` returns to /morning's context as the Bash result
- If one skill fails, the next skill continues to run (failure isolation)
- In Step 1's parallel execution, if one fails the other is unaffected
- `--model sonnet` is for cost efficiency. Adjust the flag if Opus is needed
- After everything completes, display the summary and exit (do not transition to assistant mode)
