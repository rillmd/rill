#!/bin/bash
# test/cli/test-track-managed-gitignore.sh — track_managed gitignore mode
#
# By default the auto-generated .gitignore section hides managed files (and
# .rill/) from git, so the vault repo carries only user content. With
# "track_managed": true in .rill/config.json the same section stops listing
# them: a bare clone then carries the full Rill runtime, which is what cloud
# harness execution needs (the platform clones the repo; nothing runs
# `rill update` before the session starts).
#
# Load-bearing properties:
#   - default mode ignores .rill/ and every managed-files.txt entry
#   - track_managed=true drops those from the managed section but keeps
#     the derived index files ignored, in both modes
#   - user-added lines outside the markers survive regeneration
#   - the flag is reversible (true → false restores the default section)
#   - malformed config.json falls back to the default (ignore) mode
#
# Usage: bash test/cli/test-track-managed-gitignore.sh
# Requires: bash, git, jq. No claude CLI, no network.

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
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

# No sed gate: bin/rill routes all in-place edits through sed_inplace
# (GNU/BSD probe), so this suite runs on Linux CI as well.

# Hermetic environment (same pattern as test-cli-smoke.sh)
export HOME="$WORK/home"
mkdir -p "$HOME"
export RILL_SOURCE="$REPO_ROOT"
export EDITOR=true
unset RILL_HOME 2>/dev/null || true

VAULT="$WORK/vault"

# The managed section sits between these markers
section() { sed -n '/# >>> Rill managed/,/# <<< Rill managed/p' "$VAULT/.gitignore"; }

echo "=== default mode: managed files ignored ==="
rc=0; "$RILL" init "$VAULT" --name tracktest --no-default >/dev/null 2>&1 || rc=$?
assert_eq "$rc" "0" "rill init exits 0"
export RILL_HOME="$VAULT"
assert_file_exists "$VAULT/.gitignore" ".gitignore generated"
assert_true "section | grep -qx '.rill/'" "default: .rill/ is ignored"
assert_true "section | grep -q 'rill-core.md'" "default: managed rule files are ignored"
assert_true "section | grep -qx 'inbox/tweets/.index'" "default: derived index ignored"

echo ""
echo "=== track_managed=true: managed files visible to git ==="
tmp="$(mktemp)"
jq '.track_managed = true' "$VAULT/.rill/config.json" > "$tmp" && mv "$tmp" "$VAULT/.rill/config.json"
echo "my-personal-ignore/" >> "$VAULT/.gitignore"
rc=0; "$RILL" update --vault tracktest >/dev/null 2>&1 || rc=$?
assert_eq "$rc" "0" "rill update exits 0 with track_managed=true"
assert_true "! section | grep -qx '.rill/'" "track: .rill/ no longer ignored"
assert_true "! section | grep -q 'rill-core.md'" "track: managed rule files no longer ignored"
assert_true "section | grep -qx 'inbox/tweets/.index'" "track: derived index still ignored"
assert_true "section | grep -qx 'inbox/meetings/.index'" "track: meetings index still ignored"
assert_file_contains "$VAULT/.gitignore" "my-personal-ignore/" "user-added line survives regeneration"

# git actually sees the managed files now
git -C "$VAULT" init -q 2>/dev/null || true
assert_true "git -C '$VAULT' check-ignore -q .rill/version; [ \$? -ne 0 ]" "git does not ignore .rill/ in track mode"
assert_true "git -C '$VAULT' check-ignore -q .claude/rules/rill-core.md; [ \$? -ne 0 ]" "git does not ignore managed rules in track mode"
assert_true "git -C '$VAULT' check-ignore -q inbox/tweets/.index" "git still ignores the derived index in track mode"

# The CLI itself is projected into the clone-able runtime
assert_file_exists "$VAULT/.rill/bin/rill" "CLI projected to .rill/bin/rill"
assert_true "[ -x '$VAULT/.rill/bin/rill' ]" "projected CLI is executable"
assert_true "git -C '$VAULT' check-ignore -q .rill/bin/rill; [ \$? -ne 0 ]" "projected CLI is git-visible in track mode"
rc=0; RILL_HOME="$VAULT" "$VAULT/.rill/bin/rill" guard --help >/dev/null 2>&1 || rc=$?
assert_eq "$rc" "0" "projected CLI runs from inside the vault"

