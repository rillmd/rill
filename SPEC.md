# Rill System Specification

System specification for Rill as an information system. A state machine that uses the filesystem as storage, Git for version control, and Claude Code as its processor.

## 1. System Overview

### 1.1 Purpose

A personal information management system that distills fragmented thoughts entered via voice or text into structured knowledge.

### 1.2 Design Principles

| Principle | Description |
|-----------|-------------|
| **Filesystem = Database** | All data is plain Markdown files. No dedicated DB or indexes |
| **Git = Transaction Log** | All changes tracked by Git. Serves as both version control and audit trail |
| **Claude Code = Processor** | Data transformation, distillation, and analysis are executed by Claude Code skills |
| **Append-only Input** | Original files in inbox/ are immutable. Changes are generated as derivative files |
| **Fully Automated Distillation** | Distillation from inbox/ to knowledge/ is fully automated. Humans retain deletion rights |

### 1.3 Component Architecture

```
+------------------------------------------------------+
|                       User                            |
|  (voice input / text / file placement / URL / query)  |
+------+----------+---+-----------+--------------------+
       |          |   |           |
       v          v   v           v
+-----------+ +-----------+ +--------------+
|inbox/     | | inbox/*/  | | Claude Code  |
|journal/   | | (input    | | (processing  |
|(input     | |  layer)   | |  layer)      |
| layer)    | | meetings  | |              |
+-----------+ | etc.      | +--+-----+-----+
       |      +-----------+   |     |
       |          ^           |     | direct query
       |          |           |     v
       |    +-----+------+   |  +--------------+
       |    | plugins/    |   |  | dynamic      |
       |    | rill sync   |   |  | aggregation  |
       |    | /sync       |   |  | grep/read    |
       |    +-------------+   |  | knowledge/   |
       |          |           |  +--------------+
       +----+-----+          |
            v                 |
      +-------------+        |
      |  /distill    |<-------+
      | (integrated  |
      |  processing) |
      +--+---+---+--+
         |   |   |
         v   v   v
  +------+ +-----+ +----------+ +------------+
  |knowl-| |tasks| |_organized| |knowledge/  |
  |edge/ | |  /  | |(derived) | |(search     |
  +------+ +-----+ +----------+ | anchor)    |
                                 +------------+
      +----------------+
      |  workspace/     |
      |  (workspaces)   |
      +-------+--------+
              | /close -> /distill
              v
       +----------------+
       |knowledge/notes/|
       |  (distilled)   |
       +----------------+
```

---

## 2. Data Entities

### 2.1 Entity List

| Entity | Directory | Nature | State Management |
|--------|-----------|--------|-----------------|
| Journal | `inbox/journal/` | Immutable input | `.processed` |
| Source | `inbox/*/` | Immutable input | `.processed` (with status) |
| Organized | `*/_organized/` | Derived (read-only copy) | Linked to parent's `.processed` |
| Workspace | `workspace/{id}/` | Workspace (updatable) | `_workspace.md` `status` |
| Knowledge | `knowledge/notes/` | Evergreen (updatable) | None (existence = valid) |
| Person | `knowledge/people/` | Search anchor (updatable) | None (existence = valid) |
| Org | `knowledge/orgs/` | Search anchor (updatable) | None (existence = valid) |
| Project | `knowledge/projects/` | Project profile (updatable) | None (existence = valid) |
| Interest Profile | `knowledge/me.md` | User interest profile (updatable) | None (single file) |
| Task | `tasks/*.md` | Ticket file (ADR-063) | frontmatter `status` |
| Daily Note | `reports/daily/` | Generated output (updatable) | Date file existence |
| Newsletter | `reports/newsletter/` | Generated output (updatable) | Date file existence |
| Ad-hoc Report | `reports/` subdirectories | Generated output (updatable) | frontmatter `type` + `title` |
| Page | `pages/` | Materialized View (updatable) | frontmatter `updated` |
| Recipe | `pages/*.recipe.md` | Page generation definition | None (existence = valid) |
| Taxonomy | `taxonomy.md` | Master data | None (single file) |

### 2.2 Immutability Rules

The following entities must not be modified once created:

- `inbox/journal/*.md` — original files
- `inbox/*/*.md` — original files (exception: frontmatter addition only, requires user confirmation)
- `workspace/{id}/NNN-*.md` — numbered deliverable files

The following entities are updatable:

- `knowledge/notes/*.md` — Evergreen principle. Git handles versioning
- `knowledge/people/*.md` — Status changes, alias additions, key fact accumulation, etc.
- `knowledge/orgs/*.md` — Status changes, alias additions, key fact accumulation, etc.
- `knowledge/projects/*.md` — Competitors, Watch Keywords, key fact updates (/distill auto-accumulates)
- `knowledge/me.md` — Interest Profile updates (/distill Phase 4 auto-updates, manual updates also allowed)
- `workspace/{id}/_workspace.md` — Status changes, workspace information updates
- `workspace/{id}/_log.md` — Session history appending
- `tasks/*.md` — Task ticket addition and state changes
- `taxonomy.md` — Tag additions and merges

---

## 3. State Machine

### 3.1 Journal Lifecycle

```
                    rill log "text"
                         |
                         v
               +------------------+
               |   unprocessed    |  inbox/journal/{name}.md exists
               |                  |  not listed in .processed
               +--------+---------+
                        | /distill Phase 1
                        |
                +-------+--------+
                |                |
                v                v
   +-----------------+  +---------------+
   |   organized     |  |  knowledge/   |
   | _organized/{name}| |  distilled    |
   +-----------------+  +---------------+
                |                |
                +-------+--------+
                        v
               +------------------+
               |    processed     |  filename listed in .processed
               +------------------+
```

**State determination logic**:
- `unprocessed`: File exists in `inbox/journal/*.md` and is not listed in `inbox/journal/.processed`
- `processed`: Filename is listed in `inbox/journal/.processed`

**`.processed` format**: One filename per line (no path prefix)
```
2026-02-13-1921.md
2026-02-13-1950.md
```

### 3.2 Source Lifecycle

```
          file placement          rill clip <URL>
               |                     |
               |    +----------------+
               v    v
              +-----------------+
              |   unprocessed   |  inbox/*/{name}.md exists
              |                 |  not listed in .processed
              +--------+--------+
                       | /distill Phase 2
                       v
              +-----------------+
              |    organized    |  _organized/{name}.md created
              |                 |  .processed has name:organized
              +--------+--------+
                       | /distill Phase 3
                +------+------+
                |             |
                v             v
     +---------------+ +--------------+
     |   extracted   | |   skipped    |
     | distilled to  | | explicitly   |
     | knowledge/    | | skipped      |
     +---------------+ +--------------+
```

**State determination logic**:
- `unprocessed`: File exists in `inbox/*/*.md` and is not listed in `.processed`
- `organized`: Listed in `.processed` as `filename:organized`
- `extracted`: Listed in `.processed` as `filename:extracted`
- `skipped`: Listed in `.processed` as `filename:skipped`

