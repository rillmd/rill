# /close — Information Architecture Document (IAD)

Behavioral specification for /close. A skill that completes an active workspace, generating a summary and performing knowledge distillation.

**2026-04-08 Update**: Redesigned to a two-layer sub-agent architecture per ADR-073. Phases 2-4 are delegated to Analysis sub-agent / Distillation sub-agents, while the parent only orchestrates.

---

## 1. Input/Output Definition

### Input

| ID | Input | Condition |
|----|-------|-----------|
| IO-I1 | workspace/ path or id | Complete specified WS |
| IO-I2 | Omitted | Auto-detect active WS |

### Output

| ID | Output | Condition |
|----|--------|-----------|
| IO-O1 | `workspace/{id}/_summary.md` | Always generated |
| IO-O2 | `workspace/{id}/_workspace.md` (status: completed) | Always updated |
| IO-O3 | `knowledge/notes/*.md` | Generated via knowledge distillation |
| IO-O4 | `tasks/*.md` (status: draft) | Tasks extracted from unresolved issues |
| IO-O5 | `knowledge/people/*.md`, `knowledge/projects/*.md` | Key facts appended |
| IO-O6 | `workspace/{id}/.processed` | Artifact filenames recorded |

---

## 2. Invariants

| ID | Invariant | Verification Method | Status |
|----|-----------|---------------------|--------|
| INV-01 | Original files in inbox/ are not modified | File hash comparison | ✅ |
| INV-02 | _summary.md has frontmatter (created, type: summary) | Field check | ✅ |
| INV-03 | _workspace.md status is `completed` after completion | Value check | ✅ |
| INV-04 | Distilled knowledge/notes/ satisfy INV-04 through INV-15 of the distill IAD | distill IAD reference | ✅ |
| INV-05 | File created via `rill mkfile` | created precision | ✅ |

---

## 3. Workspace Identification Rules (Phase 0)

| ID | Rule | Verification Method | Status |
|----|------|---------------------|--------|
| WS-01 | With argument -> Read metadata file (_workspace.md > _session.md > _project.md) | Backward compatibility | ✅ |
| WS-02 | No argument + multiple active WSs -> Select via AskUserQuestion | ⚠️ Interactive | ✅ |
| WS-03 | No argument + no active WS -> Exit with "No active workspace found" | Output confirmation | ✅ |
| WS-04 | status: completed -> Exit with "Already completed" | Output confirmation | ✅ |

---

## 4. _summary.md Structure Rules

| ID | Rule | Verification Method | Status |
|----|------|---------------------|--------|
| SM-01 | Title is `# {Title} — Summary` | grep `^# ` | ✅ |
| SM-02 | `## Overview` section (2-3 paragraphs) | grep | ✅ |
| SM-03 | `## Deliverables` section (table format) | grep | ✅ |
| SM-04 | `## Decisions` section (structured D-{ws-short}-{n} format, `Adopted from` required) | grep + field check | ✅ |
| SM-05 | `## Invalidated Approaches` section required (if none, explicitly state "(No invalidated approaches...)") | grep | ✅ |
| SM-06 | `## Open Issues` section | grep | ✅ |
| SM-07 | Content from all artifact files is reflected | ⚠️ LLM judgment | ✅ |

---

## 5. Knowledge Distillation Rules (Phase 2-4)

Per ADR-073, distillation is executed via a two-layer sub-agent architecture. KD-01 through KD-06 define the behavior of Distillation sub-agents.

| ID | Rule | Verification Method | Status |
|----|------|---------------------|--------|
| KD-01 | Distillation sub-agent follows the Evergreen check procedure in knowledge-agent.md | Sub-agent design | ✅ |
| KD-02 | Read budget: source deliverable + max 2 related files + _summary.md + max 2 knowledge/notes/ frontmatter | Sub-agent prompt confirmation | ✅ |
| KD-03 | Extraction targets: Decisions, per-deliverable atomic units (research / insight / reference) | Two-layer enumeration execution confirmation | ✅ |
| KD-04 | When skipping, a justification label is required (see JL-01 through JL-04) | Field check | ✅ |
| KD-05 | source specifies the artifact file path | Path check | ✅ |
| KD-06 | Run `rill strip-entity-tags` as post-processing | Post-processing confirmation | ✅ |

---

## 5b. Candidate Enumeration Rules (Phase 2, Analysis sub-agent)

Rules for when the Analysis sub-agent enumerates candidates in Phase 3.4.a-0. Core mechanism for preventing omissions.

| ID | Rule | Verification Method | Status |
|----|------|---------------------|--------|
| CL-01 | Layer 1: Enumerate exactly 1 candidate for each Decision in _summary.md | candidate.layer == 1 count vs decisions_count | ✅ |
| CL-02 | Layer 2: Scan each deliverable and enumerate atomic units of type research / insight / reference | Existence check for candidate.layer == 2 | ✅ |
| CL-03 | Merge candidates with similar slugs between L1 and L2, prioritizing L1; remove L2 | Duplicate check | ✅ |
| CL-04 | Only `IMPLEMENTATION_DETAIL` or `INTERMEDIATE_CONCLUSION` skips allowed during enumeration; skip_hint must be attached | Field check | ✅ |
| CL-05 | Vague reasons like "not novel enough" or "pragmatic scope reduction" are prohibited | String search | ✅ |
| CL-06 | Target candidate count: 2N to 5N for N deliverables (warning only if outside range, not enforced) | Range check | ⚠️ |
| CL-07 | Enumeration results returned to parent in structured YAML format | Output format check | ✅ |

