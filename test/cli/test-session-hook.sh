#!/bin/bash
# test/cli/test-session-hook.sh - `rill session-hook` session ledger (ADR-087)
#
# The session ledger lets the GUI bind Claude Code sessions to work units and
# show their state without reading terminal output. The hook runs on every
# prompt, tool call and turn end, so it must never take a session down and
# must print nothing except the SessionStart context payload.
#
# Covered:
#   - events append one JSON line each to the session's own file, with
#     tab / workspace / origin from env
#   - Write/Edit records the vault-relative path; other tools record no file
#   - Stop records files changed during the turn, including .view/ sidecars,
#     files inside untracked directories, and re-edited files; noise excluded
#   - SessionStart prints additionalContext only when RILL_WORKSPACE names an
#     existing work unit
#   - non-SessionStart events print nothing
#   - missing session id leaves an "unknown" trace; malformed input exits 0
#   - TurnFiles attribution: a workspace-bound session claims only changes in
#     its workspace; paths another session wrote this turn are excluded
#   - concurrent sessions keep every line valid JSON (one file per session)
#   - SessionStart deletes session files past the retention window
#
# Usage: bash test/cli/test-session-hook.sh
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
cleanup() {
  rm -rf "$WORK"
  rm -f "${TMPDIR:-/tmp}"/rill-sess-cse_sess_* 2>/dev/null || true
}
trap cleanup EXIT

VAULT="$WORK/vault"
mkdir -p "$VAULT/workspace/demo-ws/.view" "$VAULT/workspace/demo-ws/drafts" "$VAULT/tasks"
echo "seed" > "$VAULT/workspace/demo-ws/001-old.md"
mkdir -p "$VAULT/.rill" && echo "test" > "$VAULT/.rill/version"
export RILL_HOME="$VAULT"
SDIR="$VAULT/.rill/state/sessions"

hook() { # event, json
  printf '%s' "$2" | "$RILL" session-hook "$1"
}
ledger() { printf '%s/%s.jsonl' "$SDIR" "$1"; }
LEDGER="$SDIR/cse_sess_a.jsonl"
last() { tail -n 1 "$(ledger "${1:-cse_sess_a}")"; }

SID="cse_sess_a"

# ── SessionStart with a work unit ─────────────────────────────────────
OUT="$(RILL_WORKSPACE=workspace/demo-ws RILL_TAB=tab-1 RILL_ORIGIN=gui RILL_CLAUDE_VERSION=2.1.290 \
  hook SessionStart "{\"session_id\":\"$SID\",\"hook_event_name\":\"SessionStart\",\"source\":\"startup\"}")"
assert_file_exists "$LEDGER" "the session's ledger file is created on its first event"
assert_eq "$(last | jq -r '.event')" "SessionStart" "SessionStart is recorded"
assert_eq "$(last | jq -r '.workspace')" "workspace/demo-ws" "the workspace comes from RILL_WORKSPACE"
assert_eq "$(last | jq -r '.tab')" "tab-1" "the tab comes from RILL_TAB"
assert_eq "$(last | jq -r '.origin')" "gui" "the origin comes from RILL_ORIGIN"
assert_eq "$(last | jq -r '.claude_version')" "2.1.290" "the CLI version is recorded when provided"
CTX=no
if printf '%s' "$OUT" | jq -e '.hookSpecificOutput.hookEventName == "SessionStart"
    and (.hookSpecificOutput.additionalContext | test("workspace/demo-ws"))' >/dev/null 2>&1; then
  CTX=yes
fi
assert_eq "$CTX" "yes" "SessionStart returns context naming the work unit"

OUT="$(hook SessionStart "{\"session_id\":\"cse_sess_b\"}")"
assert_eq "$OUT" "" "SessionStart prints nothing without RILL_WORKSPACE"
OUT="$(RILL_WORKSPACE=workspace/missing hook SessionStart "{\"session_id\":\"cse_sess_b\"}")"
assert_eq "$OUT" "" "SessionStart prints nothing when the work unit does not exist"
assert_eq "$(last cse_sess_b | jq -r 'has("workspace")')" "true" "the env workspace is still recorded"