**`.processed` format**: `filename:status`
```
2026-02-16-meeting.md:organized
2026-02-15-paper.md:extracted
2026-02-10-article.md:skipped
```

**State transition conditions**:

| Transition | Trigger | Condition |
|-----------|---------|-----------|
| unprocessed → organized | `/distill` Phase 2 | Automatic |
| organized → extracted | `/distill` Phase 3 | Automatic |

### 3.3 Workspace Lifecycle

```
                    /focus
                       |
                       v
              +-----------------+
              |     active      |  _workspace.md status: active
              |                 |  interactively accumulate deliverables
              +--------+--------+
                       | /close
                       v
              +-----------------+
              |   completed     |  _summary.md generated
              |                 |  status: completed
              +-----------------+
```

**State determination logic**:
- `active`: `_workspace.md` frontmatter `status: active` (`pilot`, `planning` also treated as active)
- `completed`: `_workspace.md` frontmatter `status: completed`
- `on-hold`: `_workspace.md` frontmatter `status: on-hold`

**Directory structure**:
```
workspace/{id}/
├── _workspace.md            # State management + MOC (always kept up-to-date)
├── _summary.md              # Exists only when completed
├── _log.md                  # Session history (optional)
├── 001-description.md       # Deliverable (immutable)
├── 002-description.md       # Deliverable (immutable)
├── .processed               # Tracks distilled files via /distill single-file mode (updated on /close)
└── _organized/              # Existing organized files (if any)
```

### 3.4 Knowledge Lifecycle

```
              /extract-knowledge
              or /distill Phase 1
                       |
                       v
              +-----------------+
              |     active      |  knowledge/notes/{name}.md exists
              |  (Evergreen)    |  updatable (Git handles versioning)
              +-----------------+
```

Knowledge has no explicit state transitions. If it exists, it is valid. Content is updatable under the Evergreen principle, with Git history retaining all versions.

### 3.5 Entity (Person / Org) Lifecycle

```
              /distill Phase 2.5
              or manual creation
                       |
                       v
              +-----------------+
              |     active      |  knowledge/people/{name}.md exists
              |  (updatable)    |  knowledge/orgs/{name}.md exists
              |                 |  frontmatter updates allowed anytime
              +-----------------+
```

Entities, like Knowledge, have no explicit state transitions. If they exist, they are valid.

**Loose coupling between tasks/ and workspaces (ADR-029)**: Task tickets (`tasks/*.md`) are linked to projects via `mentions: [projects/{id}]`. No 1:1 correspondence with workspaces is required. Workspaces are created only when deliverable accumulation or deep thinking is needed.

**Workspace completion condition principle (ADR-029)**: All workspaces must have clear completion conditions. Areas (responsibility domains without end conditions) must not be workspaces. If an area is needed, decompose it into concrete projects.

**Design principles for knowledge/people/ and knowledge/orgs/**:
- **Search anchor**: Serves as the starting point for grep. Retrieves id/aliases/tags from entity files and performs cross-directory searches
- **Normalization hub**: The `aliases` field manages name variants (e.g., Jane Smith / J. Smith) in one place
- **Key fact accumulation**: The body contains distilled knowledge (key facts). /distill auto-accumulates, updating under the Evergreen principle
- **What NOT to write**: Interaction history (chronological event logs), task lists (duplicated from tasks/), aggregation results (related file lists, etc.) must not be appended to entities. These chronological and cross-cutting aggregations are dynamically executed by Claude Code via grep/read

---

## 4. Metadata Schema

### 4.1 inbox/journal/ frontmatter

```yaml
---
created: 2026-02-13T10:58+09:00    # Required: ISO 8601 + TZ
---
```

### 4.2 inbox/journal/_organized/ frontmatter

```yaml
---
created: 2026-02-13T10:58+09:00    # Inherited from original file
organized: true                     # Fixed value
---
```

### 4.3 inbox/*/ frontmatter

```yaml
---
created: 2026-02-16T10:58+09:00    # Required
source-type: meeting                # Required: meeting | article | paper | note | tweet | web-clip | other
original-source: "Google Meet"      # Optional: origin of the source data
---
```

**Additional fields for source-type: tweet**:
```yaml
---
created: 2026-02-24T10:30+09:00
source-type: tweet
url: "https://x.com/user/status/12345"   # Required: tweet URL
tweet-id: "12345"                          # Required: tweet ID
---
```

`/distill` Phase 2 uses the FixTweet API (`https://api.fxtwitter.com/{user}/status/{id}`) to fetch the body text. Also supports Twitter Articles (long-form). Fallback: oEmbed API (`https://publish.twitter.com/oembed`).

**Additional fields for source-type: web-clip**:
```yaml
---
created: 2026-02-16T15:30+09:00
source-type: web-clip
url: "https://example.com/article"   # Required: source URL
title: "Article Title"               # Required: page title
og-description: "Summary text"       # Optional: OGP description
og-image: "https://example.com/img"  # Optional: OGP image URL
---
```

### 4.4 inbox/{type}/_organized/ frontmatter

```yaml
---
created: 2026-02-16T10:58+09:00    # Inherited from original file
source-type: meeting                # Inherited from original file
original-file: inbox/{type}/{name}.md    # Required: back-reference to original file
original-source: "Google Meet"      # Inherited from original file
tags: [tag1, tag2]                  # AI-assigned
participants: [Name1, Name2]        # Source-type dependent additional metadata
---
```

### 4.5 workspace/{id}/ frontmatter

**_workspace.md**:
```yaml
---
created: 2026-02-13T19:50+09:00    # Required
updated: 2026-04-02T17:00+09:00    # Optional: last updated timestamp (auto-set by rill touch hook)
type: workspace                     # Required: fixed value
id: rill-development                # Required: matches directory name
name: Rill Development              # Required: display name
status: active                      # Required: active | completed | on-hold | pilot | planning
origin: inbox/journal/2026-02-13-1950.md  # Optional: origin file
tags: [rill]                        # Optional: max 3
mentions: [projects/rill]           # Optional: typed entity references (ADR-066)
client: Client Name                 # Optional: client name
---
```

**Deliverable files**:
```yaml
---
created: 2026-02-16T17:30+09:00    # Required
topic: rill-development             # Required
type: research                      # Required: progress | research | analysis | decision | review
tags: [rill]                        # Optional: max 3
mentions: [projects/rill]           # Optional: typed entity references (ADR-066)
---
```

**_summary.md**:
```yaml
---
created: 2026-02-16T22:00+09:00    # Required
topic: rill-development             # Required
type: summary                       # Fixed value
---
```

### 4.6 knowledge/notes/ frontmatter

