---
gui:
  - label: "/page update"
    hint: "Incremental update with latest information"
    match:
      - "pages/*.md"
    arg: path
    mode: live
  - label: "/page rebuild"
    hint: "Rebuild from scratch"
    match:
      - "pages/*.md"
    arg: path
    mode: live
---

# /page — Create and Update Pages (Materialized Views)

Manage aggregated documents (Wiki-page-like Materialized Views) that humans refer to repeatedly.

## Arguments

$ARGUMENTS — one of the following:

- Omitted → Display the list of `pages/` and ask what to do via AskUserQuestion
- Theme text (e.g., `body recomposition strategy`) → Create a new page
- File path (e.g., `pages/body-recomposition.md`) → Incremental update of that page
- File path + `rebuild` (e.g., `pages/body-recomposition.md rebuild`) → Full rebuild
- File path + text (e.g., `pages/body-recomposition.md breakfast is...`) → Incremental update (add data or apply corrections)

## New Page Creation Flow

1. Understand the user's theme and requirements
2. Exploratively collect related information:
   - Grep search in knowledge/notes/
   - Explore related workspaces in workspace/
   - Search related records in inbox/journal/
   - Search related reports in reports/
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
{Where to find the latest information. Paths or search keywords.}

## Fixed Sections (if any)
{Only sections where data placement must be exact. Such as tracking tables
where format breakage would impair functionality. Omit this section entirely if none.}

## Notes
{Data to preserve, patterns to avoid, etc. Keep minimal.}
```

**What to write in a recipe**: The page's purpose (who it's for and why it exists), source exploration hints, fixed sections where data placement must be precise
**What NOT to write in a recipe**: Section structure specifications, format directives for prose sections (table/list etc.), exhaustive aggregation rules. Structure is determined by the AI based on the page's purpose

## Update Flow

The unified flow used for all page update operations. Also handles cases where the user provides data or correction instructions.

1. Read the target page
2. **Read `pages/{id}.recipe.md`** (mandatory)
3. Branch based on the type of user input:

### 3a. No Arguments (Full Update)
- Refer to the recipe's purpose and source hints to exploratively collect related files
- Update using the previous page content as a reference point. Maintain the structure of fixed sections
- For prose sections, feel free to improve composition and writing style, not just update information
- Write with the reader in mind — when they open this page, they should understand "why this matters" and "what to do next"
- Update the frontmatter `sources` with the files actually referenced this time

### 3b. Data Provided (Incremental Update)
- Write data to the canonical source (inbox/journal/ etc.) per ADR-062 D62-5
- If fixed sections exist, place data there. Otherwise, determine the best position within the existing page context
- Do not perform source exploration (use only user-provided data)

### 3c. Correction Instructions Provided
- Identify the relevant section and fix it with Edit
- If the structure changes, update recipe.md accordingly
- Do not perform source exploration

4. Update the frontmatter `updated` to the current time (do not update for cosmetic-only edits)

## Rebuild Flow

1. Read `pages/{id}.recipe.md` to understand the page's purpose
2. Exploratively collect sources by referencing the recipe's source hints + frontmatter `sources`
3. Determine the optimal structure and content yourself based on the page's purpose, and write from scratch. Previous content is only a "reference"
4. Overwrite the page body with Edit, and update `sources` with the files actually referenced
5. **Present to the user and request feedback**:
   - "Rebuild complete. Please let me know if you have any feedback on the direction, level of detail, or missing perspectives."
6. If feedback is provided, incorporate it and improve. Update `sources` as needed
7. **Feedback learning** (only when feedback was provided): Review the diff between the first draft and final version, extract learnings, and save them. See the "Feedback Learning" section for details
8. Update the frontmatter `updated` to the current time

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

When the user provides feedback during creation or rebuild, review the diff between the first draft and final version as the last step, extract learnings, and save them.

### Procedure

1. Compare the first draft and final version, and identify **what changed** (added sections, removed elements, changes in information density, structural changes, etc.)
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
- **recipe.md is required reading for all operations**. Understand the page's purpose before writing
- A recipe communicates purpose and source hints. It does not prescribe structure
- Record files that substantively contributed to the content in the frontmatter `sources`. Update with actually referenced files on each creation, rebuild, or full update. Do not include daily journals (explore them dynamically via recipe hints)
- Not an AI search target: /distill, /briefing, /eval do not reference pages/
- When asked to directly edit (add data), also write to the canonical source (inbox/journal/ etc.) per ADR-062 D62-5
- To update the `updated` timestamp, obtain the exact current time:
  ```bash
  date +%Y-%m-%dT%H:%M%z | sed 's/\([0-9][0-9]\)$/:\1/'
  ```
