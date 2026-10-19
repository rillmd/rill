#!/bin/bash
# test/cli/test-push-rebase.sh - `rill push` with several writers on one branch
#
# Two clones of one bare remote stand in for two writers (e.g. the Mac and a
# cloud session). Covered:
#   - a plain push carries a Rill-Writer trailer (RILL_WRITER, sanitized)
#   - a push behind the remote rebases onto it instead of failing
#   - appends to a merge=union file from both writers keep both lines
#   - a same-line edit aborts the rebase, keeps the commit local, exits
#     non-zero, names the file, and leaves the remote untouched (no force)
#   - a later run pushes a commit left local by an earlier failed run
#   - a push rejected because another writer pushed between fetch and push
#     is retried once and succeeds
#   - a rebase already in progress is refused
#   - unpushed merge commits are refused rather than flattened
#   - a push rejected by a hook shows the hook's message
#   - branch.<b>.pushRemote is honored (rebase and push go to that remote)
#   - RILL_PUSH_BRANCH sends a per-session branch's work to main, rebased
#     onto main, without creating the session branch on the remote
#   - an invalid RILL_PUSH_BRANCH is refused
#   - git config rill.writer is the writer when RILL_WRITER is unset
#   - a clean, up-to-date vault reports "Nothing to push."
#
# Usage: bash test/cli/test-push-rebase.sh
# Requires: bash, git. No claude CLI, no network.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
RILL="$REPO_ROOT/bin/rill"

# shellcheck source=test/assertions/lib.sh
source "$SCRIPT_DIR/../assertions/lib.sh"

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

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# Isolate from the user's git config (e.g. a global core.hooksPath would
# bypass the per-clone hooks these cases install).
export HOME="$WORK/home" GIT_CONFIG_NOSYSTEM=1
mkdir -p "$HOME"

git init -q --bare -b main "$WORK/remote.git"

SEED="$WORK/seed"
git init -q -b main "$SEED"
git -C "$SEED" config user.email seed@example.com
git -C "$SEED" config user.name "Seed"
mkdir -p "$SEED/.rill" "$SEED/knowledge/self"
echo "test" > "$SEED/.rill/version"
printf '# Activity Log\n\n- seed\n' > "$SEED/activity-log.md"
printf 'focus: one\n' > "$SEED/knowledge/self/current-state.md"
printf 'activity-log.md merge=union\n' > "$SEED/.gitattributes"
git -C "$SEED" add -A
git -C "$SEED" commit -q -m seed
git -C "$SEED" remote add origin "$WORK/remote.git"
git -C "$SEED" push -q -u origin main

clone() {
  local dir="$1" name="$2"
  git clone -q "$WORK/remote.git" "$dir"
  git -C "$dir" config user.email "$name@example.com"
  git -C "$dir" config user.name "$name"
}
clone "$WORK/a" a
clone "$WORK/b" b

push_a() { RILL_HOME="$WORK/a" RILL_WRITER="${1:-mac}" "$RILL" push 2>&1; }
push_b() { RILL_HOME="$WORK/b" RILL_WRITER="${1:-cloud}" "$RILL" push 2>&1; }
remote_head() { git -C "$WORK/remote.git" rev-parse main; }

# --- 1. plain push with a writer trailer ------------------------------------
echo "- a1" >> "$WORK/a/activity-log.md"
rc=0; out="$(push_a "mac book")" || rc=$?
assert_eq "$rc" "0" "plain push exits 0"
assert_out_contains "$out" "Pushed." "plain push reports success"
trailer="$(git -C "$WORK/remote.git" log -1 --format='%(trailers:key=Rill-Writer,valueonly)' main | tr -d '\n')"
assert_eq "$trailer" "mac_book" "commit carries the sanitized Rill-Writer trailer"