```yaml
---
created: 2026-02-16T15:00+09:00                     # Required
updated: 2026-04-02T17:00+09:00                     # Optional: last updated timestamp (auto-set by rill touch hook)
type: insight                                        # Required: record | insight | reference
source: inbox/journal/_organized/2026-02-13-1950.md        # Required: source path
tags: [data-architecture, system-design]             # Optional: max 3
mentions: [people/person-id, orgs/org-id, projects/project-id]  # Optional: typed entity references (ADR-053, ADR-066)
related:                                             # Optional: related file paths
  - knowledge/notes/other-file.md
---
```

Note: The `mentions` field is usable not only in knowledge/notes/ but in all file types including workspace/_workspace.md, deliverable files, task tickets, etc. (ADR-066 D66-1). Project linking is also done via `mentions: [projects/{id}]`.

**Type definitions**:

| Type | Definition | Criteria |
|------|-----------|----------|
| `record` | Record of facts, data, or observations | Verifiable objective information |
| `insight` | Personal observations or interpretations | Insights derived from multiple facts |
| `reference` | Quotation of external knowledge | Others' ideas. Cite the source |

### 4.7 reports/daily/ frontmatter

```yaml
---
created: 2026-03-11T08:00+09:00    # Required
type: daily-note                    # Fixed value
date: 2026-03-11                    # Required: target date
journal-count: 3                    # Required: number of target journals
---
```

Note: Daily Note is a prose report generated by `/briefing`. Integrates forward-looking (today's focus) + backward-looking (yesterday's activity). Tasks are collected from ticket files in tasks/.

### 4.8 reports/newsletter/ frontmatter

```yaml
---
created: 2026-03-11T08:00+09:00    # Required
type: newsletter                    # Fixed value
date: 2026-03-11                    # Required: target date
keywords: [keyword1, keyword2]      # Required: keywords used for search
source-count: 15                    # Required: number of referenced sources
---
```

Note: Newsletter is a daily research report generated by `/newsletter`. Performs web searches based on user's projects and interests, generating prose reports with a 3-layer structure: fact → interpretation → implication (D31).

### 4.9 Ad-hoc report frontmatter

```yaml
---
created: 2026-03-15T00:00+09:00    # Required
type: newsletter-analysis           # Required: any string (not daily-note or newsletter)
title: "Report Title"               # Recommended: displayed in sidebar. Falls back to H1 → filename
date: 2026-03-14                    # Required: target date
source: reports/newsletter/2026-03-14.md  # Optional: analysis source
---
```

Note: Ad-hoc reports are analysis/research reports generated on request via Claude Code. All `type` values other than daily-note and newsletter are treated as ad-hoc. Can be placed in any subdirectory under `reports/` or directly under the root (D44).

### 4.9.1 reports/ searchability (D61)

reports/ are generally immutable snapshots after generation, but they are included in skill search targets. Since the content becomes part of the user's knowledge once read, it needs to be searchable as part of Rill's responsibility for knowledge externalization.

- /focus: Includes reports/ as a Grep search target in Phase 1 context collection and Phase 3 resume context
- /briefing: Can reference report content within the activity window
- /newsletter: References newsletters from the past 2 weeks (existing, no change)

reports/ content is NOT auto-distilled to knowledge/notes/. Auto-distilling AI output risks accumulating stale information and degrading knowledge/notes/ quality. For deep exploration, distill via the /focus → /close path with human curation (ADR-061).

### 4.10 Task ticket files (ADR-063)

Tasks are managed as individual files (tickets) at `tasks/{slug}.md`.

**Frontmatter schema**:

```yaml
---
created: 2026-03-24T10:00+09:00
updated: 2026-04-02T17:00+09:00    # Optional: last updated timestamp (auto-set by rill touch hook)
type: task
source: inbox/journal/_organized/2026-03-23-182737.md
tags: [project-phoenix]
mentions: [people/jane-smith, projects/project-phoenix]
status: open               # draft | open | waiting | someday | done | cancelled
due: 2026-03-25             # Due date (optional)
scheduled: 2026-03-28       # Start date or event date (optional; independent from due)
related:
  - knowledge/notes/acme-project-phoenix-contract-terms.md
---
```

**Status values**:

| Status | Meaning | Action needed? |
|--------|---------|---------------|
| `open` | You need to take the next action | Yes |
| `waiting` | Waiting for someone else's action | No (monitoring) |
| `someday` | Not active now but want to do someday | No |
| `done` | Completed | No |
| `cancelled` | Cancelled | No |

No `priority` field. Urgency is calculated from `due` and `scheduled`:
- `scheduled > today` (planned) → excluded from urgent
- `due ≤ today + 7d` AND no `scheduled` or `scheduled ≤ today` → urgent
- `scheduled ≤ today` AND has incomplete actions → urgent

`scheduled` represents "when to work on it / when it takes place." Independent from `due` (deadline). Used for meeting/event dates or planned start dates.

**Body structure**:

```markdown
# Title — Context

## Goal
(What constitutes completion. Output format and success criteria)

## Background
(Why this task is needed)

## Context
(Optional. Related file links, research summaries, dependencies. Can be lengthy)

## Request
(Optional. Requests from creator to executor. Direction, constraints, scope boundaries. Free text)

## History
- YYYY-MM-DD: Event
```

`rill task` CLI auto-generates the section scaffold. `--background` pre-sets background text, `--context` pre-sets context (related file links, etc.). Goal can be empty at capture time (filled during /solve understanding phase). Request is optional (added by creator as needed).

**Lifecycle**: Captured (just created: title + background only) → Ready (goal + context sufficient) → In Progress (execution records in history log) → Done.

**Creation flows**:
- During `/focus` session: AI proposes → user approves → generated
- CLI: `rill task "Title"` for Quick Capture
- `/distill`: Interactive skill only (non-interactive only proposes in prose within reports)

**After completion**: Retained with `status: done`. Manually convertible to `type: record` if needed.

**Example**:
```markdown
---
created: 2026-03-15T14:32+09:00
type: task
source: inbox/journal/_organized/2026-03-15-143200.md
tags: [project-phoenix]
mentions: [people/jane-smith, projects/project-phoenix]
status: open
due: 2026-03-25
---

# Jane Smith Follow-up — Check Contract Signing Status

## Goal
Complete John Doe's contract signature via Jane Smith and update the invoice status in the accounting SaaS.

## Background
Contract sent via e-signature service on 3/15. Signature requested from John Doe via Jane Smith.

## Request
Confirm signing status by 3/25. After signing is complete, update invoice status in accounting SaaS.

## History
- 3/23: Not yet signed. Jane Smith reports waiting for John Doe's response
- 3/18: Followed up via Slack
- 3/15: Contract sent via e-signature service
```

### 4.11 knowledge/people/ frontmatter

