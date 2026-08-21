# HTML Design Language — Authoring Checklist for Readable Views

Shared internal asset (underscore directory: not user-invocable; skills Read it). This is the authoring procedure and pre-ship checklist for every HTML view a Rill skill generates for a human reader — `/focus` decision digests, `/close` workspace handbooks, `/project` digests, and ad-hoc renders. Policy (when HTML exists, where it lives, what gets committed) is governed by `.claude/rules/rill-html-output.md`; this file governs **how to author a page that a human actually absorbs**.

The goal of any generated view: **lose no information, land the message**. A view that is merely styled Markdown fails; a view that summarizes away detail also fails.

## Core Principles

1. **Two layers.** Markdown is canonical and machine-facing; HTML is a derived, read-only view for humans (`rill-html-output.md` principles 1-3). Never write information back into HTML; edit the MD source and regenerate.
2. **Layer, not delete.** Summaries, emphasis, visualizations, and collapsed sections sit **on top of** the full detail, never in place of it. This is the single invariant that prevents information loss.
3. **Message-driven.** A view exists to convey one conclusion: state it in one sentence up front, build the argument structure that supports it, and make every section's connection to it explicit. Formatting plus folding without a message reads as "data laid out" and does not stick. If no message can be stated, either derive one actively at authoring time or do not build the view.
4. **Self-sufficient.** The source MD assumes its author's context (domain vocabulary, frameworks, prior decisions). A fresh reader lacks it. Teach every assumed term **before first use** — a concise definition plus one example in the body, not a glossary at the bottom. For a derived view this teaching stays within `rill-html-output.md` principle 4: unpack and restate only what the sources already contain or directly imply; if a load-bearing explanation is genuinely absent from the sources, add it to the MD source first and then generate — never author it only in HTML. A faithful re-expression is not automatically standalone-understandable. Human-facing text also follows the vault's language rules in full: repair the source's compressed coinages and calques instead of copying them.

## Authoring Procedure

Work these eight steps in order:

1. **Write the message in one sentence.** The single conclusion this page gives the reader. If it cannot be written, do not build the page (or actively establish a claim first when the source is raw research data).
2. **Inventory the source MECE.** Every part of the source maps to exactly one place in the output — this catches both omissions and duplicates. The source remains reachable as layer zero. Scope by view type: a full re-expression (single-document view, handbook) inventories the whole source into the page; a **digest** serving one read moment (e.g. a decision digest) inventories only the material relevant to that moment into the page and preserves everything else through explicit links to the MD sources — the linked source is the retained detail layer, not an omission. Do not replicate whole artifacts into a digest.
3. **Build the argument structure.** BLUF / inverted pyramid: conclusion first, then support, then background — at page level and inside each section. Summarizing is ranking, not deleting.
4. **Route each part through the visualization decision** (next section). If a visual does not add information, keep the text or table. Never ship a figure that discards values.
5. **Choose light interactions** (toolkit below). Static-rich with light controls; never hide load-bearing content — fold only secondary material.
6. **Make connections explicit.** Link every section, every rejected alternative, and every fold back to the message, the backbone (conditions, criteria), or its evidence — as visible markers ("supports X", "violates condition B"). The reader should never wonder "where does this belong?".
7. **Apply the typography and layout rules** (below).
8. **Run the ship check** (below), measure the rendered page where tooling allows, and eyeball a screenshot — numbers alone miss visual collisions, cramped fields, and arbitrary emphasis.

## Visualization Routing

1. **About 20 items or fewer / exact values matter** → **table or one sentence** (a chart only abstracts the precision away).
2. **Patterns, trends, comparisons across a set** → **chart**, in the form that fits the task (slope for change over time, not two pie charts).
3. **Both precision and pattern needed** → **keep both**: table plus chart, sparkline next to values, or chart with details on demand. A chart never replaces the numbers.
4. **Linear, conditional, or exception-heavy content** → **prose or a numbered list**. Draw a figure only when topology (branching, hierarchy, cycles, two axes, swimlanes) *is* the message; a straight-line flow diagram or a figure that drops the exceptions is lossy.
5. **Decoration test** — any element that fails "does this make the data faster or better understood?" or that conveys style rather than quantity: remove it.
6. **Integrity gate** — proportional encoding, no truncated axes, no 3D distortion.