# --- 2. behind the remote, different files: rebase, then push --------------
mkdir -p "$WORK/b/inbox"
echo "note" > "$WORK/b/inbox/b1.md"
rc=0; out="$(push_b)" || rc=$?
assert_eq "$rc" "0" "push behind the remote exits 0"
assert_out_contains "$out" "Pushed." "push behind the remote reports success"
git -C "$WORK/remote.git" show main:activity-log.md | grep -qx -- "- a1" \
  && assert_true "true" "the earlier writer's line is still on the remote" \
  || assert_true "false" "the earlier writer's line is still on the remote"
merges="$(git -C "$WORK/remote.git" rev-list --merges --count main)"
assert_eq "$merges" "0" "history stays linear (no merge commits)"

# --- 3. both writers append to a merge=union file ---------------------------
rc=0; out="$(push_a)" || rc=$?   # bring a up to date
echo "- a2" >> "$WORK/a/activity-log.md"
echo "- b2" >> "$WORK/b/activity-log.md"
rc=0; out="$(push_a)" || rc=$?
assert_eq "$rc" "0" "first append push exits 0"
rc=0; out="$(push_b)" || rc=$?
assert_eq "$rc" "0" "second append push exits 0 (union applies during rebase)"
log_remote="$(git -C "$WORK/remote.git" show main:activity-log.md)"
assert_out_contains "$log_remote" "- a2" "union keeps the first writer's line"
assert_out_contains "$log_remote" "- b2" "union keeps the second writer's line"

# --- 4. same-line edit: abort, keep local, exit non-zero, no force ----------
rc=0; out="$(push_a)" || rc=$?   # bring a up to date
printf 'focus: from a\n' > "$WORK/a/knowledge/self/current-state.md"
printf 'focus: from b\n' > "$WORK/b/knowledge/self/current-state.md"
rc=0; out="$(push_a)" || rc=$?
assert_eq "$rc" "0" "first same-line edit pushes"
before="$(remote_head)"
rc=0; out="$(push_b)" || rc=$?
assert_true "[ $rc -ne 0 ]" "conflicting push exits non-zero"
assert_out_contains "$out" "knowledge/self/current-state.md" "conflict message names the file"
assert_out_contains "$out" "not pushed" "conflict message says nothing was pushed"
assert_eq "$(remote_head)" "$before" "remote is untouched by the conflicting writer"
inprog=0
[ -d "$WORK/b/.git/rebase-merge" ] || [ -d "$WORK/b/.git/rebase-apply" ] || inprog=1
assert_eq "$inprog" "1" "the rebase was aborted, not left in progress"
assert_eq "$(cat "$WORK/b/knowledge/self/current-state.md")" "focus: from b" "the local edit is still in the working tree"
assert_eq "$(git -C "$WORK/b" status --porcelain)" "" "the local edit is committed (working tree clean)"
assert_eq "$(git -C "$WORK/b" log -1 --format=%s -- knowledge/self/current-state.md | cut -c1-8)" "journal:" "the local commit holds the edit"

# --- 5. resolve by hand; a later run pushes the commit left local -----------
git -C "$WORK/b" fetch -q origin
git -C "$WORK/b" rebase -q origin/main >/dev/null 2>&1 || true
printf 'focus: from a and b\n' > "$WORK/b/knowledge/self/current-state.md"
git -C "$WORK/b" add knowledge/self/current-state.md
GIT_EDITOR=true git -C "$WORK/b" rebase --continue >/dev/null 2>&1
rc=0; out="$(push_b)" || rc=$?
assert_eq "$rc" "0" "push after a manual resolution exits 0"
assert_out_contains "$out" "Pushed." "a commit left local by an earlier run is pushed with no new changes"
assert_eq "$(git -C "$WORK/remote.git" show main:knowledge/self/current-state.md)" "focus: from a and b" "the resolved version reached the remote"

# --- 6. race: another writer pushes between fetch and push ------------------
rc=0; out="$(push_a)" || rc=$?   # bring a up to date
mkdir -p "$WORK/a/.git/hooks"
cat > "$WORK/a/.git/hooks/pre-push" <<HOOK
#!/bin/bash
# First invocation only: let writer b push first, so a's push is rejected.
[ -f "$WORK/race-done" ] && exit 0
touch "$WORK/race-done"
env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE -u GIT_PREFIX bash -c '
  echo "- b-race" >> "$WORK/b/activity-log.md"
  git -C "$WORK/b" add -A && git -C "$WORK/b" commit -q -m race
  git -C "$WORK/b" push -q origin main
