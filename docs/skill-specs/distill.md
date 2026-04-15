# /distill — Information Architecture Document (IAD)

Behavioral specification for /distill. Codifies all rules of the skill, serving as the basis for deriving test cases.

**Legend**:
- ✅ = Working as intended (can be locked in via tests)
- ⚠️ = Review target (correctness needs confirmation)
- ❌ = Needs fixing (fix before testing)

---

## 1. Input/Output Definition

### Input

| ID | Input | Condition |
|----|-------|-----------|
| IO-I1 | `inbox/journal/*.md` | Not listed in `.processed` and not inside `_organized/` |
| IO-I2 | `inbox/{meetings,web-clips,tweets,think-outputs,sources}/*.md` | Not listed in respective `.processed` |
| IO-I3 | Single file/directory specified as argument | Single-file mode |

### Output

| ID | Output | Generation Phase |
|----|--------|------------------|
| IO-O1 | `inbox/journal/_organized/*.md` | Phase 1 |
| IO-O2 | `inbox/{type}/_organized/*.md` | Phase 2 |
| IO-O3 | `knowledge/notes/*.md` | Phase 1, 3 |
| IO-O4 | `tasks/*.md` (status: draft) | Phase 1, 2 |
| IO-O5 | `knowledge/people/*.md` (new/updated) | Phase 1, 2.5 |
| IO-O6 | `knowledge/orgs/*.md` (new/updated) | Phase 2.5 |
| IO-O7 | `knowledge/projects/*.md` (updated) | Phase 1, 3 |
| IO-O8 | `knowledge/me.md` (updated) | Phase 4 |
| IO-O9 | `inbox/*/.processed` (updated) | Phase 1 result collection, Phase 3 result collection |
| IO-O10 | `taxonomy.md` (appended) | Result collection |

---

## 2. Invariants

Rules that must never be violated, verified across all tests.

