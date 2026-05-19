# Interest Profile Update Agent

/distill Phase 4 sub-agent prompt. Updates the user's Interest Profile based on distillation results.

## Target Files

The Interest Profile lives in `knowledge/self/`:

- `knowledge/self/interests.md` — Deep Interests / Curiosity / Obligations / Career
- `knowledge/self/direction.md` — Active Projects + Cross-project meta-direction + Career direction
- `knowledge/self/profile.md` — Core Identity (rare; year-scale changes only)

**Read interests.md + direction.md + profile.md first before starting processing.** Skip a file silently if it does not exist in this vault (no-op).

## Language

Use the language specified by `output_language` (ISO 639-1) for the **additions and updates this agent writes** — namely new bullet items in `interests.md` (Deep Interests / Curiosity / Obligations / Career subsections), new entries in the `## Active Projects` section of `direction.md`, prose updates to the lead paragraph at the top of `direction.md` (the cross-project meta-direction prose, whose heading text is locale-specific and not pattern-matched by the orchestrator), and the rare Core Identity prose updates in `profile.md`. **Do not retranslate or rewrite the existing body** of any of these files — preserve every untouched line in its original language verbatim, regardless of `output_language`. Internal keys stay verbatim English regardless of `output_language` because they are structural section markers: the standard section heading names (`## Active Projects`, `### Deep Interests`, `### Curiosity`, `### Obligations`, `### Career`, `## Core Identity`), the category description parenthetical text (which is itself an instruction for LLMs and must remain fixed), file paths, frontmatter field names and values, and the `No changes to Interest Profile` sentinel emitted when no updates are made. The change-kind labels in the final report (`add` / `update` / `remove` / `promote` / `demote`) also stay English. Follow the inline `style_guide` block for vocabulary boundaries on the narrative additions.

## Current /distill Processing Results Summary

The orchestrator's prompt injects the following 4 sections plus optional language args. Combine the instructions in this file with the injected data to make judgments.

- Newly created knowledge/notes/
- Newly created/updated projects/
- Extracted tasks
- Newly created entities (people/, orgs/)
- `output_language` (optional): ISO 639-1 language code for narrative output fields (e.g. `"ja"`, `"en"`); when omitted, default to English
- `style_guide` (optional): short vocabulary-boundary rules for narrative fields (see Language section); when omitted, write narrative fields in plain English

## Judgment Criteria

Detect the following changes and route each to the appropriate self/ file.

### 1. Active Projects Changes

- Repeated mentions of a new project → Consider adding to Active Projects
  (Only add if `projects/{id}/_project.md` exists. Otherwise report only. ADR-080: project moved from `knowledge/projects/{id}.md` to `projects/{id}/_project.md`)
- Status change of an existing project (e.g., `planning` → `active`, `active` → `paused`) → Update link description. Per ADR-080 the status field is `status` (4-state: planning / active / paused / done), not the legacy `stage`

**Write target**: `knowledge/self/direction.md` "Active Projects" section

### 2. Interests Changes

- Clear emergence of a new interest topic → Add to the appropriate category
  (Do not add for just 1-2 mentions. Requires clear expression of interest or repeated mentions)
- Interest migration: a topic being repeatedly explored in Curiosity → Consider promoting to Deep Interests
- Interest decay: a topic in Deep Interests with no recent mentions → Consider demoting to Curiosity
  (Be conservative with demotions. Not mentioning for 2 weeks alone is insufficient for demotion)

**Write target**: `knowledge/self/interests.md` Deep Interests / Curiosity subsection

### 3. Obligations Changes

- Emergence of new obligatory themes (e.g., new regulations, administrative procedures) → Add to Obligations
- Completed obligations → Remove

**Write target**: `knowledge/self/interests.md` "Obligations" subsection

### 4. Career Changes

- Emergence of new career interests → Add to Career

**Write target**: `knowledge/self/interests.md` "Career" subsection

### 5. Core Identity / Direction Prose

- New cross-project direction or shift in primary theme → Update the prose at the top of `knowledge/self/direction.md` "現在のメインテーマ"
- Year-scale role / employer / company change → Update `knowledge/self/profile.md` "Core Identity"

These are rare. Apply only when the distillation surfaces an unmistakable signal.

## Rules

- **Update conservatively**: do not update if the change is not clear
- **Do not modify category descriptions (parenthetical text)**: these are instructions for LLMs and should remain fixed
- If updates are made, change the frontmatter `updated` to today's date on the file(s) you edited
- If no changes, report "No changes to Interest Profile" and finish

## Output

After processing, report the following **concisely**:

- Files edited (one line per file: `{path} — {section} ({change kind})`)
- If no updates: "No changes to Interest Profile"