Two gates on every visual: **truthful** (no distortion, no lying by omission) and **functional** (the form fits the reading task).

## Light-Interaction Toolkit

| Element | Fits | Do not use for (failure mode) | How information is preserved |
|---|---|---|---|
| `<details>` folds | Secondary detail, provenance, methodology, long enumerations | Folding essential / load-bearing content | `hidden=until-found` where supported, an expand-all control, open on print |
| Sortable / filterable table | Many items x many dimensions, finding rows that match conditions | — | Controls change the view only; all cells stay in the DOM; visible reset |
| Tabs | Mutually exclusive alternatives (per-language, per-OS, per-tier) | Sequential content or comparisons | Only when the reader picks exactly one alternative; never for ordered reading |
| SVG / CSS diagrams | Process, hierarchy, states, two axes, relationships | "Prose in boxes" | Label every node, keep underlying values visible, provide a text equivalent alongside |
| Color-coded callouts | A small consistent vocabulary (note / warning / tip / example) | Too many; color as the only signal | One or two per document; icon plus label, never color alone (WCAG 1.4.1) |
| Side notes | Sources, confidence, meta commentary (always visible on desktop) | — | Pure-CSS label/checkbox pattern; tap-to-expand on mobile, content stays in the DOM |
| Diagnostic toggles with a verdict | "Which option should *you* pick" pages | Two or fewer branches; interdependent inputs | All criteria, all branches, and a static table stay visible; the toggle only highlights |
| Two-axis map | Real items clustering on two independent dimensions | Plotting labels without items | Score and plot the actual items, label both poles, back it with a sortable table |

**Cross-cutting discoverability invariant**: any interaction that hides content can break find-in-page, screen readers, print, and deep links. Optional material may fold; **load-bearing content never folds**.

## Ship Check

- [ ] **Message**: a one-sentence conclusion opens the page, and everything serves it
- [ ] **Connections**: every section, rejection, and fold is linked to the backbone or its evidence — "where does this belong?" never arises
- [ ] **Lossless re-expression**: every affordance re-ranks, reorders, or subsets salience while keeping all content reachable (nothing removed from the search path)
- [ ] **Discoverability**: hidden material is reachable via find-in-page, screen readers, and print (`hidden=until-found` / expand-all / print styles); nothing load-bearing is folded
- [ ] **Not color alone** (WCAG 1.4.1): callouts and diagram distinctions carry an icon or text as well
- [ ] **Restraint**: one or two callouts max; every visual mark is justified by data encoding
- [ ] **Real items, not decoration**: figures and quadrants plot actual data (an empty labeled grid is chartjunk)
- [ ] **Summary plus full detail**: beneath every distilled verdict, the complete criteria / branches / values remain static and searchable (in a digest, linked MD sources may serve as that full layer — see Authoring Procedure step 2)
- [ ] **Typography** (rules below): system font stack, body size, line height, measure, wrap behavior, consistent content width
- [ ] **Rendered verification**: measure the page (font, body size, prose measure, mobile overflow, console errors) with a headless browser where available, and eyeball a screenshot

## Anti-Patterns

