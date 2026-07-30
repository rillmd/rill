#!/bin/bash
# test/cli/test-checkpoint-hooks.sh - `rill checkpoint` hook behaviour
#
# The checkpoint hooks exist so session state lands in vault files even when
# the model never decides to write one. They run on every Edit/Write, every
# turn end, every compaction and every session end, so the load-bearing
# property is that they never take a session down: every path exits 0, even
# on malformed input.
#
# Covered:
#   - track records in-vault writes and ignores sibling-repo paths
#   - on-stop nudges only after the threshold, and not again until the
#     threshold has passed a second time
#   - on-stop stays silent for sessions that never touched a work unit
#     (ordinary code sessions must not be nagged)
#   - on-end writes {unit}/_log.md with frontmatter and the last message
#   - on-end deduplicates PreCompact immediately followed by SessionEnd
#   - on-end appends a fresh entry once the session state has changed
#   - empty / malformed / session-less hook input still exits 0
#
# Usage: bash test/cli/test-checkpoint-hooks.sh
# Requires: bash, jq. No claude CLI, no network.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
RILL="$REPO_ROOT/bin/rill"
STATE_ROOT="${TMPDIR:-/tmp}"

# shellcheck source=test/assertions/lib.sh
source "$SCRIPT_DIR/../assertions/lib.sh"

if ! command -v jq >/dev/null 2>&1; then
  echo "FAIL: jq is required"
  exit 1
fi

WORK="$(mktemp -d)"
cleanup() {
  rm -rf "$WORK"
  rm -rf "$STATE_ROOT"/rill-ckpt-cse_ckpt_* 2>/dev/null || true
}
trap cleanup EXIT
cleanup_state() { rm -rf "$STATE_ROOT"/rill-ckpt-cse_ckpt_* 2>/dev/null || true; }
cleanup_state

VAULT="$WORK/vault"
mkdir -p "$VAULT/workspace/demo-ws" "$VAULT/tasks/demo-task"
export RILL_HOME="$VAULT"

TRANSCRIPT="$WORK/transcript.jsonl"
cat > "$TRANSCRIPT" <<'EOF'
{"type":"assistant","message":{"content":[{"type":"text","text":"an earlier reply"}]}}
{"type":"user","message":{"content":"go on"}}
{"type":"assistant","message":{"content":[{"type":"text","text":"CHECKPOINT MARKER TEXT"}]}}
EOF

track() { # session_id, absolute file path
  printf '{"session_id":"%s","tool_input":{"file_path":"%s"}}' "$1" "$2" | "$RILL" checkpoint track
}
on_stop() { # session_id -> prints hook JSON when it nudges, empty otherwise
  printf '{"session_id":"%s"}' "$1" | "$RILL" checkpoint on-stop
}
on_end() { # session_id, event, reason_key, reason
  printf '{"session_id":"%s","hook_event_name":"%s","%s":"%s","transcript_path":"%s"}' \
    "$1" "$2" "$3" "$4" "$TRANSCRIPT" | "$RILL" checkpoint on-end
}
count_nudges() { # session_id, turns -> number of turns that produced a nudge
  local sid="$1" turns="$2" i out n=0
  for ((i = 0; i < turns; i++)); do
    out="$(on_stop "$sid")"
    if [ -n "$out" ]; then n=$((n + 1)); fi
  done
  printf '%s' "$n"
}

# ── track ────────────────────────────────────────────────────────────
SID="cse_ckpt_a"
track "$SID" "$VAULT/workspace/demo-ws/001-a.md"
assert_file_contains "$STATE_ROOT/rill-ckpt-$SID/files" "workspace/demo-ws/001-a.md" \
  "track records an in-vault write"

track "$SID" "/somewhere/else/main.go"
assert_file_not_contains "$STATE_ROOT/rill-ckpt-$SID/files" "main.go" \
  "track ignores writes outside the vault"

# ── on-stop: nudge threshold (default 5) ─────────────────────────────
assert_eq "$(count_nudges "$SID" 4)" "0" "on-stop stays quiet below the threshold"

NUDGE="$(on_stop "$SID")"
assert_true '[ -n "$NUDGE" ]' "on-stop nudges once the threshold is reached"

NAMED=no
if printf '%s' "$NUDGE" | jq -e '.hookSpecificOutput.additionalContext
      | test("workspace/demo-ws")' >/dev/null 2>&1; then
  NAMED=yes
fi
assert_eq "$NAMED" "yes" "the nudge names the active work unit"

assert_eq "$(on_stop "$SID")" "" "on-stop does not nudge again on the very next turn"

