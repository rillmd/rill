#!/bin/bash
# test/assertions/lib.sh — Common test utilities
#
# Source this file in test scripts:
#   source "$(dirname "$0")/../assertions/lib.sh"

set -euo pipefail

# Counters
_PASS=0
_FAIL=0
_TOTAL=0
_FAILURES=()

# Colors
_GREEN='\033[0;32m'
_RED='\033[0;31m'
_YELLOW='\033[0;33m'
_NC='\033[0m'

# --- Assertion functions ---

assert_true() {
  local condition="$1" msg="$2"
  _TOTAL=$((_TOTAL + 1))
  if eval "$condition"; then
    _PASS=$((_PASS + 1))
    printf "  ${_GREEN}PASS${_NC}: %s\n" "$msg"
  else
    _FAIL=$((_FAIL + 1))
    _FAILURES+=("$msg")
    printf "  ${_RED}FAIL${_NC}: %s\n" "$msg"
  fi
}

assert_eq() {
  local actual="$1" expected="$2" msg="$3"
  _TOTAL=$((_TOTAL + 1))
  if [[ "$actual" == "$expected" ]]; then
    _PASS=$((_PASS + 1))
    printf "  ${_GREEN}PASS${_NC}: %s\n" "$msg"
  else
    _FAIL=$((_FAIL + 1))
    _FAILURES+=("$msg (got '$actual', expected '$expected')")
    printf "  ${_RED}FAIL${_NC}: %s (got '%s', expected '%s')\n" "$msg" "$actual" "$expected"
  fi
}

assert_gt() {
  local actual="$1" expected="$2" msg="$3"
  _TOTAL=$((_TOTAL + 1))
  if (( actual > expected )); then
    _PASS=$((_PASS + 1))
    printf "  ${_GREEN}PASS${_NC}: %s (%d > %d)\n" "$msg" "$actual" "$expected"
  else
    _FAIL=$((_FAIL + 1))
    _FAILURES+=("$msg ($actual <= $expected)")
    printf "  ${_RED}FAIL${_NC}: %s (%d <= %d)\n" "$msg" "$actual" "$expected"
  fi
}

assert_le() {
  local actual="$1" expected="$2" msg="$3"
  _TOTAL=$((_TOTAL + 1))
  if (( actual <= expected )); then
    _PASS=$((_PASS + 1))
    printf "  ${_GREEN}PASS${_NC}: %s (%d <= %d)\n" "$msg" "$actual" "$expected"
  else
    _FAIL=$((_FAIL + 1))
    _FAILURES+=("$msg ($actual > $expected)")
    printf "  ${_RED}FAIL${_NC}: %s (%d > %d)\n" "$msg" "$actual" "$expected"
  fi
}

assert_file_exists() {
  local path="$1" msg="$2"
  _TOTAL=$((_TOTAL + 1))
  if [[ -f "$path" ]]; then
    _PASS=$((_PASS + 1))
    printf "  ${_GREEN}PASS${_NC}: %s\n" "$msg"
  else
    _FAIL=$((_FAIL + 1))
    _FAILURES+=("$msg (not found: $path)")
    printf "  ${_RED}FAIL${_NC}: %s (not found: %s)\n" "$msg" "$path"
  fi
}

assert_file_not_exists() {
  local path="$1" msg="$2"
  _TOTAL=$((_TOTAL + 1))
  if [[ ! -f "$path" ]]; then
    _PASS=$((_PASS + 1))
    printf "  ${_GREEN}PASS${_NC}: %s\n" "$msg"
  else
    _FAIL=$((_FAIL + 1))
    _FAILURES+=("$msg (file exists: $path)")
    printf "  ${_RED}FAIL${_NC}: %s (file exists: %s)\n" "$msg" "$path"
  fi
}

assert_file_contains() {
  local file="$1" pattern="$2" msg="$3"
  _TOTAL=$((_TOTAL + 1))
  if grep -q "$pattern" "$file" 2>/dev/null; then
    _PASS=$((_PASS + 1))
    printf "  ${_GREEN}PASS${_NC}: %s\n" "$msg"
  else
    _FAIL=$((_FAIL + 1))
    _FAILURES+=("$msg (pattern '$pattern' not found in $file)")
    printf "  ${_RED}FAIL${_NC}: %s (pattern '%s' not found)\n" "$msg" "$pattern"
  fi
}

assert_file_not_contains() {
  local file="$1" pattern="$2" msg="$3"
  _TOTAL=$((_TOTAL + 1))
  if ! grep -q "$pattern" "$file" 2>/dev/null; then
    _PASS=$((_PASS + 1))
    printf "  ${_GREEN}PASS${_NC}: %s\n" "$msg"
  else
    _FAIL=$((_FAIL + 1))
    _FAILURES+=("$msg (pattern '$pattern' found in $file)")
    printf "  ${_RED}FAIL${_NC}: %s (pattern '%s' found)\n" "$msg" "$pattern"
  fi
}

assert_oneof() {
  local actual="$1" options="$2" msg="$3"
  _TOTAL=$((_TOTAL + 1))
  local found=false
  IFS=',' read -ra OPTS <<< "$options"
  for opt in "${OPTS[@]}"; do
    if [[ "$actual" == "$opt" ]]; then
      found=true
      break
    fi
  done
  if $found; then
    _PASS=$((_PASS + 1))
    printf "  ${_GREEN}PASS${_NC}: %s ('%s')\n" "$msg" "$actual"
  else
    _FAIL=$((_FAIL + 1))
    _FAILURES+=("$msg (got '$actual', expected one of: $options)")
    printf "  ${_RED}FAIL${_NC}: %s (got '%s', expected one of: %s)\n" "$msg" "$actual" "$options"
  fi
}

