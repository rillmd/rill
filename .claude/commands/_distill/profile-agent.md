# Interest Profile Update Agent

/distill Phase 4 sub-agent prompt. Updates the user's Interest Profile based on distillation results.

## Target Files

The Interest Profile lives in `knowledge/self/`:

- `knowledge/self/interests.md` — Deep Interests / Curiosity / Obligations / Career
- `knowledge/self/direction.md` — Active Projects + Cross-project meta-direction + Career direction
- `knowledge/self/profile.md` — Core Identity (rare; year-scale changes only)

**Legacy fallback**: if `knowledge/self/interests.md` does not exist, fall back to `knowledge/me.md` (the predecessor file) and apply all edits there until migration completes.

**Read the relevant files first before starting processing.** Detect which mode you are in:

- `knowledge/self/interests.md` exists → **new mode**. Read interests.md + direction.md + profile.md (skip files missing in older vaults)
- `knowledge/self/interests.md` does not exist → **legacy mode**. Read `knowledge/me.md`

## Current /distill Processing Results Summary

The orchestrator's prompt injects the following 4 sections. Combine the instructions in this file with the injected data to make judgments.

- Newly created knowledge/notes/
- Newly created/updated projects/
- Extracted tasks
- Newly created entities (people/, orgs/)

## Judgment Criteria

Detect the following changes. In **new mode**, route each detected change to the appropriate self/ file. In **legacy mode**, apply all edits to the single `knowledge/me.md`.

### 1. Active Projects Changes

- Repeated mentions of a new project → Consider adding to Active Projects
  (Only add if `knowledge/projects/{id}.md` exists. Otherwise report only)
- Stage change of an existing project (e.g., planning → pilot) → Update link description

**Write target**:
- new mode → `knowledge/self/direction.md` "Active Projects" section
- legacy → `knowledge/me.md` "Active Projects" section

### 2. Interests Changes

- Clear emergence of a new interest topic → Add to the appropriate category
  (Do not add for just 1-2 mentions. Requires clear expression of interest or repeated mentions)
- Interest migration: a topic being repeatedly explored in Curiosity → Consider promoting to Deep Interests
- Interest decay: a topic in Deep Interests with no recent mentions → Consider demoting to Curiosity
  (Be conservative with demotions. Not mentioning for 2 weeks alone is insufficient for demotion)

**Write target**:
- new mode → `knowledge/self/interests.md` Deep Interests / Curiosity subsection
- legacy → `knowledge/me.md` "Interests" section

### 3. Obligations Changes

- Emergence of new obligatory themes (e.g., new regulations, administrative procedures) → Add to Obligations
- Completed obligations → Remove

**Write target**:
- new mode → `knowledge/self/interests.md` "Obligations" subsection
- legacy → `knowledge/me.md` "Obligations" section

### 4. Career Changes

- Emergence of new career interests → Add to Career

**Write target**:
- new mode → `knowledge/self/interests.md` "Career" subsection
- legacy → `knowledge/me.md` "Career" section

### 5. Core Identity / Direction Prose

- New cross-project direction or shift in primary theme → Update the prose at the top of `knowledge/self/direction.md` "現在のメインテーマ"
- Year-scale role / employer / company change → Update `knowledge/self/profile.md` "Core Identity"

These are rare. Apply only when the distillation surfaces an unmistakable signal.

In legacy mode, both kinds collapse into `knowledge/me.md` "Core Identity" / "Active Projects".

## Rules

- **Update conservatively**: do not update if the change is not clear
- **Do not modify category descriptions (parenthetical text)**: these are instructions for LLMs and should remain fixed
- If updates are made, change the frontmatter `updated` to today's date on the file(s) you edited
- If no changes, report "No changes to Interest Profile" and finish

## Output

After processing, report the following **concisely**:

- Files edited (one line per file: `{path} — {section} ({change kind})`)
- If no updates: "No changes to Interest Profile"
