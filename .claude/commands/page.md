---
gui:
  label: "/page"
  hint: "Open conversational session"
  match:
    - "pages/*.md"
  arg: path
  order: 15
  mode: live
---

# /page — Conversational Pages

Have a conversation with your pages. Pages evolve through dialogue and incremental edits, not regeneration. The default action opens a conversational session centered on a page; updates happen as targeted edits with a diff preview, and can be undone on request.

## Arguments

$ARGUMENTS — one of the following:

- Omitted → List pages with last-updated timestamps
- `{id}` or `pages/{id}.md` → **Start a conversational session** (default action)
- `{id} "{quick message}"` → One-shot update without dialogue
- `create {theme}` → Create a new page
- `rebuild {id}` → Full rebuild (last resort, see Rebuild Flow)

## Conversational Session (default action)

When called with a page id or path, open a conversation centered on that page. The page + recipe become the shared context for the session, and the user can update information, ask questions, revise structure, or trigger a full refresh — all through dialogue.

### Session Start

1. Read `pages/{id}.md`
2. Read `pages/{id}.recipe.md` (mandatory)
3. **Load contextual background** (this is the key — do not skip):
   - Read each file listed in `frontmatter.sources` as **context**, not just for change detection. Sources are known-relevant files; their content is the conversational backdrop
   - If the page has `mentions`, read the referenced entity files (`knowledge/people/*.md`, `knowledge/orgs/*.md`, `knowledge/projects/*.md`) for entity-level context
   - Do not perform wide exploratory search (e.g., Grep across workspace/tasks) at session start — that is reserved for the "full refresh" intent. Sources + mentions is the ceiling here
4. Detect changes and new candidates that the user should notice:
   a. **Known sources changed (Layer 1)**: For each file in `frontmatter.sources`, check if it was modified after the page's `frontmatter.updated || frontmatter.created`. Use `git log --since={updated} --name-only -- {source}` or compare file mtime. Summarize only what's actually different from what the page already reflects
   b. **New related candidates (Layer 2/3)**: Read `pages/.pending` and filter for entries matching the current `page_id` (column 1, TAB-separated). For each matching entry, verify the `source_path` (column 2) is not already present in `frontmatter.sources` — if it is, treat the pending entry as stale and skip it (it will be cleaned up on the next write). Collect the remaining entries as "new related candidates" with their `origin_skill` and `detected_at`
   c. **Check for an interrupted batch** (see Batch Progression Mode below): look for an HTML comment at the end of the page body starting with `rill:pending-batch`. If present, parse its timestamp and remaining items for the opening message
5. Present the opening message:

```
📖 {page.name}（last updated: {relative-time}）

{If an interrupted batch was detected, surface it first:}
⚠️ A previous batch was interrupted on {timestamp}.
Remaining: {items}.
Resume, or discard and start fresh?

{If changes were detected in known sources (4a), list them briefly:}
Changes since last update:
- {file}: {one-line summary of what changed}

{If new related candidates are found in .pending (4b), list them:}
🌱 New related candidates since last update:
- {source_path} ({origin_skill}, {detected_at})
- {source_path} ({origin_skill}, {detected_at})
→ Review together ("全部取り込んで" activates batch mode), cherry-pick, or dismiss individually

What would you like to discuss? You can:
- Update information ("I changed X to Y")
- Ask a question ("What's my current X?")
- Revise structure ("Add a section about X")
- Request a full refresh ("Update with the latest")
- Work through the candidates ("これ全部見て", "dismiss {source_path}")
```

Omit blocks whose condition did not fire.

### Responding to User Intent

Classify the user's message into one of the following intents and respond accordingly.

#### Intent 1: Information Update

Triggered by statements providing new information ("I changed X", "the new value is Y", "add this data point").

1. Identify the relevant location in the page (via Grep or contextual reasoning)
2. Propose the change as a diff (see Edit Application Protocol)
3. On approval, apply via Edit
4. Track the edit for potential undo
5. If the data came from the user directly, also write to the canonical source (inbox/journal/ etc.) per ADR-062 D62-5