```yaml
---
created: 2026-02-18T10:00+09:00       # Required: ISO 8601 + TZ
type: person                           # Required: fixed value
id: jane-smith                         # Required: unique short identifier. Used in @mentions
name: Jane Smith                       # Required: full name
aliases: [Jane, J. Smith]              # Required: list of name variants
company: acme-corp                     # Optional: references knowledge/orgs/ id
role: IT Systems Lead                  # Optional: job title
relationship: client                   # Optional: client | partner | colleague | other
tags: [project-phoenix]                # Optional: max 3
---

IT Systems Lead at Acme Corp. Primary contact for Project Phoenix deployment and operations.

## Key Facts
- Has technical concerns about IMAP migration (prefers to keep POP operations)
- Emphasizes security requirements, interested in SOC2 certification
- Internal approval route: section manager → department head
```

frontmatter = search anchor + normalization hub. Body = distilled key facts (auto-accumulated by /distill under Evergreen principle). The company field references the id in knowledge/orgs/.

### 4.12 knowledge/orgs/ frontmatter

```yaml
---
created: 2026-03-14T00:00+09:00       # Required: ISO 8601 + TZ
type: org                              # Required: fixed value
id: acme-corp                          # Required: unique short identifier (kebab-case)
name: Acme Corporation                 # Required: official name
aliases: [Acme, Acme Corp, ACME]       # Required: list of name variants
industry: hospitality                  # Optional: industry
relationship: client                   # Optional: client | partner | vendor | other
tags: [project-phoenix]                # Optional: max 3
---

Large group-affiliated resort hotel operator. Currently deploying Project Phoenix.

## Key Facts
- Tourist destination large-scale resort hotel
- IT department is small (Jane Smith is the primary contact)
- High awareness of security and compliance
```

The `company` field in knowledge/people/ references the `id` in knowledge/orgs/. See §3.5 for design principles.

### 4.13 knowledge/projects/ frontmatter

```yaml
---
created: 2026-03-14T01:00+09:00       # Required: ISO 8601 + TZ
type: project                          # Required: fixed value
id: project-phoenix                    # Required: unique short identifier (kebab-case)
name: Project Phoenix                  # Required: project name
stage: active                          # Required: active | idea | completed
entity: example-studio                 # Optional: knowledge/orgs/ id (operating entity)
relationship: own                      # Optional: own | client-work | oss | personal
tags: [project-phoenix]                # Optional: max 3
---

Project overview description.

## Goal
- Success criteria 1
- Success criteria 2

## Current Focus
What is currently being worked on (/distill auto-updates).

## Watch

### Competitors            # Optional subsection (business projects only)
- **Competitor Inc.** — Description

### Keywords               # Optional subsection (/newsletter integration)
- "keyword1"
- "keyword2"

## Key Facts
- Fact 1 (/distill auto-accumulates. Max 20 items)

## See Also
- [task-xxx](../../tasks/task-xxx.md) — Related task
- [workspace/xxx/](../../workspace/xxx/) — Workspace name
```

Projects are initiatives the user is actively pursuing. Regardless of business, personal, or learning context, and regardless of whether they have completion conditions (ADR-049). Independent from workspace/ (no 1:1 correspondence required). /distill auto-updates "Current Focus," "Key Facts," and "See Also." /newsletter uses Watch > Keywords for Alert search keyword generation. Stage has 3 levels: `active` (in progress), `idea` (concept stage), `completed` (done).

### 4.14 knowledge/me.md frontmatter

```yaml
---
created: 2026-03-14T01:00+09:00       # Required: ISO 8601 + TZ
type: interest-profile                 # Required: fixed value
updated: 2026-03-14                    # Required: last updated date (/distill Phase 4 auto-updates)
---
```

User's interest profile. Single file. Composed of Core Identity, Active Projects (links to knowledge/projects/), and Interests (Deep Interests / Curiosity / Obligations / Career). Referenced by /newsletter as the Identity layer during search strategy construction (Phase 1). Auto-updated by /distill Phase 4.

### 4.15 workspace/{id}/_workspace.md template

_workspace.md serves as both workspace metadata and MOC (Map of Contents). See 4.5 for the frontmatter schema.

**For information-rich workspaces**:

```markdown
# Workspace Name

(Overview)

## Status

- **Phase**: Current phase
- **Tasks**: N/M complete (TODO X / WAITING Y)
- **Last Updated**: YYYY-MM-DD

## Related Tasks

-> Dynamically search tickets from tasks/ (linked via mentions)

## Related People

- @people/person-id — Role

## Knowledge Map

Organized by major topic.

### Category Name
- [file.md](../../knowledge/notes/file.md) — Summary

## Deliverables

- [001-description.md](001-description.md) — Summary
- [002-description.md](002-description.md) — Summary

## Recent Activity

- YYYY-MM-DD: Activity description
```

**Lightweight template** (for Deep Think-style workspaces):

```markdown
# Theme Name

(Theme overview)

## Issues

- [ ] Issue 1
- [ ] Issue 2

## Deliverables

- [001-description.md](001-description.md) — Summary
```

**Status definitions** (simplified in ADR-049):

| Status | Description | UI Color |
|--------|-------------|----------|
| `active` | In progress | green-500 |
| `completed` | Done | gray-400 |

### 4.16 pages/ frontmatter (ADR-062)

```yaml
---
created: 2026-03-24T10:00+09:00       # Required: ISO 8601 + TZ
type: page                             # Required: fixed value
id: body-recomposition                 # Required: matches filename (kebab-case)
name: Body Recomposition Strategy      # Required: display name
description: Aggregation of training strategy, dietary guidelines, and weekly log  # Required: one-line description
updated: 2026-03-24T08:00+09:00       # Optional: last updated timestamp (auto-set by rill touch hook. Unified from refreshed per ADR-071)
tags: [fitness]                        # Optional: topic tags
sources:                               # Optional: structured source file path array
  - knowledge/notes/training-strategy.md
---
```

Pages are aggregated documents that humans repeatedly reference (Materialized Views). Excluded from AI search targets (/distill, /briefing, /eval do not Grep pages/). Flat directory + tag management. When directly editing, first write to the canonical source (inbox/, knowledge/) then reflect to Pages.

### 4.17 pages/*.recipe.md frontmatter (ADR-062)

```yaml
---
created: 2026-03-24T10:00+09:00       # Required: ISO 8601 + TZ
type: recipe                           # Required: fixed value
---
```

Recipe is a file that describes page generation/update definitions in natural language. Includes sources, aggregation rules, structure, and notes. `/page update` and `/page rebuild` always read the recipe before updating pages. The recipe governs which sections receive what data in what format.

---

## 5. Processing Pipelines

### 5.1 /distill — Integrated Distillation Pipeline (D48)

A flat orchestrator-style integrated distillation command. Processes using external templates (`.claude/commands/_distill/`) + plugin distill.md + parallel agent spawning.

