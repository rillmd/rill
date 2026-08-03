#!/bin/bash
# test/cli/test-book-build.sh — `rill book build` smoke (no claude, no network)
#
# Covers:
#   - fixture book (test/fixtures/book) builds: exit 0, index + chapter pages
#   - frame structure: sidebar part label, section accordion, pager,
#     empty-receptacle state
#   - --out redirection
#   - error paths (all non-zero with a clear message): missing id, unknown id,
#     directory without _book.md, unknown option
#
# Usage: bash test/cli/test-book-build.sh
# Requires: bash, node (skips loudly when node is unavailable).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
RILL="$REPO_ROOT/bin/rill"

# shellcheck source=test/assertions/lib.sh
source "$SCRIPT_DIR/../assertions/lib.sh"

if ! command -v node >/dev/null 2>&1; then
  echo "SKIP: node not available; rill book build requires it"
  exit 0
fi

WORK="$(mktemp -d)"
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

mkdir -p "$WORK/vault/pages"
cp -R "$REPO_ROOT/test/fixtures/book" "$WORK/vault/pages/fixture-book"

# --- happy path (default out = pages/<id>/.view/) ---
RILL_HOME="$WORK/vault" "$RILL" book build fixture-book >/dev/null
VIEW="$WORK/vault/pages/fixture-book/.view"
assert_true "[ -f '$VIEW/index.html' ]" "index.html generated"
assert_true "[ -f '$VIEW/01-intro.html' ]" "chapter page generated"
assert_true "[ -f '$VIEW/02-details.html' ]" "second chapter page generated"
assert_true "grep -q 'class=\"part\"' '$VIEW/index.html'" "part label rendered in sidebar"
assert_true "grep -q 'Part I — Basics' '$VIEW/index.html'" "part text present"
assert_true "grep -q 'nav class=\"pager\"' '$VIEW/01-intro.html'" "pager present on chapter page"
assert_true "grep -q 'Next chapter' '$VIEW/01-intro.html'" "next-chapter link present"
assert_true "grep -q 'class=\"sec\"' '$VIEW/01-intro.html'" "current chapter sections expanded in sidebar"
assert_true "grep -q 'No pending proposals' '$VIEW/01-intro.html'" "empty receptacle state rendered"
assert_true "grep -q 'href=\"02-details.html\"' '$VIEW/01-intro.html'" "chapter .md link rewritten to .html"
assert_true "grep -q 'href=\"01-intro.html#s1-1\"' '$VIEW/02-details.html'" "fragment chapter link rewritten with fragment kept"
assert_true "grep -q 'href=\"../_book.md\"' '$VIEW/02-details.html'" "relative non-chapter link relocated one level up"
assert_true "grep -q 'id=\"R&D notes\"' '$VIEW/index.html'" "heading id decoded from entities"
assert_true "grep -q 'src=\"../assets/diagram.png\"' '$VIEW/02-details.html'" "image src relocated one level up"

# --- --out redirection ---
RILL_HOME="$WORK/vault" "$RILL" book build fixture-book --out "$WORK/out2" >/dev/null
assert_true "[ -f '$WORK/out2/index.html' ]" "--out redirects output"
assert_true "grep -q 'href=\"../vault/pages/fixture-book/_book.md\"' '$WORK/out2/02-details.html'" "custom --out computes the real relative path back to the source"
echo 'unrelated' > "$WORK/out2/keep.html"
RILL_HOME="$WORK/vault" "$RILL" book build fixture-book --out "$WORK/out2" >/dev/null
assert_true "[ -f '$WORK/out2/keep.html' ]" "cleanup only removes files with the generator marker"

# --- error paths ---
set +e
RILL_HOME="$WORK/vault" "$RILL" book build 2>"$WORK/e1" >/dev/null; rc1=$?
RILL_HOME="$WORK/vault" "$RILL" book build nope 2>"$WORK/e2" >/dev/null; rc2=$?
mkdir -p "$WORK/vault/pages/broken"
RILL_HOME="$WORK/vault" "$RILL" book build broken 2>"$WORK/e3" >/dev/null; rc3=$?
RILL_HOME="$WORK/vault" "$RILL" book build fixture-book --bogus 2>"$WORK/e4" >/dev/null; rc4=$?
set -e
assert_true "[ $rc1 -ne 0 ] && grep -q 'book id required' '$WORK/e1'" "missing id fails with message"
assert_true "[ $rc2 -ne 0 ] && grep -q 'no such book' '$WORK/e2'" "unknown id fails with message"
assert_true "[ $rc3 -ne 0 ] && grep -q '_book.md' '$WORK/e3'" "directory without _book.md fails"
assert_true "[ $rc4 -ne 0 ] && grep -q 'unknown option' '$WORK/e4'" "unknown option fails"

report_results