#### Intent 2: Question

Triggered by questions about the page's subject ("What's my Monday routine?", "Where did we decide on X?").

1. Answer using the page content as primary context; pull related knowledge notes if needed
2. Do not modify the page by default
3. After answering, if the answer contains new information worth preserving, offer: "Would you like to reflect this in the page?"

#### Intent 3: Structural Revision

Triggered by structural requests ("Add a section about X", "Merge these two sections", "Move X to the top").

1. Check the page's structural axis (Quality Principle 6) before accepting the change
2. Propose the new structure (headings, placement) and discuss with the user before writing content
3. Once the shape is agreed, draft the content in dialogue, then apply via Edit with a diff preview
4. If the structure changes materially, update `recipe.md` Notes accordingly

#### Intent 4: Full Refresh

Triggered by explicit refresh requests ("Update with the latest", "Bring this up to date", "最新にして").

1. Read `recipe.md` Source Hints as exploration guidance
2. Search exploratively:
   - Grep for `mentions` of related entities in `workspace/`, `tasks/`, `knowledge/notes/`
   - Match against the page's own `mentions` and topic keywords
   - Compare findings against `frontmatter.sources` to identify new files
3. Summarize findings to the user before making changes:

```
Found the following that are not reflected in this page:
- {file A}: {brief summary}
- {file B}: {brief summary}
- ...

How would you like to proceed? All / Select / Cancel
```

4. Apply approved items as diff-previewed edits (one at a time or in a small batch)
5. Update `frontmatter.sources` to include newly referenced files

#### Intent 5: Pending Candidates Review / Dismiss

Triggered when the user responds to the "New related candidates" block, either to take the candidates in (batch or cherry-pick) or to dismiss them.

**Review / take in**:
1. If the user says "全部取り込んで" / "apply all" / "see all" / similar broad approval, switch to **Batch Progression Mode** and process each candidate in sequence. For each:
   - Read the candidate source file
   - Propose a diff-preview showing what should be reflected in the page (a summary, a table row, a new paragraph — judge based on the candidate's content and the page's structure)
   - Apply via Edit Application Protocol (which also adds the source to `frontmatter.sources` and runs implicit ack on the pending row via `--ack`)
2. If the user cherry-picks ("this one only", "just the squat one"), process that single candidate the same way

**Dismiss**:
1. If the user says "関係ない" / "dismiss" / "not relevant" for a candidate, remove the pending row without editing the page:
   ```bash
   rill pages-pending-update --ack --page {id} --source {source_path}
   ```
2. Acknowledge in one line: "Dismissed {source_path}."
3. Do not write anything to the page body

This intent is distinct from Intent 4 (Full Refresh). Intent 4 performs exploratory search from `recipe.md` hints; Intent 5 operates on the pre-computed candidate list in `pages/.pending`.

#### Intent 6: Undo

Triggered by undo requests ("戻して", "取り消して", "undo", "revert that").

1. Locate the most recent edit applied in this session (tracked in conversation context)
2. Apply Edit with `old_string` and `new_string` swapped to revert
3. Confirm: "Reverted the last change."
4. Phase 1 supports undoing only the most recent edit. For deeper history, use Git.

### Edit Application Protocol

Every edit applied during a conversational session follows this protocol:

1. **Describe** what will change (one sentence)
2. **Show** the diff in a fenced `diff` code block:

````
Updating the Friday Legs menu:

```diff
- | 2 | Smith-Machine Squat | smith machine | 3×10-12 | — | 90s | ★★★ | Warm up lightly first time |
+ | 2 | Free Squat | barbell | 3×10-12 | 30kg | 90s | ★★★ | Transitioned from smith machine |
```

Apply?
````

