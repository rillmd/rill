#!/bin/bash
# check-taxonomy.sh — Validate tags exist in taxonomy.md
#
# Usage: bash check-taxonomy.sh <file> <taxonomy_path>

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

FILE="$1"
TAXONOMY="$2"

BASENAME=$(basename "$FILE")
echo "--- Checking taxonomy: $BASENAME ---"

# Extract tags from file
TAGS=$(fm_get_array "$FILE" "tags")

if [[ -z "$TAGS" ]]; then
  echo "  (no tags to check)"
  report_results
  exit 0
fi

# Extract valid tag names from taxonomy
VALID_TAGS=$(grep '^| ' "$TAXONOMY" | grep -v '| Tag ' | grep -v '| Old Tag' | grep -v '^|---' | awk -F'|' '{print $2}' | sed 's/^ *//;s/ *$//' | grep -v '^$')

# Also extract aliases
VALID_ALIASES=$(grep '^| ' "$TAXONOMY" | grep -v '| Tag ' | grep -v '| Old Tag' | grep -v '^|---' | awk -F'|' '{print $4}' | tr ',' '\n' | sed 's/^ *//;s/ *$//' | grep -v '^$')

ALL_VALID=$(echo -e "$VALID_TAGS\n$VALID_ALIASES" | sort -u)

while IFS= read -r tag; do
  [[ -z "$tag" ]] && continue
  if echo "$ALL_VALID" | grep -qx "$tag"; then
    assert_true "true" "Tag '$tag' exists in taxonomy"
  else
    assert_true "false" "Tag '$tag' exists in taxonomy"
  fi
done <<< "$TAGS"

report_results