- **Over-visualization / chartjunk** — decorative ink covering the data signal; replacing values with ornament (3D pies).
- **Essentials behind interaction** — folding content the reader must hold simultaneously.
- **Lossy summarizing** — a summary that *replaces* detail instead of preceding it. The reader cannot even notice what was dropped.
- **Decorative chrome / mystery meat** — ornament at the cost of function; unlabeled icons.
- **Accessibility / discoverability regressions** — hidden content vanishing from search, print, or screen readers.
- **Generated-look visual tells** (human judgment decides; expect a correction round): no left-edge accent bars on cards (`border-left: 4px`) — use a full hairline border with radius; no heavy drop shadows — hover feedback via border-color is enough; no rows of saturated solid-fill badges — desaturate, prefer outline badges, at most one strong emphasis mark; avoid pure black on pure white — prefer a near-black warm ink (e.g. `#2c2620`) on a warm off-white paper (e.g. `#faf8f2`); keep color tones consistent across pages; use emoji sparingly.
- **Notation compression in reader-facing text** — equals-sign definitions ("A = B"), slash enumerations ("X / Y / Z"), arrow chains inside prose, label-colon fragments inside sentences or table cells, multi-clause parenthetical stuffing. These are internal note-taking shorthand; re-express them as sentences and comma lists. A page written in them reads as a wall of operators, not prose.
- **Arbitrary inline emphasis** — scattered bold fragments inside card bodies or prose. Let field labels, verdict marks, and badges carry hierarchy; if emphasis is needed, apply it consistently (key metric only).
- **Cramped compound fields** — multi-item fields (e.g. a four-condition verdict) jammed onto one line; give each item its own line and breathing room.

## Typography and Layout

Typography (defaults; tune per script):

- System font stack, sans-serif; do not add web fonts. For CJK-primary pages, lead the stack with the platform's CJK sans (e.g. Hiragino on macOS).
- Body 16-18px; line height about 1.6 for Latin-primary text, about 1.8-1.9 for CJK.
- Prose measure: cap at roughly 40em (roughly 40 full-width characters for CJK), applied to running prose only.
- `overflow-wrap: break-word` — never `anywhere` (it splits words and code mid-token).
- Headings bold (700); for CJK headings enable proportional alternates (`font-feature-settings: "palt"`) — **headings only, never on body text**: `palt` collapses the space after full-width punctuation (。、) and makes prose read cramped. Check punctuation spacing in the rendered screenshot.
- Muted text still meets WCAG AA contrast (4.5:1).

Layout — separate the two widths:

- **Prose measure vs page width.** Only running prose is capped at the measure above. Structural elements — tables, card grids, figures, navigation, flow diagrams — may use the browser width (page max-width around 1080-1200px). Do not squeeze everything into a narrow blog column.
- Use browser-native building blocks: sticky top navigation (anchors + page links), `grid auto-fill minmax()` card grids, full-width filterable tables, side-by-side comparisons.

Two document shapes:

- **Single-document view** (one source or a small set → one page): the eight-step procedure on one page.
- **Aggregated handbook** (many sources → navigable set): split into **multiple pages** — a hub page (framework + index: rank table / card grid / glossary) linking to detail pages with relative links. One dense single page fails for large material. Use **one shared inline `<style>` across all pages** (one template = consistent chrome); when fanning pages out to sub-agents, hand them the template to replicate verbatim, or they diverge.
  - Link into the specific item (`href="detail.html#item-{slug}"` with `id="item-{slug}"` on the target), and auto-highlight the landing card via `:target`. Link text names the item.
  - Avoid `position: sticky` on `<thead>` (it overlaps rows on long pages); offset anchor landings under a sticky nav with `scroll-margin-top` / `scroll-padding-top`.

Hygiene (from `rill-html-output.md`):

- Regenerable derived views go in a `.view/` sidecar (gitignored, invisible to listings and `.md`-scoped search); snapshots are date-named and never regenerated in place — a new read moment gets a new file.
- Views are self-contained (inline styles, no external network dependencies) and start with a provenance comment: `<!-- generated from {md_paths} @ {timestamp} by {skill} -->`.
- Generated HTML carries no frontmatter and is written directly, not via `rill mkfile`.
- A derived view must not carry substantive information absent from its MD sources.
