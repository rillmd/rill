---
created: 2026-04-07T12:47+09:00
type: analysis
---

# /clip-tweet — Information Architecture Document (IAD)

Behavioral specification for /clip-tweet. Ingests a Twitter/X tweet URL into `inbox/tweets/`, fetches the body text via `fetch-tweet.sh`, and generates an organized version in `_organized/`.

**Test strategy**: Requires real tweet URLs, but `fetch-tweet.sh` depends on an external API (FixTweet) and is non-deterministic. Tests focus on structural validation and do not verify content accuracy.

---

## 1. Input/Output Definition

### Input

| ID | Input | Condition |
|----|-------|-----------|
| IO-I1 | Tweet URL | Must match pattern |

### Output

| ID | Output | Condition |
|----|--------|-----------|
| IO-O1 | `inbox/tweets/{slug}.md` | Thin file with frontmatter only |
| IO-O2 | `inbox/tweets/_organized/{slug}.md` | Organized version (full body text + metadata) |
| IO-O3 | `inbox/tweets/.processed` append | `{slug}:organized` |

---

## 2. Invariants

| ID | Invariant | Verification Method |
|----|-----------|---------------------|
| INV-01 | Other files in inbox/ are not modified | Hash comparison |
| INV-02 | URL matches status pattern | regex |
| INV-03 | Tracking parameters removed | URL inspection |
| INV-04 | Created via `rill mkfile` | created precision |

---

## 3. URL Validation Rules (Step 1)

| ID | Rule | Verification Method |
|----|------|---------------------|
| UV-01 | Empty URL -> exit with error | Output confirmation |
| UV-02 | Pattern mismatch -> exit with error | Output confirmation |
| UV-03 | Extract screen_name and tweet_id | Field confirmation |

---

## 4. File Creation Rules (Step 2)

| ID | Rule | Verification Method |
|----|------|---------------------|
| FC-01 | inbox/tweets/{slug}.md is created | File existence |
| FC-02 | Frontmatter contains source-type: tweet | Field check |
| FC-03 | Frontmatter contains url, tweet-id | Field check |
| FC-04 | Skip on duplicate | Output confirmation |

---

## 5. Data Retrieval Rules (Step 3)

| ID | Rule | Verification Method |
|----|------|---------------------|
| DT-01 | Execute fetch-tweet.sh | ⚠️ Log confirmation |
| DT-02 | On script failure, keep file and allow reprocessing via /distill | Error handling confirmation |

---

## 6. Organized Version Generation Rules (Step 4)

| ID | Rule | Verification Method |
|----|------|---------------------|
| OR-01 | _organized/{slug}.md is generated | File existence |
| OR-02 | _organized version frontmatter has complete tweet metadata | Field check |
| OR-03 | Tags exist in taxonomy.md | check-taxonomy.sh |
| OR-04 | original-file points to the source file | Path check |

---

## 7. .processed Update Rules (Step 5)

| ID | Rule | Verification Method |
|----|------|---------------------|
| PR-01 | Append `{slug}:organized` to .processed | Content confirmation |

---

## 8. Engagement & Relevance Rules (Step 3.7)

| ID | Rule | Verification Method |
|----|------|---------------------|
| EN-01 | engagement-save-ratio >= 1.0 -> high-save | Field check |
| EN-02 | engagement-rate >= 5.0 -> viral | Field check |
| EN-03 | Cross-reference with knowledge/projects/ and assign relevance-to | ⚠️ LLM judgment |

---

## Testability Summary

| Level | Rule Count | Percentage |
|-------|------------|------------|
| ✅ Automatically verifiable | 13 | 65% |
| ⚠️ LLM judgment / Log / External API dependent | 7 | 35% |
| **Total** | **20** | — |
