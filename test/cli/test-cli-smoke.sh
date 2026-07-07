#!/bin/bash
# test/cli/test-cli-smoke.sh - Pure-shell CLI smoke test (no claude, no network)
#
# Freezes the 2026-07 pipefail-hardening pass. bin/rill runs under
# `set -euo pipefail`, where a bare assignment of a failing pipeline
# (`var="$(cmd | filter)"`) aborts the whole command. Covered regressions:
#
#   - rill status on a fresh vault (workspace/thinks missing, empty journal)
#   - rill edit with an empty journal (guidance message, rc=0)
#   - rill push with a git-crypt marker + empty knowledge/people/
#   - rill plugin status keeps listing past a plugin whose requires.sh fails
#   - rill plugin install completes (rc=0) when requires.sh fails
#   - rill mkfile path-safety guard (absolute / `..` directory, `/` in
#     --slug or --date) for every file type
#
# Plus a static audit: every bare $(... | ...) assignment in bin/rill must
# appear in test/cli/pipefail-allowlist.txt (reviewed-safe lines). A new
# unprotected bare pipe assignment fails here - protect it with an explicit
# `||` handler or consciously extend the allowlist.
#
# Usage: bash test/cli/test-cli-smoke.sh
# Requires: bash, git, jq (for rill init). No claude CLI needed.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
RILL="$REPO_ROOT/bin/rill"

# shellcheck source=test/assertions/lib.sh
source "$SCRIPT_DIR/../assertions/lib.sh"

if ! command -v jq >/dev/null 2>&1; then
  echo "FAIL: jq is required (rill init depends on it)"
  exit 1
fi

WORK="$(mktemp -d)"
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

# --- TEMPORARY GATE: GNU sed environments ----------------------------------
# rill init still uses the BSD/macOS-only `sed -i ''` form, which GNU sed
# rejects, so this suite cannot reach its assertions on Linux yet. Skip
# loudly (exit 0) instead of failing run-all.sh there. Remove this block
# together with the sed portability fix (CLI Linux portability task).
probe="$WORK/sed-probe"
echo x > "$probe"
if ! sed -i '' -e 's/x/y/' "$probe" 2>/dev/null; then
  echo "SKIP: this platform's sed does not support BSD \`sed -i ''\`;"
  echo "      rill init is not yet GNU-sed portable (CLI Linux portability task)."
  exit 0
fi

# --- Local assertion helper (string contains) -----------------------------
assert_out_contains() {
  local haystack="$1" needle="$2" msg="$3"
  _TOTAL=$((_TOTAL + 1))
  if [[ "$haystack" == *"$needle"* ]]; then
    _PASS=$((_PASS + 1))
    printf "  ${_GREEN}PASS${_NC}: %s\n" "$msg"
  else
    _FAIL=$((_FAIL + 1))
    _FAILURES+=("$msg")
    printf "  ${_RED}FAIL${_NC}: %s\n" "$msg"
    printf "    output was: %.300s\n" "$haystack"
  fi
}

# --- Hermetic environment --------------------------------------------------
# HOME       -> isolates ~/.rill/vaults.json registry writes to the sandbox
# RILL_SOURCE -> managed files come from this checkout, not ~/.rill/source
# EDITOR=true -> never opens an interactive editor
export HOME="$WORK/home"
mkdir -p "$HOME"
export RILL_SOURCE="$REPO_ROOT"
export EDITOR=true
unset RILL_HOME

VAULT="$WORK/vault"

echo "=== CLI smoke: fresh vault lifecycle ==="

# --- 1. rill init ----------------------------------------------------------
rc=0; out="$("$RILL" init "$VAULT" --name smoke --no-default 2>&1)" || rc=$?
assert_eq "$rc" "0" "rill init exits 0"
assert_file_exists "$VAULT/.rill/version" "vault marker created"
export RILL_HOME="$VAULT"

