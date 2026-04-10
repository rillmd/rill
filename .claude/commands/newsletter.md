---
gui:
  label: "/newsletter"
  hint: "Generate daily research report"
  match:
    - "reports/**/*.md"
  arg: none
  order: 70
  mode: auto
---

# /newsletter — Daily News

Performs web searches based on the user's Interest Profile, Project entities, workspaces, and journals (3-layer context), generating a daily news report focused on **discovering unknowns + alerts**. Fully automated (no interaction).

## Arguments

$ARGUMENTS — one of the following:
- `YYYY-MM-DD` (e.g., `2026-03-11`) → Generate report for the specified date
- Omitted → Generate report for today

## Procedure

### Phase 0: Initialization + Deduplication Data Collection

1. If argument is `YYYY-MM-DD`: Use that date as target
2. If argument omitted: Use today's date as target
3. If `reports/newsletter/YYYY-MM-DD.md` already exists: Overwrite without confirmation (version history in Git)
4. If `reports/newsletter/` directory doesn't exist, create it

**3-Layer Context Collection** (execute in parallel):

5. **Identity: Interest Profile** — Read `knowledge/me.md` (~50 lines)
6. **Identity: Project Entities** — Read all `knowledge/projects/*.md` (get Competitors, Watch Keywords)
7. **Attention: Workspaces** — From all directories under `workspace/`, read `_workspace.md` (or `_session.md`) for **workspaces created within the past 2 weeks**, extracting (regardless of status — both active and completed):
   - `# heading` (workspace name)
   - Description text immediately after heading (1-2 lines)
   - Directory name (date + topic slug)
   - ※ Don't depend on tags or name: field as they can be unreliable. Use heading + description
8. **Impulse: Journals** — Read full text of past 7 days of files from `inbox/journal/` (~100 lines). Prefer `_organized/` version if same-named file exists. From journals, extract only **project/career/technology/business-related topics** as interest signals (ignore shopping, daily logs, etc.). Do not include emotions or personal information in newsletter body

**Deduplication Data Collection** (execute in parallel with above):

9. **Past 2 weeks of newsletters** — Read past 2 weeks from `reports/newsletter/`, extracting:
   - Used keywords (`keywords` frontmatter)
   - Referenced URLs (main sources section)
   - Covered topics (section headings)
10. **Known knowledge index** — Glob `knowledge/notes/*.md` filename list (for known information filtering)

### Phase 1: Search Strategy Construction

Integrate the 3-layer context (Identity / Attention / Impulse) and generate search keywords divided into **3 categories**.

**3-Layer Context Model**:
- **Identity** (me.md + projects/): Stable interest categories. Changes monthly
- **Attention** (workspace/ past 2 weeks): Currently active themes. Changes weekly
- **Impulse** (journal/ past 7 days): Not-yet-formed interests/thoughts. Changes daily

#### Alert Category (2-3 items) — Focused on detecting changes

**Source**: knowledge/projects/ Competitors + Watch Keywords + me.md Career
**Purpose**: Detect competitor movements and changes directly affecting projects

- Generate keywords from each Active Project's Watch Keywords and major competitor names
- Include Career section monitoring targets (e.g., "Anthropic Japan hiring")
- Obligations: Only keywords for detecting major changes like regulatory/institutional changes
- **`watch-domestic: true`** projects must include at least 1 Japanese keyword
- **Alert is only for "specific changes affecting project management decisions"**: Competitor pricing changes, feature releases, fundraising, partnerships, executive moves. Industry-wide trends or technology standard developments go in Discovery, not Alert

#### Deep Dive Category (1-2 items) — Thorough investigation

**Source**: me.md Deep Interests + **weighted by Attention layer (workspace themes)**
**Purpose**: Deeply explore one theme to a level where user thinks "I didn't know that"