# ── turn: prompt, tools, stop ─────────────────────────────────────────
OUT="$(RILL_TAB=tab-1 hook UserPromptSubmit "{\"session_id\":\"$SID\",\"prompt\":\"go\"}")"
assert_eq "$OUT" "" "UserPromptSubmit prints nothing"
sleep 1

OUT="$(hook PostToolUse "{\"session_id\":\"$SID\",\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$VAULT/workspace/demo-ws/002-new.md\"}}")"
assert_eq "$OUT" "" "PostToolUse prints nothing"
assert_eq "$(last | jq -r '.file')" "workspace/demo-ws/002-new.md" "Write records the vault-relative path"

hook PostToolUse "{\"session_id\":\"$SID\",\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"/elsewhere/main.go\"}}"
assert_eq "$(last | jq -r 'has("file")')" "false" "writes outside the vault record no file"

hook PostToolUse "{\"session_id\":\"$SID\",\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"ls\"}}"
assert_eq "$(last | jq -r '.tool')" "Bash" "other tools are recorded (they clear the waiting state)"
assert_eq "$(last | jq -r 'has("file")')" "false" "other tools record no file"

hook PostToolUseFailure "{\"session_id\":\"$SID\",\"tool_name\":\"WebFetch\"}"
assert_eq "$(last | jq -r '.event')" "PostToolUseFailure" "tool failures are recorded"

# Shell-made changes during the turn
echo "new" > "$VAULT/workspace/demo-ws/002-new.md"
echo "re-edit" >> "$VAULT/workspace/demo-ws/001-old.md"
echo "<html>" > "$VAULT/workspace/demo-ws/.view/digest.html"
echo "draft" > "$VAULT/workspace/demo-ws/drafts/a.md"
touch "$VAULT/workspace/demo-ws/.DS_Store"

OUT="$(hook Stop "{\"session_id\":\"$SID\",\"hook_event_name\":\"Stop\"}")"
assert_eq "$OUT" "" "Stop prints nothing (output would continue the turn)"
TF="$(grep '"TurnFiles"' "$LEDGER" | tail -n 1)"
assert_true '[ -n "$TF" ]' "Stop records the files changed during the turn"
for f in workspace/demo-ws/002-new.md workspace/demo-ws/001-old.md \
         workspace/demo-ws/.view/digest.html workspace/demo-ws/drafts/a.md; do
  assert_eq "$(printf '%s' "$TF" | jq -r --arg f "$f" '.files | index($f) != null')" "true" "TurnFiles includes $f"
done
assert_eq "$(printf '%s' "$TF" | jq -r '.files | map(select(endswith(".DS_Store"))) | length')" "0" "TurnFiles excludes .DS_Store"

hook StopFailure "{\"session_id\":\"$SID\",\"error\":\"rate_limit\"}" >/dev/null
assert_true 'grep -q "\"StopFailure\"" "$LEDGER"' "StopFailure is recorded"

hook SessionEnd "{\"session_id\":\"$SID\",\"reason\":\"prompt_input_exit\"}"
assert_eq "$(last | jq -r '.event')" "SessionEnd" "SessionEnd is recorded"
assert_file_not_exists "${TMPDIR:-/tmp}/rill-sess-$SID.turn" "SessionEnd removes the turn marker"

# ── robustness ────────────────────────────────────────────────────────
hook Stop '{"hook_event_name":"Stop"}'
assert_eq "$(last _unknown | jq -r '.event')" "unknown" "missing session id leaves an unknown trace"
for ev in SessionStart UserPromptSubmit PostToolUse Stop SessionEnd Bogus; do
  rc=0; echo '' | "$RILL" session-hook "$ev" >/dev/null 2>&1 || rc=$?
  assert_eq "$rc" "0" "session-hook $ev exits 0 on empty input"
  rc=0; echo 'not json' | "$RILL" session-hook "$ev" >/dev/null 2>&1 || rc=$?
  assert_eq "$rc" "0" "session-hook $ev exits 0 on malformed input"