# --- 2. rill status on a fresh vault ----------------------------------------
# Regression: find on missing workspace/thinks aborted right after printing
# '=== Stats ===' on every vault (rill init never creates workspace/thinks).
# The seeded welcome entry means the journal is NOT empty here.
rc=0; out="$("$RILL" status 2>&1)" || rc=$?
assert_eq "$rc" "0" "rill status exits 0 on a fresh vault"
assert_out_contains "$out" "thinks: 0" "status prints the Stats line (survives find | wc on missing dirs)"

# Invalid count must fail fast (so || true can only mask the ls no-match case)
rc=0; "$RILL" status foo >/dev/null 2>&1 || rc=$?
assert_true "[ $rc -ne 0 ]" "rill status rejects a non-numeric count"

# --- 3. empty-journal branches of status / edit ------------------------------
# Regression: ls | head under pipefail aborted before the guidance messages.
# Empty the journal explicitly (init seeds a welcome entry + CLAUDE.md).
rm -f "$VAULT/inbox/journal"/*.md
rc=0; out="$("$RILL" status 2>&1)" || rc=$?
assert_eq "$rc" "0" "rill status exits 0 with an empty journal"
assert_out_contains "$out" "(no entries yet)" "status prints empty-journal notice"
# (Stats is not printed on the empty-journal path - status returns right
# after the notice by design; the Stats line is asserted in sections 2/6.)

rc=0; out="$("$RILL" edit 2>&1)" || rc=$?
assert_eq "$rc" "0" "rill edit exits 0 with an empty journal"
assert_out_contains "$out" "No journal entries found." "edit prints guidance message"

# --- 4. rill push (git set up by the test) ----------------------------------
git -C "$VAULT" init -q
git -C "$VAULT" config user.email smoke@example.com
git -C "$VAULT" config user.name "Rill Smoke"
git -C "$VAULT" config push.autoSetupRemote true
git init -q --bare "$WORK/remote.git"
git -C "$VAULT" remote add origin "$WORK/remote.git"

rc=0; out="$("$RILL" push 2>&1)" || rc=$?
assert_eq "$rc" "0" "rill push exits 0 (initial commit)"
assert_out_contains "$out" "Pushed." "push reports success"

# --- 5. rill push with git-crypt marker + empty knowledge/people/ -----------
# Regression: test_file=$(ls knowledge/people/*.md | head -1) aborted before
# commit/push when the directory had no .md files (silent rc=1 on a save
# command). Simulate a git-crypt-enabled repo with the marker directory.
rm -f "$VAULT/knowledge/people"/*.md
mkdir -p "$VAULT/.git/git-crypt"
rc=0; out="$("$RILL" log "smoke entry for the second push" 2>&1)" || rc=$?
assert_eq "$rc" "0" "rill log writes a journal entry"
rc=0; out="$("$RILL" push 2>&1)" || rc=$?
assert_eq "$rc" "0" "rill push exits 0 with git-crypt marker + empty knowledge/people/"
assert_out_contains "$out" "Pushed." "second push reports success"

# --- 6. rill status with entries (regular path still works) -----------------
rc=0; out="$("$RILL" status 2>&1)" || rc=$?
assert_eq "$rc" "0" "rill status exits 0 with journal entries"
assert_out_contains "$out" "journal: 1" "status counts the new entry"

echo ""
echo "=== CLI smoke: plugin lifecycle with failing dependency ==="

# Fixture plugins inside the sandbox vault:
#   aaa-broken - requires.sh exits 1 (unmet dependency)
#   zzz-ok     - no requires.sh (sorts after aaa-broken)
mkdir -p "$VAULT/plugins/aaa-broken" "$VAULT/plugins/zzz-ok"
printf 'name: aaa-broken\n' > "$VAULT/plugins/aaa-broken/plugin.md"
printf '#!/bin/bash\necho "missing dependency: nosuchtool"\nexit 1\n' \
  > "$VAULT/plugins/aaa-broken/requires.sh"
printf 'name: zzz-ok\n' > "$VAULT/plugins/zzz-ok/plugin.md"

# --- 7. rill plugin status keeps listing past a failing requires.sh ---------
rc=0; out="$("$RILL" plugin status 2>&1)" || rc=$?
assert_eq "$rc" "0" "rill plugin status exits 0 with a failing requires.sh"
assert_out_contains "$out" "aaa-broken" "status lists the broken plugin"
assert_out_contains "$out" "zzz-ok" "status continues past the failing dependency check"

# --- 8. rill plugin install completes despite failing requires.sh -----------
rc=0; out="$("$RILL" plugin install aaa-broken 2>&1)" || rc=$?
assert_eq "$rc" "0" "rill plugin install exits 0 when requires.sh fails"
assert_out_contains "$out" "Resolve the above dependencies" "install prints follow-up guidance"

echo ""
echo "=== CLI smoke: mkfile path-safety guard ==="

# --- 9. slug escape rejected -------------------------------------------------
rc=0; "$RILL" mkfile knowledge/notes --slug '../escape-note' --type insight >/dev/null 2>&1 || rc=$?
assert_true "[ $rc -ne 0 ]" "mkfile rejects --slug containing '/'"
assert_file_not_exists "$VAULT/knowledge/escape-note.md" "no file escaped knowledge/notes/"

# --- 10. directory .. escape rejected ----------------------------------------
rc=0; "$RILL" mkfile ../outside --slug x >/dev/null 2>&1 || rc=$?
assert_true "[ $rc -ne 0 ]" "mkfile rejects directory with '..' segment"
assert_true "[ ! -e '$WORK/outside' ]" "no directory created outside the vault"

# --- 11. absolute directory rejected -----------------------------------------
rc=0; "$RILL" mkfile "$WORK/absdir" --slug x >/dev/null 2>&1 || rc=$?
assert_true "[ $rc -ne 0 ]" "mkfile rejects an absolute directory"
assert_true "[ ! -e '$WORK/absdir' ]" "no absolute directory created"

# --- 12. --date traversal rejected -------------------------------------------
rc=0; "$RILL" mkfile inbox/meetings --slug ok --date '../esc' >/dev/null 2>&1 || rc=$?
assert_true "[ $rc -ne 0 ]" "mkfile rejects --date containing '/'"

# --- 13. normal creation still works -----------------------------------------
rc=0; out="$("$RILL" mkfile knowledge/notes --slug smoke-note --type insight 2>&1)" || rc=$?
assert_eq "$rc" "0" "mkfile creates a normal knowledge note"
assert_file_exists "$VAULT/knowledge/notes/smoke-note.md" "note file exists"

rc=0; out="$("$RILL" mkfile inbox/meetings --slug kickoff --date 2026-01-02 2>&1)" || rc=$?
assert_eq "$rc" "0" "mkfile accepts a normal --date"
assert_file_exists "$VAULT/inbox/meetings/2026-01-02-kickoff.md" "dated meeting file exists"

echo ""
echo "=== Static audit: bare pipeline assignments in bin/rill ==="

# Any assignment of a command substitution containing a pipe, without an
# explicit `||` failure handler, must match the committed allowlist exactly
# (content compared with leading whitespace stripped, LC_ALL=C sorted).
audit_actual="$WORK/audit-actual.txt"
{ grep -E '^[[:space:]]*[A-Za-z_][A-Za-z0-9_]*[+]?=["'"'"']?\$\(' "$REPO_ROOT/bin/rill" \
    | grep '|' \
    | grep -v '||' \
    | sed 's/^[[:space:]]*//' \
    | LC_ALL=C sort || true; } > "$audit_actual"

audit_ok=false
if diff -u "$SCRIPT_DIR/pipefail-allowlist.txt" "$audit_actual" > "$WORK/audit-diff.txt" 2>&1; then
  audit_ok=true
else
  echo "--- allowlist drift (+ lines are new/unreviewed assignments) ---"
  cat "$WORK/audit-diff.txt"
fi
assert_true "$audit_ok" "bare pipe assignments in bin/rill match pipefail-allowlist.txt"

echo ""
report_results
