#!/bin/bash
# check-mentions.sh — Validate mentions field format
#
# Usage: bash check-mentions.sh <file>
#
# Validates:
# - mentions values have type prefix (people/, orgs/, projects/)
# - No entity IDs in tags field

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

FILE="$1"
BASENAME=$(basename "$FILE")
echo "--- Checking mentions: $BASENAME ---"

# Check mentions format
MENTIONS=$(fm_get_array "$FILE" "mentions")

if [[ -n "$MENTIONS" ]]; then
  while IFS= read -r mention; do
    [[ -z "$mention" ]] && continue
    assert_true "[[ '$mention' =~ ^(people|orgs|projects)/ ]]" "Mention '$mention' has type prefix"
  done <<< "$MENTIONS"
fi

# Check tags don't contain entity IDs
TAGS=$(fm_get_array "$FILE" "tags")
if [[ -n "$TAGS" ]]; then
  while IFS= read -r tag; do
    [[ -z "$tag" ]] && continue
    # Check against known entity IDs in the vault
    for entity_dir in knowledge/people knowledge/orgs knowledge/projects; do
      if [[ -d "$entity_dir" ]]; then
        for entity_file in "$entity_dir"/*.md; do
          [[ -f "$entity_file" ]] || continue
          entity_id=$(basename "$entity_file" .md)
          assert_true "[[ '$tag' != '$entity_id' ]]" "Tag '$tag' is not entity ID '$entity_id'"
        done
      fi
    done
  done <<< "$TAGS"
fi

report_results
