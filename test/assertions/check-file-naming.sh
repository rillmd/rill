#!/bin/bash
# check-file-naming.sh — Validate file naming conventions
#
# Usage: bash check-file-naming.sh <file>
#
# Validates:
# - Filename is kebab-case (lowercase, hyphens, no spaces)
# - No Wikilinks [[]] in body

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

FILE="$1"
BASENAME=$(basename "$FILE" .md)
echo "--- Checking naming: $BASENAME ---"

# Check kebab-case (allow digits and dots for dates)
assert_true "[[ '$BASENAME' =~ ^[a-z0-9][a-z0-9.-]*$ ]]" "Filename is kebab-case: $BASENAME"

# Check no Wikilinks in body
assert_file_not_contains "$FILE" '\[\[' "No Wikilinks in file"

# Check body has H1 title (for knowledge/notes/)
if [[ "$FILE" == *knowledge/notes/* ]]; then
  assert_file_contains "$FILE" '^# ' "Has H1 title"
fi

report_results
