#!/bin/bash
# test/cli/test-autosync.sh - `rill autosync` (hooks, GUI timer, jobs)
#
# Two clones of one bare remote stand in for the Mac and another writer.
# Covered:
#   - run --json pushes local changes and reports status/exit/pulled
#   - check --json sees the remote move (ls-remote only), local changes and
#     unpushed commits, without fetching
#   - run brings in another writer's commit and counts it as pulled
#   - hook-stop returns at once; the background run finishes even when the
#     hook's process group is killed right away
#   - a failed run is reported once as a systemMessage by the next hook call
#   - nothing runs when the checkout is not on the sync branch
#   - RILL_AUTOSYNC=0 turns the hook modes off
#   - CLAUDE_CODE_REMOTE=true sends a per-session branch's work to main
#   - pause holds runs while the pausing process lives
#   - a lock left by a dead process is taken over
#   - hook-stop right after a push is delayed, not dropped
#   - cloud commits carry a Claude-Session link (valid ids only)
#   - a run that waited for the lock is re-checked (pause, branch)
#   - the sync branch is the destination whatever the upstream says
#   - colored hook output still yields valid JSON
#   - pauses are per process
#   - check reports HEAD behind its tracking ref
#   - run --if-idle skips while a session is mid-turn (decided under the lock)
#
# Usage: bash test/cli/test-autosync.sh
# Requires: bash, git, perl. No claude CLI, no network.

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

export HOME="$WORK/home" GIT_CONFIG_NOSYSTEM=1
mkdir -p "$HOME"
unset RILL_WRITER RILL_PUSH_BRANCH CLAUDE_CODE_REMOTE RILL_AUTOSYNC

git init -q --bare -b main "$WORK/remote.git"

SEED="$WORK/seed"
git init -q -b main "$SEED"
git -C "$SEED" config user.email seed@example.com
git -C "$SEED" config user.name "Seed"
mkdir -p "$SEED/.rill" "$SEED/knowledge/self"
echo "test" > "$SEED/.rill/version"
printf 'focus: one\n' > "$SEED/knowledge/self/current-state.md"
git -C "$SEED" add -A
git -C "$SEED" commit -q -m seed
git -C "$SEED" remote add origin "$WORK/remote.git"
git -C "$SEED" push -q -u origin HEAD

clone() {
  local dir="$1" name="$2"
  git clone -q "$WORK/remote.git" "$dir"
  git -C "$dir" config user.email "$name@example.com"
  git -C "$dir" config user.name "$name"
  git -C "$dir" config rill.writer "$name"
}
clone "$WORK/a" mac
clone "$WORK/b" other

as_a() { RILL_HOME="$WORK/a" "$RILL" autosync "$@" 2>&1; }
push_b() { RILL_HOME="$WORK/b" "$RILL" push >/dev/null 2>&1; }
remote_head() { git -C "$WORK/remote.git" rev-parse main; }
remote_has() { git -C "$WORK/remote.git" show "main:$1" >/dev/null 2>&1; }
wait_remote_has() {
  local _
  for _ in $(seq 1 40); do
    remote_has "$1" && return 0
    sleep 0.5
  done
  return 1
}

# --- 1. run --json pushes ---------------------------------------------------
echo one > "$WORK/a/n1.md"
rc=0; out="$(as_a run --json)" || rc=$?
assert_eq "$rc" "0" "run exits 0"
assert_out_contains "$out" '"status":"pushed"' "run reports pushed"
assert_out_contains "$out" '"exit":0' "run reports exit 0"
assert_true "remote_has n1.md" "the change is on the remote"
out="$(as_a status --json)"
assert_out_contains "$out" '"status":"pushed"' "status shows the last run"

# --- 2. check: remote moved, local changes, unpushed ------------------------
echo two > "$WORK/b/n2.md"; push_b
before_track="$(git -C "$WORK/a" rev-parse origin/main)"
out="$(as_a check --json)"
assert_out_contains "$out" '"remote_moved":true' "check sees the remote move"
assert_out_contains "$out" '"dirty":false' "check sees a clean tree"
assert_eq "$(git -C "$WORK/a" rev-parse origin/main)" "$before_track" "check fetches nothing"
echo three > "$WORK/a/n3.md"
out="$(as_a check --json)"
assert_out_contains "$out" '"dirty":true' "check sees local changes"
git -C "$WORK/a" add n3.md; git -C "$WORK/a" commit -q -m local
out="$(as_a check --json)"
assert_out_contains "$out" '"unpushed":1' "check counts unpushed commits"