done
# Isolate HOME and cwd so vault resolution cannot fall back to a real vault
# registered on this machine.
rc=0; (cd "$WORK" && HOME="$WORK" RILL_HOME="$WORK/nope" "$RILL" session-hook Stop </dev/null >/dev/null 2>&1) || rc=$?
assert_eq "$rc" "0" "session-hook exits 0 without a vault"
NOTVAULT="$WORK/not-a-vault"; mkdir -p "$NOTVAULT"
printf '{"session_id":"cse_sess_x"}' | RILL_HOME="$NOTVAULT" "$RILL" session-hook Stop
assert_file_not_exists "$NOTVAULT/.rill/state/sessions" "session-hook never writes outside a vault (no .rill/version)"

# Oversized malformed input must not abort the hook (no SIGPIPE under pipefail)
BIG="$(head -c 300000 /dev/zero | tr '\0' 'x')"
rc=0; printf '{"pad":"%s"}' "$BIG" | "$RILL" session-hook Stop >/dev/null 2>&1 || rc=$?
assert_eq "$rc" "0" "a 300KB input without a session id still exits 0"
assert_eq "$(last _unknown | jq -r '.event')" "unknown" "and still leaves an unknown trace"

# Concurrent sessions: every line in every session file stays valid JSON
for i in $(seq 1 120); do echo "x" > "$VAULT/workspace/demo-ws/bulk-$i.md"; done
for n in 1 2 3 4 5 6; do
  ( sid="cse_sess_par$n"
    printf '{"session_id":"%s"}' "$sid" | "$RILL" session-hook UserPromptSubmit
    sleep 1
    touch "$VAULT"/workspace/demo-ws/bulk-*.md
    printf '{"session_id":"%s"}' "$sid" | "$RILL" session-hook Stop ) &
done
wait
BAD=0
for f in "$SDIR"/*.jsonl; do
  while IFS= read -r line; do printf '%s' "$line" | jq -e . >/dev/null 2>&1 || BAD=$((BAD + 1)); done < "$f"
done
assert_eq "$BAD" "0" "concurrent sessions never produce an unparseable ledger line"
N=0; for n in 1 2 3 4 5 6; do grep -q '"TurnFiles"' "$(ledger cse_sess_par$n)" 2>/dev/null && N=$((N + 1)); done
assert_eq "$N" "6" "every concurrent session recorded its own TurnFiles line"

# Attribution
mkdir -p "$VAULT/workspace/other-ws"
printf '{"session_id":"cse_sess_ws"}' | RILL_WORKSPACE=workspace/demo-ws "$RILL" session-hook UserPromptSubmit
printf '{"session_id":"cse_sess_other"}' | "$RILL" session-hook UserPromptSubmit
sleep 1
echo "mine" > "$VAULT/workspace/demo-ws/mine.md"
echo "elsewhere" > "$VAULT/workspace/other-ws/elsewhere.md"
echo "by-other" > "$VAULT/workspace/demo-ws/by-other.md"
printf '{"session_id":"cse_sess_other","tool_name":"Write","tool_input":{"file_path":"%s"}}' \
  "$VAULT/workspace/demo-ws/by-other.md" | "$RILL" session-hook PostToolUse
printf '{"session_id":"cse_sess_ws"}' | RILL_WORKSPACE=workspace/demo-ws "$RILL" session-hook Stop
TFW="$(grep '"TurnFiles"' "$(ledger cse_sess_ws)" | tail -n 1)"
assert_eq "$(printf '%s' "$TFW" | jq -r '.files | index("workspace/demo-ws/mine.md") != null')" "true" "a workspace-bound session records its own change"
assert_eq "$(printf '%s' "$TFW" | jq -r '.files | map(select(startswith("workspace/other-ws/"))) | length')" "0" "it does not claim changes outside its workspace"
assert_eq "$(printf '%s' "$TFW" | jq -r '.files | index("workspace/demo-ws/by-other.md") == null')" "true" "it does not claim a path another session wrote this turn"

# ── retention ─────────────────────────────────────────────────────────
OLDF="$(ledger cse_sess_old)"
echo '{"event":"Stop","session_id":"cse_sess_old"}' > "$OLDF"
touch -t 200001010000 "$OLDF"
hook SessionStart '{"session_id":"cse_sess_c"}' >/dev/null
assert_file_not_exists "$OLDF" "SessionStart deletes session files past the retention window"
assert_file_exists "$(ledger cse_sess_a)" "recent session files survive"

report_results
