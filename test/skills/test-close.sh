#!/bin/bash
# test/skills/test-close.sh — /close integration test
#
# Usage: bash test/skills/test-close.sh [--skip-execute]
#
# Copies fixtures to a temp vault, runs /close on the sample workspace,
# then validates outputs with Layer 1 assertions.
#
# --skip-execute: Skip the claude -p execution and only run assertions
#                 on an existing vault

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TEST_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ASSERTIONS_DIR="$TEST_DIR/assertions"
FIXTURES_DIR="$TEST_DIR/fixtures"
# Resolve the real repo path NOW, before we cd into the test vault below.
# Used later for contamination checks; must be absolute so it survives the cd.
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

WS_ID="2026-01-10-sample-workspace"
WS_DIR="workspace/$WS_ID"

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
  # Overlay system files from repo
  cp "$REPO_DIR/taxonomy.md" "$VAULT_DIR/taxonomy.md"
  cp "$REPO_DIR/CLAUDE.md" "$VAULT_DIR/CLAUDE.md"
  [[ -f "$REPO_DIR/SPEC.md" ]] && cp "$REPO_DIR/SPEC.md" "$VAULT_DIR/SPEC.md"
  # Initialize git
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

# --- Save pre-execution state ---
# Inbox hashes for mutation check
HASH_FILE="$RESULTS_DIR/inbox-hashes.txt"
find inbox/ -type f -name "*.md" 2>/dev/null | sort | while read -r f; do
  echo "$(file_hash "$f") $f"
done > "$HASH_FILE"

# Save workspace state before close
WS_STATUS_BEFORE=$(fm_get "$WS_DIR/_workspace.md" "status")
echo "Workspace status before: $WS_STATUS_BEFORE"

# --- Execute /close ---
if ! $SKIP_EXECUTE; then
  echo ""
  echo "=== Executing /close $WS_DIR ==="
  echo "  (this may take 2-5 minutes)"
  echo ""

  # Isolate rill resolution to the test vault (see lib.sh for details)
  isolate_test_vault "$VAULT_DIR"

  claude -p "/close $WS_DIR --auto-approve" \
    --output-format text \
    --max-turns 120 \
    2>&1 | tee "$RESULTS_DIR/close-output.log"

  echo ""
  echo "=== /close execution complete ==="

  # Verify no fixture files leaked into the real repo
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

# 2. _summary.md existence and frontmatter (INV-02)
echo "=== INV-02: _summary.md ==="
SUMMARY_FILE="$WS_DIR/_summary.md"
assert_file_exists "$SUMMARY_FILE" "INV-02: _summary.md exists"
if [[ -f "$SUMMARY_FILE" ]]; then
  SUMMARY_TYPE=$(fm_get "$SUMMARY_FILE" "type")
  assert_eq "$SUMMARY_TYPE" "summary" "INV-02: _summary.md type is 'summary'"

  SUMMARY_CREATED=$(fm_get "$SUMMARY_FILE" "created")
  assert_true "[[ -n '$SUMMARY_CREATED' ]]" "INV-02: _summary.md has created field"
fi
echo ""

# 3. Workspace status -> completed (INV-03)
echo "=== INV-03: Workspace status ==="
WS_STATUS_AFTER=$(fm_get "$WS_DIR/_workspace.md" "status")
assert_eq "$WS_STATUS_AFTER" "completed" "INV-03: _workspace.md status is 'completed'"
echo ""

# 4. _summary.md section structure (SM-01 to SM-05)
echo "=== SM: Summary sections ==="
if [[ -f "$SUMMARY_FILE" ]]; then
  # SM-01: Title with Summary
  TITLE_LINE=$(grep '^# ' "$SUMMARY_FILE" | head -1)
  assert_true "[[ -n '$TITLE_LINE' ]]" "SM-01: _summary.md has H1 title"

  # SM-02: Overview section
  HAS_OVERVIEW=$(grep -ci '^## .*Overview\|^## .*Summary' "$SUMMARY_FILE" 2>/dev/null || echo "0")
  assert_gt "$HAS_OVERVIEW" 0 "SM-02: Has overview section"

  # SM-03: Deliverables/Artifacts section
  HAS_DELIVERABLES=$(grep -ci '^## .*Deliverables\|^## .*Artifacts' "$SUMMARY_FILE" 2>/dev/null || echo "0")
  assert_gt "$HAS_DELIVERABLES" 0 "SM-03: Has deliverables section"

  # SM-04: Decisions section
  HAS_DECISIONS=$(grep -ci '^## .*Decisions\|^## .*Decision' "$SUMMARY_FILE" 2>/dev/null || echo "0")
  assert_gt "$HAS_DECISIONS" 0 "SM-04: Has decisions section"

  # SM-05: Invalidated Approaches section (required by ADR-073)
  HAS_INVALIDATED=$(grep -ci '^## Invalidated Approaches' "$SUMMARY_FILE" 2>/dev/null || echo "0")
  assert_gt "$HAS_INVALIDATED" 0 "SM-05: Has Invalidated Approaches section (ADR-073)"

  # SM-06: Open issues section
  HAS_OPEN_ISSUES=$(grep -ci '^## .*Open Issues\|^## .*Unresolved' "$SUMMARY_FILE" 2>/dev/null || echo "0")
  assert_gt "$HAS_OPEN_ISSUES" 0 "SM-06: Has open issues section"

  # SM-07: All deliverables referenced in summary
  for deliverable in "$WS_DIR"/[0-9][0-9][0-9]-*.md; do
    [[ -f "$deliverable" ]] || continue
    dname=$(basename "$deliverable")
    MENTIONED=$(grep -c "$dname" "$SUMMARY_FILE" 2>/dev/null || echo "0")
    assert_gt "$MENTIONED" 0 "SM-07: Summary references deliverable $dname"
  done

  # SM-04: Decisions use structured D-{ws-short}-{n} format with "Adopted from"
  DECISIONS_COUNT=$(grep -c '^### D-' "$SUMMARY_FILE" 2>/dev/null || echo "0")
  if [[ "$DECISIONS_COUNT" -gt 0 ]]; then
    ADOPTED_FROM_COUNT=$(grep -ci '^- \*\*Adopted from\*\*\|^- \*\*Source\*\*' "$SUMMARY_FILE" 2>/dev/null || echo "0")
    assert_gt "$ADOPTED_FROM_COUNT" 0 "SM-04: Structured decisions use 'Adopted from' field"
  else
    echo "  (info) No structured D-{id}-{n} decisions found — may indicate old /close format or small workspace"
  fi
