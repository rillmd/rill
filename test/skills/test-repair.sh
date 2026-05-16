#!/bin/bash
# test/skills/test-repair.sh — /repair integration test (smoke)
#
# Usage: bash test/skills/test-repair.sh [--skip-execute] [--vault=PATH]
#
# Smoke test: runs /repair against an empty .refresh-queue and verifies the
# skill exits cleanly with the "Queue is empty" path. A richer test that
# pre-populates the queue and verifies frontmatter repairs requires additional
# fixture preparation and is left as future work.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TEST_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ASSERTIONS_DIR="$TEST_DIR/assertions"
FIXTURES_DIR="$TEST_DIR/fixtures"
REPO_REAL_DIR="$(cd "$TEST_DIR/.." && pwd)"

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
  [[ -f "$REPO_DIR/taxonomy.md" ]] && cp "$REPO_DIR/taxonomy.md" "$VAULT_DIR/taxonomy.md"
  [[ -f "$REPO_DIR/CLAUDE.md" ]] && cp "$REPO_DIR/CLAUDE.md" "$VAULT_DIR/CLAUDE.md"
  [[ -f "$REPO_DIR/SPEC.md" ]] && cp "$REPO_DIR/SPEC.md" "$VAULT_DIR/SPEC.md"
  cd "$VAULT_DIR"

  # Ensure an empty .refresh-queue exists so /repair has a defined input state
  mkdir -p knowledge
  : > knowledge/.refresh-queue

  git init -q
  git add -A
  git commit -q -m "initial test fixtures (empty refresh-queue)"
else
  echo "=== Using existing vault: $VAULT_DIR ==="
  cd "$VAULT_DIR"
fi

TIMESTAMP=$(date +%Y%m%d-%H%M%S)
RESULTS_DIR="$TEST_DIR/results/$TIMESTAMP"
mkdir -p "$RESULTS_DIR"

# --- Snapshot inbox + knowledge/notes hashes (INV-01 immutability check) ---
HASH_FILE="$RESULTS_DIR/inbox-hashes.txt"
{
  find inbox/ -type f -name "*.md" 2>/dev/null
  find knowledge/notes -type f -name "*.md" 2>/dev/null
} | sort | while read -r f; do
  echo "$(file_hash "$f") $f"
done > "$HASH_FILE"

# --- Execute /repair ---
if ! $SKIP_EXECUTE; then
  echo ""
  echo "=== Executing /repair (empty queue smoke) ==="
  echo "  (this may take 1-2 minutes)"
  echo ""

  isolate_test_vault "$VAULT_DIR"

  claude -p "/repair" \
    --output-format text \
    --max-turns 40 \
    2>&1 | tee "$RESULTS_DIR/repair-output.log"

  check_real_repo_contamination "$REPO_REAL_DIR" "$VAULT_DIR"

  echo ""
  echo "=== /repair execution complete ==="
fi

# --- Layer 1 Assertions ---
echo ""
echo "==========================================="
echo "  Layer 1: Structural Validation"
echo "==========================================="
echo ""

# 1. Inbox + knowledge/notes immutability for empty-queue run
echo "=== INV-01: Inbox + knowledge/notes immutable on empty queue ==="
bash "$ASSERTIONS_DIR/check-no-mutation.sh" "$HASH_FILE" || true
echo ""

# 2. Empty queue path emits the documented message
echo "=== EQ: Empty-queue exit message ==="
OUTPUT_LOG="$RESULTS_DIR/repair-output.log"
if [[ -f "$OUTPUT_LOG" ]]; then
  EMPTY_HIT=$({ grep -ci 'queue is empty\|empty.*queue\|no entries' "$OUTPUT_LOG" 2>/dev/null || echo "0"; } | tr -d '[:space:]')
  assert_gt "$EMPTY_HIT" 0 "EQ-01: output mentions empty queue / no entries"
fi
echo ""

# --- Summary ---
echo ""
echo "==========================================="
echo "  Test Summary"
echo "==========================================="
echo "  Vault: $VAULT_DIR"
echo "  Results: $RESULTS_DIR"
echo "  NOTE: This is a smoke test. Populated-queue repair behavior is not asserted here"
echo ""

report_results "$VAULT_DIR" "$RESULTS_DIR"