# --- 3. run pulls another writer's commit ---------------------------------
rc=0; out="$(as_a run --json)" || rc=$?
assert_eq "$rc" "0" "run after the remote moved exits 0"
assert_out_contains "$out" '"pulled":1' "run counts the other writer's commit as pulled"
assert_true "[ -f '$WORK/a/n2.md' ]" "the other writer's file is in the working tree"
out="$(as_a check --json)"
assert_out_contains "$out" '"remote_moved":false' "after run the remote matches"

# --- 4. hook-stop returns at once; the run outlives the hook --------------
echo four > "$WORK/a/n4.md"
t0="$(date +%s)"
RILL_HOME="$WORK/a" perl -e 'setpgrp(0,0); system(@ARGV); kill("TERM", -getpgrp());' \
  bash -c "echo '{}' | '$RILL' autosync hook-stop" >/dev/null 2>&1 || true
t1="$(date +%s)"
assert_true "[ $((t1 - t0)) -le 2 ]" "hook-stop returns without waiting for the push"
assert_true "wait_remote_has n4.md" "the background run pushed after the hook's group was killed"
sleep 1
assert_true "[ ! -d '$WORK/a/.git/rill-autosync.lock' ]" "the lock is released"

# --- 5. a failure is reported once ----------------------------------------
as_a run >/dev/null || true
printf 'focus: from b\n' > "$WORK/b/knowledge/self/current-state.md"; push_b
printf 'focus: from a\n' > "$WORK/a/knowledge/self/current-state.md"
rc=0; out="$(as_a run --json)" || rc=$?
assert_true "[ $rc -ne 0 ]" "a conflicting run exits non-zero"
assert_out_contains "$out" '"status":"failed"' "the conflicting run reports failed"
out="$(echo '{}' | RILL_HOME="$WORK/a" RILL_AUTOSYNC=1 "$RILL" autosync hook-start 2>&1 || true)"
assert_out_contains "$out" '"systemMessage"' "the next hook reports the failure"
assert_out_contains "$out" "knowledge/self/current-state.md" "the report names the file"
printf 'focus: from b\n' > "$WORK/a/knowledge/self/current-state.md"
git -C "$WORK/a" fetch -q origin
git -C "$WORK/a" reset -q --hard origin/main
out="$(echo '{}' | RILL_HOME="$WORK/a" "$RILL" autosync hook-start 2>&1 || true)"
assert_eq "$out" "" "a successful hook-start prints nothing"

# --- 6. not on the sync branch: nothing runs -----------------------------
git -C "$WORK/a" switch -q -c feature
echo five > "$WORK/a/n5.md"
out="$(echo '{}' | RILL_HOME="$WORK/a" "$RILL" autosync hook-start 2>&1 || true)"
assert_eq "$(git -C "$WORK/a" status --porcelain)" "?? n5.md" "hook-start on a feature branch commits nothing"
out="$(as_a run --json)"
assert_out_contains "$out" '"status":"skipped"' "run on a feature branch reports skipped"
rm -f "$WORK/a/n5.md"
git -C "$WORK/a" switch -q main

# --- 7. RILL_AUTOSYNC=0 turns the hooks off ------------------------------
echo six > "$WORK/a/n6.md"
echo '{}' | RILL_HOME="$WORK/a" RILL_AUTOSYNC=0 "$RILL" autosync hook-start >/dev/null 2>&1 || true
assert_true "! remote_has n6.md" "RILL_AUTOSYNC=0 hook-start pushes nothing"
rm -f "$WORK/a/n6.md"

# --- 8. cloud session branch goes to main ---------------------------------
clone "$WORK/c" cloud
git -C "$WORK/c" switch -q -c claude/session-x
echo seven > "$WORK/c/n7.md"
echo '{}' | RILL_HOME="$WORK/c" CLAUDE_CODE_REMOTE=true "$RILL" autosync hook-start >/dev/null 2>&1 || true
assert_true "remote_has n7.md" "the cloud session's work reached main"
assert_true "! git -C '$WORK/remote.git' rev-parse -q --verify refs/heads/claude/session-x >/dev/null" "no session branch was created on the remote"