fi
echo ""

# 5. Knowledge notes created from distillation (INV-04 via distill IAD rules)
echo "=== KD: Knowledge distillation ==="
NEW_NOTES_COUNT=0
for f in knowledge/notes/*.md; do
  [[ -f "$f" ]] || continue
  name=$(basename "$f")
  if [[ ! -f "$FIXTURES_DIR/knowledge/notes/$name" ]]; then
    NEW_NOTES_COUNT=$((NEW_NOTES_COUNT + 1))
    echo "  New note: $name"

    # Reuse distill assertion checks on each new note
    bash "$ASSERTIONS_DIR/check-frontmatter.sh" "$f" --required "created,type,source" || true
    bash "$ASSERTIONS_DIR/check-taxonomy.sh" "$f" taxonomy.md || true
    bash "$ASSERTIONS_DIR/check-mentions.sh" "$f" || true
    bash "$ASSERTIONS_DIR/check-file-naming.sh" "$f" || true

    # KD-05: source points to workspace deliverable
    NOTE_SOURCE=$(fm_get "$f" "source")
    if [[ -n "$NOTE_SOURCE" ]]; then
      HAS_WS_SOURCE=$(echo "$NOTE_SOURCE" | grep -c "workspace/$WS_ID/" 2>/dev/null || echo "0")
      assert_gt "$HAS_WS_SOURCE" 0 "KD-05: Note $name source points to workspace deliverable"
    fi
    echo ""
  fi
done
echo "  Total new notes: $NEW_NOTES_COUNT"
echo ""

# 6. Deliverable frontmatter completion (PL-03)
echo "=== PL-03: Deliverable frontmatter ==="
for deliverable in "$WS_DIR"/[0-9][0-9][0-9]-*.md; do
  [[ -f "$deliverable" ]] || continue
  dname=$(basename "$deliverable")
  D_TAGS=$(fm_get "$deliverable" "tags")
  if [[ -n "$D_TAGS" && "$D_TAGS" != "[]" ]]; then
    assert_true "true" "PL-03: $dname has tags"
  else
    assert_true "false" "PL-03: $dname has tags"
  fi
  D_MENTIONS=$(fm_get "$deliverable" "mentions")
  if [[ -n "$D_MENTIONS" ]]; then
    assert_true "true" "PL-03: $dname has mentions"
  else
    assert_true "false" "PL-03: $dname has mentions"
  fi
done
echo ""

# 7. .processed file (PL-04)
echo "=== PL-04: .processed ==="
PROCESSED_FILE="$WS_DIR/.processed"
if [[ -f "$PROCESSED_FILE" ]]; then
  assert_file_contains "$PROCESSED_FILE" "001-oauth-provider-comparison.md" ".processed has deliverable 1"
  assert_file_contains "$PROCESSED_FILE" "002-token-refresh-strategy.md" ".processed has deliverable 2"
else
  assert_true "false" "PL-04: .processed file exists"
fi
echo ""

# 7. Task extraction from unchecked items (TK-02, TK-03)
echo "=== TK: Task extraction ==="
NEW_TASKS=0
for f in tasks/*/_task.md; do
  [[ -f "$f" ]] || continue
  name=$(basename "$(dirname "$f")")
  if [[ ! -f "$FIXTURES_DIR/tasks/$name/_task.md" ]]; then
    NEW_TASKS=$((NEW_TASKS + 1))
    echo "  New task: $name"
    TASK_STATUS=$(fm_get "$f" "status")
    assert_eq "$TASK_STATUS" "draft" "TK-03: Task $name has status: draft"
  fi
