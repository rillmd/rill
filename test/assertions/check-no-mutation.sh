#!/bin/bash
# check-no-mutation.sh — Verify inbox files were not modified
#
# Usage: bash check-no-mutation.sh <hash_file>
#
# Compares current inbox file hashes against saved hashes.
# Hash file format: one "md5 path" per line.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

HASH_FILE="$1"
echo "--- Checking inbox immutability ---"

while IFS=' ' read -r expected_hash filepath; do
  [[ -z "$expected_hash" ]] && continue
  [[ "$expected_hash" == "#"* ]] && continue

  if [[ ! -f "$filepath" ]]; then
    assert_true "false" "File exists: $filepath"
    continue
  fi

  actual_hash=$(file_hash "$filepath")
  assert_eq "$actual_hash" "$expected_hash" "Unchanged: $(basename "$filepath")"
done < "$HASH_FILE"

report_results
