# /focus — Information Architecture Document (IAD)

Behavioral specification for /focus. An interactive skill that starts or resumes workspaces.

---

## 1. Input/Output Definitions

### Input

| ID | Input | Condition |
|----|-------|-----------|
| IO-I1 | Theme text | Starting a new workspace |
| IO-I2 | Journal file path | New WS from a journal entry |
| IO-I3 | Task file path (`tasks/*.md`) | Starting/resuming WS from a task |
| IO-I4 | workspace/ path or id | Resuming an existing WS |
| IO-I5 | Omitted | If an active WS exists, suggest resuming it |

### Output

| ID | Output | Condition |
|----|--------|-----------|
| IO-O1 | `workspace/{YYYY-MM-DD}-{topic}/_workspace.md` | On new creation |
| IO-O2 | `workspace/{id}/NNN-description.md` | When artifacts are created during conversation |

---

## 2. Invariants

| ID | Invariant | Verification Method | Status |
|----|-----------|-------------------|--------|
| INV-01 | Original files in inbox/ are not modified | File hash comparison | ✅ |
| INV-02 | _workspace.md contains `created`, `type: workspace`, `id`, `name`, `status` | Field check | ✅ |
| INV-03 | Files are created via `rill mkfile` | Precision check on created | ✅ |
| INV-04 | Directory name follows `{YYYY-MM-DD}-{kebab-case-topic}` | regex | ✅ |
| INV-05 | Artifacts follow `NNN-description.md` naming convention | regex | ✅ |
| INV-06 | pages/ is excluded from search targets | Log verification | ✅ |

---

## 3. Workspace Identification Rules (Phase 0)

| ID | Rule | Verification Method | Status |
|----|------|-------------------|--------|
| WS-01 | workspace/ path specified + status: active → resume (proceed to Phase 3) | State check | ✅ |
| WS-02 | workspace/ path specified + status: completed → ask whether to resume | ⚠️ Interactive | ✅ |
| WS-03 | Omitted → list active WSs and ask to resume or create new | ⚠️ Interactive | ✅ |
| WS-04 | tasks/*.md specified → if related contains a WS, suggest resuming | related check | ✅ |
| WS-05 | When creating new WS from tasks/*.md → add WS path to task's related | Bidirectional link | ✅ |
| WS-06 | Theme specified → search for related WSs, if found ask to resume or create new | Search verification | ✅ |
| WS-07 | Metadata file priority: `_workspace.md` > `_session.md` > `_project.md` | Backward compatibility | ✅ |

---

## 4. _workspace.md Structure Rules

| ID | Rule | Verification Method | Status |
|----|------|-------------------|--------|
| WM-01 | frontmatter: created, type, id, name, status are required | Field check | ✅ |
| WM-02 | status: active (on new creation) | Value check | ✅ |
| WM-03 | origin: path of the source file (optional when theme is specified) | Conditional check | ✅ |
| WM-04 | tags: relevant tags | Existence check | ✅ |
| WM-05 | Body contains "Issues to Consider" section | grep | ✅ |
| WM-06 | Body contains "Related Files (MOC)" section | grep | ✅ |
| WM-07 | Body contains "Session History" section | grep | ✅ |
| WM-08 | Body contains "Next Steps" section | grep | ✅ |
| WM-09 | MOC links use `[display name](relative-path)` format | regex | ✅ |

---

## 5. Context Collection Rules (Phase 1)

| ID | Rule | Verification Method | Status |
|----|------|-------------------|--------|
| CX-01 | Extract 2-3 keywords from the theme and perform cross-cutting Grep search | Log verification | ✅ |
| CX-02 | Search targets: knowledge, inbox, workspace, reports, tasks | Grep path verification | ✅ |
| CX-03 | pages/ is excluded from search targets | Grep path verification | ✅ |
| CX-04 | Prefer _organized/ versions for inbox | Path verification | ✅ |

---

## 6. Conversation Phase Rules (Phase 3)

| ID | Rule | Verification Method | Status |
|----|------|-------------------|--------|
| DI-01 | Analytical or report-style output is saved to files (File-first principle) | File existence check | ✅ |
| DI-02 | Artifact creation uses `rill mkfile` | Precision of created | ✅ |
| DI-03 | Update _workspace.md every 2-3 conversation exchanges | Update frequency | ✅ |
| DI-04 | Add new artifacts to MOC | MOC verification | ✅ |
| DI-05 | Update checkboxes for completed issues | Checkbox state | ✅ |
