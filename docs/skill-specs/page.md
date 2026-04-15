---
created: 2026-04-07T11:02+09:00
type: analysis
---

# /page — Information Architecture Document (IAD)

Behavioral specification for /page. An interactive skill that manages creation, updating, and rebuilding of Pages (Materialized Views).

**Test strategy**: Only new creation is testable via `claude -p` (update/rebuild requires existing pages + recipes + feedback loops).

---

## 1. Input/Output Definitions

### Input

| ID | Input | Condition |
|----|-------|-----------|
| IO-I1 | Theme text | New creation |
| IO-I2 | pages/ file path | update / rebuild |
| IO-I3 | pages/{id}.recipe.md | update / rebuild (must read) |
| IO-I4 | knowledge/, workspace/, inbox/, reports/ | Context collection |

### Output

| ID | Output | Condition |
|----|--------|-----------|
| IO-O1 | `pages/{id}.md` | New creation / update / rebuild |
| IO-O2 | `pages/{id}.recipe.md` | On new creation |

---

## 2. Invariants

| ID | Invariant | Verification Method | Status |
|----|-----------|-------------------|--------|
| INV-01 | Original files in inbox/ are not modified | File hash comparison | ✅ |
| INV-02 | Page frontmatter contains `created`, `type: page`, `id`, `name`, `description` | Field check | ✅ |
| INV-03 | Files are created via `rill mkfile` | Precision of created | ✅ |
| INV-04 | File names are kebab-case with no date prefix | regex | ✅ |

---

## 3. New Creation Rules

| ID | Rule | Verification Method | Status |
|----|------|-------------------|--------|
| CR-01 | pages/{id}.md is generated | File existence | ✅ |
| CR-02 | pages/{id}.recipe.md is generated | File existence | ✅ |
| CR-03 | recipe has type: recipe set | Field check | ✅ |
| CR-04 | recipe contains "Purpose of This Page" section | grep | ✅ |
| CR-05 | recipe contains "Source Hints" section | grep | ✅ |
| CR-06 | Page frontmatter contains `sources` | Field check | ✅ |
| CR-07 | Context collection searches knowledge/notes/ | ⚠️ Log verification | ✅ |
| CR-08 | Feedback is requested from the user | ⚠️ Interactive | ✅ |

---

## 4. Document Quality Rules

| ID | Rule | Verification Method | Status |
|----|------|-------------------|--------|
| DQ-01 | Multiple abstraction layers (prose + tables/lists) | ⚠️ LLM judgment | ✅ |
| DQ-02 | Contains both summaries and raw data | ⚠️ LLM judgment | ✅ |
| DQ-03 | Scannable structure (headings, table headers) | grep `^## ` count | ✅ |
| DQ-04 | Consistent structural axis | ⚠️ LLM judgment | ✅ |

---

## 5. Update/Rebuild Rules

| ID | Rule | Verification Method | Status |
|----|------|-------------------|--------|
| UP-01 | recipe.md is always Read | ⚠️ Log verification | ✅ |
| UP-02 | Fixed section structure is maintained | ⚠️ LLM judgment | ✅ |
| UP-03 | updated timestamp is refreshed | Value check | ✅ |
| UP-04 | sources is updated with actually referenced files | ⚠️ LLM judgment | ✅ |
| RB-01 | rebuild writes from scratch | ⚠️ LLM judgment | ✅ |
| RB-02 | Feedback is requested after rebuild | ⚠️ Interactive | ✅ |

---

## 6. Pipeline Control Rules

| ID | Rule | Verification Method | Status |
|----|------|-------------------|--------|
| PL-01 | Excluded from AI search targets (/distill, /briefing, /eval do not reference pages/) | Design verification | ✅ |
| PL-02 | When editing directly, also write to the canonical source (D62-5) | ⚠️ Log verification | ✅ |

---

## Testability Summary

| Level | Rule Count | Percentage |
|-------|-----------|------------|
| ✅ Automatically verifiable (new creation scenario) | 11 | 42% |
| ⚠️ LLM judgment / interactive / log / update-only | 15 | 58% |
| **Total** | **26** | — |
