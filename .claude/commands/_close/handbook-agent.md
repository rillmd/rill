# /close Handbook Sub-agent

/close Phase 4 sub-agent prompt (spawned in parallel with the Distillation sub-agents). Authors the **aggregated workspace handbook** — the human-readable HTML view of the completed workspace — into `workspace/{workspace_id}/.view/`, implementing the "workspace completion" read moment defined in `rill-html-output.md` ("When HTML Is Generated").

**IMPORTANT**: This file is a template. The parent /close skill reads this file, fills in the placeholders (workspace id, summary path, deliverable MOC), and passes the result as the `prompt` parameter when spawning the sub-agent via the Agent tool. The sub-agent receives this as its initial context and has no visibility into the parent's conversation history.

## Target

- Workspace ID: `{workspace_id}`
- Workspace path: `workspace/{workspace_id}/`
- `_summary.md` path: `workspace/{workspace_id}/_summary.md` (already written by the Analysis sub-agent)
- All deliverables in this workspace (from the Analysis report):

```
{deliverable_moc}
```

- `output_language` (optional): ISO 639-1 language code for narrative output (e.g. `"ja"`, `"en"`); when omitted, default to English
- `style_guide` (optional): short vocabulary-boundary rules for narrative output; when omitted, write narrative text in plain English

## Your job

Author the workspace handbook: a navigable HTML view that lets a human absorb the whole completed workspace without opening each Markdown artifact. You:

1. Read `.claude/commands/_view/design-language.md` **first** — it is the authoring procedure and pre-ship checklist this page must follow (message-driven, layer-not-delete, visualization routing, typography/layout, ship check)
2. Read `workspace/{workspace_id}/_summary.md` and every deliverable in full: all `NNN-*.md` files plus committed HTML-canonical artifacts (`NNN-*.html` etc. with no same-basename MD source — their HTML is the only record). Skip derived HTML regenerable from MD sources (`.view/` sidecars, same-basename `.html` twins)
3. Choose the document shape (single page vs multi-page — see below)
4. Write the handbook into `workspace/{workspace_id}/.view/`
5. Return a short structured report to the parent

You MUST NOT:

- Create or modify any file outside `workspace/{workspace_id}/.view/`
- Modify `_summary.md`, `_workspace.md`, or any deliverable
- Carry substantive information absent from the MD sources into the handbook (`rill-html-output.md` principle 4 — if a load-bearing explanation is missing, leave it out rather than inventing it; the parent run is completing the workspace and its sources are final)

## Document shape — qualitative judgment

Per the design language's "Two document shapes":

- **Single page** → `workspace/{workspace_id}/.view/handbook.html`. Choose this when the workspace's material fits one navigable page — a handful of artifacts whose full re-expression still reads as one coherent document a reader can scroll.
- **Multi-page** → `workspace/{workspace_id}/.view/handbook/` (hub `index.html` + detail pages, relative links, one shared inline `<style>` replicated verbatim across pages). Choose this when a single page would become an unnavigable wall — many dense artifacts whose re-expression would crowd each other out. Group related artifacts into chapter pages where that reads better than one page per artifact; the hub carries the framework and index (rank table / card grid / links into specific items).

The judgment is qualitative — decide by whether a reader could actually navigate the single page, not by a file-count threshold.

## Content requirements

1. **Start page re-expresses `_summary.md`.** The hub (or the top of the single page) states the workspace's message in one sentence, then re-expresses the summary's Overview, Decisions, Invalidated Approaches, and Open Issues in handbook form, with navigation to every artifact's section or detail page.
2. **Every deliverable is covered.** Each artifact (MD and HTML-canonical) gets a re-expressed section or detail page. Layer, not delete: prefer self-contained re-expression inside the handbook; for the largest workspaces a detail section may condense the artifact's argument, but it must then link the MD original explicitly as the retained full-detail layer (the reader can open it in the GUI's Markdown view). Never drop an artifact silently.
3. **HTML-canonical artifacts** (mocks, diagrams) are covered by linking them from the handbook with a described role (relative path into the workspace directory) — do not duplicate their content into the handbook; they are already human-readable HTML.
4. **Connections explicit.** Decisions link to the artifacts they were adopted from; invalidated approaches link to what invalidated them; every section declares where it belongs (design language, Authoring Procedure step 6).

## Technical constraints

- Self-contained: inline styles, no external network dependencies. A multi-page handbook is self-contained at the `handbook/` directory level — relative references to sibling pages are allowed, plus relative links out to the workspace's own MD/HTML sources (`rill-html-output.md` principle 7)
- Provenance: every generated page opens with `<!-- generated from {md_paths} @ {timestamp} by /close -->` (list the pages' actual sources; the hub may list `_summary.md` + the deliverable set)
- No frontmatter; write the HTML files directly (not via `rill mkfile`)
- Stable name, not a dated snapshot: the handbook is the durable view of a completed workspace, regenerated only when the workspace is reopened and re-closed. The parent /close has already deleted any previous handbook output (both `handbook.html` and the `handbook/` directory) before spawning you — write your chosen shape fresh; do not assume or preserve prior files. As a safety net, if either prior output still exists at your paths, delete it before writing (an earlier close may have used the other shape, or a page split yours no longer produces)
- Run the design language's ship check before returning; where no measuring tooling is available in your context, self-review the HTML source against the checklist instead

## Language

Use the language specified by `output_language` for all narrative text in the handbook (headings, prose, labels, link text). English exceptions per the vault's language rules: tokens inside backticks/code, proper nouns, ASCII acronyms, file paths and slugs. Follow the inline `style_guide` block for vocabulary boundaries. When omitted, write in English.

## Output — return to parent

Return ONE of the following structured reports. Use this exact format:

```yaml
status: created
shape: single | multi
path: workspace/{workspace_id}/.view/handbook.html   # or .view/handbook/index.html
pages: {N}            # 1 for single
artifacts_covered: {M}
```

```yaml
status: error
reason: "one-line description of what failed"
```

Handbook generation is non-fatal to /close (`rill-html-output.md` principle 8): on `error` the parent logs a warning and completes the close with Markdown alone. Do not retry endlessly — report the error and stop.

## Constraints summary

- Write only under `workspace/{workspace_id}/.view/`
- `.view/` is gitignored — the handbook is a derived, regenerable render, never committed
- Do not read `knowledge/`, `tasks/`, or other vault layers — the workspace directory, `_summary.md`, and the design language file are your whole world
- Return only the structured YAML report, nothing else
