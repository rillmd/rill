#!/bin/bash
# test/skills/test-distill.sh — /distill integration test
#
# Usage: bash test/skills/test-distill.sh [--skip-execute]
#
# Copies fixtures to a temp vault, runs /distill via claude -p,
# then validates outputs with Layer 1 assertions.
#
# --skip-execute: Skip the claude -p execution and only run assertions
#                 on an existing vault (for re-running assertions after manual fixes)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TEST_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ASSERTIONS_DIR="$TEST_DIR/assertions"
FIXTURES_DIR="$TEST_DIR/fixtures"
REPO_REAL_DIR="$(cd "$TEST_DIR/.." && pwd)"  # For contamination check after claude -p

source "$ASSERTIONS_DIR/lib.sh"

SKIP_EXECUTE=false
VAULT_DIR=""
for arg in "$@"; do
  case "$arg" in
    --skip-execute) SKIP_EXECUTE=true ;;
    --vault=*) VAULT_DIR="${arg#--vault=}" ;;
  esac
done

# --- Setup ---
if [[ -z "$VAULT_DIR" ]]; then
  VAULT_DIR=$(mktemp -d -t rill-test-XXXXXX)
  echo "=== Setting up test vault: $VAULT_DIR ==="
  cp -r "$FIXTURES_DIR"/* "$VAULT_DIR/"
  # Copy rill CLI, skill files, and system files from the real repo
  REPO_DIR="$(cd "$TEST_DIR/.." && pwd)"
  cp -r "$REPO_DIR/.claude" "$VAULT_DIR/.claude"
  cp -r "$REPO_DIR/bin" "$VAULT_DIR/bin"
  [[ -d "$REPO_DIR/plugins" ]] && cp -r "$REPO_DIR/plugins" "$VAULT_DIR/plugins"
  # Overlay system files from repo (taxonomy, CLAUDE.md, SPEC.md)
  # These are the files being localized — must use repo versions, not fixture copies
  cp "$REPO_DIR/taxonomy.md" "$VAULT_DIR/taxonomy.md"
  cp "$REPO_DIR/CLAUDE.md" "$VAULT_DIR/CLAUDE.md"
  [[ -f "$REPO_DIR/SPEC.md" ]] && cp "$REPO_DIR/SPEC.md" "$VAULT_DIR/SPEC.md"
  # Initialize git (rill mkfile may need it)
  cd "$VAULT_DIR"
  git init -q
  git add -A
  git commit -q -m "initial test fixtures"
else
  echo "=== Using existing vault: $VAULT_DIR ==="
  cd "$VAULT_DIR"
fi

TIMESTAMP=$(date +%Y%m%d-%H%M%S)
RESULTS_DIR="$TEST_DIR/results/$TIMESTAMP"
mkdir -p "$RESULTS_DIR"

# --- Save inbox hashes for mutation check ---
HASH_FILE="$RESULTS_DIR/inbox-hashes.txt"
find inbox/ -type f -name "*.md" | sort | while read -r f; do
  echo "$(file_hash "$f") $f"
done > "$HASH_FILE"

# --- Execute /distill ---
if ! $SKIP_EXECUTE; then
  echo ""
  echo "=== Executing /distill ==="
  echo "  (this may take 1-3 minutes)"
  echo ""

  isolate_test_vault "$VAULT_DIR"

  claude -p "/distill" \
    --output-format text \
    --max-turns 80 \
    2>&1 | tee "$RESULTS_DIR/distill-output.log"

  check_real_repo_contamination "$REPO_REAL_DIR" "$VAULT_DIR"

  echo ""
  echo "=== /distill execution complete ==="
fi

# --- Layer 1 Assertions ---
echo ""
echo "==========================================="
echo "  Layer 1: Structural Validation"
echo "==========================================="
echo ""

# 1. Inbox immutability (INV-01)
echo "=== INV-01: Inbox immutability ==="
bash "$ASSERTIONS_DIR/check-no-mutation.sh" "$HASH_FILE" || true
echo ""

# 2. Organized files created and validated (OR-01-04)
echo "=== OR: Organized files ==="
for journal in inbox/journal/2026-*.md; do
  name=$(basename "$journal")
  assert_file_exists "inbox/journal/_organized/$name" "Organized version: $name"
done
bash "$ASSERTIONS_DIR/check-organized.sh" "inbox/journal/_organized" "inbox/journal" || true
echo ""

# 2b. Existing file immutability (INV-02, INV-03)
echo "=== INV-02/03: Existing file immutability ==="
for existing in knowledge/notes/saas-freemium-pricing-strategy.md knowledge/notes/oauth-provider-selection-criteria.md; do
  if [[ -f "$existing" && -f "$FIXTURES_DIR/$existing" ]]; then
    orig_created=$(fm_get "$FIXTURES_DIR/$existing" "created")
    curr_created=$(fm_get "$existing" "created")
    assert_eq "$curr_created" "$orig_created" "INV-02: created unchanged in $(basename $existing)"
    orig_source=$(fm_get "$FIXTURES_DIR/$existing" "source")
    curr_source=$(fm_get "$existing" "source")
    if [[ -n "$orig_source" ]]; then
      assert_eq "$curr_source" "$orig_source" "INV-03: source unchanged in $(basename $existing)"
    fi
  fi
done
echo ""

# 3. Knowledge notes created
echo "=== KE: Knowledge notes ==="
NEW_NOTES_COUNT=0
for f in knowledge/notes/*.md; do
  [[ -f "$f" ]] || continue
  # Check if this is a new file (not in fixtures)
  name=$(basename "$f")
  if [[ ! -f "$FIXTURES_DIR/knowledge/notes/$name" ]]; then
    NEW_NOTES_COUNT=$((NEW_NOTES_COUNT + 1))
    echo "  New note: $name"

    # Run all assertion checks on each new note
    bash "$ASSERTIONS_DIR/check-frontmatter.sh" "$f" --required "created,type,source" || true
    bash "$ASSERTIONS_DIR/check-taxonomy.sh" "$f" taxonomy.md || true
    bash "$ASSERTIONS_DIR/check-mentions.sh" "$f" || true
    bash "$ASSERTIONS_DIR/check-file-naming.sh" "$f" || true
    echo ""
  fi
done
assert_gt "$NEW_NOTES_COUNT" 0 "New knowledge notes were created"
echo ""

# 4. .processed updated (PS-01, PS-02) + format validation (INV-11, INV-12)
echo "=== PS: .processed state ==="
assert_file_contains "inbox/journal/.processed" "2026-01-15-103000.md" ".processed has journal 1"
assert_file_contains "inbox/journal/.processed" "2026-01-15-143000.md" ".processed has journal 2"
assert_file_contains "inbox/journal/.processed" "2026-01-15-183000.md" ".processed has journal 3"
assert_file_contains "inbox/journal/.processed" "2026-01-15-210000.md" ".processed has journal 4"
assert_file_contains "inbox/journal/.processed" "2026-01-15-220000.md" ".processed has journal 5"

# INV-11: journal .processed has filename only (no path prefix)
JOURNAL_PATH_PREFIX=$({ grep '/' "inbox/journal/.processed" 2>/dev/null || true; } | wc -l | tr -d ' ')
assert_eq "$JOURNAL_PATH_PREFIX" "0" "INV-11: journal .processed has no path prefixes"

# Web clip .processed
if [[ -f "inbox/web-clips/.processed" ]]; then
  assert_file_contains "inbox/web-clips/.processed" "oauth-provider-migration-guide" ".processed has web clip"
  # INV-12: format is filename:status
  WEBCLIP_FORMAT=$({ grep -E '^[^:]+:(organized|extracted|skipped)$' "inbox/web-clips/.processed" 2>/dev/null || true; } | wc -l | tr -d ' ')
  WEBCLIP_TOTAL=$(wc -l < "inbox/web-clips/.processed" | tr -d ' ')
  if (( WEBCLIP_TOTAL > 0 )); then
    assert_eq "$WEBCLIP_FORMAT" "$WEBCLIP_TOTAL" "INV-12: web-clips .processed has filename:status format"
  fi
fi
echo ""

# 5. No Wikilinks anywhere (INV-15)
echo "=== INV-15: No Wikilinks ==="
WIKILINK_COUNT=$({ grep -rl '\[\[' knowledge/notes/ 2>/dev/null || true; } | wc -l | tr -d ' ')
assert_eq "$WIKILINK_COUNT" "0" "No Wikilinks in knowledge/notes/"
echo ""

# 6. Entity creation check (EN-01)
echo "=== EN: Entity creation ==="
# Note: Phase 2.5 entity auto-creation triggers only from _organized/ participants field,
# which is set by inbox/meetings/ processing. Journal-only vaults won't trigger EN-01.
# This check is informational; EN-01 testing requires meetings fixtures.
if ls knowledge/people/jordan-kim*.md 1>/dev/null 2>&1; then
  echo "  INFO: Jordan Kim entity was created (Phase 2.5 triggered)"
  JORDAN_KIM_FILE=$(ls knowledge/people/jordan-kim*.md | head -1)
  if [[ -n "$JORDAN_KIM_FILE" ]]; then
    assert_file_contains "$JORDAN_KIM_FILE" "company:" "Jordan Kim has company field"
  fi
else
  echo "  INFO: Jordan Kim entity not created (expected — no meetings/ fixture)"
fi
echo ""

# 7. Task creation check (TK-03, TK-05)
echo "=== TK: Task extraction ==="
NEW_TASKS=0
for f in tasks/*.md; do
  [[ -f "$f" ]] || continue
  name=$(basename "$f")
  if [[ ! -f "$FIXTURES_DIR/tasks/$name" ]]; then
    NEW_TASKS=$((NEW_TASKS + 1))
    echo "  New task: $name"
    TASK_STATUS=$(fm_get "$f" "status")
    assert_eq "$TASK_STATUS" "draft" "Task $name has status: draft"
  fi
done
echo "  Total new tasks: $NEW_TASKS"

# TK-05: Duplicate task not created (oauth-provider-investigation already exists)
if [[ -f "tasks/oauth-provider-investigation.md" ]]; then
  TASK_STATUS_EXISTING=$(fm_get "tasks/oauth-provider-investigation.md" "status")
  assert_eq "$TASK_STATUS_EXISTING" "open" "TK-05: Existing task status unchanged (not overwritten)"
fi

# TK-04: Task background has 2+ sentences (spot check on new tasks)
for f in tasks/*.md; do
  [[ -f "$f" ]] || continue
  name=$(basename "$f")
  if [[ ! -f "$FIXTURES_DIR/tasks/$name" ]]; then
    # Count sentences in background section (rough: count periods)
    BG_TEXT=$(awk '/^## Background|^## Goal/{found=1; next} found && /^## /{exit} found{print}' "$f" 2>/dev/null)
    if [[ -n "$BG_TEXT" ]]; then
      SENTENCE_COUNT=$(echo "$BG_TEXT" | grep -o '[.]' | wc -l | tr -d ' ')
      assert_gt "$SENTENCE_COUNT" 1 "TK-04: Task $name background has 2+ sentences"
    fi
  fi
done
echo ""

# 8. Evergreen check: duplicate skip (EV-02)
echo "=== EV-02: Duplicate skip ==="
# journal/183000 is about the same topic as existing saas-freemium-pricing-strategy.md (insight)
# It should NOT create a new note about freemium pricing (same topic + same type)
# Check: no new file with "freemium" or "plg" in name that duplicates the existing note
FREEMIUM_NOTES=0
for f in knowledge/notes/*freemium*.md knowledge/notes/*plg*.md; do
  [[ -f "$f" ]] || continue
  name=$(basename "$f")
  if [[ ! -f "$FIXTURES_DIR/knowledge/notes/$name" ]]; then
    # New file about freemium — check if it duplicates existing
    NEW_TYPE=$(fm_get "$f" "type")
    if [[ "$NEW_TYPE" == "insight" ]]; then
      FREEMIUM_NOTES=$((FREEMIUM_NOTES + 1))
      echo "  WARNING: New insight about freemium/PLG: $name (potential EV-02 violation)"
    fi
  fi
done
# Allow 0 or 1 new freemium insight (the first journal creates one, the duplicate should be skipped)
assert_le "$FREEMIUM_NOTES" 1 "EV-02: At most 1 freemium/PLG insight (dedup working)"
echo ""

# 9. Key fact accumulation check (KF-01, KF-02, KF-04)
echo "=== KF: Key fact accumulation ==="
bash "$ASSERTIONS_DIR/check-keyfacts.sh" "." "$FIXTURES_DIR" || true
echo ""

# 10. Profile immutability check (PF-02)
echo "=== PF-02: Profile category descriptions ==="
if [[ -f "knowledge/me.md" && -f "$FIXTURES_DIR/knowledge/me.md" ]]; then
  # Check that category descriptions in parentheses are unchanged
  for category in "Deep Interests" "Curiosity" "Obligations" "Career"; do
    ORIG_LINE=$(grep "## $category" "$FIXTURES_DIR/knowledge/me.md" 2>/dev/null || true)
    CURR_LINE=$(grep "## $category" "knowledge/me.md" 2>/dev/null || true)
    if [[ -n "$ORIG_LINE" ]]; then
      assert_eq "$CURR_LINE" "$ORIG_LINE" "PF-02: '$category' heading unchanged"
    fi
  done
fi
echo ""

# --- Summary ---
echo ""
echo "==========================================="
echo "  Test Summary"
echo "==========================================="
echo "  Vault: $VAULT_DIR"
echo "  Results: $RESULTS_DIR"
echo "  New knowledge notes: $NEW_NOTES_COUNT"
echo "  New tasks: $NEW_TASKS"
echo ""

# Save summary
cat > "$RESULTS_DIR/summary.json" <<EOF
{
  "timestamp": "$TIMESTAMP",
  "vault": "$VAULT_DIR",
  "new_notes": $NEW_NOTES_COUNT,
  "new_tasks": $NEW_TASKS,
  "pass": $_PASS,
  "fail": $_FAIL,
  "total": $_TOTAL
}
EOF

report_results || true

echo ""
echo "Vault preserved at: $VAULT_DIR"
echo "To re-run assertions: bash $0 --skip-execute --vault=$VAULT_DIR"