# --- 9. pause holds runs while the pausing process lives -------------------
as_a run >/dev/null || true
( RILL_HOME="$WORK/a" "$RILL" autosync pause; sleep 3 ) &
pauser=$!
sleep 1
echo eight > "$WORK/a/n8.md"
out="$(as_a run --json)"
assert_out_contains "$out" '"status":"skipped"' "run while paused is skipped"
assert_out_contains "$out" "paused" "the skip names the pause"
wait "$pauser"
out="$(as_a run --json)"
assert_out_contains "$out" '"status":"pushed"' "run after the pausing process ended pushes"

# --- 10. a dead holder's lock is taken over -------------------------------
mkdir "$WORK/a/.git/rill-autosync.lock"
echo 999999 > "$WORK/a/.git/rill-autosync.lock/pid"
echo nine > "$WORK/a/n9.md"
rc=0; out="$(as_a run --json)" || rc=$?
assert_out_contains "$out" '"status":"pushed"' "a stale lock is taken over"

# --- 11. hook-stop right after a push is delayed, not dropped -------------
echo ten > "$WORK/a/n10.md"
echo '{}' | RILL_HOME="$WORK/a" "$RILL" autosync hook-stop >/dev/null 2>&1
echo '{}' | RILL_HOME="$WORK/a" "$RILL" autosync hook-stop >/dev/null 2>&1
assert_true "wait_remote_has n10.md" "a hook-stop within the minimum interval still pushes"

# --- 12. cloud commits link the conversation (Claude-Session trailer) -----
echo eleven > "$WORK/c/n11.md"
echo '{}' | RILL_HOME="$WORK/c" CLAUDE_CODE_REMOTE=true CLAUDE_CODE_REMOTE_SESSION_ID=cse_01AbC-x_9 \
  "$RILL" autosync hook-start >/dev/null 2>&1 || true
sess="$(git -C "$WORK/remote.git" log -1 --format='%(trailers:key=Claude-Session,valueonly)' main | tr -d '\n')"
assert_eq "$sess" "https://claude.ai/code/session_01AbC-x_9" "a cloud commit carries the Claude-Session link"
wr="$(git -C "$WORK/remote.git" log -1 --format='%(trailers:key=Rill-Writer,valueonly)' main | tr -d '\n')"
assert_eq "$wr" "cloud" "the Rill-Writer trailer is still there"
echo twelve > "$WORK/c/n12.md"
echo '{}' | RILL_HOME="$WORK/c" CLAUDE_CODE_REMOTE=true CLAUDE_CODE_REMOTE_SESSION_ID='cse_bad id' \
  "$RILL" autosync hook-start >/dev/null 2>&1 || true
sess="$(git -C "$WORK/remote.git" log -1 --format='%(trailers:key=Claude-Session,valueonly)' main | tr -d '\n')"
assert_eq "$sess" "" "an invalid session id adds no link"

# --- 13. a pause that starts while a run waits for the lock holds it -------
as_a run >/dev/null || true
sleep 30 &
holder=$!
mkdir "$WORK/a/.git/rill-autosync.lock"
echo "$holder" > "$WORK/a/.git/rill-autosync.lock/pid"
echo thirteen > "$WORK/a/n13.md"
as_a run --json > "$WORK/run13.out" &
runner=$!
sleep 1
( RILL_HOME="$WORK/a" "$RILL" autosync pause; sleep 4 ) &
pauser=$!
sleep 1
rm -rf "$WORK/a/.git/rill-autosync.lock"
kill "$holder" 2>/dev/null || true
wait "$runner" || true
assert_out_contains "$(cat "$WORK/run13.out")" '"status":"skipped"' "a run that waited is re-checked and skipped while paused"
assert_true "! remote_has n13.md" "nothing was pushed during the pause"
wait "$pauser" || true

