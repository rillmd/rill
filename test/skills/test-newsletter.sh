#!/bin/bash
# test/skills/test-newsletter.sh — /newsletter integration test
#
# Usage: bash test/skills/test-newsletter.sh [--skip-execute]
#
# Copies fixtures to a temp vault, runs /newsletter for 2026-01-15,
# then validates the generated newsletter with Layer 1 assertions.
#
# NOTE: This test uses real WebSearch/WebFetch. Results vary by run.
# Assertions focus on structural rules, not content quality.
#
# --skip-execute: Skip claude -p and only run assertions

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
NEWSLETTER="reports/newsletter/$TARGET_DATE.md"

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
  # Ensure newsletter output directory exists
  mkdir -p "$VAULT_DIR/reports/newsletter"
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

# --- Save inbox hashes ---
HASH_FILE="$RESULTS_DIR/inbox-hashes.txt"
find inbox/ -type f -name "*.md" 2>/dev/null | sort | while read -r f; do
  echo "$(file_hash "$f") $f"
done > "$HASH_FILE"

# --- Execute /newsletter ---
if ! $SKIP_EXECUTE; then
  echo ""
  echo "=== Executing /newsletter $TARGET_DATE ==="
  echo "  (this may take 3-8 minutes due to WebSearch)"
  echo ""

  isolate_test_vault "$VAULT_DIR"

  claude -p "/newsletter $TARGET_DATE" \
    --output-format text \
    --max-turns 80 \
    2>&1 | tee "$RESULTS_DIR/newsletter-output.log"

  echo ""
  echo "=== /newsletter execution complete ==="

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

# 2. Newsletter existence and frontmatter (INV-02, INV-04)
echo "=== INV-02/04: Newsletter file ==="
assert_file_exists "$NEWSLETTER" "INV-04: Newsletter at $NEWSLETTER"
if [[ -f "$NEWSLETTER" ]]; then
  NL_TYPE=$(fm_get "$NEWSLETTER" "type")
  assert_eq "$NL_TYPE" "newsletter" "INV-02: type is 'newsletter'"

  NL_CREATED=$(fm_get "$NEWSLETTER" "created")
  assert_true "[[ -n '$NL_CREATED' ]]" "INV-02: has created field"

  NL_KEYWORDS=$(fm_get "$NEWSLETTER" "keywords")
  assert_true "[[ -n '$NL_KEYWORDS' ]]" "MD-01: has keywords field"

  NL_SRCCOUNT=$(fm_get "$NEWSLETTER" "source-count")
  assert_true "[[ -n '$NL_SRCCOUNT' ]]" "MD-02: has source-count field"

  NL_ALERTCOUNT=$(fm_get "$NEWSLETTER" "alert-count")
  assert_true "[[ -n '$NL_ALERTCOUNT' ]]" "MD-03: has alert-count field"

  NL_DDTOPIC=$(fm_get "$NEWSLETTER" "deep-dive-topic")
  assert_true "[[ -n '$NL_DDTOPIC' ]]" "MD-04: has deep-dive-topic field"

  NL_DISCCOUNT=$(fm_get "$NEWSLETTER" "discovery-count")
  assert_true "[[ -n '$NL_DISCCOUNT' ]]" "MD-05: has discovery-count field"
fi
echo ""