- Select 1-2 themes from Deep Interests
- **Workspace weighting**: Themes being worked on in past 2 weeks' workspaces get higher selection probability (e.g., CRM design workspace exists → CRM × AI latest trends as Deep Dive candidate)
- **Journal weighting**: Business/tech themes mentioned in past 7 days' journals are also included as candidates (e.g., "want to release Rill" → OSS PKM tool release strategy)
- **Forced rotation**: Do not select themes overlapping with past 2 weeks' newsletter covered topics
- Evaluate theme's "depth potential": Avoid themes unlikely to yield new info on deeper investigation (e.g., fixed content like invoice system rules)
- Generate 2-3 search keywords per theme (varying angles)

#### Discovery Category (2-3 items) — Findings & Recommendations

**Source**: me.md Curiosity + **adjacent areas of Attention/Impulse layers**
**Purpose**: "If you're interested in this, you might find that interesting too"

- Select themes from Curiosity section
- **Workspace adjacent exploration**: The "neighbor's neighbor" of recent workspace themes yields highest-value Discoveries
  - e.g., During CRM feature design → conversational CRM, AI-native CRM latest trends
  - e.g., During content marketing automation → AI ghostwriting ethics, synthetic media
- **Journal-originated exploration**: Include themes appearing in journals but not yet as workspaces
- **Adjacent exploration**: Consciously seek the "neighbor's neighbor" of Deep Interests and Active Projects
  - e.g., Interested in Claude Code → compiler theory, programming language design
  - e.g., PKM × AI → cognitive science, spaced repetition
- Prioritize topics not yet in knowledge/notes/ filename list
- **Serendipity**: OK to intentionally include 1 "unexpected" topic

**Common Keyword Generation Rules**:
- Prefer English keywords (for web search coverage)
- Make phrases specific ("Claude Code agent SDK release 2026" not "AI")
- Include the search year for latest information
- **Keywords used in past 2 weeks' newsletters are prohibited**
- Record category name (Alert/DeepDive/Discovery) and 1-line selection rationale as internal notes for each keyword

### Phase 2: WebSearch Execution

For each keyword generated in Phase 1:

1. Search with WebSearch tool (each keyword independent, execute in parallel where possible)
2. Collect top 3-5 results from each search
3. **Determine publication date where possible** (from URL, snippet, article content)
4. **Deduplication**: Exclude URLs referenced in past 2 weeks' newsletters
5. Aggregate all results into temporary lists by category

### Phase 3: Deep Investigation

Fetch full content with WebFetch by category:

#### Alert Category
- Select only articles where **actual change occurred** for each competitor/monitoring target (3-5 articles)
- **Freshness filter**: Only articles published within the past 2 weeks qualify as Alert candidates. Older articles are not accepted as Alerts (may be covered in Deep Dive or Discovery)
- If no changes detected, don't force article retrieval
- **Primary source verification (required)**: Alert candidate facts **must be verified by WebFetching primary sources (official sites, official announcements, first-party pages)** before inclusion. Do not compose Alerts solely from secondary sources (news articles, blogs). Example: hiring info → WebFetch official careers page, feature release → WebFetch official blog/changelog, fundraising → WebFetch press release. If primary source cannot be WebFetched, explicitly state in Alert body ("could not verify from official page")

#### Deep Dive Category
- **WebFetch top 8-10 most important results** for the selected theme
- Prioritize primary information (official announcements, papers, official docs over blog aggregation articles)

#### Discovery Category
- WebFetch top 3-5 results per theme

**Common WebFetch Tasks**:
- **Publication date confirmation**: Determine from in-article dates, URL patterns, bylines
- Deep Dive / Discovery: If WebFetch fails, may substitute with search result snippets
- **Alert: Snippet-only substitution prohibited**. If primary source WebFetch fails, either explicitly state in Alert body or exclude from Alerts
- Silently skip timeouts and 403 errors (but follow above rules for Alert primary source verification failures)

**Selection Criteria**:
- **Freshness is top priority**: Strongly prefer articles from past 1-2 weeks
- **Known information filter**: Skip content clearly overlapping with knowledge/notes/ filenames
- High relevance to user's projects