3. **Wait for confirmation**. Implicit confirmation (user says "yes", "go ahead", continues to next topic) or explicit ("apply it") is fine. Silent acceptance is not — if unclear, ask.
4. **Apply** via Edit tool
5. **Update `frontmatter.updated`** to the current time *every time* an edit is applied (obtain with `date +%Y-%m-%dT%H:%M%z | sed 's/\([0-9][0-9]\)$/:\1/'`). This way, a session interrupted mid-way still leaves the page in a consistent state with a correct timestamp
6. **Update `frontmatter.sources`** if the edit was informed by a new file not already listed
   - **Implicit ack of pending entries**: if the newly added source was present in `pages/.pending` for this page, remove that pending row by running `rill pages-pending-update --ack --page {id} --source {source_path}`. This keeps `.pending` consistent with absorbed sources automatically
7. **Track** the edit in conversation context: `{file_path, old_string, new_string, applied_at}` — for potential undo

### Batch Progression Mode

When the user signals that multiple edits should be applied as a set, switch into **batch mode** and run them continuously without awaiting intervening confirmations. This exists because in practice, LLMs tend to end their turn after 2–3 tool calls even when the user has already approved a larger batch — leaving the page in a half-updated state that the user may or may not notice.

**Activation signals** (examples — interpret liberally, not exhaustively):

- Japanese: 「全部やって」「この方向で進めてください」「5日分お願い」「続けて」「一括で」「まとめて」「全部適用」
- English: "apply all", "go ahead with the whole batch", "do the set", "continue through them", "all of them"

When you have presented a plan (e.g., "I'll update Monday through Friday's menus as follows…") and the user responds with broad approval for the plan itself, batch mode is active for the scope of that plan.

**Behavior during batch mode**:

1. For each item in the batch: present the diff, apply via Edit, then immediately move to the next. Do not stop to ask "Apply?" between items — approval was granted for the batch as a whole
2. Every applied item still runs the full Edit Application Protocol steps 5–7 (`frontmatter.updated` refresh, `frontmatter.sources` update, conversation-context tracking). The page stays in a consistent state even if the batch is interrupted
3. **Do not end the turn mid-batch.** Complete the full set within one turn whenever tool-call limits allow. The "turn-splitting gravity" around the 3rd tool call is the specific failure mode this section exists to prevent — resist it
4. At batch completion, present one summary of what was applied (not per-item confirmations). Any open follow-up questions happen after the summary, not between items

**What deactivates batch mode**:

- All items applied (normal completion) — emit the summary
- Explicit pause from the user ("止めて", "wait", "hold on", "戻って") — write the interruption marker (below) before returning control
- A blocker that requires new information the batch didn't anticipate — ask for the information, but first write the interruption marker so the remaining scope isn't lost

**Interruption marker**:

If a batch is paused before completion, append (or update) a single HTML comment at the end of the page body listing the remaining items:

```html
<!-- rill:pending-batch 2026-04-17T15:30+09:00 — Remaining: Wednesday legs, Thursday push, Friday pull -->
```

Rules for the marker:

- Exactly one `rill:pending-batch` comment per page. Overwrite an existing marker rather than stacking
- Place at the very end of the body (after all content)
- Remove the marker when the batch is resumed to completion, or when the user explicitly says "discard"
- On next session start, step 4 above detects and surfaces it

### Session End

A session ends naturally when the user stops engaging. No explicit "end" command is required. Because `frontmatter.updated` and `frontmatter.sources` are maintained incrementally (see Edit Application Protocol steps 5-6), the page is always in a consistent state. No special finalization is needed.

When the session has included at least one applied edit and the user signals closure (done, moving on, thanks, etc.), show a brief session summary:

```
Session complete. Applied 3 changes:
- Updated Friday squat exercise (Smith-Machine → Free Squat, 30kg)
- Added 4/17 progress note
- Refreshed frontmatter.sources

Commit when ready via normal git workflow.
```

**Do not auto-commit.** The user commits via their normal git workflow. Automatic commits may be added in a future phase after observing usage.

## Quick Update (no dialogue)

Triggered by `/page {id} "{message}"` — a one-shot update without conversational back-and-forth.

1. Read page + recipe
2. Interpret the message and determine the target location
3. Show the diff
4. **Apply immediately** (no explicit confirmation — this is the "quick" tradeoff)
5. Return a one-line summary

