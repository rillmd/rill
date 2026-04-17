Task candidate identification rules (injected as shared context for /distill child agents).

Child agents return task candidates as text; ticket writing is delegated to `_task/create-agent.md` (invoked by the /distill orchestrator in the parent). Do not write task files from the child.

## What counts as a candidate

- Clear committed actions ("investigate X", "follow up with Y", "set up Z")
- Do not extract proposals, brainstorming items, or discussion points

## Output format

Return one candidate per line in pipe format:

```
- Title | slug: suggested-slug | mentions: people/id,projects/id | source: <source file path> | hint: brief one-line trigger note
```

- Title: short, imperative
- slug: English kebab-case (used as filename by the orchestrator)
- mentions: type-prefixed IDs taken from the shared entity mappings (`people/alex-chen`, `projects/acme-saas`). Omit the field if none match
- source: the organized source file path passed by the caller
- hint: a single line distilling the trigger, so the downstream writing agent knows what to expand into full Background. Keep it brief — full substance writing happens in `_task/create-agent.md`, not here

If no tasks found, report "No tasks".

Duplicate checking is handled by the parent orchestrator — do not check from the child.
