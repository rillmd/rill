Task candidate identification rules (injected as shared context for /distill child agents).

Child agents return task candidates as text; ticket writing is delegated to `_task/create-agent.md` (invoked by the /distill orchestrator in the parent). Do not write task files from the child.

## Language

When the parent agent has received an `output_language` argument (see its own Language section), write the candidate's `Title` and `hint` fields in that language. Internal keys stay verbatim English regardless of `output_language` because the orchestrator and downstream `_task/create-agent.md` parser string-match them: the pipe field names (`slug:`, `mentions:`, `source:`, `hint:`, `depends-on:`, `blocks:`), the kebab-case `slug` value, the type-prefixed mentions IDs (`people/{id}`, `projects/{id}`, `orgs/{id}`), the source file path, the depends-on / blocks `tasks/{slug}` references, and the `No tasks` sentinel emitted when nothing qualifies. When `output_language` is absent or the parent did not inject it, write `Title` and `hint` in plain English.

## What counts as a candidate

- Clear committed actions ("investigate X", "follow up with Y", "set up Z")
- Do not extract proposals, brainstorming items, or discussion points

## Output format

Return one candidate per line in pipe format:

```
- Title | slug: suggested-slug | mentions: people/id,projects/id | source: <source file path> | hint: brief one-line trigger note | depends-on: tasks/foo,tasks/bar | blocks: tasks/qux
```

- Title: short, imperative
- slug: English kebab-case (used as filename by the orchestrator)
- mentions: type-prefixed IDs taken from the shared entity mappings (`people/alex-chen`, `projects/acme-saas`). Omit the field if none match
- source: the organized source file path passed by the caller
- hint: a single line distilling the trigger, so the downstream writing agent knows what to expand into full Background. Keep it brief — full substance writing happens in `_task/create-agent.md`, not here
- depends-on (optional): comma-separated `tasks/{slug}` references when the source explicitly states this action must wait on another task being completed first. Omit the field if no dependency signal is present
- blocks (optional): comma-separated `tasks/{slug}` references when the source explicitly states this action unblocks named downstream tasks. Omit the field if no signal. Prefer setting `depends-on` on the downstream task when both directions are equivalent

If no tasks found, report "No tasks".

Duplicate checking is handled by the parent orchestrator — do not check from the child.
