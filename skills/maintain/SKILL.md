---
name: maintain
description: Run note quality maintenance — invoke /inspect to diagnose vault metadata, then /repair to fix queued issues. Use when the user wants weekly or periodic Rill vault health maintenance.
---

# /maintain — Quality Maintenance

> **Tool references in this skill** (`sub-agent`, "skill invocation") describe **intent**, not Claude-specific tool calls. Each harness should map them to its native equivalent — Claude Code uses its built-in Skill / Agent tools as named; Codex CLI uses its own skill invocation mechanism (mention / implicit / `/skills`) and sub-agent mechanism as appropriate.

Runs note quality inspection and repair sequentially. Diagnoses issues with /inspect, then fixes them with /repair if any are found.

## Arguments

$ARGUMENTS — None

## Steps

### Step 1: Quality Inspection

Invoke the `inspect` skill (via the harness's skill mechanism).

/inspect diagnoses taxonomy health + metadata accuracy + consistency, and adds problematic files to `knowledge/.refresh-queue`.

### Step 2: Repair Decision

Read `knowledge/.refresh-queue` and check the count.

- If count is 0: Display "No repairs needed. Quality is good." and finish
- If count is greater than 0: Proceed to Step 3

### Step 3: Metadata Repair

Invoke the `repair` skill (via the harness's skill mechanism).

/repair reads files from `.refresh-queue` and batch-normalizes tags/mentions/type.

### Step 4: Completion Summary

- /inspect diagnostic results (files inspected, issues found)
- /repair results (files repaired, files skipped)

## Why /inspect and /repair Are Invoked Inline

/inspect and /repair use sub-agents internally, but are not as heavy as /distill.
The combined context consumption of the 2 skills is manageable (~50-80K tokens).
To avoid the process startup overhead of spawning a new harness session, they are run sequentially inline within the current session.

## Rules

- If /inspect fails, do not run /repair (cannot repair without diagnostic results)
- After everything completes, display a summary and finish (do not transition to assistant mode)
