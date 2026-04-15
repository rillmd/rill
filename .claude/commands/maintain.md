# /maintain — Quality Maintenance

Runs note quality inspection and repair sequentially. Diagnoses issues with /inspect, then fixes them with /repair if any are found.

## Arguments

$ARGUMENTS — None

## Steps

### Step 1: Quality Inspection

Run Skill("/inspect").

/inspect diagnoses taxonomy health + metadata accuracy + consistency, and adds problematic files to `knowledge/.refresh-queue`.

### Step 2: Repair Decision

Read `knowledge/.refresh-queue` and check the count.

- If count is 0: Display "No repairs needed. Quality is good." and finish
- If count is greater than 0: Proceed to Step 3

### Step 3: Metadata Repair

Run Skill("/repair").

/repair reads files from `.refresh-queue` and batch-normalizes tags/mentions/type.

### Step 4: Completion Summary

- /inspect diagnostic results (files inspected, issues found)
- /repair results (files repaired, files skipped)

## Why /inspect and /repair Are Called via the Skill Tool

/inspect and /repair use Agent sub-agents, but are not as heavy as /distill.
The combined context consumption of the 2 skills is manageable (~50-80K tokens).
To avoid the process startup overhead of `claude -p`, they are run sequentially via the Skill tool.

## Rules

- If /inspect fails, do not run /repair (cannot repair without diagnostic results)
- After everything completes, display a summary and finish (do not transition to assistant mode)