done
echo "  Total new tasks: $NEW_TASKS"
# TK-02: The unchecked item "migration schedule" should trigger task extraction
# Note: This may or may not produce a task (depends on LLM judgment), so we don't assert > 0
echo ""

# 8. Key fact preservation (KF)
echo "=== KF: Key fact preservation ==="
bash "$ASSERTIONS_DIR/check-keyfacts.sh" "." "$FIXTURES_DIR" || true
echo ""

# 9. Existing file immutability
echo "=== INV: Existing file immutability ==="
for existing in knowledge/notes/saas-freemium-pricing-strategy.md knowledge/notes/oauth-provider-selection-criteria.md; do
  if [[ -f "$existing" && -f "$FIXTURES_DIR/$existing" ]]; then
    orig_created=$(fm_get "$FIXTURES_DIR/$existing" "created")
    curr_created=$(fm_get "$existing" "created")
    assert_eq "$curr_created" "$orig_created" "Existing created unchanged: $(basename $existing)"
  fi
done
echo ""

# ADR-073: Two-layer sub-agent procedure signals (from close-output.log)
# Helper: grep_count returns exactly one line with an integer, regardless of whether grep matched.
# Avoids the "0\n0" bug that comes from combining grep -c (which prints "0" + exits 1 on miss)
# with a `|| echo 0` fallback under `set -o pipefail`.
grep_count() {
  local pattern="$1" file="$2"
  if [[ ! -f "$file" ]]; then
    echo 0
    return
  fi
  local raw
  raw=$(grep -c -iE "$pattern" "$file" 2>/dev/null || true)
  # raw may be empty or a number. Strip whitespace and default to 0.
  raw=${raw//[[:space:]]/}
  echo "${raw:-0}"
}

echo "=== ADR-073: Two-layer sub-agent procedure ==="
LOG_FILE="$RESULTS_DIR/close-output.log"
if [[ -f "$LOG_FILE" ]]; then
  HAS_CANDIDATES=$(grep_count 'candidates_total|Distillation candidates|Candidates enumerated|L1-[0-9]|L2-[0-9]|candidate' "$LOG_FILE")
  assert_gt "$HAS_CANDIDATES" 0 "CL-07: Analysis sub-agent enumeration output appears in log"

  HAS_SELFCHECK=$(grep_count 'self-check|Atomic notes created|Uncovered|enumerated' "$LOG_FILE")
  assert_gt "$HAS_SELFCHECK" 0 "SC-04: Self-check block appears in completion report"

  HAS_VERIFY=$(grep_count 'Invalidated Approaches|cross-deliverable|IA-[0-9]' "$LOG_FILE")
  if [[ "$HAS_VERIFY" -gt 0 ]]; then
    assert_true "true" "CV: Cross-verify / Invalidated Approaches referenced in log"
  else
    echo "  (info) No Invalidated Approaches or cross-verify signal in log — may be normal for a clean workspace with no invalidated content"
  fi

  FORBIDDEN=$(grep_count 'pragmatic scope reduction|to save time|not novel enough|context budget running low' "$LOG_FILE")
  assert_eq "$FORBIDDEN" "0" "JL: No forbidden vague justifications in output (ADR-073)"

  UNCOVERED_NONZERO=$(grep_count 'Uncovered:[[:space:]]*[1-9]' "$LOG_FILE")
  assert_eq "$UNCOVERED_NONZERO" "0" "SC-02: Self-check reports uncovered == 0"
else
  echo "  (skipped: no close-output.log — likely --skip-execute mode)"
fi
echo ""

# 10. Related task sync check (TS-01)
echo "=== TS: Related task sync ==="
MIGRATION_TASK="tasks/plan-auth-migration-schedule/_task.md"
if [[ -f "$MIGRATION_TASK" ]]; then
  MIGRATION_STATUS=$(fm_get "$MIGRATION_TASK" "status")
  echo "  Migration task status: $MIGRATION_STATUS"
  # The task references this workspace and the workspace covers the topic
  # (Auth0 chosen, token refresh decided). LLM should judge it partially done.
  # We don't assert done/open since it depends on LLM judgment + auto-approval,
  # but we verify the task file wasn't corrupted
  MIGRATION_TYPE=$(fm_get "$MIGRATION_TASK" "type")
  assert_eq "$MIGRATION_TYPE" "task" "TS: Migration task type preserved"
fi
echo ""

# --- Summary ---
echo ""
echo "==========================================="
echo "  Test Summary"
echo "==========================================="
echo "  Vault: $VAULT_DIR"
echo "  Results: $RESULTS_DIR"
echo "  WS status: $WS_STATUS_BEFORE → $WS_STATUS_AFTER"
echo "  New knowledge notes: $NEW_NOTES_COUNT"
echo "  New tasks: $NEW_TASKS"
echo ""

# Save summary
cat > "$RESULTS_DIR/summary.json" <<EOF
{
  "timestamp": "$TIMESTAMP",
  "vault": "$VAULT_DIR",
  "skill": "close",
  "workspace": "$WS_ID",
  "ws_status_before": "$WS_STATUS_BEFORE",
  "ws_status_after": "$WS_STATUS_AFTER",
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