```
Architecture:
  distill.md (~100-line orchestrator)
    +-- _distill/journal-agent.md   — Phase 1 journal distillation
    +-- _distill/knowledge-agent.md — Phase 3 knowledge extraction (also ref'd by /close)
    +-- _distill/task-extraction.md — Task extraction rules (shared definition)
    +-- _distill/profile-agent.md   — Phase 4 Interest Profile update
    +-- plugins/*/distill.md        — Phase 2 source-type-specific organization (plugins)

  close.md (workspace distillation, ADR-072)
    +-- Reads knowledge-agent.md + uses _summary.md as filter

Parallel execution groups:
  Group 1: Phase 1 + 2 (mutually independent, max 5 parallel)
  Group 2: Phase 2.5 + 3 (depends on Group 1 output, mutually independent and parallelizable)
  Group 3: Phase 4 + 5 (depends on all Phase results)

Phase 1: inbox/journal/ distillation
  Input:  inbox/journal/*.md (unprocessed)
  Process: Organize + knowledge extraction + task extraction + key fact appending via _distill/journal-agent.md
  Output: inbox/journal/_organized/*.md, knowledge/notes/*.md, knowledge/people/*.md
  State:  Append to inbox/journal/.processed

* Workspace distillation is executed directly in parent context by /close (ADR-072)

Phase 2: inbox/*/ organization (plugin routing)
  Input:  inbox/*/*.md (unprocessed)
  Process: Plugin Discovery resolves source-type -> plugin
           plugins/{name}/distill.md (if matching plugin exists)
           plugins/_default-distill.md (if no match)
  Output: inbox/{type}/_organized/*.md, tasks/*.md
  State:  Append to inbox/*/.processed as name:organized

Phase 2.5: Automatic entity extraction
  Input:  participants: and tags: from inbox/{type}/_organized/ processed in Group 1
  Process: Cross-reference with knowledge/people/, knowledge/orgs/ -> auto-create new entities
  Output: knowledge/people/*.md, knowledge/orgs/*.md

Phase 3: Automatic knowledge extraction
  Input:  Files with status=organized in inbox/*/.processed
  Process: Knowledge extraction via _distill/knowledge-agent.md (Glob/Grep Evergreen check)
  Output: knowledge/notes/*.md (with mentions)
  State:  Update inbox/*/.processed to extracted

Phase 4: Interest Profile update
  Input:  Summary of all Phase 1-3 processing results
  Process: Update knowledge/me.md via _distill/profile-agent.md
  Output: knowledge/me.md

Phase 5: Post-distill Hooks
  Input:  plugins/*/hooks/post-distill.md
  Process: Plugin-specific post-processing (failures are non-fatal)

Shared context (injected by orchestrator into each agent):
  - taxonomy_yaml: Tag vocabulary in YAML list format (D46-3)
  - people_mapping: People entity one-line mapping
  - orgs_mapping: Orgs entity one-line mapping
  - projects_mapping: Projects entity one-line mapping
  - entity_ids: All entity IDs (/repair only)
  * knowledge/notes/ filename list is deprecated (D48-2). Each agent explores via Glob/Grep

Evergreen check (D48-2):
  Old: Pass full filename list (~6,200 tokens) to agents
  New: Each agent explores via Glob/Grep
    1. Extract 3-5 search terms from key concepts
    2. Glob("knowledge/notes/*{keyword}*") for candidate search
    3. Grep("{concept}", knowledge/notes/) for content search
    4. Same topic found -> skip / not found -> create new

Batch processing policy (D14 + D48):
  1. Pre-load: taxonomy.md + entity mappings (once in parent context)
  2. Process each file in an independent Agent (max 5 parallel)
  3. Templates are Read by agents themselves (not pre-read by parent)
  4. After result collection, batch-update .processed + run rill strip-entity-tags
```

### 5.2 /repair — Metadata Batch Repair

```
/repair:
  Input:  knowledge/.refresh-queue (populated by /inspect)
  Process: Update tags/mentions/type via _distill/repair-agent.md
           Preserve existing related values (no changes)
  Post-process: rill strip-entity-tags (deterministic entity ID removal)
  Output: knowledge/notes/*.md (frontmatter updates only)

Responsibility separation:
  /distill  — Intake of new information (inbox/ -> knowledge/)
  /inspect  — Quality diagnosis + queue population (knowledge/ health check)
  /repair   — Metadata repair (.refresh-queue batch processing)
  /eval     — Metadata quality quantitative assessment (calibration)

Batch design:
  - 70 items/agent limit, max 4 parallel
  - Shared context: full taxonomy (including deprecated tags) + entity mapping
  - New tag creation prohibited (only approved tags from taxonomy.md)
  - Prefer specific sub-tags over mega-tags (50+ occurrences)
```

### 5.3 /focus → /close — Workspace Pipeline (D28)

```
/focus:
  1. Workspace detection or theme input
     - With argument: open workspace for specified path/theme
     - Without argument: display list of active workspaces
  2. Context collection (cross-search knowledge/notes/, inbox/journal/, inbox/*/, workspace/)
  3. Create workspace/{YYYY-MM-DD}-{topic}/, generate _workspace.md (for new workspaces)
  4. Interactive phase (accumulate deliverables as NNN-*.md)
  5. Continuously update _workspace.md
  Backward compat: Search priority _workspace.md > _session.md > _project.md

/close:
  1. Identify active workspace
  2. Analyze all deliverables, generate _summary.md
  3. Cross-reference with .processed and warn if undistilled files exist
  4. Change _workspace.md status to completed
```

### 5.4 /briefing — Daily Note Generation Pipeline (D30)

```
  Input:  tasks/*.md, workspace/*/_workspace.md,
          past 3 days of inbox/journal/ and knowledge/notes/,
          inbox/ unprocessed count, git log
  Process: Internal data collection -> prose report generation (fully automated, no dialogue)
  Output: reports/daily/YYYY-MM-DD.md
  State:  File existence serves as processed marker. Re-execution overwrites (versions saved in Git history)
```

**Key changes (D30, changes from former D19-3)**:
- Merged `/daily-report`: Forward-looking (today's focus) + backward-looking (yesterday's activity) combined into single Daily Note
- Output location changed from `workspace/daily/` to `reports/daily/`
- Fully automated: abolished interactive task review (Phase 1.5)
- WebSearch separated to `/newsletter` (separate skill)
- Assistant mode abolished (generate report and exit)
- Prose report quality: prose with context and recommended actions as the base, not bullet-point lists
- Tasks collected from ticket files in tasks/
- InboxBanner information included in body (snapshot, not a GUI component)
- Re-execution overwrites without confirmation (versions retained in Git history)

### 5.5 /newsletter — Daily Research Report Pipeline (D31)

```
  Input:  workspace/*/_workspace.md (active), tasks/*.md,
          past 7 days of knowledge/notes/, past 3 days of inbox/journal/
  Process: Context collection -> keyword extraction (max 8)
           -> WebSearch (independent search per keyword)
           -> WebFetch (full content of top 5 important results)
           -> prose report generation
  Output: reports/newsletter/YYYY-MM-DD.md
  State:  File existence serves as processed marker. Re-execution overwrites (versions saved in Git history)
```