### Phase 4: Report Generation

Generate at `reports/newsletter/YYYY-MM-DD.md` with the following structure.

#### File Creation

First create the file with `rill mkfile` (to ensure timestamp accuracy):

```bash
rill mkfile reports/newsletter --type newsletter \
  --field "keywords=[keyword1, keyword2, ...]" \
  --field "source-count=N" \
  --field "alert-count=N" \
  --field 'deep-dive-topic="Theme name"' \
  --field "discovery-count=N"
# For specific date: add --date YYYY-MM-DD
```

Then use Edit to append body to the output path (frontmatter is pre-generated by `rill mkfile`).

#### Template

```markdown
# YYYY-MM-DD Daily News

## Alerts

(Generate section only if changes detected. If none, use single line "No notable developments")

> ⚡ [1-line change summary] — YYYY-MM-DD

(Prose with details. Start with time anchor like "On Month Day,".
What changed, why it matters, impact on projects.
Inline source URL + publication date: [Title](URL) (YYYY-MM-DD).
200-400 characters per Alert. Keep Obligations alerts concise.
**Timeline is critical information**: Never be vague about when a change occurred)

---

## Deep Dive: [Theme Name]

> Sources: YYYY/M — YYYY/M (composed primarily from articles in the past N days)
> Why this theme: (1-line explanation of which Interest Profile category and why)

(Prose. Minimum 1000 characters. Write in 3-layer structure:

1. **Facts**: What is happening. Inline source URLs and publication dates
   - Format: [Title](URL) (YYYY-MM)
   - Unknown date: [Title](URL) (date unknown)
2. **Interpretation**: What it means. Technical/business context
3. **Implications**: How it affects user's projects and interests

**Freshness differentiation**: Clearly distinguish between recent developments (past 1-2 weeks)
and background context (older information) at the paragraph level.
Never write old information as if it were new news)

---

## Discovery

### [Theme Name]: [1-line why this is recommended]

(Prose. 300-500 characters. Explicitly state connection points to user's existing interests.
Recommended format: "If you're interested in X, here's why Y is worth watching...")

### [Theme Name]: [1-line why this is recommended]

(Same. 2-3 Discovery sections)

---

## Research Metadata

- **Search Keywords**:
  - Alert: keyword1, keyword2
  - Deep Dive: keyword3, keyword4
  - Discovery: keyword5, keyword6
- **Information Freshness**: YYYY-MM-DD — YYYY-MM-DD
- **Source Count**: N items
- **Interest Profile Reference**: Deep Interests [theme], Curiosity [theme]
- **Key Sources**:
  - [Title](URL) (YYYY-MM)
  - ...
```

### Post-output

Display a summary (3-5 lines) and finish. Do not transition to assistant mode.

## Rules

- **Fully automated**: No interaction. Everything from keyword selection to generation is automatic
- **Prose-based**: Write engaging prose, not bullet point lists
- **All facts require source URL + publication date**: No hallucination. Use only information obtained from WebSearch/WebFetch, with source URLs and publication year-month for all facts
- **Explicit information freshness**: Never write old information as new news. Clearly distinguish "latest developments" from "background information" at the paragraph level in the body
- **Convey the unknown**: Avoid repeating information the user already knows (topics in knowledge/notes/). Prioritize new information, new perspectives, new connections
- **Interest Profile is a guide**: Don't be overly constrained by categories. Especially in Discovery, unexpected suggestions are welcome
- **Alert only when change occurs**: If no change, summarize as "No notable developments." Don't force-create sections
- **Deep Dive goes deep**: 1000+ characters. Not a superficial summary, but deep enough to make the reader think "I didn't know that"
- **Thorough deduplication**: Eliminate overlap with past 2 weeks' keywords, URLs, and topics
- **Re-execution overwrites**: Version history is in Git
- **Never modify inbox/ original files** (read-only)
