# HTML Output Rules — Rill

Markdown is the vault's canonical format; HTML is how humans read it. This rule defines when HTML files exist in a vault, where they live, how they are named, what gets committed, and what the AI reads on resume. Layer rules (`rill-outputs.md`, `rill-workspace.md`, `rill-tasks.md`) defer to this file for HTML policy.

The underlying asymmetry: AI reads and writes long Markdown cheaply; humans absorb a structured HTML page far better than a wall of Markdown. The vault therefore keeps two layers — Markdown as the machine-facing source of truth, HTML as the human-facing reading surface — and never lets the second layer become a write surface.

## HTML Classes

Every HTML file in a vault belongs to one of four classes:

| Class | Role | MD canonical? | Typical examples | Git |
|---|---|---|---|---|
| **A. Derived view** | Human-readable projection of one or more MD sources; regenerable | Yes | `.view/` digests, handbooks, book reading views (`rill book build`); same-basename report twins | `.view/` sidecars gitignored; same-basename twins committed |
| **B. Primary HTML** | The HTML *is* the deliverable; no MD twin | No | UI mocks, architecture / comparison diagrams, plugin templates | Committed |
| **C. Judgment / handoff surface** | Presents a decision, status, or walkthrough to the user | Either | Decision digests, run digests, plan reviews, meeting runbooks | Committed unless generated as a `.view/` sidecar |
| **D. External presentation** | Material for people outside the vault | Either | Meeting handouts, client-facing documents | Committed (archival) |

The commit boundary is regenerability, not class: anything that can be rebuilt from MD sources on demand lives in a `.view/` sidecar and stays out of git; anything that is a deliverable in its own right is committed. Two deliberate exceptions are regenerable yet committed for archival value: committed archival twins (same-basename report twins, principle 6), and class D external deliverables generated from MD — handed to people outside the vault, so the shipped version is preserved in git even though it could be rebuilt.

## Global Principles

