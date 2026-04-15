#!/bin/bash
# check-frontmatter.sh — Validate frontmatter fields of generated files
#
# Usage: bash check-frontmatter.sh <file> --required "field1,field2,field3"
#
# Validates:
# - File has frontmatter (--- delimiters)
# - Required fields are present
# - 'type' is one of record/insight/reference (for knowledge/notes/)
# - 'tags' has <= 3 items
# - 'created' is ISO 8601 format
# - 'status' is 'draft' (for tasks/)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

FILE="$1"
shift

REQUIRED_FIELDS=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --required) REQUIRED_FIELDS="$2"; shift 2 ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

BASENAME=$(basename "$FILE")
echo "--- Checking frontmatter: $BASENAME ---"

# Check frontmatter exists
assert_true "[[ \$(head -1 '$FILE') == '---' ]]" "Has frontmatter delimiter"

# Check required fields
if [[ -n "$REQUIRED_FIELDS" ]]; then
  IFS=',' read -ra FIELDS <<< "$REQUIRED_FIELDS"
  for field in "${FIELDS[@]}"; do
    field=$(echo "$field" | xargs) # trim whitespace
    assert_true "[[ -n \$(fm_get '$FILE' '$field') ]]" "Required field '$field' exists"
  done
fi

# Check type validity (for knowledge/notes/ files)
if [[ "$FILE" == *knowledge/notes/* ]]; then
  TYPE=$(fm_get "$FILE" "type")
  if [[ -n "$TYPE" ]]; then
    assert_oneof "$TYPE" "record,insight,reference" "Type is valid"
  fi
fi

# Check tags count <= 3
TAG_COUNT=$(fm_count_array "$FILE" "tags")
if (( TAG_COUNT > 0 )); then
  assert_le "$TAG_COUNT" 3 "Tags count <= 3"
fi

# Check created format (ISO 8601)
CREATED=$(fm_get "$FILE" "created")
if [[ -n "$CREATED" ]]; then
  assert_true "[[ '$CREATED' =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2} ]]" "Created is ISO 8601"
fi

# Check task status = draft (for tasks/ files)
if [[ "$FILE" == *tasks/* ]]; then
  TASK_STATUS=$(fm_get "$FILE" "status")
  if [[ -n "$TASK_STATUS" ]]; then
    assert_eq "$TASK_STATUS" "draft" "Task status is draft"
  fi
fi

# Check mentions field exists (MN-02: always present)
if [[ "$FILE" == *knowledge/notes/* ]]; then
  MENTIONS_LINE=$(awk '/^---$/{n++; next} n==1 && /^mentions:/{print; exit}' "$FILE")
  assert_true "[[ -n '$MENTIONS_LINE' ]]" "mentions field exists (MN-02)"
fi

# Check related count <= 5 (INV-13)
RELATED_COUNT=$(fm_count_array "$FILE" "related")
if (( RELATED_COUNT > 0 )); then
  assert_le "$RELATED_COUNT" 5 "Related count <= 5 (INV-13)"
fi

# Check source points to _organized/ for knowledge/notes/ (KE-03)
if [[ "$FILE" == *knowledge/notes/* ]]; then
  SOURCE=$(fm_get "$FILE" "source")
  if [[ -n "$SOURCE" && "$SOURCE" == *inbox/journal/* ]]; then
    assert_true "[[ '$SOURCE' == *_organized/* ]]" "Source points to _organized/ (KE-03)"
  fi
fi

# Check source for tasks (TK-07)
if [[ "$FILE" == *tasks/* ]]; then
  SOURCE=$(fm_get "$FILE" "source")
  if [[ -n "$SOURCE" && "$SOURCE" == *inbox/journal/* ]]; then
    assert_true "[[ '$SOURCE' == *_organized/* ]]" "Task source points to _organized/ (TK-07)"
  fi
fi

report_results
