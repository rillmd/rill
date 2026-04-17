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
| SC-01 | Title is `# YYYY-MM-DD Daily Briefing` | grep `^# ` | ✅ |
| SC-02 | `## Yesterday's Activity` section exists | grep `^## Yesterday's Activity` | ✅ |
| SC-03 | `## Today's Focus` section exists | grep | ✅ |
| SC-04 | `## Situation Analysis` section exists | grep | ✅ |
| SC-05 | `## Notes` section exists (may be omitted if no information) | grep (optional) | ✅ |
| SC-06 | `## Related` section (only when newsletter exists) | Conditional grep | ✅ |
| SC-07 | Each section is prose-based (not bullet-point lists) | ⚠️ LLM judgment | ✅ |

---

## 4. Task Display Rules

| ID | Rule | Verification Method | Status |
|----|------|---------------------|--------|
| TK-01 | Tasks are collected from ticket files (tasks/*/_task.md) | Source confirmation | ✅ |
| TK-02 | Focus targets: due within 7 days / waiting / matching projects of active WSs | ⚠️ LLM judgment | ✅ |
| TK-03 | Task links use relative path format `[Title](../../tasks/{slug}/_task.md)` | regex | ✅ |
| TK-04 | Waiting tickets display `waiting` in backticks | grep | ✅ |
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
