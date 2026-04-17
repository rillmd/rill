---
created: 2026-04-07T11:10+09:00
type: analysis
---

# /solve — Information Architecture Document (IAD)

Behavioral specification for /solve. A skill that reads tasks and autonomously performs research, analysis, and artifact generation.

**Test strategy**: With `claude -p`, a single turn progresses through Phase 0→1→2→3→4. Task understanding, artifact generation under the task directory, and task status / history updates are structurally verified.

Post-ADR-077 (D77-1/D77-2): /solve never creates a workspace. All artifacts land under `tasks/{slug}/` alongside `_task.md`.

---

## 2. Invariants

| ID | Invariant | Verification Method |
|----|-----------|-------------------|
| INV-01 | inbox/ is immutable | Hash comparison |
| INV-02 | Safety boundary compliance (no code changes, no external communication) | Log verification |
| INV-03 | Do not execute if task status is done/cancelled | Output verification |
| INV-04 | No new workspace is created during /solve (ADR-077 D77-1) | `workspace/` diff check |

---

## 3. Phase 0-1: Task Understanding

| ID | Rule | Verification Method |
|----|------|-------------------|
| P0-01 | Read the task file | ⚠️ Log |
| P0-02 | Read the source file | ⚠️ Log |
| P0-03 | Read the related files | ⚠️ Log |
| P1-01 | Briefing includes a goal summary | ⚠️ LLM judgment |

---

## 4. Phase 2: Design

| ID | Rule | Verification Method |
|----|------|-------------------|
| P2-01 | Determine artifact placement (Enrich / Research / Code) | ⚠️ LLM judgment |
| P2-02 | Explicitly state safety boundaries | ⚠️ LLM judgment |

---

## 5. Phase 3: Execution

ADR-076/077: artifacts live inside the task directory (`tasks/{slug}/NNN-*.md`).
The old workspace-generation path (pre-ADR-077) is removed.

| ID | Rule | Verification Method |
|----|------|-------------------|
| P3-01 | For Research pattern, new artifact files are created under `tasks/{slug}/` | File existence |
| P3-02 | Artifacts follow `NNN-description.md` naming with auto-incremented numbering | regex |
| P3-03 | Artifacts have required frontmatter (`created`, `type`) | Field check |
| P3-04 | For Enrich pattern, `tasks/{slug}/_task.md` body is updated in place | Diff check |
| P3-05 | For Code pattern, an implementation plan artifact is created under the task directory, and no code changes are written in the target repo | File existence + diff |
| P3-06 | No `workspace/` directory is created as a side effect of /solve (ADR-077 D77-1) | `workspace/` listing diff |

---

## 6. Phase 4: Completion

| ID | Rule | Verification Method |
|----|------|-------------------|
| P4-01 | Task status is changed to `waiting` when the AI completes the work | fm_get |
| P4-02 | Task `## History` section contains an execution record line | grep |
| P4-03 | Task `## Context` section is extended with links to new artifacts (when any) | grep |
| P4-04 | activity-log.md has an entry for the /solve run | grep |

---

## Testability Summary

| Level | Rule Count | Percentage |
|-------|-----------|------------|
| ✅ Automatically verifiable | 11 | 58% |
| ⚠️ LLM judgment / log | 8 | 42% |
| **Total** | **19** | — |