# --- Frontmatter utilities ---

# Extract raw frontmatter YAML from a file (between --- delimiters)
extract_frontmatter_raw() {
  local file="$1"
  sed -n '1{/^---$/!q};1,/^---$/{/^---$/!p}' "$file" | tail -n +1
}

# Get a frontmatter field value (simple single-line values)
fm_get() {
  local file="$1" field="$2"
  # Extract frontmatter block, then grep for the field
  awk '/^---$/{n++; next} n==1{print}' "$file" | grep "^${field}:" | sed "s/^${field}: *//" | head -1
}

# Get frontmatter array field as space-separated values
# Handles both inline [a, b] and multi-line - a formats
fm_get_array() {
  local file="$1" field="$2"
  local value
  value=$(fm_get "$file" "$field")
  # Inline array: [a, b, c]
  if [[ "$value" =~ ^\[.*\]$ ]]; then
    echo "$value" | tr -d '[]' | tr ',' '\n' | sed 's/^ *//;s/ *$//' | grep -v '^$'
  else
    echo "$value"
  fi
}

# Count items in a frontmatter array field
fm_count_array() {
  local file="$1" field="$2"
  fm_get_array "$file" "$field" | grep -c -v '^$' 2>/dev/null || echo 0
}

# --- File hash utilities ---

# --- Test vault isolation (prevents rill mkfile from writing to the real repo) ---
#
# Historical context: until 2026-04-08, running `test/skills/test-*.sh` could
# silently contaminate the developer's real repository. The root cause was that
# `~/.local/bin/rill` is a symlink to the real repo's `bin/rill`, and
# `resolve_rill_home()` followed the symlink — so when a sub-agent invoked
# `rill mkfile ...` (without a `bin/` prefix) inside a test vault, the file was
# created in the real repo instead.
#
# These helpers isolate the test environment and detect any leakage.

# Call BEFORE `claude -p`, after `VAULT_DIR` is set. Exports PATH and RILL_HOME
# so that both the vault's `bin/rill` and any `rill` on PATH resolve to vault.
isolate_test_vault() {
  local vault_dir="$1"
  if [[ -z "$vault_dir" || ! -d "$vault_dir" ]]; then
    echo "  WARNING: isolate_test_vault: invalid vault_dir: $vault_dir" >&2
    return 1
  fi
  export PATH="$vault_dir/bin:$PATH"
  export RILL_HOME="$vault_dir"
  echo "  vault isolated: PATH=$vault_dir/bin:..., RILL_HOME=$vault_dir"
}

# Call AFTER `claude -p`, with the real repo dir (resolved at script top) and
# the vault dir. Checks universal canary files that should ONLY ever live in
# a test fixture vault.
check_real_repo_contamination() {
  local repo_real_dir="$1" vault_dir="$2"
  if [[ -z "$repo_real_dir" || "$repo_real_dir" == "$vault_dir" ]]; then
    return 0
  fi
  local found=false
  # Universal canaries: files that exist in test fixtures but should NEVER
  # appear in a developer's real repository
  for canary in \
    "knowledge/people/alex-chen.md" \
    "knowledge/projects/sample-project.md" \
    "knowledge/notes/oauth-provider-comparison-auth0-clerk-supabase.md" \
    "knowledge/notes/sample-project-oauth-provider-auth0-adoption.md" \
    "workspace/2026-01-10-sample-workspace/_workspace.md" \
    "workspace/2026-01-10-sample-workspace/_summary.md"
  do
    if [[ -e "$repo_real_dir/$canary" ]]; then
      found=true
      echo ""
      echo "  WARNING: CONTAMINATION DETECTED: $repo_real_dir/$canary"
      echo "      A test-fixture file leaked into the real repository."
      echo "      A sub-agent likely called \`rill mkfile\` with RILL_HOME resolving"
      echo "      to the real repo. Check PATH/RILL_HOME isolation at the top of"
      echo "      this test script, and ensure sub-agent prompts use \`bin/rill\`."
      echo ""
    fi
  done
  if ! $found; then
    echo "  OK: Contamination check: no fixture files leaked to $repo_real_dir"
  fi
}

# Get MD5 hash of a file
file_hash() {
  md5 -q "$1" 2>/dev/null || md5sum "$1" 2>/dev/null | cut -d' ' -f1
}

# Hash all files in a directory (recursive, sorted)
dir_hash() {
  local dir="$1"
  find "$dir" -type f | sort | xargs md5 -q 2>/dev/null | md5 -q 2>/dev/null
}

# --- Reporting ---

report_results() {
  echo ""
  echo "==========================================="
  if (( _FAIL == 0 )); then
    printf "${_GREEN}ALL PASSED${_NC}: %d/%d\n" "$_PASS" "$_TOTAL"
  else
    printf "${_RED}FAILED${_NC}: %d passed, %d failed out of %d\n" "$_PASS" "$_FAIL" "$_TOTAL"
    echo ""
    echo "Failures:"
    for f in "${_FAILURES[@]}"; do
      printf "  - %s\n" "$f"
    done
  fi
  echo "==========================================="
  return "$_FAIL"
}
