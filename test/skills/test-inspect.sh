#!/bin/bash
# test/skills/test-inspect.sh — /inspect integration test
#
# Usage: bash test/skills/test-inspect.sh [--skip-execute] [--vault=PATH]
#
# Verifies that /inspect detects taxonomy / metadata issues and appends
# affected files to knowledge/.refresh-queue. /inspect is read-only on file
# bodies; it only updates .refresh-queue and emits a diagnostic report.

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
  # Mirror the deploy layout: source skills/*/SKILL.md ships to the vault
  # as .claude/skills/*/SKILL.md (canonical skill form; see bin/rill cmd_update).
  mkdir -p "$VAULT_DIR/.claude/skills"
  cp -r "$REPO_DIR/skills/"* "$VAULT_DIR/.claude/skills/"
  cp -r "$REPO_DIR/bin" "$VAULT_DIR/bin"
  [[ -d "$REPO_DIR/plugins" ]] && cp -r "$REPO_DIR/plugins" "$VAULT_DIR/plugins"
  [[ -f "$REPO_DIR/taxonomy.md" ]] && cp "$REPO_DIR/taxonomy.md" "$VAULT_DIR/taxonomy.md"
  [[ -f "$REPO_DIR/CLAUDE.md" ]] && cp "$REPO_DIR/CLAUDE.md" "$VAULT_DIR/CLAUDE.md"
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

# --- Snapshot inbox + knowledge hashes for mutation check (INV-01) ---
HASH_FILE="$RESULTS_DIR/inbox-hashes.txt"
{
  find inbox/ -type f -name "*.md" 2>/dev/null
  find knowledge/notes -type f -name "*.md" 2>/dev/null
} | sort | while read -r f; do
  echo "$(file_hash "$f") $f"
done > "$HASH_FILE"

# --- Execute /inspect ---
if ! $SKIP_EXECUTE; then
  echo ""
  echo "=== Executing /inspect ==="
  echo "  (this may take 1-3 minutes)"
  echo ""

  isolate_test_vault "$VAULT_DIR"

  claude -p "/inspect" \
    --output-format text \
    --max-turns 80 \
    2>&1 | tee "$RESULTS_DIR/inspect-output.log"

  check_real_repo_contamination "$REPO_REAL_DIR" "$VAULT_DIR"

  echo ""
  echo "=== /inspect execution complete ==="
fi

# --- Layer 1 Assertions ---
echo ""
echo "==========================================="
echo "  Layer 1: Structural Validation"
echo "==========================================="
echo ""

# 1. Inbox + knowledge/notes immutability (INV-01)
echo "=== INV-01: Inbox + knowledge/notes immutability (/inspect must not edit bodies) ==="
bash "$ASSERTIONS_DIR/check-no-mutation.sh" "$HASH_FILE" || true
echo ""

# 2. .refresh-queue: file created and contains paths
echo "=== RQ-01: .refresh-queue exists or inspect reported clean ==="
REFRESH_QUEUE="knowledge/.refresh-queue"
if [[ -f "$REFRESH_QUEUE" ]]; then
  QUEUE_LINES=$({ wc -l < "$REFRESH_QUEUE" 2>/dev/null || echo 0; } | tr -d '[:space:]')
  echo "  .refresh-queue exists with $QUEUE_LINES line(s)"
  if (( QUEUE_LINES > 0 )); then
    # Validate each queued path exists and is under knowledge/notes/
    while read -r path; do
      [[ -z "$path" ]] && continue
      if [[ "$path" =~ ^knowledge/notes/.+\.md$ ]]; then
        assert_true "[[ -f '$path' ]]" "RQ-02: queued path exists: $path"
      else
        echo "  FAIL: RQ-02: queued path not under knowledge/notes/: $path"
        _FAIL=$((_FAIL + 1))
        _TOTAL=$((_TOTAL + 1))
      fi
    done < "$REFRESH_QUEUE"
  fi
else
  echo "  INFO: .refresh-queue not produced. Acceptable when inspect found nothing to repair"
fi
echo ""

# 3. Diagnostic report content checks (PH: phases echoed in output)
echo "=== PH: Phase markers in inspect output ==="
OUTPUT_LOG="$RESULTS_DIR/inspect-output.log"
if [[ -f "$OUTPUT_LOG" ]]; then
  HAS_TAXONOMY=$({ grep -ci 'taxonomy\|Topic Tags\|Deprecated Tags' "$OUTPUT_LOG" 2>/dev/null || echo "0"; } | tr -d '[:space:]')
  assert_gt "$HAS_TAXONOMY" 0 "PH-01: output mentions taxonomy"

  HAS_METADATA=$({ grep -ci 'metadata\|sampling\|frontmatter' "$OUTPUT_LOG" 2>/dev/null || echo "0"; } | tr -d '[:space:]')
  assert_gt "$HAS_METADATA" 0 "PH-02: output mentions metadata/sampling"
fi
echo ""

# --- Summary ---
echo ""
echo "==========================================="
echo "  Test Summary"
echo "==========================================="
echo "  Vault: $VAULT_DIR"
echo "  Results: $RESULTS_DIR"
[[ -f "$REFRESH_QUEUE" ]] && echo "  Queue file: $REFRESH_QUEUE ($QUEUE_LINES line(s))"
echo ""

report_results "$VAULT_DIR" "$RESULTS_DIR"