**Keyword extraction priority**:
1. Project-specific themes (2-3) — from active workspaces
2. Recent knowledge (1-2) — from past 7 days of knowledge/notes/
3. Task-derived (1-2) — from TODO/WAITING tasks
4. Core interests (1-2) — from journals

**Report structure**: Executive summary → theme-based sections (3 layers: fact → interpretation → implication) → research metadata

---

## 6. Link Structure

### 6.1 Reference Graph

```
knowledge/notes/{name}.md
  +-- source: inbox/{type}/_organized/{name}.md    <- References organized version
                +-- original-file: inbox/*/{name}.md  <- Back-reference to original

knowledge/notes/{name}.md
  +-- source: inbox/journal/_organized/{name}.md    <- References organized version
                (original is inbox/journal/{name}.md, traceable via filename correspondence)

knowledge/notes/{name}.md
  +-- source: workspace/{id}/{NNN}-{desc}.md  <- Directly references deliverable

knowledge/notes/{name}.md
  +-- related: knowledge/{other}.md            <- Inter-knowledge relationships

workspace/{id}/_workspace.md
  <- id functions as tag: linked to knowledge/ and inbox/*/ via tags: [project-phoenix]
  <- tasks/*.md linked via mentions: [projects/{id}]
  <- _log.md records session and decision history chronologically

knowledge/people/{name}.md
  <- Referenced by tasks/*.md via mentions: [people/person-id]
  <- Discoverable via participants: in inbox/{type}/_organized/
```

### 6.2 Path Format

- Relative paths from repository root
- No leading `/`
- Standard Markdown links `[text](path)`. No Wikilinks `[[]]`

### 6.3 _organized/ Priority Read Rule

When reading a file referenced by `source:`, if an identically-named file exists in `_organized/`, prefer reading that version. This ensures AI always accesses structured, organized data.

---

## 7. Tag System

### 7.1 Management Method

- `taxonomy.md` is the sole tag vocabulary master
- AI-managed (assignment, creation, monthly merges)
- No human involvement required

### 7.2 Constraints

| Item | Rule |
|------|------|
| Assignment targets | Files in knowledge/, inbox/{type}/_organized/, knowledge/people/ |
| Count limit | Max 3 per file |
| Format | Inline array `tags: [a, b]` |
| Naming | Lowercase kebab-case |
| New tags | Check existing tags and aliases first, then add to taxonomy.md if not found |
| Maintenance | Monthly automated merge and cleanup by AI |

---

## 8. CLI Interface

### 8.1 Commands

| Command | Purpose |
|---------|---------|
| `rill log [text]` | Add text to inbox/journal/. Opens editor if no argument |
| `rill i` / `rill interactive` | Interactive mode. Continuous input separated by blank lines |
| `rill push` | git add -A && commit && push |
| `rill status [n]` | Display recent n journal entries |
| `rill clip <url>` | Fetch URL metadata and save to inbox/web-clips/ |
| `rill edit` | Open latest journal in editor |
| `rill plugin <sub>` | Plugin management (list, install, uninstall, status) |
| `rill sync [name]` | Execute plugin adapters to sync external sources |
| `rill mkfile <dir>` | Create file with accurate timestamp (for Claude Code skills) |

### 8.2 Claude Code Skills

| Skill | Trigger | Role |
|-------|---------|------|
| `/morning` | Manual or automated | Daily user-facing reports: `/briefing` + `/newsletter` in parallel via `claude -p` (D58, D75). `/sync` and `/distill` are not chained — run them separately; see `docs/guides/scheduling.md` |
| `/distill` | Manual or scheduled | Integrated distillation pipeline. No args = batch, with args = single-file distillation (D58) |
| `/briefing` | /morning or manual | Daily Note generation. Notes section surfaces unprocessed inbox count + /sync /distill recommendation (D30, D75) |
| `/newsletter` | /morning or manual | Daily research report generation (D31) |
| `/focus` | Manual | Start/resume workspace (D28) |
| `/close` | Manual | Complete workspace (D28) |
| `/maintain` | Manual or automated | Quality maintenance: /inspect → /repair (D58) |
| `/page` | Manual | Pages creation, update, rebuild (D62) |
| `/clip-tweet` | Manual | Tweet ingestion |
| `/plugin` | Manual | Interactive plugin management (with guidance, diagnostics, and suggestions) |
| `/sync` | Manual or scheduled | Interactive external source sync + /distill chain suggestion (D75) |
| `/sync-google-meet` | Called from /sync | Interactive Google Meet notes import |
| `/sync-voice-memo` | Called from /sync | Interactive voice memo sync |

**GUI Integration Metadata (ActionMenu)**:

Adding an optional `gui:` field to a skill's frontmatter auto-registers it in the GUI ActionMenu. No GUI code changes needed.

```yaml
gui:
  label: "/extract-knowledge"         # Command name displayed in ActionMenu
  hint: "Extract atomic knowledge and save to knowledge/notes/"  # One-line skill description
  match:                              # Glob patterns for valid file paths
    - "inbox/**/*.md"
    - "workspace/**/*.md"
  arg: path                           # path | workspace-id | none
  order: 40                           # Display order (lower = higher. Recommend increments of 10)
```

| Field | Type | Description |
|-------|------|-------------|
| `label` | string | Command name displayed in ActionMenu (e.g., `/review`) |
| `hint` | string | One-line skill description. Shown as ActionMenu subtext |
| `match` | string[] | Glob patterns for file paths where this skill is valid |
| `arg` | enum | Argument construction method. `path` = current file path, `workspace-id` = workspace ID, `none` = no argument |
| `order` | number | Display order priority. Lower = displayed higher. Default 99 (bottom) when unspecified |

- `gui:` supports single entry (flat format) or multiple entries (YAML list `- label:` format)
- Skills without `gui:` are not shown in ActionMenu (CLI only)
- Skills are resolved by glob-matching `match` patterns against the current FileViewer file path
- Class A skills (`arg: none`, system-wide operations) are handled in InboxBanner or empty states, not ActionMenu

**Context budget design principle**:

Guidelines for file reading within skills. As Rill data accumulates, unlimited file scanning overwhelms the context window.

- Each skill must specify file reading limits (e.g., "max 20, newest first")
- Reference /distill's ADR-014 pattern (pre-loading + compression + agent separation)
- `tasks/` is searched by multiple skills (`/briefing`, `/distill`). Filter targets by status as file count grows
- Grep-based searches naturally narrow via keywords, but set count limits for large result sets
- /close workspace distillation is an exception: since all files are already read in Phase 1, execute directly in parent context without delegating to sub-agents. Reference knowledge-agent.md extraction rules and use _summary.md as a filter. knowledge-agent.md Read budget does not apply (ADR-072)

### 8.3 Plugin System

Implements data ingestion from external services as interchangeable "plugins."

