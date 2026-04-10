# Interest Profile Update Agent

/distill Phase 4 sub-agent prompt. Updates knowledge/me.md based on distillation results.

## Target File
knowledge/me.md

**Read this file first before starting processing.**

## Current /distill Processing Results Summary
The orchestrator's prompt injects the following 4 sections. Combine the instructions in this file with the injected data to make judgments.
- Newly created knowledge/notes/
- Newly created/updated projects/
- Extracted tasks
- Newly created entities (people/, orgs/)

## Judgment Criteria

Detect the following changes and directly Edit me.md:

### 1. Active Projects Changes
- Repeated mentions of a new project → Consider adding to Active Projects
  (Only add if knowledge/projects/{id}.md exists. Otherwise report only)
- Stage change of existing project (e.g., planning → pilot) → Update link description

### 2. Interests Changes
- Clear emergence of a new interest topic → Add to appropriate category
  (Do not add for just 1-2 mentions. Requires clear expression of interest or repeated mentions)
- Interest migration: Topic being repeatedly explored in Curiosity → Consider promoting to Deep Interests
- Interest decay: Topic in Deep Interests with no recent mentions → Consider demoting to Curiosity
  (Be conservative with demotions. Not mentioning for 2 weeks alone is insufficient for demotion)

### 3. Obligations Changes
- Emergence of new obligatory themes (e.g., new regulations, administrative procedures) → Add to Obligations
- Completed obligations → Remove

### 4. Career Changes
- Emergence of new career interests → Add to Career

## Rules
- **Update conservatively**: Do not update if the change is not clear
- **Do not modify category descriptions (parenthetical text)**: These are instructions for LLMs and should remain fixed
- If updates are made, change the frontmatter `updated` to today's date
- If no changes, report "No changes to Interest Profile" and finish

## Output
After processing, report the following **concisely**:
- Updated sections (section name + change content in one line)
- If no updates: "No changes to Interest Profile"
