#!/bin/bash
# test/skills/test-clip-tweet.sh — /clip-tweet integration test
#
# Usage: bash test/skills/test-clip-tweet.sh [--skip-execute]
#
# Tests tweet ingestion using a real public tweet URL.
# fetch-tweet.sh requires network access (FixTweet API).
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

# Use the most stable public tweet on the platform: Jack's first tweet (2006)
TWEET_URL="https://x.com/jack/status/20"

# --- Setup ---
if [[ -z "$VAULT_DIR" ]]; then
  VAULT_DIR=$(mktemp -d -t rill-test-XXXXXX)
  echo "=== Setting up test vault: $VAULT_DIR ==="
  cp -r "$FIXTURES_DIR"/* "$VAULT_DIR/"
  REPO_DIR="$(cd "$TEST_DIR/.." && pwd)"
  cp -r "$REPO_DIR/.claude" "$VAULT_DIR/.claude"
  cp -r "$REPO_DIR/bin" "$VAULT_DIR/bin"
  # Remove empty plugins fixture dir to avoid nested copy
  [[ -d "$VAULT_DIR/plugins" ]] && rmdir "$VAULT_DIR/plugins" 2>/dev/null || true
  [[ -d "$REPO_DIR/plugins" ]] && cp -r "$REPO_DIR/plugins" "$VAULT_DIR/plugins"
  cp "$REPO_DIR/taxonomy.md" "$VAULT_DIR/taxonomy.md"
  cp "$REPO_DIR/CLAUDE.md" "$VAULT_DIR/CLAUDE.md"
  [[ -f "$REPO_DIR/SPEC.md" ]] && cp "$REPO_DIR/SPEC.md" "$VAULT_DIR/SPEC.md"
  mkdir -p "$VAULT_DIR/inbox/tweets/_organized"
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

# Save inbox hashes (excluding inbox/tweets/ which we'll add to)
HASH_FILE="$RESULTS_DIR/inbox-hashes.txt"
find inbox/ -type f -name "*.md" -not -path "inbox/tweets/*" 2>/dev/null | sort | while read -r f; do
  echo "$(file_hash "$f") $f"
done > "$HASH_FILE"

# --- Execute /clip-tweet ---
if ! $SKIP_EXECUTE; then
  echo ""
  echo "=== Executing /clip-tweet $TWEET_URL ==="
  echo "  (this may take 1-3 minutes, requires network)"
  echo ""

  isolate_test_vault "$VAULT_DIR"

  claude -p "/clip-tweet $TWEET_URL" \
    --output-format text \
    --max-turns 60 \
    2>&1 | tee "$RESULTS_DIR/clip-tweet-output.log"

  echo ""
  echo "=== /clip-tweet execution complete ==="

  check_real_repo_contamination "$REPO_REAL_DIR" "$VAULT_DIR"
fi

# --- Layer 1 Assertions ---
echo ""
echo "==========================================="
echo "  Layer 1: Structural Validation"
echo "==========================================="
echo ""

# 1. Inbox immutability (excluding tweets/) (INV-01)
echo "=== INV-01: Inbox immutability (non-tweet) ==="
bash "$ASSERTIONS_DIR/check-no-mutation.sh" "$HASH_FILE" || true
echo ""

# 2. Tweet file creation (FC-01)
echo "=== FC-01: Tweet file creation ==="
TWEET_FILE=""
for f in inbox/tweets/*.md; do
  [[ -f "$f" ]] || continue
  fname=$(basename "$f")
  if [[ -f "$f" ]]; then
    TWEET_FILE="$f"
    echo "  Found: $fname"
    break
  fi
done

if [[ -z "$TWEET_FILE" ]]; then
  assert_true "false" "FC-01: Tweet file created in inbox/tweets/"
else
  assert_true "true" "FC-01: Tweet file created"

  # FC-02: source-type
  TW_TYPE=$(fm_get "$TWEET_FILE" "source-type")
  assert_eq "$TW_TYPE" "tweet" "FC-02: source-type is 'tweet'"

  # FC-03: url and tweet-id
  TW_URL=$(fm_get "$TWEET_FILE" "url")
  assert_true "[[ -n '$TW_URL' ]]" "FC-03: has url"

  TW_TID=$(fm_get "$TWEET_FILE" "tweet-id")
  assert_true "[[ -n '$TW_TID' ]]" "FC-03: has tweet-id"

  # INV-04: created field exists (rill mkfile)
  TW_CREATED=$(fm_get "$TWEET_FILE" "created")
  assert_true "[[ -n '$TW_CREATED' ]]" "INV-04: has created (rill mkfile)"
fi
echo ""

# 3. Organized version creation (OR-01)
echo "=== OR-01: Organized version ==="
ORG_FILE=""
for f in inbox/tweets/_organized/*.md; do
  [[ -f "$f" ]] || continue
  ORG_FILE="$f"
  echo "  Found: $(basename $f)"
  break
done

if [[ -z "$ORG_FILE" ]]; then
  echo "  INFO: No _organized file (fetch-tweet.sh may have failed)"
  echo "  Skipping OR-* assertions (network/API dependent)"
else
  assert_true "true" "OR-01: _organized version exists"

  # OR-02: tweet metadata in frontmatter
  ORG_AUTHOR=$(fm_get "$ORG_FILE" "tweet-author")
  assert_true "[[ -n '$ORG_AUTHOR' ]]" "OR-02: has tweet-author"

  ORG_DATE=$(fm_get "$ORG_FILE" "tweet-date")
  assert_true "[[ -n '$ORG_DATE' ]]" "OR-02: has tweet-date"

  # OR-04: original-file points to original
  ORG_ORIG=$(fm_get "$ORG_FILE" "original-file")
  HAS_ORIG=$(echo "$ORG_ORIG" | grep -c 'inbox/tweets/' 2>/dev/null || true)
  HAS_ORIG=$(echo "${HAS_ORIG:-0}" | tail -1 | tr -d '[:space:]')
  assert_gt "$HAS_ORIG" 0 "OR-04: original-file references inbox/tweets/"

  # OR-03: tags exist in taxonomy (if tags present)
  ORG_TAGS=$(fm_get "$ORG_FILE" "tags" 2>/dev/null || true)
  if [[ -n "$ORG_TAGS" && "$ORG_TAGS" != "[]" ]]; then
    bash "$ASSERTIONS_DIR/check-taxonomy.sh" "$ORG_FILE" taxonomy.md || true
  else
    echo "  INFO: No tags field in organized file (skipping taxonomy check)"
  fi
fi
echo ""

# 4. .processed update (PR-01)
echo "=== PR-01: .processed ==="
if [[ -f "inbox/tweets/.processed" ]]; then
  HAS_ORG_STATUS=$({ grep -c ':organized' inbox/tweets/.processed 2>/dev/null || echo "0"; } | tr -d '[:space:]')
  if (( HAS_ORG_STATUS > 0 )); then
    assert_true "true" "PR-01: .processed has organized entries"
  else
    echo "  INFO: .processed exists but no :organized entry"
  fi
else
  echo "  INFO: .processed not created (fetch-tweet may have failed)"
fi
echo ""

# 5. Existing file immutability
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
if [[ -n "$TWEET_FILE" ]]; then echo "  Tweet file: $(basename $TWEET_FILE)"; fi
if [[ -n "$ORG_FILE" ]]; then echo "  Organized: $(basename $ORG_FILE)"; fi
echo ""

cat > "$RESULTS_DIR/summary.json" <<EOF
{
  "timestamp": "$TIMESTAMP",
  "vault": "$VAULT_DIR",
  "skill": "clip-tweet",
  "tweet_file_created": $([ -n "$TWEET_FILE" ] && echo true || echo false),
  "organized_created": $([ -n "$ORG_FILE" ] && echo true || echo false),
  "pass": $_PASS,
  "fail": $_FAIL,
  "total": $_TOTAL
}
EOF

report_results || true

echo ""
echo "Vault preserved at: $VAULT_DIR"
echo "To re-run assertions: bash $0 --skip-execute --vault=$VAULT_DIR"