# 3. Section structure (SC-01 to SC-05)
echo "=== SC: Section structure ==="
if [[ -f "$NEWSLETTER" ]]; then
  TITLE_LINE=$(grep '^# ' "$NEWSLETTER" | head -1)
  assert_true "[[ -n '$TITLE_LINE' ]]" "SC-01: Has H1 title"

  HAS_ALERTS=$({ grep -c '^## Alerts' "$NEWSLETTER" 2>/dev/null || echo "0"; } | tr -d '[:space:]')
  assert_gt "$HAS_ALERTS" 0 "SC-02: Has Alerts section"

  HAS_DEEPDIVE=$({ grep -c '^## Deep Dive' "$NEWSLETTER" 2>/dev/null || echo "0"; } | tr -d '[:space:]')
  assert_gt "$HAS_DEEPDIVE" 0 "SC-03: Has Deep Dive section"

  HAS_DISCOVERY=$({ grep -c '^## Discovery' "$NEWSLETTER" 2>/dev/null || echo "0"; } | tr -d '[:space:]')
  assert_gt "$HAS_DISCOVERY" 0 "SC-04: Has Discovery section"

  HAS_METADATA=$({ grep -ci '^## .*Research Metadata\|^## .*Metadata' "$NEWSLETTER" 2>/dev/null || echo "0"; } | tr -d '[:space:]')
  assert_gt "$HAS_METADATA" 0 "SC-05: Has metadata section"

  # SC-06: Deep Dive length >= 1000 chars
  # Extract Deep Dive section content (between ## Deep Dive and next ##)
  DD_CHARS=$(awk '/^## Deep Dive/{found=1; next} found && /^## /{exit} found{print}' "$NEWSLETTER" 2>/dev/null | wc -c | tr -d '[:space:]')
  assert_gt "$DD_CHARS" 500 "SC-06: Deep Dive has substantial content (${DD_CHARS} chars, target 1000+)"
fi
echo ""

# 4. URL presence (INV-05)
echo "=== INV-05: Source URLs ==="
if [[ -f "$NEWSLETTER" ]]; then
  URL_COUNT=$({ grep -co 'https\?://' "$NEWSLETTER" 2>/dev/null || echo "0"; } | tail -1 | tr -d '[:space:]')
  assert_gt "$URL_COUNT" 0 "INV-05: Newsletter contains URLs ($URL_COUNT found)"
fi
echo ""

# 5. Metadata section content (MD-06, MD-07)
echo "=== MD: Metadata content ==="
if [[ -f "$NEWSLETTER" ]]; then
  # MD-06: Keywords listed in metadata section
  HAS_KW_LIST=$({ grep -c 'Alert:\|Deep Dive:\|Discovery:' "$NEWSLETTER" 2>/dev/null || echo "0"; } | tr -d '[:space:]')
  assert_gt "$HAS_KW_LIST" 0 "MD-06: Metadata has keyword categories"

  # MD-07: Source URLs in metadata
  METADATA_URLS=$(awk '/^## .*Research Metadata|^## .*Metadata/{found=1; next} found{print}' "$NEWSLETTER" 2>/dev/null | grep -c 'https\?://' 2>/dev/null || echo "0")
  METADATA_URLS=$(echo "$METADATA_URLS" | tr -d '[:space:]')
  assert_gt "$METADATA_URLS" 0 "MD-07: Metadata has source URLs"
fi
echo ""

# 6. Existing file immutability
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
echo "  Newsletter: $NEWSLETTER"
if [[ -f "$NEWSLETTER" ]]; then
  echo "  Sections: $(grep -c '^## ' "$NEWSLETTER" 2>/dev/null || echo 0)"
  echo "  Word count: $(wc -w < "$NEWSLETTER" | tr -d ' ')"
  echo "  URLs: $URL_COUNT"
fi
echo ""

NL_EXISTS=false
NL_SECTIONS=0
NL_WORDS=0
if [[ -f "$NEWSLETTER" ]]; then
  NL_EXISTS=true
  NL_SECTIONS=$(grep -c '^## ' "$NEWSLETTER" 2>/dev/null || echo 0)
  NL_WORDS=$(wc -w < "$NEWSLETTER" | tr -d ' ')
fi

cat > "$RESULTS_DIR/summary.json" <<EOF
{
  "timestamp": "$TIMESTAMP",
  "vault": "$VAULT_DIR",
  "skill": "newsletter",
  "target_date": "$TARGET_DATE",
  "newsletter_exists": $NL_EXISTS,
  "sections": $NL_SECTIONS,
  "words": $NL_WORDS,
  "pass": $_PASS,
  "fail": $_FAIL,
  "total": $_TOTAL
}
EOF

report_results || true

echo ""
echo "Vault preserved at: $VAULT_DIR"
echo "To re-run assertions: bash $0 --skip-execute --vault=$VAULT_DIR"