1. **Markdown canonical.** Every internal artifact with an MD source keeps Markdown as its source of truth. Diagrams embedded in derived views keep their source (Mermaid, SVG) on the MD side so the AI can edit them.
2. **Derived HTML is read-only.** HTML generated from MD sources (class A, and class C/D when derived) is never hand-edited and never a write-back target — edits go to the MD source and the view is regenerated. Class B — and any class C/D file authored without an MD source — is the exception: the HTML file *is* the source, and the AI creates and revises it directly when asked. Skill search globs stay `.md`-scoped in all cases.
3. **Resume reads MD only.** `/focus`, `/solve`, `/distill`, and any other resume path Read `.md` files; the skip applies to derived HTML — anything regenerable from MD sources — which is never loaded into AI context during resume or search. HTML-canonical artifacts (class B, and class C/D authored without an MD source) are the exception: when resuming work that targets such an artifact, the agent reads it, because the HTML is the only record of its current state; resumes not targeting it still skip it. (Working directly on a specific HTML deliverable at the user's request likewise reads that file.)
4. **No HTML-only information in derived output.** Views generated from MD sources may reorder, summarize, and teach, but must not carry substantive information absent from those sources — reading the MD always yields full context. Files whose HTML is the source (class B, source-less C/D) are exempt by definition.
5. **Naming.** Regenerable derived views — single- or multi-source — go into a `.view/` directory next to their sources (dot-prefixed: invisible to listings and AI search); `.view/` placement is the default for any render not kept as an archival deliverable. A committed archival twin (the deliberate exception in the commit boundary above, e.g. a report twin) swaps the extension in place (`foo.md` → `foo.html`, same directory, same basename). Standalone class B/C/D files use normal artifact naming (`NNN-{desc}.html`).
   The dot prefix hides `.view/` from the AI only (search, resume); the GUI's reading surface still lists its contents under a Read shelf, so a derived render is never invisible to the person it was rendered for (ADR-086).
6. **Commit policy** (revised 2026-08, supersedes the earlier "commit all HTML, never gitignore" decision, which shipped implementation reversed — ADR-085). Primary and handoff HTML (classes B, C, D) is committed. Derived `.view/` sidecars are gitignored (`**/.view/` in the managed `.gitignore` block) and regenerated on demand. Committed class A twins are allowed where archival value exists but must honor principle 4.
7. **Expressiveness is unconstrained (L0).** No mandated template; the AI chooses presentation per context. The only hard constraints are technical. Self-containment: a single-page render is one self-contained file (styles inline, no external network dependencies); a multi-page `.view/` view is self-contained at the directory level — relative references to co-located assets and sibling pages are allowed, but nothing outside the view directory tree beyond its MD sources. Current `rill book build` output predates this requirement (it leaves remote image URLs in place and links local images outside the view directory) and is exempt until the builder embeds or copies assets; new generators must meet it. Provenance: derived views identify their source and generator via a head comment `<!-- generated from {md_path} @ {timestamp} by {skill} -->` or equivalent generator metadata (e.g. a `generator` meta tag plus a visible footer attribution, as `rill book build` emits). These constraints govern pages generated at read moments; persistent generation templates (`plugins/{name}/templates/`) are generation sources, not generated pages — new templates should avoid external network dependencies, but templates that predate this rule are exempt until next revised.
8. **Generation failure is non-fatal.** If HTML generation fails, the producing skill still succeeds with Markdown alone.

## When HTML Is Generated

HTML is generated at **read moments** — the points where a human reads in order to judge — not continuously and not as a 1:1 mirror of every MD file. The table below is the doctrine's target wiring: `rill book build` is shipped; the `/focus`, `/close`, and `/project` generation steps are wired into those skills progressively. Until a producer implements its step, that read moment is served on explicit user request.

| Read moment | Producer | Output |
|---|---|---|
| Decision point during a live session | `/focus` | Decision digest snapshot → `workspace/{id}/.view/` (dated; a snapshot serves that one read moment and is disposable afterwards — the judged content and the decision record live in MD, so losing the sidecar loses nothing durable) |
| Workspace completion | `/close` | Aggregated handbook (single or multi-page) → `workspace/{id}/.view/` |
| Project review (status / end of an autonomous run) | `/project` | Project digest with pending decisions → `projects/{slug}/.view/` |
| Book reading | `rill book build` | Fixed-style reading view → `pages/{id}/.view/` |
| Explicit user request | any skill | Ad-hoc render, placed per the class rules above |

Two anti-patterns this model replaces:

- **1:1 mirroring** — generating an HTML twin for every MD artifact produces unread files and constant regeneration cost.
- **Continuous regeneration during a volatile phase** — a live-updated view of work still in flux rots the moment it is built. While content is volatile, Markdown is the working surface; a dated snapshot generated at the read moment is always correct *as of that moment*.

Staleness is handled by regeneration at the next read moment, never by hooks that chase every MD edit.

## Layer-by-Layer Operations

| Layer | Default | HTML appears as | Class | AI resume reads |
|---|---|---|---|---|
| `inbox/` (all types) | MD only | Handout derivative under `_organized/` (ad-hoc) | C/D | MD (`_organized/` preferred) |
| `knowledge/` | MD only | Never | — | MD |
| `workspace/{id}/` | MD artifacts | Mocks / diagrams as committed artifacts; digests and handbooks under `.view/` | B; A/C | `.md`; an HTML-canonical artifact only when it is the resumed work's target (principle 3) |
| `tasks/{slug}/` | MD artifacts | Ad-hoc plan / review / guide renders | C | MD |
| `projects/{slug}/` | MD | Project digest under `.view/` | A/C | MD |
| `pages/` | MD (human-canonical documents) | Book reading view under `pages/{id}/.view/` | A | — (pages excluded from AI search) |
| `reports/` | MD | Optional same-basename twin (`{date}.html`, committed, ad-hoc) | A | MD |
| `plugins/{name}/templates/` | HTML templates | Persistent generation sources | B | — (expanded at runtime) |
| `.claude/`, `docs/`, `taxonomy.md`, `activity-log.md` | MD only | Never | — | MD |

HTML files carry no frontmatter and are not created via `rill mkfile` — producing skills write them directly (`rill-data-model.md`, `rill-claude-code-integration.md`).

## Cross-Reference

- `rill-outputs.md` — reports/ and pages/ specifics, including books and `rill book build`
- `rill-workspace.md` — file-first principle; workspace artifact conventions
- `rill-tasks.md` — task artifact conventions
- ADR-085 — pages as human-canonical documents; the `.view/` gitignored sidecar
