#!/bin/bash
# test/cli/test-activity-log-sync.sh - `rill activity-log` /sync completion
#
# Submitting a /sync prompt must not log sync:complete on its own: the run
# has not happened yet and may fail. The prompt hook leaves a per-session
# pending marker, and the Stop hook (which fires only when the turn
# completed) turns it into exactly one sync:complete line.
#
# Covered:
#   - a /sync prompt writes nothing to activity-log.md
#   - Stop for the same session writes one sync:complete line with the target
#   - Stop for another session writes nothing; a second Stop writes nothing
#   - bare /sync logs the "manual" target
#   - hooks print nothing and exit 0 on empty or malformed input
#
# Usage: bash test/cli/test-activity-log-sync.sh
# Requires: bash, jq. No claude CLI, no network.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
RILL="$REPO_ROOT/bin/rill"

# shellcheck source=test/assertions/lib.sh
source "$SCRIPT_DIR/../assertions/lib.sh"

if ! command -v jq >/dev/null 2>&1; then
  echo "FAIL: jq is required"
  exit 1
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

VAULT="$WORK/vault"
mkdir -p "$VAULT/.rill" "$WORK/tmp"
echo "test" > "$VAULT/.rill/version"
: > "$VAULT/activity-log.md"
LOG="$VAULT/activity-log.md"

# Isolate HOME, cwd and TMPDIR so neither vault resolution nor the
# per-session scratch directory can touch real state.
hook() { # subcommand, stdin
  (cd "$WORK" && printf '%s' "$2" | HOME="$WORK" TMPDIR="$WORK/tmp" RILL_HOME="$VAULT" \
    "$RILL" activity-log "$1")
}
sync_lines() { grep -c 'sync:complete' "$LOG" || true; }

echo "=== /sync prompt then Stop ==="
OUT="$(hook on-prompt '{"session_id":"als_a","prompt":"/sync x"}')"
assert_eq "$OUT" "" "the prompt hook prints nothing"
assert_eq "$(sync_lines)" "0" "a /sync prompt alone writes nothing to activity-log.md"

OUT="$(hook on-stop '{"session_id":"als_b"}')"
assert_eq "$OUT" "" "the Stop hook prints nothing"
assert_eq "$(sync_lines)" "0" "Stop for another session writes nothing"

hook on-stop '{"session_id":"als_a"}' >/dev/null
assert_eq "$(sync_lines)" "1" "Stop for the same session writes exactly one sync:complete line"
assert_eq "$(grep -c 'sync:complete "x"' "$LOG" || true)" "1" "the line carries the sync target"

hook on-stop '{"session_id":"als_a"}' >/dev/null
assert_eq "$(sync_lines)" "1" "a later Stop does not log the same sync again"

echo "=== bare /sync ==="
hook on-prompt '{"session_id":"als_c","prompt":"/sync"}' >/dev/null
hook on-stop '{"session_id":"als_c"}' >/dev/null
assert_eq "$(grep -c 'sync:complete "manual"' "$LOG" || true)" "1" "bare /sync logs the manual target"

echo "=== empty and malformed input ==="
for sub in on-prompt on-stop; do
  for input in '' 'not json' '{}' '{"prompt":"/sync y"}'; do
    rc=0; OUT="$(hook "$sub" "$input" 2>/dev/null)" || rc=$?
    assert_eq "$rc" "0" "$sub exits 0 on input '$input'"
    assert_eq "$OUT" "" "$sub prints nothing on input '$input'"
  done
done
assert_eq "$(sync_lines)" "2" "input without a session id writes no sync line"

report_results
