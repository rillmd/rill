# Theme Extraction Agent

`/retrospective` Phase 2 Batch A sub-agent. Extracts cross-workspace themes and divergent conclusions from a partitioned subset of `workspace/*/` files.

## Target inputs

The orchestrator partitions the period's active + completed workspaces across 5 agent invocations. Each invocation receives:

- `workspace_paths`: a list of `workspace/{id}/_workspace.md` paths to process
- `period_start`: ISO date (Monday of the target ISO week)
- `period_end`: ISO date (Sunday of the target ISO week)
- `entity_mapping`: shared one-line entity mappings (people / orgs / projects) for resolving mention names

## Read budget

For each workspace path:

1. Full Read of `_workspace.md` (typically 100-300 lines)
2. Read of the most recent 3 `[0-9]*-*.md` artifacts in the same directory (full content)
3. Frontmatter-only Read of all remaining `[0-9]*-*.md` artifacts (first 10 lines)

Avoid reading every artifact in full — the recency-weighted budget keeps per-agent tokens under ~30K (artifact 012 §3.3).

## What to extract

For each workspace, identify:

1. **Themes** (3-5 per workspace): short noun-phrase labels of the dominant questions / topics in the workspace. Bias toward themes that appear in both `_workspace.md` body and recent artifact headings (signals durability)
2. **Conclusion per theme** (when a conclusion exists): the position the workspace has converged on, framed as a single declarative sentence. If the workspace is still exploring, return `"(in progress)"` instead of fabricating a conclusion
3. **Anchor link**: the most representative artifact for each theme — typically a `type: decision` artifact, or the most recent artifact if no decisions exist

Skip themes that are purely procedural (e.g., "set up worktree", "commit and push") — these are workflow noise, not knowledge themes.

## Output

Return a JSON-like block (the orchestrator parses it):

```yaml
themes:
  - name: {short noun phrase, kebab-friendly}
    workspace: workspace/{id}/
    summary: {1-line summary of the theme}
    conclusion: {1-sentence position, or "(in progress)"}
    anchor: {relative path to representative artifact}
contradictions_signal:
  - {theme name, only when this workspace's conclusion differs sharply from the workspace's earlier artifact conclusion on the same theme — useful for cross-WS contradiction detection later}
```

The orchestrator clusters themes by `name` (with semantic fuzziness) across all 5 agent outputs. Clusters spanning 2+ workspaces become Cross-WS Themes. Clusters with divergent `conclusion` values become Contradictions.

## Output schema requirements

- `themes`: max 5 per workspace
- `conclusion`: max 1 sentence, max 25 words
- `summary`: max 1 line, max 20 words
- Use entity mention IDs (`people/foo`, `projects/bar`) verbatim when entities appear in summaries — do not paraphrase them away

## Failure handling

- A workspace's `_workspace.md` cannot be read → emit one normal entry **inside the same top-level `themes:` list** with all required fields populated so the coordinator's uniform parsing still works. The wrapping shape stays identical to normal output; only the contents differ. **The placeholder `name` must include the workspace `id` so multiple unreadable workspaces produce distinct names and do not falsely cluster as a shared Cross-WS Theme:**
  ```yaml
  themes:
    - name: "(skipped — {id} unreadable)"          # {id} = directory name from the workspace path, so each failure is unique
      workspace: workspace/{id}/                    # the path the orchestrator passed in
      summary: "(could not read _workspace.md)"
      conclusion: "(in progress)"
      anchor: workspace/{id}/_workspace.md          # still link to where the user can investigate
  contradictions_signal: []
  ```
  Additionally, the coordinator MUST exclude any theme whose `name` starts with `"(skipped — "` from cross-workspace clustering — they are failure markers, not real themes.
- A workspace has zero artifacts → use only `_workspace.md` body; emit at most 2 themes
- The agent's read budget is exhausted before all workspaces are processed → emit themes for processed workspaces and append a comment line at the end of the YAML output (`# processing incomplete due to budget`). Do not break the top-level schema

## Constraints

- Do not write any file. Output is text returned to the orchestrator
- Do not invoke other agents or skills
- Do not Read entity files (`knowledge/people/*`, `knowledge/orgs/*`, `projects/*/_project.md` — top-level per ADR-080) — use the injected `entity_mapping` for name resolution
- Do not run `Grep` to count mentions — the orchestrator already has the Tier dict; per-agent grep is forbidden (artifact 013 §1.1 design principle 5)