| ID | Invariant | Verification Method | Status |
|----|-----------|---------------------|--------|
| INV-01 | Original files in inbox/ are not modified (read-only) | File hash comparison | ✅ |
| INV-02 | Frontmatter `created` is immutable (never changed once set) | Before/after comparison | ✅ |
| INV-03 | Frontmatter `source` is immutable | Before/after comparison | ✅ |
| INV-04 | knowledge/notes/ `type` is only `record` / `insight` / `reference` | Enum check | ✅ |
| INV-05 | `tags` max 3 | Count | ✅ |
| INV-06 | `tags` values exist in `taxonomy.md` | Cross-reference | ✅ |
| INV-07 | `tags` must not contain entity IDs | Cross-reference against entity ID list | ✅ |
| INV-08 | `mentions` requires type prefix (`people/`, `orgs/`, `projects/`) | regex | ✅ |
| INV-09 | Filenames are English kebab-case | regex | ✅ |
| INV-10 | File created via `rill mkfile` (LLM must not write `created` directly) | created precision check | ✅ |
| INV-11 | `.processed` (journal) contains filenames only (no path prefix) | Format check | ✅ |
| INV-12 | `.processed` (inbox/*) uses `filename:status` format | Format check | ✅ |
| INV-13 | `related` max 5 entries | Count | ✅ |
| INV-14 | Task ticket `status` is `draft` (for AI auto-generated tasks) | Value check | ✅ |
| INV-15 | Markdown links use `[text](path)` format. Wikilinks `[[]]` are not used | grep | ✅ |

---

## 3. Knowledge Extraction Rules

### 3.1 Basic Rules

| ID | Rule | Verification Method | Status |
|----|------|---------------------|--------|
| KE-01 | 1 file = 1 atomic concept | ⚠️ LLM judgment | ✅ |
| KE-02 | Body starts with `# Title` heading | grep `^# ` | ✅ |
| KE-03 | `source` uses the processed file path (for journal, uses the `_organized/` version) | Path verification | ✅ |
| KE-04 | Body text in user's preferred language, technical terms in English | ⚠️ LLM judgment | ✅ |
| KE-05 | When entity references exist, set typed references in mentions | mentions verification | ✅ |

### 3.2 Evergreen Check (Duplicate Detection)

| ID | Rule | Verification Method | Status |
|----|------|---------------------|--------|
| EV-01 | Always perform Evergreen check before creating new files | Log confirmation (indirect) | ✅ |
| EV-02 | Same topic + same type -> skip | Duplicate fixture verification | ✅ |
| EV-03 | Same topic + different type -> create new + specify existing in related | Different-type fixture verification | ✅ |
| EV-04 | Read of existing files is frontmatter-only (first 10 lines; full-text Read prohibited) | Log confirmation (indirect) | ✅ |
| EV-05 | Extract 3-5 search terms, record hit/miss status for each | Log confirmation | ✅ |
| EV-06 | On partial hits: consider creating new file for information corresponding to missed search terms | ⚠️ LLM judgment | ✅ |

**EV-03 Review Result (2026-04-06)**: ✅ Maintain current behavior. The design intent of separating facts from interpretations is sound.

**EV-06 Review Result (2026-04-06)**: ✅ LLM judgment is acceptable. Contextual judgment is more appropriate than setting explicit thresholds.

### 3.3 Type Selection Logic

| ID | Rule | Verification Method | Status |
|----|------|---------------------|--------|
| TY-01 | External source (web-clip, paper, article) -> `reference` | Type check | ✅ |
| TY-02 | Personal insight + supporting evidence -> `insight` | ⚠️ LLM judgment | ✅ |
| TY-03 | Facts / data / observations -> `record` | ⚠️ LLM judgment | ✅ |
| TY-04 | Ambiguous between record and insight -> `record` (conservative default) | Ambiguous input fixture | ✅ |

**TY-04 Review Result (2026-04-06)**: ✅ record default is acceptable. Maintaining conservative approach.

---

## 4. Tagging Rules

| ID | Rule | Verification Method | Status |
|----|------|---------------------|--------|
| TG-01 | Select tags by referencing taxonomy.md descriptions (guessing from name alone is prohibited) | ⚠️ LLM judgment | ✅ |
| TG-02 | Max 3 tags | Count | ✅ |
| TG-03 | Entity IDs must not be included in tags (managed via mentions) | ID list cross-reference | ✅ |
| TG-04 | Prefer specific sub-tags over mega-tags with 50+ entries | ⚠️ LLM judgment | ✅ |
| TG-05 | New tag creation is allowed, but must verify no synonyms exist in existing tags and aliases | taxonomy cross-reference | ✅ |
| TG-06 | Tag vocabulary injected in YAML list format (name + desc). Inline format is prohibited | Context injection format | ✅ |
| TG-07 | Lowercase kebab-case | regex | ✅ |

---

## 5. mentions Field Rules

| ID | Rule | Verification Method | Status |
|----|------|---------------------|--------|
| MN-01 | Type prefix required: `people/{id}`, `orgs/{id}`, `projects/{id}` | regex | ✅ |
| MN-02 | Array syntax required (even if empty, use `mentions: []`). **Always include** | YAML parse | ✅ |
| MN-03 | Extract by cross-referencing People mapping name/aliases against body text | Entity input fixture | ✅ |
| MN-04 | Do not mention generic titles ("manager", "client") | Negative fixture | ✅ |
| MN-05 | `mentions: []` (empty array) = no entity match | Value check | ✅ |
| MN-06 | Missing mentions field = legacy file or oversight (repair via /refresh) | Field existence check | ✅ |

**MN-02/05/06 Review Result (2026-04-06)**: The mentions field was in an ambiguous state due to design changes. **Policy finalized**: Always include mentions field in all files. When no entity match exists, set `mentions: []`. Missing field indicates "legacy file" or "oversight" and is a repair target for /refresh. The semantic distinction between MN-05/MN-06 is abolished, unified to **"mentions field should always be present"**.

---

## 6. Entity Auto-Creation Rules (Phase 2.5)

| ID | Rule | Verification Method | Status |
|----|------|---------------------|--------|
| EN-01 | Participant name not in People mapping -> create new Person | New person input fixture | ✅ |
| EN-02 | String matching (mapping) before creation -> double-check with Grep (knowledge/people/) | Log confirmation | ✅ |
| EN-03 | New Person id is kebab-case | regex | ✅ |
| EN-04 | Organization not in Org mapping -> create new Org | New organization input fixture | ✅ |
| EN-05 | Update Person's company field to orgs/ id | Field value check | ✅ |
| EN-06 | Relationship inferred from context (client / partner / colleague, etc.) | ⚠️ LLM judgment | ✅ |

**EN-06 Review Result (2026-04-06)**: ✅ Inference is acceptable.

---

## 7. Task Extraction Rules

| ID | Rule | Verification Method | Status |
|----|------|---------------------|--------|
| TK-01 | Statement with clear action verb -> task candidate | Task input fixture | ✅ |
| TK-02 | Suggestions / questions / observations only -> do not create task | Negative fixture | ✅ |
| TK-03 | Created with `status: draft` (all AI auto-generated tasks are draft) | Value check | ✅ |
| TK-04 | Background is 2-4 sentences. Readable by third parties. No over-compression | ⚠️ Sentence count | ✅ |
| TK-05 | Duplicate check against existing tickets required | Duplicate task fixture | ✅ |
| TK-06 | Context includes related knowledge/notes/ paths in `Title::Path` format | Format check | ✅ |
| TK-07 | source uses _organized/ path | Path check | ✅ |

---

## 8. Organized Version (_organized/) Creation Rules

| ID | Rule | Verification Method | Status |
|----|------|---------------------|--------|
| OR-01 | Inherit original `created` | Value comparison | ✅ |
| OR-02 | Add `organized: true` to frontmatter | Value check | ✅ |
| OR-03 | Organize and structure content but do not change original meaning | ⚠️ LLM judgment | ✅ |
| OR-04 | Save to `_organized/` with the same filename | Path check | ✅ |

---

## 9. Key Fact Accumulation Rules (people/, projects/)

| ID | Rule | Verification Method | Status |
|----|------|---------------------|--------|
| KF-01 | Do not add semantically duplicate information | ⚠️ LLM judgment | ✅ |
| KF-02 | Target max ~20 items. Report only if exceeded | Count | ✅ |
| KF-03 | Read of people/projects/ limited to target files only (max 3) | Log confirmation | ✅ |
| KF-04 | Update targets in projects/: Key Facts, Competitors, Watch Keywords | Section confirmation | ✅ |

---

## 10. Profile Update Rules (Phase 4)

| ID | Rule | Verification Method | Status |
|----|------|---------------------|--------|
| PF-01 | Update conservatively (do not update if change is not clear) | Update frequency check | ✅ |
| PF-02 | Do not modify category descriptions (parenthetical text) | String comparison | ✅ |
| PF-03 | Add to Active Projects only if knowledge/projects/{id}.md exists | File existence check | ✅ |
| PF-04 | Do not demote Interests just because they haven't been mentioned in the past 2 weeks | ⚠️ LLM judgment | ✅ |
| PF-05 | Do not add new Interest from only 1-2 mentions | ⚠️ LLM judgment | ⚠️ Not yet designed |

**PF-05 Review Result (2026-04-06)**: ⚠️ This threshold has not been sufficiently designed and remains provisional. Maintaining current state for now; tests will only verify "conservative behavior." Threshold optimization is a future task.

---

## 11. Pipeline Control Rules

| ID | Rule | Verification Method | Status |
|----|------|---------------------|--------|
| PL-01 | Max 5 agents in parallel. Batch split if exceeded | Log confirmation | ✅ |
| PL-02 | On agent error, skip and do not append to .processed | Error fixture | ✅ |
| PL-03 | workspace/ directory specified -> redirect to /close | workspace input test | ✅ |
| PL-04 | All categories 0 files -> exit with "No unprocessed files" | Empty input test | ✅ |
| PL-05 | Phase 1/2 are mutually independent (can run in parallel) | Design confirmation | ✅ |
| PL-06 | Phase 2.5 and Phase 3 are mutually independent (can run in parallel) | Design confirmation | ✅ |
| PL-07 | Phase 4 executes after Phase 1-3 completion | Dependency | ✅ |
| PL-08 | .processed update is batched after all agents complete | Timing confirmation | ✅ |
| PL-09 | Run `rill strip-entity-tags` during result collection | Post-processing confirmation | ✅ |

---

## 12. .processed State Machine

| ID | Rule | Verification Method | Status |
|----|------|---------------------|--------|
| PS-01 | journal: not listed -> append filename (`2026-01-15-103000.md`) | Format check | ✅ |
| PS-02 | inbox/*: not listed -> `filename:organized` -> `filename:extracted` | State transition | ✅ |
| PS-03 | On skip: `filename:skipped` | State check | ✅ |
| PS-04 | On error: do not append to .processed (allows retry) | Error state check | ✅ |

---

## 13. Context Injection Rules

| ID | Rule | Verification Method | Status |
|----|------|---------------------|--------|
| CX-01 | Taxonomy injected in YAML list format (name + desc) | Format confirmation | ✅ |
| CX-02 | People mapping in extended one-line format (`people/id: name \| aliases: ... \| company: ...`) | Format confirmation | ✅ |
| CX-03 | Orgs mapping in one-line format (`orgs/id: name (aliases)`) | Format confirmation | ✅ |
| CX-04 | Projects mapping in one-line format (`projects/id: name (stage, tags)`) | Format confirmation | ✅ |
| CX-05 | Agent prompt templates are Read by the agents themselves | Design confirmation | ✅ |
| CX-06 | Full text of target files is not read in the parent context | Design confirmation | ✅ |

---

## 14. Single-File Mode Specific Rules

| ID | Rule | Verification Method | Status |
|----|------|---------------------|--------|
| SF-01 | If identically-named file exists in _organized/, prefer that one | Path resolution | ✅ |
| SF-02 | Exclude `_workspace.md`, `_summary.md`, `_organized/` from targets | Exclusion check | ✅ |
| SF-03 | Phase 2 (organized version creation) is not executed (target is assumed pre-structured) | Output check | ✅ |
| SF-04 | Phase 4 (Profile update), Phase 5 (Plugin hooks) are not executed | Output check | ✅ |

---

## Review Results Summary (2026-04-06)

| ID | Rule | Result | Notes |
|----|------|--------|-------|
| **EV-03** | Same topic + different type -> create new | ✅ Maintain current | Separating facts from interpretations is sound |
| **EV-06** | New creation judgment on partial hits | ✅ LLM judgment acceptable | Contextual judgment more appropriate than explicit thresholds |
| **TY-04** | Ambiguous record/insight -> record default | ✅ Maintain current | Conservative approach is acceptable |
| **MN-02/05/06** | mentions field handling | ✅ **Policy finalized**: always include | Missing field = legacy file. Repair via /refresh |
| **EN-06** | Context-based relationship inference | ✅ Inference acceptable | |
| **PF-05** | Interest addition threshold | ⚠️ Remains undesigned | Provisional state. Tests verify only "conservative behavior" |