If the target location cannot be determined reliably, abort with an error message rather than guessing. Tell the user to use the conversational session (`/page {id}`) for ambiguous updates.

## Create Flow

(Note: Phase 3 will redesign this flow to be conversational — built section-by-section through dialogue, mirroring the quality of `/focus` deliverables. The flow below is the current one-shot approach, retained until that work lands.)

1. Understand the user's theme and requirements
2. Exploratively collect related information:
   - Grep search in `knowledge/notes/`
   - Explore related workspaces in `workspace/`
   - Search related records in `inbox/journal/`
   - Search related reports in `reports/`
3. Create the page file with `rill mkfile pages --slug {id} --type page --name "Display Name" --desc "Description" --tags "[tag1, tag2]"` (`--name` and `--desc` are required; omitting them causes an error)
4. Write the first draft based on collected information. Follow the quality principles, and determine the content and structure yourself
5. Record files that substantively contributed to the content in the frontmatter `sources` field
6. **Present the first draft to the user and request feedback**:
   - "I've created the first draft. Please let me know if you have any feedback on the direction, level of detail, or missing perspectives."
7. Incorporate feedback and improve. If additional source exploration is needed, do so. Update `sources` as well
8. **Feedback learning** (only when feedback was provided): Review the diff between the first draft and final version, extract learnings, and save them. See the "Feedback Learning" section for details
9. Create `pages/{id}.recipe.md` (`type: recipe`, `page: {id}`). Write it in the following format:

### recipe.md Format

A recipe is a file that communicates the "purpose" of a page. It does not prescribe structure or formatting.

```markdown
# Recipe: {Page Name}

## Purpose of This Page
{Who opens this page, when, and why. 1-3 sentences.}

## Source Hints
{Where to find the latest information. Natural-language guidance for exploration —
not strict query definitions. Prefer mentions/tags and thematic descriptions over
rigid file-name globs. Example:
- workspaces and tasks that mention projects/rill
- knowledge notes about release and launch topics
- recent journal entries touching on release work}

## Fixed Sections (if any)
{Only sections where data placement must be exact. Such as tracking tables
where format breakage would impair functionality. Omit this section entirely if none.}

## Notes
{Data to preserve, patterns to avoid, etc. Keep minimal.}
```

**What to write in a recipe**: The page's purpose (who it's for and why it exists), exploration hints (natural language, not strict globs), fixed sections where data placement must be precise
**What NOT to write in a recipe**: Section structure specifications, format directives for prose sections (table/list etc.), exhaustive aggregation rules, strict file-name patterns that would break when files are named differently. Structure is determined by the AI based on the page's purpose; exploration is guided by Claude Code's judgment using the hints.

## Rebuild Flow (last resort)

Rebuild is a destructive operation that rewrites the entire page. Use only when:

- The page's structure is fundamentally misaligned with its purpose
- The information is too stale for incremental updates to catch up
- The conversational session has lost direction and needs a reset

**Day-to-day updates should go through the conversational session, not rebuild.**

1. Read `pages/{id}.recipe.md` to understand the page's purpose
2. Exploratively collect sources by referencing the recipe's Source Hints + `frontmatter.sources`
3. Determine the optimal structure and content yourself based on the page's purpose, and write from scratch. Previous content is only a "reference"
4. Overwrite the page body with Edit, and update `sources` with the files actually referenced
5. **Present to the user and request feedback**:
   - "Rebuild complete. Please let me know if you have any feedback on the direction, level of detail, or missing perspectives."
6. If feedback is provided, incorporate it and improve. Update `sources` as needed
7. **Feedback learning** (only when feedback was provided): See the "Feedback Learning" section
8. Update `frontmatter.updated` to the current time

## Document Quality Principles

Pages are "documents that humans read repeatedly." Write according to these principles:

**1. Include Multiple Layers of Abstraction**
Don't compose with prose alone, tables alone, or lists alone. Use prose to convey the big picture and "why it matters," tables to catalog individual items, and lists to enumerate ideas or caveats. A single format inevitably leaves gaps.

