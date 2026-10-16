# /briefing — Information Architecture Document (IAD)

Behavioral specification for /briefing. Two entry points share one daily note: `--handoff` (unattended morning handoff) and the default standup (the user talks, the skill organizes).

---

## 1. Input/Output Definition

### Input

| ID | Input | Condition |
|----|-------|-----------|
| IO-I1 | `tasks/*/_task.md` (status: open/waiting) | Filtered via Grep |
| IO-I2 | `knowledge/self/current-state.md`, `direction.md`, `constraints.md` | /pulse refreshed when older than 12h |
| IO-I3 | `workspace/**/_workspace.md` (status: active) Next Steps | Touched in 14 days or named in current-state |
| IO-I4 | `briefing-context.sh` YAML (activity window, inbox counts, task counts) | Always |
| IO-I5 | Mail and calendar via tools the vault declares | Only when declared; failures recorded |
| IO-I6 | `reports/daily/*.md` (most recent before target) | Yesterday's standup commitments |
| IO-I7 | Proactive run directory for the target date (e.g. `reports/anticipation/{DATE}/`) | Existence check |
| IO-I8 | The user's monologue | Standup mode only |

### Output

| ID | Output | Condition |
|----|--------|-----------|
| IO-O1 | `reports/daily/YYYY-MM-DD.md`, handoff block between `<!-- handoff:start -->` and `<!-- handoff:end -->` | Handoff mode. Replaces only the block |
| IO-O2 | Same file, `## Standup` section below the block | Standup mode. Appended, or replaced on a later standup the same day |

---

## 2. Invariants

| ID | Invariant | Verification Method | Status |
|----|-----------|---------------------|--------|
| INV-01 | Original files in inbox/ are not modified | File hash comparison | ✅ |
| INV-02 | Frontmatter contains `created`, `type: daily-note`, `date`, `journal-count` | Field check | ✅ |
| INV-03 | File created via `rill mkfile` | created precision check | ✅ |
| INV-04 | Output file path is `reports/daily/YYYY-MM-DD.md` | Path check | ✅ |
| INV-05 | Body text in user's preferred language | ⚠️ LLM judgment | ✅ |
| INV-06 | A handoff rerun leaves an existing standup section unchanged | Diff outside markers | ⚠️ manual |
| INV-07 | Items whose source could not be read are not listed as "Nothing needed now" | ⚠️ LLM judgment | ✅ |

---

## 3. Section Structure Rules (handoff)

| ID | Rule | Verification Method | Status |
|----|------|---------------------|--------|
| SC-01 | Title is `# YYYY-MM-DD Daily Briefing` (verbatim in every language) | grep `^# ` | ✅ |
| SC-02 | Handoff markers present, start before end | grep `<!-- handoff:start -->` / `<!-- handoff:end -->` | ✅ |
| SC-03 | Inside the block: one `## ` heading (canonical "Morning Handoff") and four `### ` sections in order — Needs you today, Deadlines ahead, Nothing needed now, New since yesterday — present even when empty | count `^### ` inside the block = 4 | ✅ |
| SC-04 | A coverage line names the sources read and the ones that could not be read | ⚠️ LLM judgment | ✅ |
| SC-05 | "Needs you today" items carry minutes and an end point | ⚠️ LLM judgment | ✅ |
| SC-06 | "Deadlines ahead" shows the time-left arithmetic when an estimate exists | ⚠️ LLM judgment | ✅ |

Headings are canonical English in the skill and rendered in the vault language at runtime; the fixture vault has no language rule, so the English forms are checked there.

---

## 4. Task Display Rules

| ID | Rule | Verification Method | Status |
|----|------|---------------------|--------|
| TK-01 | Tasks are collected from ticket files (tasks/*/_task.md) | Source confirmation | ✅ |
| TK-03 | Reference links use relative path format `[Title](../../tasks/{slug}/_task.md)` or `../../workspace/{id}/_workspace.md` | regex | ✅ |
| TK-05 | Overdue tasks are detected and displayed | ⚠️ LLM judgment | ✅ |
| TK-06 | done, draft, cancelled, someday statuses are not Read | Log confirmation | ✅ |

---

## 5. Standup Rules

| ID | Rule | Verification Method | Status |
|----|------|---------------------|--------|
| ST-01 | With no text, reply with one line and end the turn; no source reading before the user talks | Log confirmation | ⚠️ manual |
| ST-02 | One organizing reply: what was said, what was not mentioned, at most two questions, commitments (3–5, minutes + end point), Not today (reason + return) | ⚠️ LLM judgment | ⚠️ manual |
| ST-03 | No time-slot allocation and no calendar writes | Log confirmation | ⚠️ manual |
| ST-04 | The retrospective nudge never fires in standup mode | State file unchanged | ⚠️ manual |

---

## 6. Pipeline Control Rules

| ID | Rule | Verification Method | Status |
|----|------|---------------------|--------|
| PL-01 | Handoff mode is fully unattended; no questions | Log confirmation | ✅ |
| PL-02 | Handoff rerun replaces only the marked block | Diff | ⚠️ manual |
| PL-03 | Handoff finishes with a 2–3 line summary | Log confirmation | ✅ |
| PL-04 | Plugin hooks are non-fatal on failure | Error handling | ✅ |