# The projected CLI is under guard protection (managed file)
assert_true "grep -qx '.rill/bin/rill' '$VAULT/.rill/managed-files.txt'" "projected CLI registered in managed-files.txt"
rc=0; RILL_HOME="$VAULT" "$RILL" guard ".rill/bin/rill" >/dev/null 2>&1 || rc=$?
assert_true "[ $rc -ne 0 ]" "rill guard blocks edits to the projected CLI"

# A second update must not falsely report the projected CLI as retired
rc=0; "$RILL" update --vault tracktest > "$WORK/second-update.txt" 2>&1 || rc=$?
assert_eq "$rc" "0" "second update exits 0"
assert_file_not_contains "$WORK/second-update.txt" "'.rill/bin/rill' is no longer managed" "no false stale report for the projected CLI"

# init from a projected CLI with no installed source is refused before writes
rc=0
env -u RILL_SOURCE HOME="$WORK/home" \
  "$VAULT/.rill/bin/rill" init "$WORK/newvault" --name refused --no-default >/dev/null 2>&1 || rc=$?
assert_true "[ $rc -ne 0 ]" "clone-local CLI refuses rill init without a real source"
assert_true "[ ! -d '$WORK/newvault/.rill' ]" "refused init leaves no partial vault behind"

# The PII allowlist must stay out of git even in track mode
echo "owner@example-own.jp" > "$VAULT/.rill/pii-allowlist.txt"
rc=0; "$RILL" update --vault tracktest >/dev/null 2>&1 || rc=$?
assert_eq "$rc" "0" "update succeeds with an allowlist present"
assert_true "git -C '$VAULT' check-ignore -q .rill/pii-allowlist.txt" "pii-allowlist stays git-ignored in track mode"

# A clone-local CLI must never treat .rill/ as a distribution source:
# with no installed source to fall back to, update refuses before
# touching managed-files.txt.
managed_before="$(wc -l < "$VAULT/.rill/managed-files.txt" | tr -d ' ')"
rc=0
env -u RILL_SOURCE HOME="$WORK/home" RILL_HOME="$VAULT" \
  "$VAULT/.rill/bin/rill" update --vault tracktest >/dev/null 2>&1 || rc=$?
assert_true "[ $rc -ne 0 ]" "clone-local CLI refuses to update without a real source"
managed_after="$(wc -l < "$VAULT/.rill/managed-files.txt" | tr -d ' ')"
assert_eq "$managed_after" "$managed_before" "managed-files.txt untouched by the refused update"

echo ""
echo "=== reversible: back to default ==="
git -C "$VAULT" add -A >/dev/null 2>&1
git -C "$VAULT" -c user.email=t@t -c user.name=t commit -qm "track managed" >/dev/null 2>&1
tmp="$(mktemp)"
jq '.track_managed = false' "$VAULT/.rill/config.json" > "$tmp" && mv "$tmp" "$VAULT/.rill/config.json"
rc=0; "$RILL" update --vault tracktest > "$WORK/revert-out.txt" 2>&1 || rc=$?
assert_eq "$rc" "0" "rill update exits 0 with track_managed=false"
assert_true "section | grep -qx '.rill/'" "revert: .rill/ ignored again"
assert_true "section | grep -q 'rill-core.md'" "revert: managed rules ignored again"
assert_file_contains "$VAULT/.gitignore" "my-personal-ignore/" "user-added line still present after revert"
assert_file_contains "$WORK/revert-out.txt" "still tracked" "flip-to-false warns that committed managed files stay tracked"
assert_file_contains "$WORK/revert-out.txt" "git rm -r -q --cached" "untrack guidance is shown"

echo ""
echo "=== malformed config falls back to default ==="
echo 'not json' > "$VAULT/.rill/config.json"
rc=0; "$RILL" update --vault tracktest >/dev/null 2>&1 || rc=$?
assert_eq "$rc" "0" "rill update survives malformed config.json"
assert_true "section | grep -qx '.rill/'" "malformed config: default (ignore) mode"

report_results
