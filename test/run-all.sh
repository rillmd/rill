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
    ((TOTAL_FAIL++))
  fi
  echo ""
}

# Currently only /distill test is implemented
run_test "/distill" "$SCRIPT_DIR/skills/test-distill.sh"

# Future tests:
# run_test "/briefing" "$SCRIPT_DIR/skills/test-briefing.sh"
# run_test "/focus" "$SCRIPT_DIR/skills/test-focus.sh"
# run_test "/close" "$SCRIPT_DIR/skills/test-close.sh"

echo "============================================"
if (( TOTAL_FAIL == 0 )); then
  echo "  All test suites passed"
else
  echo "  $TOTAL_FAIL test suite(s) failed"
fi
echo "============================================"