**Design principles**:
- Rill is the "destination," not the "sync engine." Data transport mechanisms are separated as plugins
- "Directory = Plugin" principle (Tier 3): install = directory addition + symlink, uninstall = symlink removal
- plugin.md = human-readable documentation, directory structure = manifest (no AI parser needed)
- 2-layer management: `rill plugin` (shell, mechanical) + `/plugin` (Claude Code, interactive)

**Skill distribution model**:

Tier 1-2 skills are distributed from the source repository (`~/.rill/source/`) to vaults. Initial copy via `rill init`, sync to latest via `rill update`. Distribution targets are recorded in the vault's `.rill/managed-files.txt` (Category A: managed). User-created skills (`personal-*.md`, `my-*.md`) are unmanaged and untouched by `rill update`.

**3 Tier classification**:

| Tier | Description | Examples | Distribution Method |
|------|-------------|---------|-------------------|
| Tier 1: Core | System foundation skills | `/distill`, `/briefing`, `/plugin`, `/sync` | `managed-files.txt` (auto-sync via `rill update`) |
| Tier 2: Built-in | Standard workflows | `/focus`, `/close` | `managed-files.txt` (auto-sync via `rill update`) |
| Tier 3: External | Plugin-provided skills | `/sync-meetings` | `plugins/*/commands/` → symlink to `.claude/commands/` |

**Directory structure**:
```
plugins/
├── README.md           # Plugin development contract
├── _lib.sh             # Shared library (create_source_file, etc.)
├── _default-distill.md # Fallback distill prompt (D33)
├── .gitignore          # Common: *.synced, *.config
└── {plugin-name}/      # Individual plugin
    ├── plugin.md       # Documentation + frontmatter (source-type, inbox-dir)
    ├── adapter.sh      # Transport script (executed by rill sync)
    ├── distill.md      # Source-type-specific distill prompt (optional, D33)
    ├── commands/       # Skill originals
    │   └── *.md        # Symlinked to .claude/commands/ on install
    └── .gitignore      # Exclude .synced
```

**plugin.md frontmatter** (D33, D38):
```yaml
# Existing (source only) — no change
---
source-type: meeting      # source capability: source-type this plugin claims
inbox-dir: inbox/meetings # source capability: ingestion target directory
---

# New: plugin with multiple capabilities
---
source-type: sales-contact        # source capability (optional)
inbox-dir: inbox/contacts          # source capability (optional)
data-dir: data                     # workflow capability: plugin-specific data
search-scope: true                 # workflow capability: Claude Code search target (explores plugin data-dir)
hooks:                             # hooks capability
  post-distill: hooks/post-distill.md
  briefing: hooks/briefing.md
---
```

**Capability model** (D38):

| Capability | Provides | Example |
|-----------|----------|---------|
| source | adapter.sh, distill.md, inbox-dir | google-meet |
| workflow | commands/, data/ | CRM |
| hooks | post-distill, briefing, etc. | CRM |

Hook execution spec: /distill scans plugins/ after all Phases complete → execute hooks as sub-agents → failures are non-fatal (log and continue).

**distill.md pattern** (D33):
- `/distill` Phase 2 reads `plugins/*/plugin.md` frontmatter, building a `source-type → plugin` mapping
- If a matching plugin exists for a file's source-type, Reads `plugins/{name}/distill.md` for the agent prompt
- No plugin (tweet/web-clip) → hardcoded fallback
- Otherwise → `plugins/_default-distill.md`

**Install / uninstall flow**:
- `rill plugin install <name>`: Create relative symlinks from `plugins/{name}/commands/*.md` to `.claude/commands/`
- `rill plugin uninstall <name>`: Remove symlinks in `.claude/commands/` pointing to this plugin. Directory is preserved

---

## 9. System Invariants

The following conditions must always hold:

1. **Input immutability**: Original files in `inbox/journal/*.md` and `inbox/*/*.md` must not be modified once created
2. **State consistency**: Every file listed in `.processed` must have a corresponding `_organized/` file
3. **Link integrity**: `source:` paths in knowledge/ must point to existing files
4. **Tag consistency**: All tags used in knowledge/ must be listed in `taxonomy.md`
5. **Workspace uniqueness**: Only one `_workspace.md` per directory
6. **Number continuity**: `NNN-*.md` files within workspace/{id}/ are sequentially numbered from 001 with no gaps
7. **Frontmatter requirement**: All .md files must have frontmatter (inbox/journal/ original files require only `created`)
8. **Distillation automation**: Distillation from inbox/ to knowledge/ is fully automated. Humans exercise post-hoc deletion rights
9. **Entity ID uniqueness**: All entity `id` fields across knowledge/ (people/ + orgs/) must be system-wide unique. No duplicate `id` values
10. **Entity knowledge accumulation**: Body text in knowledge/people/ and knowledge/orgs/ contains distilled knowledge (key facts). However, the following must NOT be written:
    - Interaction history (chronological event logs)
    - Task lists (duplicated from tasks/)
    - Aggregation results (related file lists, interaction lists, etc.)
    These chronological and cross-cutting aggregations are dynamically executed by Claude Code via grep/read
11. **Normalization consistency**: The `aliases` field is the sole normalization hub for name variants. Task `mentions: [people/person-id]` uses the `id` field from knowledge/people/
12. **Loose coupling of tasks/ and workspaces**: Task tickets (`tasks/*.md`) are linked to projects via `mentions: [projects/{id}]`. No 1:1 correspondence with workspaces is required (ADR-029)
13. **Workspace completion conditions**: All workspaces must have completion conditions. Areas (responsibility domains without end conditions) must not be workspaces (ADR-029)
14. **PII container encryption**: Files in knowledge/people/ and knowledge/orgs/ are encrypted with git-crypt. Contact information (phone numbers, email addresses, etc.) must be stored only in these directories and not in non-encrypted files like knowledge/notes/ (ADR-047)
15. **Pages AI search exclusion**: pages/ is a human-facing Materialized View and excluded from AI search. /distill, /briefing, /eval do not Grep pages/. Page updates are only performed by `/page` skill, which always reads the recipe first (ADR-062)

---

## 10. File Naming Conventions

