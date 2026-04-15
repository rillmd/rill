#!/bin/bash
# check-organized.sh — Validate _organized/ files against their originals
#
# Usage: bash check-organized.sh <organized_dir> <original_dir>
#
# Validates (OR-01, OR-02, OR-04):
# - Each organized file has a corresponding original
# - created field matches the original
# - organized: true is present in frontmatter

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

ORGANIZED_DIR="$1"
ORIGINAL_DIR="$2"

echo "--- Checking organized files: $ORGANIZED_DIR ---"

for organized in "$ORGANIZED_DIR"/*.md; do
  [[ -f "$organized" ]] || continue
  name=$(basename "$organized")

  # OR-04: same filename in _organized/
  original="$ORIGINAL_DIR/$name"
  assert_file_exists "$original" "OR-04: Original exists for $name"

  if [[ ! -f "$original" ]]; then
    continue
  fi

  # OR-01: created field matches original
  orig_created=$(fm_get "$original" "created")
  org_created=$(fm_get "$organized" "created")
  if [[ -n "$orig_created" && -n "$org_created" ]]; then
    assert_eq "$org_created" "$orig_created" "OR-01: created matches for $name"
  fi

  # OR-02: organized: true is present
  org_flag=$(fm_get "$organized" "organized")
  assert_eq "$org_flag" "true" "OR-02: organized: true for $name"
done

report_results
