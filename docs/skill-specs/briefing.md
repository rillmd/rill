# /briefing — Information Architecture Document (IAD)

Behavioral specification for /briefing. A fully automated (no interaction) skill that generates a Daily Note.

---

## 1. Input/Output Definition

### Input

| ID | Input | Condition |
|----|-------|-----------|
| IO-I1 | `tasks/*/_task.md` (status: open/waiting) | Filtered via Grep |
| IO-I2 | `inbox/journal/*.md` (within activity window) | Identified by briefing-context.sh |
| IO-I3 | `knowledge/notes/*.md` (created within activity window) | Identified by briefing-context.sh |
| IO-I4 | `activity-log.md` (entries within activity window) | Time range filter |
| IO-I5 | `workspace/**/_workspace.md` (status: active) | Filtered via Grep |
| IO-I6 | `reports/daily/*.md` (most recent 1 file) | Previous briefing |
| IO-I7 | `reports/newsletter/*.md` (current day) | Existence check |

### Output

| ID | Output | Condition |
|----|--------|-----------|
| IO-O1 | `reports/daily/YYYY-MM-DD.md` | Always generated. Overwrites existing |

---

## 2. Invariants

| ID | Invariant | Verification Method | Status |
|----|-----------|---------------------|--------|
| INV-01 | Original files in inbox/ are not modified | File hash comparison | ✅ |
| INV-02 | Frontmatter contains `created`, `type: daily-note`, `date`, `journal-count` | Field check | ✅ |
| INV-03 | File created via `rill mkfile` | created precision check | ✅ |
| INV-04 | Output file path is `reports/daily/YYYY-MM-DD.md` | Path check | ✅ |
| INV-05 | Body text in user's preferred language, technical terms in English | ⚠️ LLM judgment | ✅ |

---

## 3. Section Structure Rules

| ID | Rule | Verification Method | Status |
|----|------|---------------------|--------|
| SC-01 | Title is `# YYYY-MM-DD Daily Briefing` (weekday goes in the main-theme line, not the H1; the H1 stays verbatim in every output language) | grep `^# ` | ✅ |
| SC-02 | Activity section exists: `## Today's Flow` (v3 canonical) or `## Yesterday's Activity` (v2 fallback) | grep `^## .*Flow\|^## .*Yesterday\|^## .*Activity` | ✅ |
| SC-03 | Focus section exists: `## ⚠️ Today's Focus` or `## ★ Today's Focus` (v3) or `## Today's Focus` (v2 fallback) | grep `^## .*Focus\|^## .*Today` | ✅ |
| SC-04 | Cards section exists: `## In Parallel (N)` (v3 canonical) or `## Situation Analysis` (v2 fallback) | grep `^## .*Parallel\|^## .*Situation\|^## .*Analysis` | ✅ |
| SC-05 | `## Notes` section exists (may be omitted if no information) | grep (optional) | ✅ |
| SC-06 | Discards section exists: `## Narrowed out` (v3 canonical) or `## Related` (v2 fallback, conditional) | grep `^## .*Narrowed\|^## .*Related` | ✅ |
| SC-07 | Each section is prose-based (not bullet-point lists) — exception: the In Parallel cards use the fixed 4-element schema (Stuck / Next step / Resume / Source) as bulleted | ⚠️ LLM judgment | ✅ |

Section-name rows above state the **canonical English** headings. The skill renders headings in the vault's configured language (`.claude/rules/personal-language.md`; English when absent) — the grep patterns verify the English-default fixture vault; localized vaults render translated equivalents.

---

## 4. Task Display Rules

| ID | Rule | Verification Method | Status |
|----|------|---------------------|--------|
| TK-01 | Tasks are collected from ticket files (tasks/*/_task.md) | Source confirmation | ✅ |
| TK-02 | Focus targets: due within 7 days / waiting / matching projects of active WSs | ⚠️ LLM judgment | ✅ |
| TK-03 | Reference links use relative path format — `[Title](../../tasks/{slug}/_task.md)` or `[Title](../../workspace/{id}/_workspace.md)` (v3: 5-item narrowing may produce all-workspace briefings; at least one link of either kind must be present) | regex | ✅ |
| TK-04 | Waiting tickets display `waiting` in backticks **when surfaced as a card**. In v3, waiting tickets may collapse into the "Narrowed out" count summary without surfacing as a card, in which case the literal `waiting` token may not appear — TK-04 is informational only in this case | grep (optional) | ✅ |
| TK-05 | Overdue tasks are detected and displayed | ⚠️ LLM judgment | ✅ |
| TK-06 | done, draft, cancelled, someday statuses are not Read | Log confirmation | ✅ |

---

## 5. Data Collection Rules

| ID | Rule | Verification Method | Status |
|----|------|---------------------|--------|
| DC-01 | Activity window is based on day_boundary (03:00) | briefing-context.sh | ✅ |
| DC-02 | Journal prefers reading from _organized/ | Path confirmation | ✅ |
| DC-03 | knowledge/notes/ Read limited to max 10 files | Count | ✅ |
| DC-04 | Read previous briefing (most recent 1 file excluding current day) | File confirmation | ✅ |
| DC-05 | Retrieve list of journal filenames from past 2 weeks | Log confirmation | ✅ |
| DC-06 | Workspace: detect completion candidates (all checklist items checked) | ⚠️ LLM judgment | ✅ |
| DC-07 | Workspace: long-term active warning (no updates for 7+ days) | Date calculation | ✅ |

---

## 6. Pipeline Control Rules

| ID | Rule | Verification Method | Status |
|----|------|---------------------|--------|
| PL-01 | Fully automated (no interaction). Do not use AskUserQuestion | Log confirmation | ✅ |
| PL-02 | Overwrite existing files without confirmation | Overwrite confirmation | ✅ |
| PL-03 | After output, display a summary (3-5 lines) and finish | Log confirmation | ✅ |
| PL-04 | Plugin hook (Phase 1.5) is non-fatal on failure | Error handling | ✅ |
