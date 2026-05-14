#!/bin/bash
# test/run-all.sh — Run all skill tests
#
# Usage: bash test/run-all.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "============================================"
echo "  Rill Skill Test Suite"
echo "============================================"
echo ""

TOTAL_PASS=0
TOTAL_FAIL=0

run_test() {
  local name="$1" script="$2"
  echo "--- Running: $name ---"
  if bash "$script"; then
    echo "  → $name: PASSED"
  else
    echo "  → $name: FAILED"
    # Use assignment form (not `((TOTAL_FAIL++))`) — post-increment when
    # TOTAL_FAIL=0 evaluates the expression to 0, which under `set -e` would
    # exit the script on the first failing suite instead of running the rest.
    TOTAL_FAIL=$((TOTAL_FAIL + 1))
  fi
  echo ""
}

run_test "/distill"     "$SCRIPT_DIR/skills/test-distill.sh"
run_test "/briefing"    "$SCRIPT_DIR/skills/test-briefing.sh"
run_test "/clip-tweet"  "$SCRIPT_DIR/skills/test-clip-tweet.sh"
run_test "/close"       "$SCRIPT_DIR/skills/test-close.sh"
run_test "/focus"       "$SCRIPT_DIR/skills/test-focus.sh"
run_test "/newsletter"  "$SCRIPT_DIR/skills/test-newsletter.sh"
run_test "/page"        "$SCRIPT_DIR/skills/test-page.sh"
run_test "/solve"       "$SCRIPT_DIR/skills/test-solve.sh"
run_test "/inspect"     "$SCRIPT_DIR/skills/test-inspect.sh"
run_test "/repair"      "$SCRIPT_DIR/skills/test-repair.sh"
run_test "/eval"        "$SCRIPT_DIR/skills/test-eval.sh"

echo "============================================"
if (( TOTAL_FAIL == 0 )); then
  echo "  All test suites passed"
else
  echo "  $TOTAL_FAIL test suite(s) failed"
fi
echo "============================================"
