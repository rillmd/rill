#!/bin/bash
# test/cli/test-pii-regex-guard.sh — pii-regex-guard.sh stdin/tree behavior
#
# Regression suite for the guard that CI runs over the tree and over PR
# commit messages. The load-bearing properties:
#   - the built-in noreply exemption lets Claude Code's Co-Authored-By
#     trailer (noreply@anthropic.com) and GitHub's anonymized commit
#     addresses (*@users.noreply.github.com) through in BOTH modes — these
#     appear in every Claude-authored commit message, and without the
#     exemption every such PR fails the commit-message scan (the 2026-08-10
#     PR #83 failure)
#   - the exemption is full-match-anchored: lookalikes that extend the local
#     part or swap the domain still fail
#   - everything else (personal-looking emails, phones, secrets) still fails
#     in --stdin mode, where the path allowlist does not apply
#   - tree mode honors the exemption path-independently, and still enforces
#     the per-path allowlist for all other hits
#
# Usage: bash test/cli/test-pii-regex-guard.sh
# Requires: bash, git. No claude CLI, no network.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
GUARD="$REPO_ROOT/test/cli/pii-regex-guard.sh"

# shellcheck source=test/assertions/lib.sh
source "$SCRIPT_DIR/../assertions/lib.sh"

WORK="$(mktemp -d)"
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

# stdin mode needs a CWD inside some git repo (the script resolves the repo
# root before reading stdin); the real repo works and its tree is not read.
run_stdin() {
  local rc=0
  (cd "$REPO_ROOT" && bash "$GUARD" --stdin) > "$WORK/out.txt" 2>&1 || rc=$?
  echo "$rc"
}

echo "=== stdin mode: noreply exemption ==="

rc="$(printf 'Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>\n' | run_stdin)"
assert_eq "$rc" "0" "Claude Code co-author trailer passes"

rc="$(printf 'Co-authored-by: octocat <octocat@users.noreply.github.com>\n' | run_stdin)"
assert_eq "$rc" "0" "GitHub anonymized commit address passes"

rc="$(printf 'Co-authored-by: octocat <12345+octocat@users.noreply.github.com>\n' | run_stdin)"
assert_eq "$rc" "0" "GitHub id+login anonymized address passes"

echo ""
echo "=== stdin mode: exemption anchoring ==="

rc="$(printf 'Contact: foo.noreply@anthropic.com\n' | run_stdin)"
assert_eq "$rc" "1" "extended local part (foo.noreply@) still fails"

rc="$(printf 'Contact: noreply@fixture.example\n' | run_stdin)"
assert_eq "$rc" "1" "noreply local part on another domain still fails"

rc="$(printf 'noreply@anthropic.com and alice@fixture.example\n' | run_stdin)"
assert_eq "$rc" "1" "safe address sharing a line with an unsafe one still fails"

# The combined pattern is leftmost-longest: an email match can shadow an
# overlapping phone/secret match, so a value smuggled into the local part of
# a safe-shaped address must be re-caught inside the match.
rc="$(printf 'Co-authored-by: x <ghp_abcdefghijklmnopqrst@users.noreply.github.com>\n' | run_stdin)"
assert_eq "$rc" "1" "secret token as safe-address local part still fails"

rc="$(printf 'Co-authored-by: x <090-1234-5678@users.noreply.github.com>\n' | run_stdin)"
assert_eq "$rc" "1" "phone number as safe-address local part still fails"

echo ""
echo "=== stdin mode: non-email patterns unaffected ==="

rc="$(printf 'Reach me at alice@fixture.example\n' | run_stdin)"
assert_eq "$rc" "1" "personal-shaped email fails"
assert_file_contains "$WORK/out.txt" "alice@fixture" "violation output names the offending line"

rc="$(printf 'Call 090-1234-5678 tomorrow\n' | run_stdin)"
assert_eq "$rc" "1" "phone number fails"

rc="$(printf 'token ghp_abcdefghijklmnopqrst0123456789ABCDEF\n' | run_stdin)"
assert_eq "$rc" "1" "secret-shaped token fails"

rc="$(printf 'a normal commit message\n\nwith body text only\n' | run_stdin)"
assert_eq "$rc" "0" "clean text passes"

rc="$(printf 'fix guard\n\nCo-Authored-By: Claude Fable 5 <noreply@anthropic.com>\n' | run_stdin)"
assert_eq "$rc" "0" "realistic Claude commit message passes end-to-end"

echo ""
echo "=== tree mode: exemption + allowlist ==="

TREE="$WORK/scratch"
mkdir -p "$TREE/test"
git -C "$TREE" init -q

# No commits are made in the scratch repo — `git add` alone is enough for
# `git ls-files`, so no git identity is configured.
run_tree() {
  local rc=0
  (cd "$TREE" && bash "$GUARD") > "$WORK/tree-out.txt" 2>&1 || rc=$?
  echo "$rc"
}

printf 'docs quoting Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>\n' > "$TREE/README.md"
git -C "$TREE" add -A
rc="$(run_tree)"
assert_eq "$rc" "0" "tree: noreply trailer passes with no allowlist entry"

printf 'contact alice@fixture.example here\n' > "$TREE/note.md"
git -C "$TREE" add -A
rc="$(run_tree)"
assert_eq "$rc" "1" "tree: unallowlisted email fails"
assert_file_contains "$WORK/tree-out.txt" "note.md" "tree violation names the file"

printf 'note.md\t@fixture\\.example\tsynthetic placeholder\n' > "$TREE/test/pii-regex-allowlist.txt"
git -C "$TREE" add -A
rc="$(run_tree)"
assert_eq "$rc" "0" "tree: allowlisted email passes"

report_results
