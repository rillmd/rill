Returns task candidates as text (does not write to files. Ticket creation is handled by the parent context).

- Only extract clear actions ("investigate X", "set up Y", etc.)
- Do not extract proposals or discussion items as tasks
- Format: `- Title | slug: suggested-slug | mentions: people/id | source: {source file path} | background: background text | context: Note Title::path, Note Title::path`
- slug must be English kebab-case (used directly as filename)
- mentions: Use type-prefixed IDs from the shared context entity list for matching people
- source: Use the source file path specified by the caller
- If no tasks found, report "No tasks"
- Duplicate checking is handled by the parent context (not needed here)

**Background writing rules (highest priority)**:

Background is the most important field of a task. Write it so that reading the task alone makes clear "what this task is about, what the issue is, and why it was created."

Must include (2-4 sentences):
- **Why this task is needed** (motivation/problem)
- **Core insight from the source** (not just "investigate X" but "given insight Y, investigate X to address issue Z")
- **Contextual information** (relevant situation, constraints, prerequisites if any)

Prohibited:
- Compressing to 1 sentence. Avoiding information loss is the top priority
- Copying source text verbatim. Reorganize so a third party can understand

**Context writing rules**:

- List related knowledge/notes/ files as comma-separated `Title::path` pairs
  - knowledge/notes/ files created from the same source (from knowledge extraction)
  - Existing related files discovered during Evergreen check
- Do not include the source file (already recorded in frontmatter source)
- Maximum 5 items. Omit context field if none applicable
