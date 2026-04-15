#!/bin/bash
# test/skills/test-focus.sh — /focus integration test
#
# Usage: bash test/skills/test-focus.sh [--skip-execute] [--scenario=A|B|AB]
#
# Two scenarios:
#   A: New workspace from theme — tests Phase 0->1->2
#   B: Resume existing workspace — tests WS-01, context collection on resume
#
# Default: both scenarios (AB)
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
SCENARIO="AB"
for arg in "$@"; do
  case "$arg" in
    --skip-execute) SKIP_EXECUTE=true ;;
    --vault=*) VAULT_DIR="${arg#--vault=}" ;;
    --scenario=*) SCENARIO="${arg#--scenario=}" ;;
  esac
done

EXISTING_WS="workspace/2026-01-10-sample-workspace"

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

# --- Save inbox hashes ---
HASH_FILE="$RESULTS_DIR/inbox-hashes.txt"
find inbox/ -type f -name "*.md" 2>/dev/null | sort | while read -r f; do
  echo "$(file_hash "$f") $f"
done > "$HASH_FILE"

# Save existing workspace state for scenario B
if [[ -f "$EXISTING_WS/_workspace.md" ]]; then
  cp "$EXISTING_WS/_workspace.md" "$RESULTS_DIR/ws-before.md"
fi