# A write into the work unit resets the idle counter, and the nudge window
# with it: the next nudge is one threshold away, not two. Clearing only the
# turn counter would let the quiet period grow with every nudge.
track "$SID" "$VAULT/workspace/demo-ws/002-b.md"
assert_eq "$(count_nudges "$SID" 4)" "0" "writing an artifact resets the idle counter"
assert_eq "$(count_nudges "$SID" 1)" "1" "the nudge window resets with it, rather than doubling"

# ── on-stop: sessions with no work unit stay silent ──────────────────
SID_NOWORK="cse_ckpt_none"
track "$SID_NOWORK" "$VAULT/README.md"
assert_eq "$(count_nudges "$SID_NOWORK" 7)" "0" \
  "sessions that touch no work unit are never nudged"

# ── on-end: writes the log ───────────────────────────────────────────
on_end "$SID" "PreCompact" "trigger" "auto"
LOG="$VAULT/workspace/demo-ws/_log.md"
assert_file_exists "$LOG" "on-end creates {unit}/_log.md"
assert_file_contains "$LOG" "type: log" "the log carries frontmatter"
assert_file_contains "$LOG" "PreCompact: auto" "the log records the event and reason"
assert_file_contains "$LOG" "CHECKPOINT MARKER TEXT" "the log captures the last assistant message"
assert_file_contains "$LOG" "workspace/demo-ws/002-b.md" "the log lists the files touched"

BEFORE="$(file_hash "$LOG")"
on_end "$SID" "SessionEnd" "reason" "clear"
assert_eq "$(file_hash "$LOG")" "$BEFORE" \
  "SessionEnd right after PreCompact does not duplicate the entry"

track "$SID" "$VAULT/workspace/demo-ws/003-c.md"
on_end "$SID" "SessionEnd" "reason" "clear"
assert_true '[ "$(file_hash "$LOG")" != "$BEFORE" ]' \
  "a changed session state appends a new entry"

# ── on-end: task work units ──────────────────────────────────────────
SID_TASK="cse_ckpt_task"
track "$SID_TASK" "$VAULT/tasks/demo-task/_task.md"
on_end "$SID_TASK" "SessionEnd" "reason" "logout"
assert_file_exists "$VAULT/tasks/demo-task/_log.md" "task directories get checkpoints too"

# ── on-end: moving back to an earlier work unit still checkpoints ────
# `touched` is deduplicated and the transcript has not moved, so only the
# unit itself distinguishes this checkpoint from the previous one.
SID_SWITCH="cse_ckpt_switch"
mkdir -p "$VAULT/workspace/ws-a" "$VAULT/workspace/ws-b"
track "$SID_SWITCH" "$VAULT/workspace/ws-a/001-a.md"
on_end "$SID_SWITCH" "SessionEnd" "reason" "clear"
track "$SID_SWITCH" "$VAULT/workspace/ws-b/001-b.md"
on_end "$SID_SWITCH" "SessionEnd" "reason" "clear"
assert_file_exists "$VAULT/workspace/ws-b/_log.md" "the second work unit gets its own log"

A_BEFORE="$(file_hash "$VAULT/workspace/ws-a/_log.md")"
track "$SID_SWITCH" "$VAULT/workspace/ws-a/001-a.md"   # already-seen path
on_end "$SID_SWITCH" "PreCompact" "trigger" "auto"
assert_true '[ "$(file_hash "$VAULT/workspace/ws-a/_log.md")" != "$A_BEFORE" ]' \
  "returning to an earlier work unit is not mistaken for a duplicate"

# ── on-end: no work unit means no file ───────────────────────────────
on_end "$SID_NOWORK" "SessionEnd" "reason" "clear"
assert_file_not_exists "$VAULT/_log.md" "no work unit means nothing is written"

# ── malformed input must never fail the session ──────────────────────
for sub in track on-stop on-end; do
  rc=0
  echo '' | "$RILL" checkpoint "$sub" >/dev/null 2>&1 || rc=$?
  assert_eq "$rc" "0" "checkpoint $sub exits 0 on empty input"

  rc=0
  echo 'not json at all' | "$RILL" checkpoint "$sub" >/dev/null 2>&1 || rc=$?
  assert_eq "$rc" "0" "checkpoint $sub exits 0 on malformed input"

  rc=0
  echo '{"tool_input":{"file_path":"/x"}}' | "$RILL" checkpoint "$sub" >/dev/null 2>&1 || rc=$?
  assert_eq "$rc" "0" "checkpoint $sub exits 0 without a session id"
done

report_results
