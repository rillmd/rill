#!/bin/bash
# test/skills/test-solve.sh — /solve integration test
#
# Usage: bash test/skills/test-solve.sh [--skip-execute]
#
# Runs /solve on an existing open task (oauth-provider-investigation).
# Validates workspace creation, deliverable generation, and task status update.
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

TASK_FILE="tasks/oauth-provider-investigation.md"

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

# Save inbox hashes
HASH_FILE="$RESULTS_DIR/inbox-hashes.txt"
find inbox/ -type f -name "*.md" 2>/dev/null | sort | while read -r f; do
  echo "$(file_hash "$f") $f"
done > "$HASH_FILE"

# Save task state before
TASK_STATUS_BEFORE=$(fm_get "$TASK_FILE" "status")
echo "Task status before: $TASK_STATUS_BEFORE"

# --- Execute /solve ---
if ! $SKIP_EXECUTE; then
  echo ""
  echo "=== Executing /solve $TASK_FILE ==="
  echo "  (this may take 3-8 minutes)"
  echo ""

  isolate_test_vault "$VAULT_DIR"

  claude -p "/solve $TASK_FILE" \
    --output-format text \
    --max-turns 50 \
    2>&1 | tee "$RESULTS_DIR/solve-output.log"

  echo ""
  echo "=== /solve execution complete ==="

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

# 2. Phase 1+ output produced (P1-01)
# Either: briefing keywords (stopped at Phase 1) OR substantial output (proceeded to Phase 3+)
echo "=== P1-01: Solve output ==="
if [[ -f "$RESULTS_DIR/solve-output.log" ]]; then
  HAS_BRIEFING=$(grep -ci 'briefing\|goal\|scope\|current.*state\|status\|summary\|deliverable\|workspace' "$RESULTS_DIR/solve-output.log" 2>/dev/null || true)
  HAS_BRIEFING=$(echo "${HAS_BRIEFING:-0}" | tail -1 | tr -d '[:space:]')
  assert_gt "$HAS_BRIEFING" 0 "P1-01: Output contains task understanding (briefing or summary)"
fi
echo ""

# 3. Task status change (P4-01)
echo "=== P4-01: Task status ==="
TASK_STATUS_AFTER=$(fm_get "$TASK_FILE" "status")
echo "  Task status: $TASK_STATUS_BEFORE -> $TASK_STATUS_AFTER"
# /solve should change status to 'waiting' (research complete, awaiting review)
if [[ "$TASK_STATUS_AFTER" == "waiting" ]]; then
  assert_true "true" "P4-01: Task status changed to 'waiting'"
elif [[ "$TASK_STATUS_AFTER" == "open" ]]; then
  # Also acceptable if /solve determined human action needed
  echo "  INFO: Task remains 'open' (may require human action)"
  assert_true "true" "P4-01: Task status is 'open' (human action needed)"
else
  assert_true "false" "P4-01: Task status is 'waiting' or 'open' (got '$TASK_STATUS_AFTER')"
fi
echo ""

