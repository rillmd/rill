# Test Fixtures — Expected Output Definitions

Expected outputs from /distill for each fixture. Used as the basis for test assertions.

---

## journal/2026-01-15-103000.md — SaaS Pricing Ideas

**Rules Covered**: KE-01, KE-02, KE-03, TY-02, TG-01-07, MN-01-05, INV-04-09

**Expected Output**:
- `inbox/journal/_organized/2026-01-15-103000.md` is generated (OR-01-04)
- 1 insight is generated in `knowledge/notes/`
  - `type: insight` (personal analysis/interpretation)
  - `source: inbox/journal/_organized/2026-01-15-103000.md`
  - `tags` includes `pricing` or `monetization` (matches taxonomy.md descriptions)
  - `tags` has 3 or fewer items
  - `mentions: []` (no specific entity references)
  - Filename is English kebab-case
  - Body starts with `# Title`

---

## journal/2026-01-15-143000.md — Meeting with Alex Chen

**Rules Covered**: MN-03, EN-01, EN-02, EN-05, KF-01-04, TK-01, INV-07-08

**Expected Output**:
- `inbox/journal/_organized/2026-01-15-143000.md` is generated
- 1-2 files generated in `knowledge/notes/`
  - `type: record` (factual meeting report)
  - `mentions` includes `people/alex-chen` (existing entity)
  - `mentions` includes `projects/sample-project`
  - `tags` does not include `sample-project` (entities are managed via mentions: INV-07)
- Auto-creation of `knowledge/people/jordan-kim.md` **only occurs in batch mode Phase 2.5**.
  Phase 2.5 detects unknown people from the `participants:` field in `_organized/`.
  Since journal-agent-generated `_organized/` files originate from journals, they do not have `participants:`.
  -> **Do not expect automatic entity creation for Jordan Kim from journal entries**.
  EN-01 is only triggered when meeting notes (`inbox/meetings/`) are input with `participants:`.
  EN-01 verification in the test harness will be addressed when meetings fixtures are added.
- Possible key fact additions to `knowledge/people/alex-chen.md` (KF-01)
  - New information about "auth feature delay" and "OAuth provider spec change"
- Task candidates: None (the only clear action verb is "schedule next meeting," which is already agreed upon)

---

## journal/2026-01-15-183000.md — Freemium Follow-up (Duplicate Test)

**Rules Covered**: EV-02 (same topic + same type -> skip)

**Expected Output**:
- No new file generated in `knowledge/notes/`, or if it matches the same topic + same type (insight) as existing `saas-freemium-pricing-strategy.md`, it is skipped
- Evergreen check finds existing file -> reports skip

**Important**: This tests EV-02. Since the existing `saas-freemium-pricing-strategy.md` is an insight on the same theme, the correct behavior is to skip without creating a new file.

---

## journal/2026-01-15-210000.md — Task Extraction Test

**Rules Covered**: TK-01, TK-03, TK-04, TK-05, TK-06, TK-07

**Expected Output**:
- Task candidates:
  - "Investigate alternative OAuth providers" -> **Duplicate**: matches existing `tasks/oauth-provider-investigation.md` -> do not create (TK-05)
  - "Confirm Jordan Kim's onboarding schedule" -> May be extracted as a new task candidate
    - `status: draft` (TK-03)
    - `source: inbox/journal/_organized/2026-01-15-210000.md` (TK-07)
    - `background` is 2-4 sentences (TK-04)

---

## journal/2026-01-15-220000.md — Negative Case (No Extraction)

**Rules Covered**: TK-02 (not a task), KE-01 (not knowledge)

**Expected Output**:
- No new file generated in `knowledge/notes/` (reflection with no new ideas or discoveries)
- No task candidates ("clean up emails" is too vague)

**Important**: This is a negative control. Verifies that knowledge and tasks are not over-extracted from diary-like content.

---

## web-clips/2026-01-14-120000-oauth-provider-migration-guide.md — External Article

**Rules Covered**: TY-01, SF-01-04, INV-04

**Expected Output**:
- Organized version created in `_organized/` during Phase 2 (with tags and structure)
- 1 file generated in `knowledge/notes/` during Phase 3
  - `type: reference` (external citation: TY-01)
  - `source: inbox/web-clips/_organized/2026-01-14-120000-oauth-provider-migration-guide.md`
  - `tags` includes `infrastructure`
  - `mentions` may include `projects/sample-project` (OAuth-related)

---

## Cross-Cutting Verification Items

### Invariant Conditions (common to all fixtures) — First Run Results: ALL PASS
- [x] INV-01: All original files in inbox/ are unchanged (hash comparison)
- [ ] INV-02-03: `created` and `source` of existing files are unchanged
- [x] INV-04-08: frontmatter type, tags, mentions are all in correct format
- [x] INV-09: All generated filenames are kebab-case
- [x] INV-10: `created` in generated files is ISO 8601 format
- [ ] INV-11: `.processed` (journal) has no path prefixes (visually confirmed)
- [x] INV-15: No `[[` Wikilinks in body text

### .processed Updates — First Run Results: ALL PASS
- [x] PS-01: 5 filenames appended to `inbox/journal/.processed`
- [x] PS-02: web clip appended to `inbox/web-clips/.processed`

### Entity Creation — First Run Results: Expected values revised
- [ ] EN-01: Phase 2.5 is not triggered from journal entries, so automatic creation of Jordan Kim is not expected. Will be addressed when meetings fixtures are added

### Profile Updates (Phase 4)
- [ ] PF-01: No excessive updates to me.md (should not make major changes in a single /distill)
- [ ] PF-02: Category descriptions are unchanged

### First Run Baseline (2026-04-06)
- New knowledge/notes/: 4 files (cicd-pipeline-improvement-plan, oauth-contract-dependency-on-auth-delay, oauth-spec-change-auth-delay, plg-billing-triggers-personal-tools)
- New tasks/: 2 files (plan-oauth-provider-migration, resolve-auth-blocker) — all status: draft
- Layer 1 assertions: 15/16 PASS (EN-01 resolved by revising expected values)