' >/dev/null 2>&1
exit 0
HOOK
chmod +x "$WORK/a/.git/hooks/pre-push"
echo "- a-race" >> "$WORK/a/activity-log.md"
rc=0; out="$(push_a)" || rc=$?
assert_eq "$rc" "0" "push rejected by a race is retried and succeeds"
log_remote="$(git -C "$WORK/remote.git" show main:activity-log.md)"
assert_out_contains "$log_remote" "- a-race" "the retried push carries the writer's line"
assert_out_contains "$log_remote" "- b-race" "the racing writer's line survives"
rm -f "$WORK/a/.git/hooks/pre-push"

# --- 7. a rebase already in progress is refused -----------------------------
mkdir -p "$WORK/a/.git/rebase-merge"
rc=0; out="$(push_a)" || rc=$?
assert_true "[ $rc -ne 0 ]" "push refuses while a rebase is in progress"
assert_out_contains "$out" "rebase is already in progress" "refusal explains the in-progress rebase"
rmdir "$WORK/a/.git/rebase-merge"

# --- 8. nothing to push -----------------------------------------------------
rc=0; out="$(push_a)" || rc=$?
assert_eq "$rc" "0" "an up-to-date vault exits 0"
assert_out_contains "$out" "Nothing to push." "an up-to-date vault reports nothing to push"

# --- 9. unpushed merge commits are refused, not flattened ------------------
git -C "$WORK/a" checkout -q -b side
echo "side" > "$WORK/a/side.md"
git -C "$WORK/a" add side.md && git -C "$WORK/a" commit -q -m side
git -C "$WORK/a" checkout -q main
echo "- a-main" >> "$WORK/a/activity-log.md"
git -C "$WORK/a" commit -q -am main-side
git -C "$WORK/a" merge -q --no-ff -m merge side
rc=0; out="$(push_b)" || rc=$?   # advance the remote
echo "- b-advance" >> "$WORK/b/activity-log.md"
rc=0; out="$(push_b)" || rc=$?
before="$(remote_head)"
rc=0; out="$(push_a)" || rc=$?
assert_true "[ $rc -ne 0 ]" "push refuses to rebase unpushed merge commits"
assert_out_contains "$out" "merge commits" "refusal explains the merge commits"
assert_eq "$(remote_head)" "$before" "remote is untouched when merges are refused"
assert_file_exists "$WORK/a/side.md" "the merged file is still in the working tree"
git -C "$WORK/a" pull -q --no-rebase --no-edit origin main >/dev/null 2>&1
git -C "$WORK/a" push -q origin main

# --- 10. a hook's rejection message is shown -------------------------------
rc=0; out="$(push_a)" || rc=$?   # bring a up to date
printf '#!/bin/bash\necho "blocked by test hook" >&2\nexit 1\n' > "$WORK/a/.git/hooks/pre-push"
chmod +x "$WORK/a/.git/hooks/pre-push"
echo "- a-hook" >> "$WORK/a/activity-log.md"
rc=0; out="$(push_a)" || rc=$?
assert_true "[ $rc -ne 0 ]" "push rejected by a hook exits non-zero"
assert_out_contains "$out" "blocked by test hook" "the hook's message reaches the user"
rm -f "$WORK/a/.git/hooks/pre-push"
rc=0; out="$(push_a)" || rc=$?
assert_eq "$rc" "0" "the commit kept by the hook rejection is pushed next time"