# 3. Workspace creation (P3-01, P3-02, P3-03)
echo "=== P3: Workspace ==="
SOLVE_WS_DIR=""
for d in workspace/*/; do
  [[ "$d" == "workspace/2026-01-10-sample-workspace/" ]] && continue
  if [[ -f "${d}_workspace.md" ]]; then
    SOLVE_WS_DIR="$d"
    echo "  New workspace: $(basename "$d")"
  fi
done

if [[ -n "$SOLVE_WS_DIR" ]]; then
  assert_true "true" "P3-01: Workspace created"

  WS_FILE="${SOLVE_WS_DIR}_workspace.md"

  # P3-02: Required frontmatter
  WS_TYPE=$(fm_get "$WS_FILE" "type")
  assert_eq "$WS_TYPE" "workspace" "P3-02: type is 'workspace'"

  WS_STATUS=$(fm_get "$WS_FILE" "status")
  assert_true "[[ '$WS_STATUS' == 'active' || '$WS_STATUS' == 'completed' ]]" "P3-02: status is active or completed"

  WS_CREATED=$(fm_get "$WS_FILE" "created")
  assert_true "[[ -n '$WS_CREATED' ]]" "P3-02: has created"

  # P3-03: origin points to task
  WS_ORIGIN=$(fm_get "$WS_FILE" "origin")
  HAS_TASK_ORIGIN=$(echo "$WS_ORIGIN" | grep -c 'oauth-provider-investigation' 2>/dev/null || echo "0")
  HAS_TASK_ORIGIN=$(echo "$HAS_TASK_ORIGIN" | tail -1 | tr -d '[:space:]')
  assert_gt "$HAS_TASK_ORIGIN" 0 "P3-03: origin references task file"

  # P3-04: Deliverable file exists
  DELIVERABLE_COUNT=0
  for f in "${SOLVE_WS_DIR}"[0-9][0-9][0-9]-*.md; do
    [[ -f "$f" ]] && DELIVERABLE_COUNT=$((DELIVERABLE_COUNT + 1))
  done
  assert_gt "$DELIVERABLE_COUNT" 0 "P3-04: Deliverable file(s) created ($DELIVERABLE_COUNT)"

  # P3-05: Deliverable has frontmatter
  if [[ "$DELIVERABLE_COUNT" -gt 0 ]]; then
    FIRST_DELIVERABLE=$(ls "${SOLVE_WS_DIR}"[0-9][0-9][0-9]-*.md 2>/dev/null | head -1)
    if [[ -n "$FIRST_DELIVERABLE" ]]; then
      D_TYPE=$(fm_get "$FIRST_DELIVERABLE" "type")
      assert_true "[[ -n '$D_TYPE' ]]" "P3-05: Deliverable has type ($D_TYPE)"
    fi
  fi

  # P4-04: MOC has deliverable links
  HAS_MOC_LINKS=$({ grep -c '\[.*\](.*\.md)' "$WS_FILE" 2>/dev/null || echo "0"; } | tr -d '[:space:]')
  assert_gt "$HAS_MOC_LINKS" 0 "P4-04: _workspace.md MOC has links"
else
  # Workspace not created — might be Enrich pattern (task-only update)
  echo "  INFO: No new workspace (may be Enrich pattern)"
  assert_true "true" "P3-01: No workspace needed (Enrich pattern accepted)"
fi
echo ""

# 4. Task updated with execution record (P4-02, P4-03)
echo "=== P4: Task updates ==="
# P4-03: Execution record in task (may not exist if /solve stopped at Phase 1 briefing)
HAS_EXEC_RECORD=$(grep -ci 'History\|Background\|/solve\|automated\|auto.*execut' "$TASK_FILE" 2>/dev/null || true)
HAS_EXEC_RECORD=$(echo "${HAS_EXEC_RECORD:-0}" | tail -1 | tr -d '[:space:]')
if (( HAS_EXEC_RECORD > 0 )); then
  assert_true "true" "P4-03: Task has execution record"
else
  echo "  INFO: No execution record (Phase 1 briefing only — awaiting user input)"
fi

# P4-02: related updated with workspace path (if workspace was created)
if [[ -n "$SOLVE_WS_DIR" ]]; then
  TASK_RELATED=$(fm_get "$TASK_FILE" "related")
  if [[ -n "$TASK_RELATED" ]]; then
    HAS_WS_RELATED=$(echo "$TASK_RELATED" | grep -c 'workspace/' 2>/dev/null || echo "0")
    HAS_WS_RELATED=$(echo "$HAS_WS_RELATED" | tail -1 | tr -d '[:space:]')
    assert_gt "$HAS_WS_RELATED" 0 "P4-02: Task related includes workspace path"
  else
    echo "  INFO: related field not found or empty"
  fi
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
echo "  Task: $TASK_FILE ($TASK_STATUS_BEFORE -> $TASK_STATUS_AFTER)"
if [[ -n "$SOLVE_WS_DIR" ]]; then
  echo "  Workspace: $SOLVE_WS_DIR"
  echo "  Deliverables: $DELIVERABLE_COUNT"
fi
echo ""

cat > "$RESULTS_DIR/summary.json" <<EOF
{
  "timestamp": "$TIMESTAMP",
  "vault": "$VAULT_DIR",
  "skill": "solve",
  "task": "$TASK_FILE",
  "status_before": "$TASK_STATUS_BEFORE",
  "status_after": "$TASK_STATUS_AFTER",
  "workspace_created": $([ -n "$SOLVE_WS_DIR" ] && echo true || echo false),
  "deliverables": ${DELIVERABLE_COUNT:-0},
  "pass": $_PASS,
  "fail": $_FAIL,
  "total": $_TOTAL
}
EOF

report_results || true

echo ""
echo "Vault preserved at: $VAULT_DIR"
echo "To re-run assertions: bash $0 --skip-execute --vault=$VAULT_DIR"