**2. Include Both Summaries and Raw Data**
Prose summaries alone (the forest) lack specificity and feel "thin." Raw data alone in tables or lists (the trees) lack context and feel like a "data dump." Readers need both "grasping the big picture" and "checking individual items," so include both.

**3. Make It Scannable**
Create a structure where readers can find the information they need without reading the entire document. Table headers, row labels, and section headings serve as anchors that let readers visually scan to the relevant section.

**4. Include a Gradient of Certainty**
Don't limit content to confirmed facts. Include in-progress items, ideas at the concept stage, and fragments. A range of maturity — "confirmed → in progress → concept → idea" — lets readers see the full picture. However, always make clear what is confirmed and what is not.

**5. Write Each Fact in Exactly One Place**
Don't scatter the same information across multiple sections. When a related section needs to reference something, designate one canonical location and point to it from elsewhere. Scattered information causes two problems: "not knowing where to look" and "missed updates."

**6. Choose One Structural Axis**
Decide on a single axis for the entire page (chronological, phase-based, categorical, etc.) and arrange all sections along that axis. Mixed axes cause readers to lose track of where they are. When adding a section, verify it fits the axis before adding it.

**7. Re-evaluate the Entire Page When Adding Sections**
After adding or modifying a section, re-read the entire page and verify: (a) the new section's information doesn't duplicate existing sections, (b) the section count hasn't grown to the point of impairing readability, (c) the page's axis (principle 6) is still intact. If there are issues, restructure rather than simply appending.

## Feedback Learning

When the user provides feedback during creation, rebuild, or a conversational session, review what changed and why, and save the learnings.

### Procedure

1. Identify **what changed** from the first draft / prior state to the final version (added sections, removed elements, changes in information density, structural changes, etc.)
2. Identify **why it changed** from the user's feedback
3. Classify learnings into two types:

**Skill-level learnings** (generalizable to other pages):
- Example: "The first draft was prose-only and lacked information density. Adding a table with raw data improved the evaluation."
- Example: "An idea stock section was well-received for roadmap-type pages, but may be unnecessary for operational reference pages."
- → **Save to auto memory as feedback type**. Prefix the description with "/page skill feedback:" to make it searchable later

**Page-specific learnings** (to apply in the next update of that page):
- Example: "For this page, presenting competitive analysis in category-based tables was preferred."
- → **Append to the "Notes" section of the target page's recipe.md**

### Evolution of Quality Principles

Skill-level learnings accumulate in auto memory over time. When sufficient examples have gathered and additions, modifications, or deletions to the quality principles are deemed necessary, the "Document Quality Principles" section of this skill file itself may be updated. In that case, confirm with the user via AskUserQuestion: "May I update the quality principles?"

## Rules

- Use `rill mkfile` for creating files in pages/
- **recipe.md is required reading for all operations** (conversational session, create, rebuild, quick update). Understand the page's purpose before writing
- A recipe communicates purpose and exploration hints. It does not prescribe structure
- **In conversational sessions, always show a diff before applying an edit.** Silent application breaks the trust model. Track each applied edit in conversation context for potential undo
- **Support the undo request** ("戻して", "revert", "undo") by reversing the last tracked edit. Phase 1 supports only one-step undo; deeper history is recovered via Git
- **Do not auto-commit.** The user commits via their normal git workflow
- Record files that substantively contributed to the content in `frontmatter.sources`. Update on each session that applied edits, creation, rebuild, or quick update. Do not include daily journals (explore them dynamically via recipe hints)
- Not an AI search target: /distill, /briefing, /eval do not reference pages/
- When the user provides data during a conversation, also write to the canonical source (inbox/journal/ etc.) per ADR-062 D62-5
- To update the `updated` timestamp, obtain the exact current time:
  ```bash
  date +%Y-%m-%dT%H:%M%z | sed 's/\([0-9][0-9]\)$/:\1/'
  ```