---

## 5c. Cross-deliverable Verify Rules (Phase 4, Distillation sub-agent)

Rules for each Distillation sub-agent to verify consistency with other deliverables before writing a note. Second layer of defense against error propagation.

| ID | Rule | Verification Method | Status |
|----|------|---------------------|--------|
| CV-01 | Extract 3-5 key claims from the candidate's rationale | Sub-agent operation log | ✅ |
| CV-02 | Run Grep search within workspace for each key claim | Tool log | ✅ |
| CV-03 | If contradicting claims found -> skip + `INTERMEDIATE_CONCLUSION` | Judgment logic | ✅ |
| CV-04 | Cross-reference with Invalidated Approaches list required | Cross-reference confirmation | ✅ |
| CV-05 | Verify step is mandatory and cannot be skipped | Prompt description | ✅ |
| CV-06 | Verify step tool call budget: max 5 calls (Grep + additional Read) | Budget discipline | ✅ |

---

## 5d. Self-check Rules (Phase 5, parent)

Aggregation and verification rules on the parent side. Final line of defense for completeness.

| ID | Rule | Verification Method | Status |
|----|------|---------------------|--------|
| SC-01 | Equation must hold: enumerated = X + Y + Z + R + uncovered | Arithmetic check | ✅ |
| SC-02 | If `uncovered > 0`, STOP before proceeding to Phase 6+ | Control flow | ✅ |
| SC-03 | If `rejected > 0`, report to user and request judgment | User interaction | ✅ |
| SC-04 | Self-check results must always be displayed in the completion report | Output check | ✅ |
| SC-05 | Evergreen race resolution: merge or delete one of new note pairs with slug edit-distance <= 3 | Duplicate detection | ✅ |

---

## 5e. Justification Labels (Phase 4, Distillation sub-agent)

Required justification labels when skipping. Concretization of the vague-reason prohibition.

| ID | Label | Meaning | Required Attachment |
|----|-------|---------|---------------------|
| JL-01 | `EVERGREEN_DUPLICATE` | Same content exists in an existing note | `existing_file: knowledge/notes/xxx.md` |
| JL-02 | `INTERMEDIATE_CONCLUSION` | Intermediate conclusion that was later refuted | `contradicted_by: workspace/{id}/NNN.md` |
| JL-03 | `IMPLEMENTATION_DETAIL` | Rill-specific implementation detail with no reusability | `reason: {1 line}` |
| JL-04 | `MERGED_INTO_OTHER` | Merged into another candidate | `merged_into: {candidate id}` |

**Prohibited**: "pragmatic scope reduction", "to save time", "not novel enough", "context budget running low", "already sufficient coverage", or reasons without labels. Parent rejects these.

---

## 6. Task Extraction Rules

| ID | Rule | Verification Method | Status |
|----|------|---------------------|--------|
| TK-01 | All checklist items `[x]` -> skip task extraction | Check state | ✅ |
| TK-02 | Unchecked items exist -> extract task candidates per task-extraction.md | Task generation confirmation | ✅ |
| TK-03 | Created with status: draft | Value check | ✅ |
| TK-04 | Duplicate check against existing tickets | Duplicate confirmation | ✅ |

---

## 7. Related Task Sync Rules

| ID | Rule | Verification Method | Status |
|----|------|---------------------|--------|
| TS-01 | Grep-detect tasks in tasks/ that reference the WS via source/related | Grep confirmation | ✅ |
| TS-02 | Targets: status is open/waiting/draft (skip done/cancelled) | Filter confirmation | ✅ |
| TS-03 | Compare goal against _summary.md to determine completion | ⚠️ LLM judgment | ✅ |
| TS-04 | Present judgment results as a list and request user confirmation | ⚠️ Interactive | ✅ |
| TS-05 | Only change status to done for approved tasks | State confirmation | ✅ |
| TS-06 | Append completion record to History section | Content confirmation | ✅ |
| TS-07 | 0 related tasks -> skip (no display) | Condition confirmation | ✅ |

---

## 8. Pipeline Control Rules

| ID | Rule | Verification Method | Status |
|----|------|---------------------|--------|
| PL-01 | Analysis sub-agent must Read all files in Phase 1 (no omissions) | Sub-agent output | ✅ |
| PL-02 | Distillation sub-agents dispatched in max 5 parallel, batch processed | Startup log | ✅ |
| PL-03 | If artifact frontmatter lacks mentions/tags, assign them (Phase 6, parent) | Field confirmation | ✅ |
| PL-04 | Record all artifact filenames in .processed (Phase 7, parent) | File confirmation | ✅ |
| PL-05 | Backward compatibility: WSs with only `_session.md` / `_project.md` are processed normally | Design confirmation | ✅ |
| PL-06 | Do not proceed to Phase 4 unless user checkpoint approval is granted in Phase 3 | Control flow | ✅ |
| PL-07 | Parent detects sub-agent timeout / abnormal termination and records as skipped + TIMEOUT | Error handling | ✅ |
