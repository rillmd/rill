#!/bin/bash
# test/skills/test-page.sh — /page integration test
#
# Usage: bash test/skills/test-page.sh [--skip-execute]
#
# Tests new page creation from a theme related to existing fixture data.
# Validates page + recipe file structure.
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
  mkdir -p "$VAULT_DIR/pages"
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

# --- Execute /page ---
if ! $SKIP_EXECUTE; then
  echo ""
  echo "=== Executing /page OAuth Authentication Provider Selection Guide ==="
  echo "  (this may take 1-3 minutes)"
  echo ""

  isolate_test_vault "$VAULT_DIR"

  claude -p "/page OAuth Authentication Provider Selection Guide" \
    --output-format text \
    --max-turns 30 \
    2>&1 | tee "$RESULTS_DIR/page-output.log"

  echo ""
  echo "=== /page execution complete ==="

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

# Find the created page
echo "=== CR: Page creation ==="
PAGE_FILE=""
RECIPE_FILE=""
for f in pages/*.md; do
  [[ -f "$f" ]] || continue
  fname=$(basename "$f")
  [[ "$fname" == *.recipe.md ]] && continue
  PAGE_TYPE=$(fm_get "$f" "type")
  if [[ "$PAGE_TYPE" == "page" ]]; then
    PAGE_FILE="$f"
    PAGE_ID="${fname%.md}"
    RECIPE_FILE="pages/${PAGE_ID}.recipe.md"
    echo "  Found page: $fname"
  fi
done

if [[ -z "$PAGE_FILE" ]]; then
  assert_true "false" "CR-01: Page file was created"
else
  assert_true "true" "CR-01: Page file was created ($PAGE_FILE)"

  # INV-02: Required frontmatter
  echo "=== INV-02: Page frontmatter ==="
  PG_TYPE=$(fm_get "$PAGE_FILE" "type")
  assert_eq "$PG_TYPE" "page" "INV-02: type is 'page'"

  PG_CREATED=$(fm_get "$PAGE_FILE" "created")
  assert_true "[[ -n '$PG_CREATED' ]]" "INV-02: has created"

  PG_ID=$(fm_get "$PAGE_FILE" "id")
  assert_true "[[ -n '$PG_ID' ]]" "INV-02: has id"

  PG_NAME=$(fm_get "$PAGE_FILE" "name")
  assert_true "[[ -n '$PG_NAME' ]]" "INV-02: has name"

  PG_DESC=$(fm_get "$PAGE_FILE" "description")
  assert_true "[[ -n '$PG_DESC' ]]" "INV-02: has description"

  # INV-04: Filename is kebab-case, no date prefix
  echo "=== INV-04: Filename convention ==="
  HAS_DATE=$(echo "$PAGE_ID" | grep -cE '^[0-9]{4}-[0-9]{2}-[0-9]{2}' 2>/dev/null || true)
  HAS_DATE=$(echo "${HAS_DATE:-0}" | tail -1 | tr -d '[:space:]')
  assert_eq "$HAS_DATE" "0" "INV-04: No date prefix in page filename"

  IS_KEBAB=$(echo "$PAGE_ID" | grep -cE '^[a-z0-9]+(-[a-z0-9]+)*$' 2>/dev/null || true)
  IS_KEBAB=$(echo "${IS_KEBAB:-0}" | tail -1 | tr -d '[:space:]')
  assert_gt "$IS_KEBAB" 0 "INV-04: Filename is kebab-case"

  # CR-06: sources in frontmatter
  PG_SOURCES=$(fm_get "$PAGE_FILE" "sources")
  if [[ -n "$PG_SOURCES" ]]; then
    assert_true "true" "CR-06: has sources field"
  else
    echo "  INFO: sources field not present (may be empty for new page)"
  fi

  # DQ-03: Scannable structure (multiple sections)
  echo "=== DQ-03: Document structure ==="
  SECTION_COUNT=$({ grep -c '^## ' "$PAGE_FILE" 2>/dev/null || echo "0"; } | tr -d '[:space:]')
  assert_gt "$SECTION_COUNT" 1 "DQ-03: Has multiple sections ($SECTION_COUNT)"

  # CR-02: Recipe file exists
  echo "=== CR-02: Recipe file ==="
  if [[ -f "$RECIPE_FILE" ]]; then
    assert_true "true" "CR-02: recipe.md exists"

    # CR-03: Recipe type
    RC_TYPE=$(fm_get "$RECIPE_FILE" "type")
    assert_eq "$RC_TYPE" "recipe" "CR-03: recipe type is 'recipe'"

    # CR-04: Recipe has purpose section
    HAS_PURPOSE=$({ grep -ci 'Purpose' "$RECIPE_FILE" 2>/dev/null || echo "0"; } | tr -d '[:space:]')
    assert_gt "$HAS_PURPOSE" 0 "CR-04: recipe has purpose section"

    # CR-05: Recipe has source hints
    HAS_HINTS=$({ grep -ci 'Source\|Hint' "$RECIPE_FILE" 2>/dev/null || echo "0"; } | tr -d '[:space:]')
    assert_gt "$HAS_HINTS" 0 "CR-05: recipe has source hints section"
  else
    assert_true "false" "CR-02: recipe.md exists"
  fi
fi
echo ""

# Existing file immutability
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
if [[ -n "$PAGE_FILE" ]]; then
  echo "  Page: $PAGE_FILE"
  echo "  Recipe: $RECIPE_FILE (exists: $([[ -f "$RECIPE_FILE" ]] && echo yes || echo no))"
  echo "  Sections: $SECTION_COUNT"
fi
echo ""

PG_EXISTS=false
RC_EXISTS=false
if [[ -n "$PAGE_FILE" ]]; then PG_EXISTS=true; fi
if [[ -f "$RECIPE_FILE" ]]; then RC_EXISTS=true; fi

cat > "$RESULTS_DIR/summary.json" <<EOF
{
  "timestamp": "$TIMESTAMP",
  "vault": "$VAULT_DIR",
  "skill": "page",
  "page_exists": $PG_EXISTS,
  "recipe_exists": $RC_EXISTS,
  "pass": $_PASS,
  "fail": $_FAIL,
  "total": $_TOTAL
}
EOF

report_results || true

echo ""
echo "Vault preserved at: $VAULT_DIR"
echo "To re-run assertions: bash $0 --skip-execute --vault=$VAULT_DIR"
