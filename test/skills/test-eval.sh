#!/bin/bash
# test/skills/test-eval.sh — /eval integration test (smoke, single-query)
#
# Usage: bash test/skills/test-eval.sh [--skip-execute] [--vault=PATH]
#
# Smoke test for /eval: runs against a minimal one-query eval/queries.yaml so
# the Deep Path agent fan-out is bounded. Asserts that eval/results/*-deep.yaml
# is produced and contains expected fields. Full 20-query benchmarks live in
# the real vault, not here.

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

  # Provide a minimal eval/queries.yaml in the real /eval format
  # (top-level sequence; entries with id/query/type/scope).
  # 7 queries span the 4 supported types (factual / synthesis / entity / exploratory)
  # to satisfy Phase 2 stratified sampling; agent fan-out is still bounded.
  mkdir -p eval
  cat > eval/queries.yaml <<'EOF'
# Minimal smoke fixture for /eval integration test.
# Real vaults have ~20 queries; this minimal set keeps agent fan-out bounded
# while still meeting Phase 2 stratified-sampling type coverage.
- id: SQ1
  query: "Which OAuth provider was selected for sample-project?"
  type: factual
  scope: narrow
- id: SQ2
  query: "What concerns does Alex Chen have about onboarding?"
  type: entity
  scope: narrow
- id: SQ3
  query: "What is the silent refresh strategy decision?"
  type: factual
  scope: narrow
- id: SQ4
  query: "How do Auth0, Clerk, and Supabase compare for B2B usage?"
  type: synthesis
  scope: medium
- id: SQ5
  query: "What follow-up tasks remain on the OAuth migration?"
  type: synthesis
  scope: medium
- id: SQ6
  query: "What are emerging risks for the auth migration?"
  type: exploratory
  scope: medium
- id: SQ7
  query: "What patterns exist across recent provider-decision notes?"
  type: exploratory
  scope: medium
EOF
  if [[ -f "$REPO_DIR/eval/concept.md" ]]; then
    cp "$REPO_DIR/eval/concept.md" eval/concept.md
  fi

  git init -q
  git add -A
  git commit -q -m "initial test fixtures (minimal eval queries)"
else
  echo "=== Using existing vault: $VAULT_DIR ==="
  cd "$VAULT_DIR"
fi

TIMESTAMP=$(date +%Y%m%d-%H%M%S)
RESULTS_DIR="$TEST_DIR/results/$TIMESTAMP"
mkdir -p "$RESULTS_DIR"

# --- Snapshot inbox + knowledge/notes hashes (INV-01) ---
HASH_FILE="$RESULTS_DIR/inbox-hashes.txt"
{
  find inbox/ -type f -name "*.md" 2>/dev/null
  find knowledge/notes -type f -name "*.md" 2>/dev/null
} | sort | while read -r f; do
  echo "$(file_hash "$f") $f"
done > "$HASH_FILE"

# --- Execute /eval ---
if ! $SKIP_EXECUTE; then
  echo ""
  echo "=== Executing /eval --refresh-deep (single-query smoke) ==="
  echo "  (this may take 2-5 minutes)"
  echo ""

  isolate_test_vault "$VAULT_DIR"

  claude -p "/eval --refresh-deep" \
    --output-format text \
    --max-turns 100 \
    2>&1 | tee "$RESULTS_DIR/eval-output.log"

  check_real_repo_contamination "$REPO_REAL_DIR" "$VAULT_DIR"

  echo ""
  echo "=== /eval execution complete ==="
fi

# --- Layer 1 Assertions ---
echo ""
echo "==========================================="
echo "  Layer 1: Structural Validation"
echo "==========================================="
echo ""

# 1. Inbox + knowledge/notes immutability — /eval is read-only on note bodies
echo "=== INV-01: Inbox + knowledge/notes immutability (/eval is read-only) ==="
bash "$ASSERTIONS_DIR/check-no-mutation.sh" "$HASH_FILE" || true
echo ""

# 2. Deep Path result file emitted
echo "=== EV-01: Deep Path result file emitted ==="
DEEP_FILES=( eval/results/*-deep.yaml )
if [[ -f "${DEEP_FILES[0]}" ]]; then
  echo "  Found: ${DEEP_FILES[0]}"
  assert_true "[[ -s '${DEEP_FILES[0]}' ]]" "EV-01: deep yaml is non-empty"
else
  echo "  FAIL: EV-01: no eval/results/*-deep.yaml produced"
  _FAIL=$((_FAIL + 1))
  _TOTAL=$((_TOTAL + 1))
fi
echo ""

# 3. Metrics file (eval/results/{date}.yaml) emitted
echo "=== EV-02: Metrics result file emitted ==="
METRIC_FILES=( eval/results/*.yaml )
HAS_METRIC=0
for f in "${METRIC_FILES[@]}"; do
  case "$f" in
    *-deep.yaml) ;;
    *) [[ -f "$f" ]] && HAS_METRIC=1 ;;
  esac
done
if (( HAS_METRIC == 1 )); then
  _PASS=$((_PASS + 1))
  _TOTAL=$((_TOTAL + 1))
  echo "  PASS: EV-02: metrics yaml present"
else
  echo "  INFO: EV-02: no plain metrics yaml — acceptable when Deep Path only"
fi
echo ""

# --- Summary ---
echo ""
echo "==========================================="
echo "  Test Summary"
echo "==========================================="
echo "  Vault: $VAULT_DIR"
echo "  Results: $RESULTS_DIR"
echo "  NOTE: Smoke test with 1-query fixture. Full 20-query benchmark is out of scope"
echo ""

report_results "$VAULT_DIR" "$RESULTS_DIR"