| Directory | Naming Pattern | Example |
|-----------|---------------|---------|
| inbox/journal/ | `YYYY-MM-DD-HHmmss.md` | `2026-02-13-105830.md` |
| inbox/*/ | `YYYY-MM-DD-description.md` | `2026-02-16-acme-meeting.md` |
| inbox/*/ (web-clip) | `YYYY-MM-DD-HHmmss-title-slug.md` | `2026-02-16-153000-article-title.md` |
| workspace/ (date-prefixed) | `{YYYY-MM-DD}-{topic}/` | `2026-02-13-rill-development/` |
| workspace/ deliverables | `NNN-description.md` | `001-journal-review.md` |
| tasks/ | `{slug}.md` (kebab-case) | `acme-project-phoenix-followup.md` |
| knowledge/notes/ | `{description}.md` (kebab-case) | `ai-tool-pricing-justification.md` |
| knowledge/people/ | `{id}.md` (kebab-case) | `jane-smith.md` |
| knowledge/orgs/ | `{id}.md` (kebab-case) | `acme-corp.md` |
| workspace/{id}/ | `{id}/` (kebab-case) | `project-phoenix/` |
| reports/daily/ | `YYYY-MM-DD.md` | `2026-03-11.md` |
| reports/newsletter/ | `YYYY-MM-DD.md` | `2026-03-11.md` |
| reports/ (ad-hoc) | `YYYY-MM-DD-slug.md` | `2026-03-14-analysis.md` |
| pages/ | `{id}.md` (kebab-case, no date prefix) | `body-recomposition.md` |
| pages/ (recipe) | `{id}.recipe.md` | `body-recomposition.recipe.md` |
| plugins/ | `{plugin-name}/` (kebab-case) | `google-meet/` |

### 10.1 Timestamp Design Principles (ADR-060)

Rill adopts an append-only log structure where chronological display is the foundation of the entire system. Timestamp accuracy directly impacts data reliability.

#### Principle 1: Never let LLMs generate timestamps

LLMs round times or write inaccurate values. Timestamps for filenames and `created` fields must be generated programmatically.

- **File creation**: Use the `rill mkfile` command. The tool ensures both filename naming conventions and `created` frontmatter
- **Journals**: `rill log` / Electron IPC (`journal:save`) generates via `date` command / `new Date()`
- **Web Clips**: `rill clip` generates

#### Principle 2: Separation of `created` and `date`

| Field | Meaning | Example |
|-------|---------|---------|
| `created` | Actual time the file was created (ISO 8601) | `2026-03-23T11:41+09:00` |
| `date` | Date the file belongs to (reports only) | `2026-03-23` |

`created` is always the actual generation time. `date` indicates "which day this report covers." When regenerating a report for a past date, `created` is the regeneration time while `date` is the specified date.

#### Principle 3: Chronological sort reliability hierarchy

```
filename timestamp > rill CLI-generated created > file mtime > LLM-written created
```

The GUI timeline sort follows this hierarchy (`ipc.ts` `timeKey()` function).

#### `rill mkfile` command

```bash
rill mkfile <directory> [--slug <name>] [--type <type>] [--date <YYYY-MM-DD>] [--field key=value ...]
```

- Auto-generates filename following the directory's naming conventions
- `created` uses actual time obtained via `date` command
- `--date` overrides filename and `date` field (`created` remains actual time)
- On collision, appends suffix (`-1`, `-2`, ...)
- Outputs repository-root-relative path to stdout

---

## 11. Search Strategy

### 11.1 Current Method

Direct frontmatter search via ripgrep. No indexes.

```bash
# Search by tag
rg -l 'tags:.*project-phoenix' knowledge/

# Search by type
rg -l '^type: insight' knowledge/

# Search by date
rg -l '^created: 2026-02-16' inbox/journal/

# Search for active workspaces
rg -l '^status: active' workspace/*/_workspace.md
```

### 11.2 Scalability

| File Count | Estimated Response Time | Action |
|-----------|------------------------|--------|
| ~500 (1 year) | 10-30ms | None needed |
| ~2,500 (3 years) | 30-80ms | None needed |
| ~5,000 (5 years) | 50-100ms | None needed |
| ~10,000 (10 years) | 100-200ms | Consider yearly splitting of inbox/journal/ |
| ~50,000+ | 500ms+ | Consider SQLite index introduction |

---

## 12. Documentation Management

### 12.1 Distinction Between PKM Data and System Documentation

Two types of data coexist in the Rill repository:

| Category | Directories | Content | Change Frequency |
|----------|-------------|---------|-----------------|
| **PKM Data** | inbox/journal/, inbox/*/, workspace/, knowledge/, tasks/, reports/ | User's thoughts, external inputs, distilled knowledge | Daily |
| **System Documentation** | SPEC.md, docs/, CLAUDE.md | Rill's own design, specifications, decisions | On system changes |

These two are clearly distinguished. PKM Data is the "content" managed by Rill, while System Documentation is the "blueprint" of Rill itself.

### 12.2 SPEC.md

- System specification for Rill as an information system
- Documents state machine, metadata schema, processing pipelines, and invariants
- Must be updated whenever system design changes

### 12.3 ADR (Architecture Decision Records)

- Format: `docs/decisions/NNN-title.md`
- Records technical decisions and their rationale
- Workspace discussions (thought processes) and ADRs (finalized decisions) are separate:
  - workspace/{id}/ = thinking/project workspace (exploration, discussion, research)
  - docs/decisions/ = record of finalized decisions (traceability)
- ADRs contain reference links to workspace discussion history

### 12.4 ADR List

See developer supplement [`docs/SPEC-app.md`](docs/SPEC-app.md) §1 for the ADR list. ADR files are only managed within the `rill-dev` repository (internal operations documentation, not for public release).

---

## 13. Desktop App (app/)

See developer supplement [`docs/SPEC-app.md`](docs/SPEC-app.md) §2 for Electron desktop app (app/) specifications. Covers tech stack, IPC, window model, Terminal Integration, Write-back, File Change Detection, and Markdown Rendering.

---

## 14. Security (ADR-047)

### 14.1 PII Encryption

Transparent encryption via git-crypt. Plaintext locally, ciphertext on remote (GitHub).

Encryption targets (defined in `.gitattributes`):

| Directory | Reason |
|-----------|--------|
| `knowledge/people/*.md` | Person entities (contact information) |
| `knowledge/orgs/*.md` | Organization entities |
| `plugins/sales-crm/data/**/*.md` | CRM deal data |

Encryption method: AES-256-CTR (deterministic encryption with SHA-1 HMAC-derived synthetic IV)

### 14.2 PII Container Isolation Principle

Sensitive PII (contact information) is consolidated in encrypted containers (people/, orgs/, crm data/). Personal names appearing in knowledge/notes/ are acceptable, but contact information (phone numbers, email addresses, etc.) must not be recorded there.

### 14.3 Binary PII Handling

Binary files containing PII (e.g., business card images) must not be committed to Git (`.gitignore`). Keep locally only. For encrypted backup needs, use git-annex + S3 or Restic.

### 14.4 Pre-commit PII Detection

A pre-commit hook detects and warns when phone number or email address patterns are committed to non-encrypted files. The hook script is stored in the source repository at `bin/hooks/pre-commit-pii-check.sh` and installed to the vault's `.git/hooks/pre-commit` via `rill crypt init`.

### 14.5 Key Management

- Export the symmetric key via `git-crypt export-key` and back up to a secure location (e.g., 1Password)
- If the key is lost, encrypted files cannot be decrypted (recovery from pre-encryption Git history is possible)
- `rill crypt init` handles git-crypt auto-initialization + key backup guidance + pre-commit hook installation. `rill crypt doctor` (`rill doctor`) checks encryption status
