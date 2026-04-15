---
created: 2026-04-07T11:10+09:00
type: analysis
---

# /solve — Information Architecture Document (IAD)

Behavioral specification for /solve. A skill that reads tasks and autonomously performs research, analysis, and artifact generation.

**Test strategy**: With `claude -p`, a single turn progresses through Phase 0→1→2→3→4. Task understanding, WS creation, artifact generation, and status updates are structurally verified.

---

## 2. Invariants

| ID | Invariant | Verification Method |
|----|-----------|-------------------|
| INV-01 | inbox/ is immutable | Hash comparison |
| INV-02 | Safety boundary compliance (no code changes, no external communication) | Log verification |
| INV-03 | Do not execute if task status is done/cancelled | Output verification |

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

| ID | Rule | Verification Method |
|----|------|-------------------|
| P3-01 | workspace directory is created | File existence |
| P3-02 | _workspace.md has required frontmatter | Field check |
| P3-03 | _workspace.md origin points to the task file | Path check |
| P3-04 | Artifact files (NNN-*.md) are created | File existence |
| P3-05 | Artifacts have frontmatter | Field check |

---

## 6. Phase 4: Completion

| ID | Rule | Verification Method |
|----|------|-------------------|
| P4-01 | Task status is changed to waiting | fm_get |
| P4-02 | Task related includes the workspace path | fm_get |
| P4-03 | Task History section contains execution record | grep |
| P4-04 | _workspace.md MOC includes artifact links | grep |

---

## Testability Summary

| Level | Rule Count | Percentage |
|-------|-----------|------------|
| ✅ Automatically verifiable | 10 | 53% |
| ⚠️ LLM judgment / log | 9 | 47% |
| **Total** | **19** | — |
