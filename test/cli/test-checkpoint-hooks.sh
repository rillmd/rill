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
on_stop() { # session_id -> side effects only, never prints
  printf '{"session_id":"%s"}' "$1" | "$RILL" checkpoint on-stop
}
on_prompt() { # session_id -> prints hook JSON when it nudges, empty otherwise
  printf '{"session_id":"%s","prompt":"next"}' "$1" | "$RILL" checkpoint on-prompt
}
on_end() { # session_id, event, reason_key, reason
  printf '{"session_id":"%s","hook_event_name":"%s","%s":"%s","transcript_path":"%s"}' \
    "$1" "$2" "$3" "$4" "$TRANSCRIPT" | "$RILL" checkpoint on-end
}
count_nudges() { # session_id, turns -> nudges seen across that many turns
  # One turn is a prompt followed by a Stop, so the reminder is checked on the
  # way in and the idle counter advances on the way out.
  local sid="$1" turns="$2" i out n=0
  for ((i = 0; i < turns; i++)); do
    out="$(on_prompt "$sid")"
    if [ -n "$out" ]; then n=$((n + 1)); fi
    on_stop "$sid"
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

# ── the reminder: threshold (default 5), delivered on UserPromptSubmit ──
# The first Stop is consumed by the write above, so the threshold is reached
# on the sixth Stop, not the fifth.
assert_eq "$(count_nudges "$SID" 5)" "0" "on-stop stays quiet below the threshold"

assert_eq "$(on_stop "$SID")" "" "Stop itself never prints, so it cannot continue the turn"
NUDGE="$(on_prompt "$SID")"
assert_true '[ -n "$NUDGE" ]' "the reminder arrives on the next prompt once the threshold is reached"

NAMED=no
if printf '%s' "$NUDGE" | jq -e '.hookSpecificOutput.additionalContext
      | test("workspace/demo-ws")' >/dev/null 2>&1; then
  NAMED=yes
fi
assert_eq "$NAMED" "yes" "the reminder names the active work unit"

on_stop "$SID"
assert_eq "$(on_prompt "$SID")" "" "the reminder does not repeat on the very next turn"

# A write into the work unit resets the idle counter, and the nudge window
# with it: the next nudge is one threshold away, not two. Clearing only the
# turn counter would let the quiet period grow with every nudge.
track "$SID" "$VAULT/workspace/demo-ws/002-b.md"
# The Stop that closes the writing turn is consumed, not counted: PostToolUse
# and Stop both fire inside the same assistant turn, so counting it would make
# the threshold one turn short.
assert_eq "$(count_nudges "$SID" 5)" "0" "the turn containing the write is not counted as idle"
assert_eq "$(count_nudges "$SID" 2)" "1" "the reminder window resets with it, rather than doubling"

# ── sessions with no work unit stay silent ───────────────────────────
SID_NOWORK="cse_ckpt_none"
track "$SID_NOWORK" "$VAULT/README.md"
assert_eq "$(count_nudges "$SID_NOWORK" 7)" "0" \
  "sessions that touch no work unit are never nudged"

# ── on-end: writes the log ───────────────────────────────────────────
on_end "$SID" "PreCompact" "trigger" "auto"
LOG="$VAULT/workspace/demo-ws/_log.md"
assert_file_exists "$LOG" "on-end creates {unit}/_log.md"
assert_file_contains "$LOG" "type: progress" \
  "the log carries schema-conforming frontmatter"
assert_file_contains "$LOG" "PreCompact: auto" "the log records the event and reason"
assert_file_not_contains "$LOG" "CHECKPOINT MARKER TEXT" \
  "no free text is stored by default, so the contact-detail invariant holds structurally"
assert_file_contains "$LOG" "workspace/demo-ws/002-b.md" "the log lists the files touched"

BEFORE="$(file_hash "$LOG")"
on_end "$SID" "SessionEnd" "reason" "clear"
assert_eq "$(file_hash "$LOG")" "$BEFORE" \
  "SessionEnd right after PreCompact does not duplicate the entry"

track "$SID" "$VAULT/workspace/demo-ws/003-c.md"
on_end "$SID" "SessionEnd" "reason" "clear"
assert_true '[ "$(file_hash "$LOG")" != "$BEFORE" ]' \
  "a changed session state appends a new entry"

# ── task work units: nudged, but no file written ─────────────────────
# `_log.md` belongs to the workspace layout. The task layout defines
# `_task.md` plus numbered artifacts, so a checkpoint file there would sit
# outside the schema; task continuity lives in `## Current Position`.
SID_TASK="cse_ckpt_task"
track "$SID_TASK" "$VAULT/tasks/demo-task/_task.md"
# Nudges first: SessionEnd drops the session scratch, and with it the counter.
assert_eq "$(count_nudges "$SID_TASK" 7)" "1" "tasks still get the reminder"
on_end "$SID_TASK" "SessionEnd" "reason" "logout"
assert_file_not_exists "$VAULT/tasks/demo-task/_log.md" \
  "tasks do not get an out-of-schema _log.md"

# ── the opt-in excerpt is redacted before it reaches the vault ───────
# Free text is off by default. With RILL_CKPT_EXCERPT=1 it is scrubbed on
# the way in, since ADR-047 keeps contact details out of workspace/.
SID_PII="cse_ckpt_pii"
PII_TRANSCRIPT="$WORK/pii.jsonl"
cat > "$PII_TRANSCRIPT" <<'PIIEOF'
{"type":"assistant","message":{"content":[{"type":"text","text":"Mail alex@example.com or call +81 90-1234-5678 or 090.1234.5678, key sk-abcdefghijklmnop12345"}]}}
PIIEOF
mkdir -p "$VAULT/workspace/ws-pii"
track "$SID_PII" "$VAULT/workspace/ws-pii/001-x.md"
RILL_CKPT_EXCERPT=1 sh -c 'printf "{\"session_id\":\"$1\",\"hook_event_name\":\"SessionEnd\",\"reason\":\"clear\",\"transcript_path\":\"$2\"}" | "$3" checkpoint on-end' _ \
  "$SID_PII" "$PII_TRANSCRIPT" "$RILL"
PII_LOG="$VAULT/workspace/ws-pii/_log.md"
assert_file_not_contains "$PII_LOG" "alex@example.com" "email addresses are redacted"
assert_file_not_contains "$PII_LOG" "1234-5678" "phone numbers are redacted"
assert_file_not_contains "$PII_LOG" "sk-abcdefghijklmnop12345" "credential-shaped strings are redacted"
assert_file_contains "$PII_LOG" "redacted" "the redaction is visible in the opt-in excerpt"
assert_file_not_contains "$PII_LOG" "090.1234.5678" "dot-separated phone numbers are redacted too"

# ── on-end: moving back to an earlier work unit still checkpoints ────
# `touched` is deduplicated and the transcript has not moved, so only the
# unit itself distinguishes this checkpoint from the previous one.
SID_SWITCH="cse_ckpt_switch"
mkdir -p "$VAULT/workspace/ws-a" "$VAULT/workspace/ws-b"
track "$SID_SWITCH" "$VAULT/workspace/ws-a/001-a.md"
on_end "$SID_SWITCH" "PreCompact" "trigger" "auto"
track "$SID_SWITCH" "$VAULT/workspace/ws-b/001-b.md"
on_end "$SID_SWITCH" "PreCompact" "trigger" "auto"
assert_file_exists "$VAULT/workspace/ws-b/_log.md" "the second work unit gets its own log"

A_BEFORE="$(file_hash "$VAULT/workspace/ws-a/_log.md")"
track "$SID_SWITCH" "$VAULT/workspace/ws-a/001-a.md"   # already-seen path
on_end "$SID_SWITCH" "PreCompact" "trigger" "auto"
assert_true '[ "$(file_hash "$VAULT/workspace/ws-a/_log.md")" != "$A_BEFORE" ]' \
  "returning to an earlier work unit is not mistaken for a duplicate"

# ── re-editing a known file still counts as progress ─────────────────
# `touched` is deduplicated, so without the write generation a session that
# only re-edits files it already listed would look unchanged and lose its
# SessionEnd checkpoint.
SID_REEDIT="cse_ckpt_reedit"
mkdir -p "$VAULT/workspace/ws-re"
track "$SID_REEDIT" "$VAULT/workspace/ws-re/001-a.md"
printf '{"session_id":"%s","hook_event_name":"PreCompact","trigger":"auto"}' "$SID_REEDIT" \
  | "$RILL" checkpoint on-end
RE_LOG="$VAULT/workspace/ws-re/_log.md"
RE_BEFORE="$(file_hash "$RE_LOG")"
track "$SID_REEDIT" "$VAULT/workspace/ws-re/001-a.md"   # same path again
printf '{"session_id":"%s","hook_event_name":"PreCompact","trigger":"auto"}' "$SID_REEDIT" \
  | "$RILL" checkpoint on-end
assert_true '[ "$(file_hash "$RE_LOG")" != "$RE_BEFORE" ]' \
  "re-editing an already-listed file still produces a checkpoint"

# ── credential shapes that must not survive ──────────────────────────
SID_CRED="cse_ckpt_cred"
CRED_TRANSCRIPT="$WORK/cred.jsonl"
cat > "$CRED_TRANSCRIPT" <<'CREDEOF'
{"type":"assistant","message":{"content":[{"type":"text","text":"keys AKIAIOSFODNN7EXAMPLE and AIzaSyD-1234567890abcdefg and glpat-abcdefghij1234567890"}]}}
CREDEOF
mkdir -p "$VAULT/workspace/ws-cred"
track "$SID_CRED" "$VAULT/workspace/ws-cred/001-x.md"
RILL_CKPT_EXCERPT=1 sh -c 'printf "{\"session_id\":\"$1\",\"hook_event_name\":\"SessionEnd\",\"reason\":\"clear\",\"transcript_path\":\"$2\"}" | "$3" checkpoint on-end' _ \
  "$SID_CRED" "$CRED_TRANSCRIPT" "$RILL"
CRED_LOG="$VAULT/workspace/ws-cred/_log.md"
assert_file_not_contains "$CRED_LOG" "AKIAIOSFODNN7EXAMPLE" "AWS key ids are redacted"
assert_file_not_contains "$CRED_LOG" "AIzaSyD-1234567890abcdefg" "Google API keys are redacted"
assert_file_not_contains "$CRED_LOG" "glpat-abcdefghij1234567890" "GitLab tokens are redacted"

# ── the Codex hook projection reaches checkpoint too ─────────────────
# Codex-initialized vaults route through `rill codex-hook`; without wiring
# there the feature would be Claude-only.
SID_CODEX="cse_ckpt_codex"
mkdir -p "$VAULT/workspace/ws-codex"
printf '{"session_id":"%s","tool_input":{"file_path":"%s"}}' \
  "$SID_CODEX" "$VAULT/workspace/ws-codex/001-a.md" | "$RILL" codex-hook post-write >/dev/null 2>&1
assert_file_contains "$STATE_ROOT/rill-ckpt-$SID_CODEX/files" "workspace/ws-codex/001-a.md" \
  "the Codex post-write hook feeds checkpoint track"

# ── RILL_HOME shapes that must still resolve ─────────────────────────
# resolve_rill_home returns $RILL_HOME verbatim, so a trailing slash, a
# relative path or a symlinked vault all reach the hooks as-is. A plain
# prefix strip would classify every write as external and silence
# everything, so each shape is pinned here.
SID_HOME="cse_ckpt_home"
(
  export RILL_HOME="$VAULT/"
  track "$SID_HOME" "$VAULT/workspace/demo-ws/010-slash.md"
)
assert_file_contains "$STATE_ROOT/rill-ckpt-$SID_HOME/files" "workspace/demo-ws/010-slash.md" \
  "a trailing slash in RILL_HOME still resolves in-vault writes"

SID_REL="cse_ckpt_rel"
(
  cd "$WORK"
  export RILL_HOME="vault"
  track "$SID_REL" "$VAULT/workspace/demo-ws/011-rel.md"
)
assert_file_contains "$STATE_ROOT/rill-ckpt-$SID_REL/files" "workspace/demo-ws/011-rel.md" \
  "a relative RILL_HOME still resolves in-vault writes"

SID_LINK="cse_ckpt_link"
ln -s "$VAULT" "$WORK/linked-vault"
(
  export RILL_HOME="$WORK/linked-vault"
  track "$SID_LINK" "$VAULT/workspace/demo-ws/012-link.md"
)
assert_file_contains "$STATE_ROOT/rill-ckpt-$SID_LINK/files" "workspace/demo-ws/012-link.md" \
  "a symlinked RILL_HOME still resolves in-vault writes"

# ── on-end: no work unit means no file ───────────────────────────────
on_end "$SID_NOWORK" "SessionEnd" "reason" "clear"
assert_file_not_exists "$VAULT/_log.md" "no work unit means nothing is written"

# ── session scratch is dropped when the session really ends ──────────
SID_CLEAN="cse_ckpt_clean"
mkdir -p "$VAULT/workspace/ws-clean"
track "$SID_CLEAN" "$VAULT/workspace/ws-clean/001-a.md"
printf '{"session_id":"%s","hook_event_name":"PreCompact","trigger":"auto"}' "$SID_CLEAN" \
  | "$RILL" checkpoint on-end
assert_true '[ -d "$STATE_ROOT/rill-ckpt-$SID_CLEAN" ]' \
  "PreCompact keeps the session scratch, since the session continues"
printf '{"session_id":"%s","hook_event_name":"SessionEnd","reason":"clear"}' "$SID_CLEAN" \
  | "$RILL" checkpoint on-end
assert_true '[ ! -d "$STATE_ROOT/rill-ckpt-$SID_CLEAN" ]' \
  "SessionEnd drops the session scratch"

# ... including when there was no work unit to write for.
SID_CLEAN2="cse_ckpt_clean2"
track "$SID_CLEAN2" "$VAULT/README.md"
printf '{"session_id":"%s","hook_event_name":"SessionEnd","reason":"clear"}' "$SID_CLEAN2" \
  | "$RILL" checkpoint on-end
assert_true '[ ! -d "$STATE_ROOT/rill-ckpt-$SID_CLEAN2" ]' \
  "SessionEnd cleans up even when nothing was written"

# ── malformed input must never fail the session ──────────────────────
for sub in track on-stop on-prompt on-end; do
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