# =============================================
# Scenario A: New workspace from theme
# =============================================
if [[ "$SCENARIO" == *A* ]]; then
  echo ""
  echo "==========================================="
  echo "  Scenario A: New workspace from theme"
  echo "==========================================="

  if ! $SKIP_EXECUTE; then
    # Temporarily hide existing active workspace so /focus creates a new one
    # (otherwise Phase 0 detects the existing WS and asks AskUserQuestion,
    #  which blocks in claude -p mode)
    if [[ -f "$EXISTING_WS/_workspace.md" ]]; then
      sed -i.bak 's/^status: active/status: completed/' "$EXISTING_WS/_workspace.md"
      git add -A && git commit -q -m "temp: hide active ws for scenario A"
    fi

    echo ""
    echo "=== Executing /focus Kubernetes cluster optimization ==="
    echo "  (this may take 1-3 minutes)"
    echo ""

    isolate_test_vault "$VAULT_DIR"

    # Use a theme unrelated to existing fixtures to avoid WS-06 search hit
    claude -p "/focus Kubernetes cluster optimization" \
      --output-format text \
      --max-turns 30 \
      2>&1 | tee "$RESULTS_DIR/focus-a-output.log"

    echo ""
    echo "=== Scenario A execution complete ==="

    check_real_repo_contamination "$REPO_REAL_DIR" "$VAULT_DIR"

    # Restore existing workspace for scenario B
    if [[ -f "$EXISTING_WS/_workspace.md.bak" ]]; then
      mv "$EXISTING_WS/_workspace.md.bak" "$EXISTING_WS/_workspace.md"
      git add -A && git commit -q -m "temp: restore active ws for scenario B"
    fi
  fi

  echo ""
  echo "--- Scenario A: Assertions ---"
  echo ""

  # Find the newly created workspace directory
  NEW_WS_DIR=""
  for d in workspace/*/; do
    [[ "$d" == "$EXISTING_WS/" ]] && continue
    [[ -f "${d}_workspace.md" ]] && NEW_WS_DIR="$d"
  done

  # INV-04: Directory name matches {YYYY-MM-DD}-{kebab-case}
  if [[ -n "$NEW_WS_DIR" ]]; then
    WS_DIRNAME=$(basename "$NEW_WS_DIR")
    echo "  New workspace: $WS_DIRNAME"
    HAS_DATE_PREFIX=$(echo "$WS_DIRNAME" | grep -cE '^[0-9]{4}-[0-9]{2}-[0-9]{2}-' 2>/dev/null || echo "0")
    assert_gt "$HAS_DATE_PREFIX" 0 "INV-04: Directory has date prefix"

    NEW_WS_FILE="${NEW_WS_DIR}_workspace.md"

    # WM-01: Required frontmatter fields
    echo "=== WM-01: _workspace.md frontmatter ==="
    WM_TYPE=$(fm_get "$NEW_WS_FILE" "type")
    assert_eq "$WM_TYPE" "workspace" "WM-01: type is 'workspace'"

    WM_STATUS=$(fm_get "$NEW_WS_FILE" "status")
    assert_eq "$WM_STATUS" "active" "WM-02: status is 'active'"

    WM_CREATED=$(fm_get "$NEW_WS_FILE" "created")
    assert_true "[[ -n '$WM_CREATED' ]]" "WM-01: has created"

    WM_ID=$(fm_get "$NEW_WS_FILE" "id")
    assert_true "[[ -n '$WM_ID' ]]" "WM-01: has id"

    WM_NAME=$(fm_get "$NEW_WS_FILE" "name")
    assert_true "[[ -n '$WM_NAME' ]]" "WM-01: has name"

    # WM-04: tags exist
    WM_TAGS=$(fm_get "$NEW_WS_FILE" "tags")
    assert_true "[[ -n '$WM_TAGS' ]]" "WM-04: has tags"

    # WM-04 extended: tags are in taxonomy
    if [[ -n "$WM_TAGS" ]]; then
      bash "$ASSERTIONS_DIR/check-taxonomy.sh" "$NEW_WS_FILE" taxonomy.md || true
    fi

    # WM-05 to WM-08: Required sections
    echo "=== WM-05-08: Required sections ==="
    HAS_ISSUES=$({ grep -ci 'Issues to Consider\|Key Questions\|Discussion Points' "$NEW_WS_FILE" 2>/dev/null || echo "0"; } | tr -d '[:space:]')
    assert_gt "$HAS_ISSUES" 0 "WM-05: Has issues/questions section"

    HAS_MOC=$({ grep -ci 'Related Files\|MOC\|References' "$NEW_WS_FILE" 2>/dev/null || echo "0"; } | tr -d '[:space:]')
    assert_gt "$HAS_MOC" 0 "WM-06: Has MOC/related files section"

    HAS_HISTORY=$({ grep -ci 'Session History\|History\|Log' "$NEW_WS_FILE" 2>/dev/null || echo "0"; } | tr -d '[:space:]')
    assert_gt "$HAS_HISTORY" 0 "WM-07: Has session history section"

    HAS_NEXT=$({ grep -ci 'Next Steps\|Next Actions\|TODO' "$NEW_WS_FILE" 2>/dev/null || echo "0"; } | tr -d '[:space:]')
    assert_gt "$HAS_NEXT" 0 "WM-08: Has next steps section"

    # WM-09: MOC section exists and uses Markdown link format (if links present)
    # CX-01: Context collection ran (verified by MOC section existence — WM-06 above)
    echo "=== CX: Context collection ==="
    HAS_MD_LINKS=$({ grep -c '\[.*\](.*\.md)' "$NEW_WS_FILE" 2>/dev/null || echo "0"; } | tr -d '[:space:]')
    if (( HAS_MD_LINKS > 0 )); then
      # If links exist, verify they use proper Markdown format (not Wikilinks)
      HAS_WIKILINKS=$({ grep -c '\[\[' "$NEW_WS_FILE" 2>/dev/null || echo "0"; } | tr -d '[:space:]')
      assert_eq "$HAS_WIKILINKS" "0" "WM-09: MOC uses Markdown links, not Wikilinks"
    fi
    echo "  INFO: MOC links found: $HAS_MD_LINKS (0 is valid if no related files exist)"

  else
    assert_true "false" "Scenario A: New workspace was created"
  fi
  echo ""
fi

# =============================================
# Scenario B: Resume existing workspace
# =============================================
if [[ "$SCENARIO" == *B* ]]; then
  echo ""
  echo "==========================================="
  echo "  Scenario B: Resume existing workspace"
  echo "==========================================="

  if ! $SKIP_EXECUTE; then
    echo ""
    echo "=== Executing /focus $EXISTING_WS ==="
    echo "  (this may take 1-3 minutes)"
    echo ""

    isolate_test_vault "$VAULT_DIR"

    claude -p "/focus $EXISTING_WS" \
      --output-format text \
      --max-turns 30 \
      2>&1 | tee "$RESULTS_DIR/focus-b-output.log"

    echo ""
    echo "=== Scenario B execution complete ==="

    check_real_repo_contamination "$REPO_REAL_DIR" "$VAULT_DIR"
  fi

  echo ""
  echo "--- Scenario B: Assertions ---"
  echo ""

  # WS-01: Workspace status remains active (not changed to something else)
  echo "=== WS-01: Workspace resumed correctly ==="
  if [[ -f "$EXISTING_WS/_workspace.md" ]]; then
    WS_STATUS=$(fm_get "$EXISTING_WS/_workspace.md" "status")
    assert_eq "$WS_STATUS" "active" "WS-01: Status remains 'active' after resume"

    # Existing _workspace.md core fields preserved
    WS_ID=$(fm_get "$EXISTING_WS/_workspace.md" "id")
    assert_eq "$WS_ID" "2026-01-10-sample-workspace" "WS-01: id preserved"

    WS_NAME=$(fm_get "$EXISTING_WS/_workspace.md" "name")
    assert_true "[[ -n '$WS_NAME' ]]" "WS-01: name preserved"
  fi

  # Verify the output references deliverable content (context was collected)
  echo "=== B-CTX: Resume context collection ==="
  if [[ -f "$RESULTS_DIR/focus-b-output.log" ]]; then
    # The model should have read and referenced the workspace deliverables
    HAS_AUTH0_REF=$({ grep -ci 'auth0\|OAuth\|provider\|authentication' "$RESULTS_DIR/focus-b-output.log" 2>/dev/null || echo "0"; } | tr -d '[:space:]')
    assert_gt "$HAS_AUTH0_REF" 0 "B-CTX: Output references OAuth/Auth0 (read deliverables)"

    HAS_TOKEN_REF=$({ grep -ci 'token\|refresh' "$RESULTS_DIR/focus-b-output.log" 2>/dev/null || echo "0"; } | tr -d '[:space:]')
    assert_gt "$HAS_TOKEN_REF" 0 "B-CTX: Output references token refresh (read 002 deliverable)"

    # The model should mention the unchecked item (migration schedule)
    HAS_UNCHECKED=$({ grep -ci 'migration\|schedule' "$RESULTS_DIR/focus-b-output.log" 2>/dev/null || echo "0"; } | tr -d '[:space:]')
    assert_gt "$HAS_UNCHECKED" 0 "B-CTX: Output references unchecked item (migration schedule)"
  fi

  # Non-destruction: existing deliverables unchanged
  echo "=== B-INV: Existing files preserved ==="
  for deliverable in "$EXISTING_WS"/[0-9][0-9][0-9]-*.md; do
    [[ -f "$deliverable" ]] || continue
    dname=$(basename "$deliverable")
    if [[ -f "$FIXTURES_DIR/$EXISTING_WS/$dname" ]]; then
      orig_hash=$(file_hash "$FIXTURES_DIR/$EXISTING_WS/$dname")
      curr_hash=$(file_hash "$deliverable")
      assert_eq "$curr_hash" "$orig_hash" "B-INV: Deliverable $dname unchanged"
    fi
  done
  echo ""
fi

# =============================================
# Common assertions
# =============================================
echo ""
echo "==========================================="
echo "  Common Assertions"
echo "==========================================="
echo ""

# INV-01: Inbox immutability
echo "=== INV-01: Inbox immutability ==="
bash "$ASSERTIONS_DIR/check-no-mutation.sh" "$HASH_FILE" || true
echo ""

# Existing knowledge file immutability
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
echo "  Scenarios: $SCENARIO"
echo ""

# Count new workspaces
NEW_WS_COUNT=0
for d in workspace/*/; do
  [[ "$d" == "$EXISTING_WS/" ]] && continue
  [[ -f "${d}_workspace.md" ]] && NEW_WS_COUNT=$((NEW_WS_COUNT + 1))
done
echo "  New workspaces: $NEW_WS_COUNT"

cat > "$RESULTS_DIR/summary.json" <<EOF
{
  "timestamp": "$TIMESTAMP",
  "vault": "$VAULT_DIR",
  "skill": "focus",
  "scenarios": "$SCENARIO",
  "new_workspaces": $NEW_WS_COUNT,
  "pass": $_PASS,
  "fail": $_FAIL,
  "total": $_TOTAL
}
EOF

report_results || true

echo ""
echo "Vault preserved at: $VAULT_DIR"
echo "To re-run assertions: bash $0 --skip-execute --vault=$VAULT_DIR"