# --- 14. the sync branch is the destination, whatever the upstream says ----
clone "$WORK/e" e2
(cd "$WORK/e" && git push -q origin HEAD:refs/heads/other)
git -C "$WORK/e" branch -q -u origin/other
git -C "$WORK/e" config push.default upstream
echo fourteen > "$WORK/e/n14.md"
rc=0; out="$(RILL_HOME="$WORK/e" "$RILL" autosync run --json 2>&1)" || rc=$?
assert_eq "$rc" "0" "run with a different upstream exits 0"
assert_true "remote_has n14.md" "the work went to the sync branch"
assert_true "! git -C '$WORK/remote.git' show other:n14.md >/dev/null 2>&1" "not to the upstream branch"
out="$(RILL_HOME="$WORK/e" "$RILL" autosync check --json 2>&1)"
assert_out_contains "$out" '"unpushed":0' "check agrees nothing is left to push"

# --- 15. colored hook output still gives valid JSON ------------------------
mkdir -p "$WORK/a/.git/hooks"
printf '#!/bin/sh\nprintf "\\033[31mrejected by hook\\033[0m\\n" >&2\nexit 1\n' > "$WORK/a/.git/hooks/pre-push"
chmod +x "$WORK/a/.git/hooks/pre-push"
echo fifteen > "$WORK/a/n15.md"
out="$(as_a run --json || true)"
assert_true "printf '%s' '$out' | python3 -c 'import json,sys; json.load(sys.stdin)'" "run --json stays valid JSON with colored hook output"
assert_out_contains "$out" "rejected by hook" "the hook's message is kept"
rm -f "$WORK/a/.git/hooks/pre-push"

# --- 16. two pausing processes: one ending does not lift the other's pause --
( RILL_HOME="$WORK/a" "$RILL" autosync pause; sleep 6 ) &
p_long=$!
( RILL_HOME="$WORK/a" "$RILL" autosync pause; sleep 1 ) &
p_short=$!
wait "$p_short" || true
echo sixteen > "$WORK/a/n16.md"
out="$(as_a run --json)"
assert_out_contains "$out" "paused" "the remaining pause still holds runs"
wait "$p_long" || true

# --- 17. a background run re-checks the branch it was started on ----------
as_a run >/dev/null || true
echo seventeen > "$WORK/a/n17.md"
echo '{}' | RILL_HOME="$WORK/a" "$RILL" autosync hook-stop >/dev/null 2>&1
git -C "$WORK/a" switch -q -c side
sleep 14
assert_true "! remote_has n17.md" "a branch switch before the background run stops it"
git -C "$WORK/a" switch -q main
rm -f "$WORK/a/n17.md"

# --- 18. a result file in another format still gives valid JSON ------------
printf '0\nPushed.\n' > "$WORK/a/.git/rill-autosync.last"
out="$(as_a status --json)"
assert_true "printf '%s' '$out' | python3 -c 'import json,sys; json.load(sys.stdin)'" "status --json is valid JSON for an old-format result file"
assert_out_contains "$out" '"status":"unknown"' "an unreadable result reports unknown"

# --- 19. check reports HEAD behind a tracking ref someone else fetched ------
as_a run >/dev/null || true
echo nineteen > "$WORK/b/n19.md"; push_b
git -C "$WORK/a" fetch -q origin
out="$(as_a check --json)"
assert_out_contains "$out" '"remote_moved":false' "after a fetch the remote matches the tracking ref"
assert_out_contains "$out" '"behind":1' "check reports HEAD one commit behind"

# --- 20. run --if-idle skips while a session is mid-turn -------------------
as_a run >/dev/null || true
mkdir -p "$WORK/a/.rill/state/sessions"
printf '{"t":1,"event":"UserPromptSubmit","session_id":"s1"}\n' > "$WORK/a/.rill/state/sessions/s1.jsonl"
echo twenty > "$WORK/a/n20.md"
out="$(as_a run --json --if-idle)"
assert_out_contains "$out" '"status":"skipped"' "run --if-idle skips while a session is mid-turn"
assert_true "! remote_has n20.md" "nothing is pushed"
printf '{"t":2,"event":"Stop","session_id":"s1"}\n' >> "$WORK/a/.rill/state/sessions/s1.jsonl"
out="$(as_a run --json --if-idle)"
assert_out_contains "$out" '"status":"pushed"' "run --if-idle pushes once the turn ended"
rm -rf "$WORK/a/.rill/state"

echo ""
report_results
