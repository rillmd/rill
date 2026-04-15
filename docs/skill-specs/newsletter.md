---
created: 2026-04-07T10:46+09:00
type: analysis
---

# /newsletter — Information Architecture Document (IAD)

Behavioral specification for /newsletter. A skill that generates daily news reports using WebSearch/WebFetch.

**Note**: This skill depends on external APIs (WebSearch/WebFetch), so output content depends on real-time web data. Tests should focus on **structural rules** only, with **content quality rules** left to LLM judgment.

---

## 1. Input/Output Definitions

### Input

| ID | Input | Condition |
|----|-------|-----------|
| IO-I1 | `knowledge/me.md` | Identity layer |
| IO-I2 | `knowledge/projects/*.md` | Identity layer (Competitors, Watch Keywords) |
| IO-I3 | `workspace/**/_workspace.md` (past 2 weeks) | Attention layer |
| IO-I4 | `inbox/journal/*.md` (past 7 days) | Impulse layer |
| IO-I5 | `reports/newsletter/*.md` (past 2 weeks) | Deduplication |
| IO-I6 | `knowledge/notes/*.md` filename list | Known information filter |

### Output

| ID | Output | Condition |
|----|--------|-----------|
| IO-O1 | `reports/newsletter/YYYY-MM-DD.md` | Always generated. Overwrites existing |

---

## 2. Invariants

| ID | Invariant | Verification Method | Status |
|----|-----------|-------------------|--------|
| INV-01 | Original files in inbox/ are not modified | File hash comparison | ✅ |
| INV-02 | frontmatter contains `created`, `type: newsletter`, `keywords`, `source-count` | Field check | ✅ |
| INV-03 | Files are created via `rill mkfile` | Precision check on created | ✅ |
| INV-04 | Output file path matches `reports/newsletter/YYYY-MM-DD.md` | Path check | ✅ |
| INV-05 | All facts include source URLs | URL pattern detection | ✅ |

---

## 3. Section Structure Rules

| ID | Rule | Verification Method | Status |
|----|------|-------------------|--------|
| SC-01 | Title is `# YYYY-MM-DD Daily News` | grep `^# ` | ✅ |
| SC-02 | `## Alerts` section exists | grep | ✅ |
| SC-03 | `## Deep Dive:` section exists | grep | ✅ |
| SC-04 | `## Discovery` section exists | grep | ✅ |
| SC-05 | `## Research Metadata` section exists | grep | ✅ |
| SC-06 | Deep Dive is 1000+ characters | Character count | ✅ |
| SC-07 | Each section is prose-based | ⚠️ LLM judgment | ✅ |

---

## 4. 3-Layer Context Rules

| ID | Rule | Verification Method | Status |
|----|------|-------------------|--------|
| CX-01 | Read knowledge/me.md | ⚠️ Log verification | ✅ |
| CX-02 | Read knowledge/projects/*.md | ⚠️ Log verification | ✅ |
| CX-03 | Read workspace/ from the past 2 weeks | ⚠️ Log verification | ✅ |
| CX-04 | Read inbox/journal/ from the past 7 days | ⚠️ Log verification | ✅ |
| CX-05 | Prefer _organized/ versions | ⚠️ Log verification | ✅ |

---

## 5. Search Strategy Rules

| ID | Rule | Verification Method | Status |
|----|------|-------------------|--------|
| SR-01 | 2-3 keywords for Alert slots | Metadata verification | ✅ |
| SR-02 | 1-2 keywords for Deep Dive slots | Metadata verification | ✅ |
| SR-03 | 2-3 keywords for Discovery slots | Metadata verification | ✅ |
| SR-04 | Prefer English keywords | ⚠️ LLM judgment | ✅ |
| SR-05 | Exclude keywords used in the past 2 weeks | ⚠️ LLM judgment | ✅ |

---

## 6. Content Quality Rules

| ID | Rule | Verification Method | Status |
|----|------|-------------------|--------|
| CQ-01 | Alerts only when there is a change | ⚠️ LLM judgment | ✅ |
| CQ-02 | Alert freshness filter (within 2 weeks) | ⚠️ LLM judgment | ✅ |
| CQ-03 | Alert primary source verification | ⚠️ LLM judgment | ✅ |
| CQ-04 | Deep Dive follows 3-layer structure (Facts → Interpretation → Implications) | ⚠️ LLM judgment | ✅ |
| CQ-05 | Discovery explicitly connects to user interests | ⚠️ LLM judgment | ✅ |
| CQ-06 | Old information is not presented as new news | ⚠️ LLM judgment | ✅ |

---

## 7. Metadata Rules

| ID | Rule | Verification Method | Status |
|----|------|-------------------|--------|
| MD-01 | frontmatter `keywords` contains list of used keywords | Field check | ✅ |
| MD-02 | frontmatter `source-count` contains number of referenced sources | Field check | ✅ |
| MD-03 | frontmatter `alert-count` contains number of alerts | Field check | ✅ |
| MD-04 | frontmatter `deep-dive-topic` contains topic name | Field check | ✅ |
| MD-05 | frontmatter `discovery-count` contains number of discoveries | Field check | ✅ |
| MD-06 | Research Metadata section contains list of search keywords | grep | ✅ |
| MD-07 | Research Metadata section contains key source URLs | grep URL | ✅ |

---

## 8. Pipeline Control Rules

| ID | Rule | Verification Method | Status |
|----|------|-------------------|--------|
| PL-01 | Fully automated (no interaction) | Log verification | ✅ |
| PL-02 | Existing files are overwritten without confirmation | Overwrite verification | ✅ |
| PL-03 | After output, display a summary (3-5 lines) and terminate | Log verification | ✅ |

---

## Testability Summary

| Level | Rule Count | Percentage |
|-------|-----------|------------|
| ✅ Automatically verifiable | 18 | 46% |
| ⚠️ LLM judgment / log verification | 21 | 54% |
| **Total** | **39** | — |

**Test strategy**: Focus on the 18 automatically verifiable rules (structure, frontmatter, section existence, URL presence, Deep Dive character count). Do not verify WebSearch result content.