# --- 11. branch.<b>.pushRemote is honored ----------------------------------
git clone -q --bare "$WORK/remote.git" "$WORK/private.git"
git -C "$WORK/b" remote add private "$WORK/private.git"
git -C "$WORK/b" config branch.main.pushRemote private
origin_before="$(remote_head)"
echo "- b-private" >> "$WORK/b/activity-log.md"
rc=0; out="$(push_b)" || rc=$?
assert_eq "$rc" "0" "push to the configured pushRemote exits 0"
assert_eq "$(remote_head)" "$origin_before" "origin is untouched when pushRemote names another remote"
assert_out_contains "$(git -C "$WORK/private.git" show main:activity-log.md)" "- b-private" "the commit reached the pushRemote"

# --- 12. RILL_PUSH_BRANCH: a per-session branch pushes to main ------------
clone "$WORK/c" c
git -C "$WORK/c" checkout -q -b claude/session-1
rc=0; out="$(push_a)" || rc=$?   # advance origin/main past c's base
echo "- a-before-cloud" >> "$WORK/a/activity-log.md"
rc=0; out="$(push_a)" || rc=$?
echo "- cloud" >> "$WORK/c/activity-log.md"
rc=0; out="$(RILL_HOME="$WORK/c" RILL_WRITER=cloud RILL_PUSH_BRANCH=main "$RILL" push 2>&1)" || rc=$?
assert_eq "$rc" "0" "push with RILL_PUSH_BRANCH=main exits 0"
log_remote="$(git -C "$WORK/remote.git" show main:activity-log.md)"
assert_out_contains "$log_remote" "- cloud" "the session branch's line reached main"
assert_out_contains "$log_remote" "- a-before-cloud" "main's newer line survives (rebased, not overwritten)"
assert_eq "$(git -C "$WORK/remote.git" branch --list 'claude/*')" "" "the session branch is not created on the remote"
trailer="$(git -C "$WORK/remote.git" log -1 --format='%(trailers:key=Rill-Writer,valueonly)' main | tr -d '\n')"
assert_eq "$trailer" "cloud" "the cloud commit carries its writer"
rc=0; out="$(RILL_HOME="$WORK/c" RILL_PUSH_BRANCH=main "$RILL" push 2>&1)" || rc=$?
assert_out_contains "$out" "Nothing to push." "a second run with nothing new reports nothing to push"

# A single-branch clone of the session branch still rebases onto main.
git -C "$WORK/remote.git" branch claude/session-2 main
git clone -q --single-branch -b claude/session-2 "$WORK/remote.git" "$WORK/d"
git -C "$WORK/d" config user.email "d@example.com"; git -C "$WORK/d" config user.name d
echo "- a-after-d-clone" >> "$WORK/a/activity-log.md"
rc=0; out="$(push_a)" || rc=$?
echo "- single-branch" >> "$WORK/d/activity-log.md"
rc=0; out="$(RILL_HOME="$WORK/d" RILL_PUSH_BRANCH=main "$RILL" push 2>&1)" || rc=$?
assert_eq "$rc" "0" "a single-branch clone pushes to main with RILL_PUSH_BRANCH"
log_remote="$(git -C "$WORK/remote.git" show main:activity-log.md)"
assert_out_contains "$log_remote" "- single-branch" "the single-branch clone's line reached main"
assert_out_contains "$log_remote" "- a-after-d-clone" "main's newer line survives the single-branch push"

rc=0; out="$(RILL_HOME="$WORK/c" RILL_PUSH_BRANCH='bad..name' "$RILL" push 2>&1)" || rc=$?
assert_true "[ $rc -ne 0 ]" "an invalid RILL_PUSH_BRANCH is refused"

# --- 13. git config rill.writer ---------------------------------------------
git -C "$WORK/c" config rill.writer configured-writer
echo "- configured" >> "$WORK/c/activity-log.md"
rc=0; out="$(unset RILL_WRITER; RILL_HOME="$WORK/c" RILL_PUSH_BRANCH=main "$RILL" push 2>&1)" || rc=$?
trailer="$(git -C "$WORK/remote.git" log -1 --format='%(trailers:key=Rill-Writer,valueonly)' main | tr -d '\n')"
assert_eq "$trailer" "configured-writer" "rill.writer names the writer when RILL_WRITER is unset"

echo ""
report_results
