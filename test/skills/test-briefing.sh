#!/bin/bash
# test/skills/test-briefing.sh — /briefing integration test
#
# Usage: bash test/skills/test-briefing.sh [--skip-execute]
#
# Copies fixtures to a temp vault, runs /briefing for 2026-01-15,
# then validates the generated Daily Note with Layer 1 assertions.
#
# --skip-execute: Skip the claude -p execution and only run assertions

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

TARGET_DATE="2026-01-15"
DAILY_NOTE="reports/daily/$TARGET_DATE.md"

# --- Setup ---
if [[ -z "$VAULT_DIR" ]]; then
  VAULT_DIR=$(mktemp -d -t rill-test-XXXXXX)
  echo "=== Setting up test vault: $VAULT_DIR ==="
  cp -r "$FIXTURES_DIR"/* "$VAULT_DIR/"
  REPO_DIR="$(cd "$TEST_DIR/.." && pwd)"
  cp -r "$REPO_DIR/.claude" "$VAULT_DIR/.claude"
  cp -r "$REPO_DIR/bin" "$VAULT_DIR/bin"
  [[ -d "$REPO_DIR/plugins" ]] && cp -r "$REPO_DIR/plugins" "$VAULT_DIR/plugins"
  cp "$REPO_DIR/taxonomy.md" "$VAULT_DIR/taxonomy.md"
  cp "$REPO_DIR/CLAUDE.md" "$VAULT_DIR/CLAUDE.md"
  [[ -f "$REPO_DIR/SPEC.md" ]] && cp "$REPO_DIR/SPEC.md" "$VAULT_DIR/SPEC.md"
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
find inbox/ -type f -name "*.md" 2>/dev/null | sort | while read -r f; do
  echo "$(file_hash "$f") $f"
done > "$HASH_FILE"

# --- Execute /briefing ---
if ! $SKIP_EXECUTE; then
  echo ""
  echo "=== Executing /briefing $TARGET_DATE ==="
  echo "  (this may take 1-3 minutes)"
  echo ""

  isolate_test_vault "$VAULT_DIR"

  claude -p "/briefing $TARGET_DATE" \
    --output-format text \
    --max-turns 50 \
    2>&1 | tee "$RESULTS_DIR/briefing-output.log"

  echo ""
  echo "=== /briefing execution complete ==="

  check_real_repo_contamination "$REPO_REAL_DIR" "$VAULT_DIR"
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

# 2. Daily Note existence and frontmatter (INV-02, INV-04)
echo "=== INV-02/04: Daily Note ==="
assert_file_exists "$DAILY_NOTE" "INV-04: Daily Note at $DAILY_NOTE"
if [[ -f "$DAILY_NOTE" ]]; then
  DN_TYPE=$(fm_get "$DAILY_NOTE" "type")
  assert_eq "$DN_TYPE" "daily-note" "INV-02: type is 'daily-note'"

  DN_DATE=$(fm_get "$DAILY_NOTE" "date")
  assert_eq "$DN_DATE" "$TARGET_DATE" "INV-02: date matches target"

  DN_CREATED=$(fm_get "$DAILY_NOTE" "created")
  assert_true "[[ -n '$DN_CREATED' ]]" "INV-02: has created field"

  DN_JCOUNT=$(fm_get "$DAILY_NOTE" "journal-count")
  assert_true "[[ -n '$DN_JCOUNT' ]]" "INV-02: has journal-count field"
fi
echo ""

# 3. Section structure (SC-01 to SC-05)
echo "=== SC: Section structure ==="
if [[ -f "$DAILY_NOTE" ]]; then
  # SC-01: Title
  TITLE_LINE=$(grep '^# ' "$DAILY_NOTE" | head -1)
  assert_true "[[ -n '$TITLE_LINE' ]]" "SC-01: Has H1 title"

  # SC-02: Yesterday's Activity
  HAS_ACTIVITY=$(grep -ci '^## .*Yesterday\|^## .*Activity' "$DAILY_NOTE" 2>/dev/null || echo "0")
  assert_gt "$HAS_ACTIVITY" 0 "SC-02: Has activity section"

  # SC-03: Today's Focus
  HAS_FOCUS=$(grep -ci '^## .*Today\|^## .*Focus' "$DAILY_NOTE" 2>/dev/null || echo "0")
  assert_gt "$HAS_FOCUS" 0 "SC-03: Has focus section"

  # SC-04: Situation Analysis
  HAS_ANALYSIS=$(grep -ci '^## .*Situation\|^## .*Analysis' "$DAILY_NOTE" 2>/dev/null || echo "0")
  assert_gt "$HAS_ANALYSIS" 0 "SC-04: Has analysis section"

  # SC-05: Notes (optional — only check if content warrants it)
  HAS_NOTES=$(grep -ci '^## .*Notes\|^## .*Attention\|^## .*Caution' "$DAILY_NOTE" 2>/dev/null || echo "0")
  echo "  INFO: Notes section present: $HAS_NOTES (optional)"
fi
echo ""

# 4. Task display rules (TK-03, TK-04)
echo "=== TK: Task display ==="
if [[ -f "$DAILY_NOTE" ]]; then
  # TK-03: Task links use relative path format ../../tasks/
  TASK_LINKS=$(grep -c '../../tasks/\|tasks/' "$DAILY_NOTE" 2>/dev/null || echo "0")
  assert_gt "$TASK_LINKS" 0 "TK-03: Has task links"

  # TK-04: waiting tasks shown with backtick marker
  # The fixture has confirm-jordan-kim-onboarding with status: waiting
  HAS_WAITING=$({ grep -c '`waiting`\|waiting' "$DAILY_NOTE" 2>/dev/null || echo "0"; } | tr -d '[:space:]')
  assert_gt "$HAS_WAITING" 0 "TK-04: waiting task marker present"

  # Check that open tasks are referenced
  HAS_OAUTH_TASK=$({ grep -c 'oauth-provider-investigation\|OAuth' "$DAILY_NOTE" 2>/dev/null || echo "0"; } | tr -d '[:space:]')
  assert_gt "$HAS_OAUTH_TASK" 0 "TK-01: References open task (oauth investigation)"

  # TK-05: Overdue task detection (review-auth0-contract has due: 2026-01-13, target is 2026-01-15)
  HAS_OVERDUE=$({ grep -ci 'overdue\|expired\|delayed\|auth0.*contract\|review-auth0-contract\|contract.*review' "$DAILY_NOTE" 2>/dev/null || echo "0"; } | tr -d '[:space:]')
  assert_gt "$HAS_OVERDUE" 0 "TK-05: Overdue task detected or referenced"
fi
echo ""

# 5. Previous briefing reference (DC-04)
echo "=== DC-04: Previous briefing ==="
if [[ -f "$DAILY_NOTE" ]]; then
  # The previous day's briefing (2026-01-14.md) was available.
  # The new briefing should reference or build on previous content.
  HAS_PREV_REF=$({ grep -ci 'previous\|prior\|2026-01-14\|yesterday\|last briefing' "$DAILY_NOTE" 2>/dev/null || echo "0"; } | tr -d '[:space:]')
  assert_gt "$HAS_PREV_REF" 0 "DC-04: References previous briefing content"
fi
echo ""

# 6. Workspace mention (DC-06/07)
echo "=== DC: Workspace awareness ==="
if [[ -f "$DAILY_NOTE" ]]; then
  HAS_WS_REF=$(grep -ci 'sample-workspace\|auth\|authentication\|workspace' "$DAILY_NOTE" 2>/dev/null || echo "0")
  assert_gt "$HAS_WS_REF" 0 "DC-06: References active workspace"
fi
echo ""

# 7. No Wikilinks (reuse from distill invariants)
echo "=== INV: No Wikilinks ==="
if [[ -f "$DAILY_NOTE" ]]; then
  WIKILINK_COUNT=$(grep -c '\[\[' "$DAILY_NOTE" 2>/dev/null || true)
  WIKILINK_COUNT=${WIKILINK_COUNT:-0}
  WIKILINK_COUNT=$(echo "$WIKILINK_COUNT" | tail -1 | tr -d '[:space:]')
  assert_eq "$WIKILINK_COUNT" "0" "No Wikilinks in Daily Note"
fi
echo ""

# 8. Existing file immutability
echo "=== INV: Existing file immutability ==="
for existing in knowledge/notes/saas-freemium-pricing-strategy.md knowledge/notes/oauth-provider-selection-criteria.md; do
  if [[ -f "$existing" && -f "$FIXTURES_DIR/$existing" ]]; then
    orig_created=$(fm_get "$FIXTURES_DIR/$existing" "created")
    curr_created=$(fm_get "$existing" "created")
    assert_eq "$curr_created" "$orig_created" "Existing created unchanged: $(basename $existing)"
  fi
done
echo ""

# --- Summary ---
echo ""
echo "==========================================="
echo "  Test Summary"
echo "==========================================="
echo "  Vault: $VAULT_DIR"
echo "  Results: $RESULTS_DIR"
echo "  Daily Note: $DAILY_NOTE"
if [[ -f "$DAILY_NOTE" ]]; then
  echo "  Sections: $(grep -c '^## ' "$DAILY_NOTE" 2>/dev/null || echo 0)"
  echo "  Word count: $(wc -w < "$DAILY_NOTE" | tr -d ' ')"
fi
echo ""

# Save summary
DN_EXISTS=false
DN_SECTIONS=0
DN_WORDS=0
if [[ -f "$DAILY_NOTE" ]]; then
  DN_EXISTS=true
  DN_SECTIONS=$(grep -c '^## ' "$DAILY_NOTE" 2>/dev/null || echo 0)
  DN_WORDS=$(wc -w < "$DAILY_NOTE" | tr -d ' ')
fi

cat > "$RESULTS_DIR/summary.json" <<EOF
{
  "timestamp": "$TIMESTAMP",
  "vault": "$VAULT_DIR",
  "skill": "briefing",
  "target_date": "$TARGET_DATE",
  "daily_note_exists": $DN_EXISTS,
  "sections": $DN_SECTIONS,
  "words": $DN_WORDS,
  "pass": $_PASS,
  "fail": $_FAIL,
  "total": $_TOTAL
}
EOF

report_results || true

echo ""
echo "Vault preserved at: $VAULT_DIR"
echo "To re-run assertions: bash $0 --skip-execute --vault=$VAULT_DIR"
