#!/bin/bash
# check-keyfacts.sh — Validate key fact accumulation in people/ and projects/
#
# Usage: bash check-keyfacts.sh <current_dir> <fixtures_dir>
#
# Validates (KF-01, KF-02, KF-04):
# - people/ and projects/ files are not corrupted (frontmatter intact)
# - Key facts section exists and is not deleted
# - Key fact count <= 20 (KF-02)
# - Frontmatter immutable fields (created, id, name) are unchanged
# - Structure sections are preserved (projects/: Goal, Watch, Competitors, Keywords, See Also)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

CURRENT_DIR="$1"
FIXTURES_DIR="$2"

echo "--- Checking key fact accumulation ---"

# Check people/ files
echo ""
echo "  == people/ =="
for fixture_file in "$FIXTURES_DIR"/knowledge/people/*.md; do
  [[ -f "$fixture_file" ]] || continue
  name=$(basename "$fixture_file")
  current_file="$CURRENT_DIR/knowledge/people/$name"

  if [[ ! -f "$current_file" ]]; then
    assert_true "false" "people/$name still exists"
    continue
  fi

  # Frontmatter immutability
  orig_created=$(fm_get "$fixture_file" "created")
  curr_created=$(fm_get "$current_file" "created")
  assert_eq "$curr_created" "$orig_created" "people/$name: created unchanged"

  orig_id=$(fm_get "$fixture_file" "id")
  curr_id=$(fm_get "$current_file" "id")
  assert_eq "$curr_id" "$orig_id" "people/$name: id unchanged"

  orig_name_val=$(fm_get "$fixture_file" "name")
  curr_name_val=$(fm_get "$current_file" "name")
  assert_eq "$curr_name_val" "$orig_name_val" "people/$name: name unchanged"

  # Key facts section exists
  assert_file_contains "$current_file" "## Key Facts" "people/$name: key facts section exists"

  # Key fact count <= 20
  KF_COUNT=$(grep -c '^- ' "$current_file" 2>/dev/null || echo "0")
  assert_le "$KF_COUNT" 20 "people/$name: key facts <= 20 (KF-02)"

  # Original key facts are preserved (not deleted)
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    # Extract the key fact text (remove leading "- ")
    fact="${line#- }"
    if ! grep -qF "$fact" "$current_file" 2>/dev/null; then
      assert_true "false" "people/$name: original fact preserved: $fact"
    else
      assert_true "true" "people/$name: original fact preserved: ${fact:0:50}..."
    fi
  done < <(awk '/^## Key Facts/{found=1; next} found && /^## /{exit} found && /^- /{print}' "$fixture_file")
done

# Check projects/ files
echo ""
echo "  == projects/ =="
for fixture_file in "$FIXTURES_DIR"/knowledge/projects/*.md; do
  [[ -f "$fixture_file" ]] || continue
  name=$(basename "$fixture_file")
  current_file="$CURRENT_DIR/knowledge/projects/$name"

  if [[ ! -f "$current_file" ]]; then
    assert_true "false" "projects/$name still exists"
    continue
  fi

  # Frontmatter immutability
  orig_created=$(fm_get "$fixture_file" "created")
  curr_created=$(fm_get "$current_file" "created")
  assert_eq "$curr_created" "$orig_created" "projects/$name: created unchanged"

  orig_id=$(fm_get "$fixture_file" "id")
  curr_id=$(fm_get "$current_file" "id")
  assert_eq "$curr_id" "$orig_id" "projects/$name: id unchanged"

  # Structure sections preserved (KF-04)
  for section in "Goal" "Watch" "Competitors" "Keywords" "Key Facts" "See Also"; do
    if grep -q "## $section\|### $section" "$fixture_file" 2>/dev/null; then
      assert_file_contains "$current_file" "$section" "projects/$name: section '$section' preserved"
    fi
  done

  # Key fact count <= 20
  KF_COUNT=$(awk '/^## Key Facts/{found=1; next} found && /^## /{exit} found && /^- /{c++} END{print c+0}' "$current_file")
  assert_le "$KF_COUNT" 20 "projects/$name: key facts <= 20 (KF-02)"

  # Original key facts are preserved
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    fact="${line#- }"
    if ! grep -qF "$fact" "$current_file" 2>/dev/null; then
      assert_true "false" "projects/$name: original fact preserved: $fact"
    else
      assert_true "true" "projects/$name: original fact preserved: ${fact:0:50}..."
    fi
  done < <(awk '/^## Key Facts/{found=1; next} found && /^## /{exit} found && /^- /{print}' "$fixture_file")
done

report_results
