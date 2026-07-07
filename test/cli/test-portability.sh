#!/usr/bin/env bash
# test/cli/test-portability.sh -- CLI portability regression tests (BSD/GNU)
#
# Guards the Linux-portability fixes: the sed_inplace() helper in bin/rill
# (BSD sed needs `-i ''`, GNU sed rejects the separate empty suffix) and the
# dual-mode stat in .claude/commands/_lib/briefing-context.sh.
#
# Pure shell, no claude invocation. Flavor-agnostic: the functional sections
# exercise whichever sed/stat flavor is native to the host, so the same file
# passes on macOS (BSD userland) today and on GNU/Linux CI runners. Running
# it on both platforms covers both branches of every dual-mode site.
#
# Usage: bash test/cli/test-portability.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
RILL_BIN="$REPO_ROOT/bin/rill"
BRIEFING_LIB="$REPO_ROOT/.claude/commands/_lib/briefing-context.sh"

PASS_COUNT=0
FAIL_COUNT=0

pass() { PASS_COUNT=$((PASS_COUNT + 1)); echo "  ok: $1"; }
fail() { FAIL_COUNT=$((FAIL_COUNT + 1)); echo "  FAIL: $1"; }

# --- Sandbox (isolated HOME / RILL_SOURCE / RILL_HOME) -----------------
TMP_ROOT="$(mktemp -d -t rill-portability-XXXXXX)"
cleanup() { rm -rf "$TMP_ROOT"; }
trap cleanup EXIT

export HOME="$TMP_ROOT/home"
mkdir -p "$HOME"
export RILL_SOURCE="$REPO_ROOT"
VAULT="$TMP_ROOT/vault"
mkdir -p "$VAULT"

echo "=== test-portability: syntax ==="

if bash -n "$RILL_BIN"; then pass "bash -n bin/rill"; else fail "bash -n bin/rill"; fi
if bash -n "$BRIEFING_LIB"; then pass "bash -n briefing-context.sh"; else fail "bash -n briefing-context.sh"; fi

echo "=== test-portability: static guards ==="

# Every in-place sed must route through sed_inplace(). Exactly two raw
# `sed -i` invocations may exist: the helper's GNU and BSD branches.
# Comment lines are excluded from the count.
raw_sed_lines="$(grep -nE '\bsed -i\b' "$RILL_BIN" | grep -vE '^[0-9]+:[[:space:]]*#' || true)"
raw_sed_count="$(printf '%s' "$raw_sed_lines" | grep -c 'sed -i' || true)"
if [ "$raw_sed_count" -eq 2 ]; then
  pass "bin/rill has exactly 2 raw 'sed -i' sites (both inside sed_inplace)"
else
  fail "bin/rill raw 'sed -i' count is $raw_sed_count (expected 2):"
  printf '%s\n' "$raw_sed_lines"
fi

# briefing-context.sh must carry both stat flavors.
if grep -q "stat -f '%m %N'" "$BRIEFING_LIB" && grep -q "stat -c '%Y %n'" "$BRIEFING_LIB"; then
  pass "briefing-context.sh carries both BSD and GNU stat forms"
else
  fail "briefing-context.sh is missing a stat flavor"
fi

# No other BSD-only constructs may creep into bin/rill (GNU date has no -v/-j;
# GNU readlink -f is fine but BSD's is not, so bin/rill avoids readlink -f).
bsd_only="$(grep -nE '\bdate -v|\bdate -j|\bstat -f|\breadlink -f' "$RILL_BIN" | grep -vE '^[0-9]+:[[:space:]]*#' || true)"
if [ -z "$bsd_only" ]; then
  pass "bin/rill has no other BSD-only constructs (date -v/-j, stat -f, readlink -f)"
else
  fail "bin/rill grew BSD-only constructs:"
  printf '%s\n' "$bsd_only"
fi

echo "=== test-portability: rill init seeds placeholders (sed_inplace) ==="

if (cd "$VAULT" && "$RILL_BIN" init --name portability-test --no-default >/dev/null 2>&1); then
  pass "rill init completes (rc=0)"
else
  fail "rill init failed"
fi

if [ -f "$VAULT/taxonomy.md" ] && ! grep -q '__INIT_DATE__' "$VAULT/taxonomy.md"; then
  pass "taxonomy.md seeded with __INIT_DATE__ replaced"
else
  fail "taxonomy.md missing or still contains __INIT_DATE__"
fi

if ! grep -rq '__INIT_DATE__\|__INIT_DAY__' "$VAULT/knowledge" "$VAULT/inbox" 2>/dev/null; then
  pass "seeded sample content has no __INIT_ placeholders"
else
  fail "seeded sample content still contains __INIT_ placeholders"
fi

export RILL_HOME="$VAULT"

echo "=== test-portability: rill touch insert + update (sed_inplace) ==="

NOTE="$VAULT/knowledge/notes/portability-touch-test.md"
printf -- '---\ncreated: 2026-01-01T00:00+09:00\ntype: insight\ntags: [testing]\n---\n\nTouch test body.\n' > "$NOTE"

# cmd_touch reads PostToolUse hook JSON from stdin
printf '{"tool_input":{"file_path":"%s"}}' "$NOTE" | "$RILL_BIN" touch
if [ "$(grep -c '^updated:' "$NOTE")" -eq 1 ]; then
  pass "rill touch inserts updated: after created: (append form)"
else
  fail "rill touch insert produced $(grep -c '^updated:' "$NOTE") updated: lines (expected 1)"
fi

# Rewrite updated: to a sentinel, then re-touch: the substitute branch must
# replace it. (The touch timestamp is minute-granular, so comparing two
# immediate touches would be flaky; the sentinel is deterministic.)
awk '{ if ($0 ~ /^updated:/) print "updated: 2020-01-01T00:00+09:00"; else print }' "$NOTE" > "$NOTE.tmp" && mv "$NOTE.tmp" "$NOTE"
printf '{"tool_input":{"file_path":"%s"}}' "$NOTE" | "$RILL_BIN" touch
if [ "$(grep -c '^updated:' "$NOTE")" -eq 1 ] && ! grep -q '^updated: 2020-01-01' "$NOTE"; then
  pass "rill touch updates existing updated: in place (substitute form)"
else
  fail "rill touch update: count=$(grep -c '^updated:' "$NOTE"), line=$(grep '^updated:' "$NOTE" | tr '\n' ' ')"
fi

if grep -qE '^updated: [0-9]{4}-[0-9]{2}-[0-9]{2}T' "$NOTE"; then
  pass "updated: value is a well-formed timestamp"
else
  fail "updated: value malformed: $(grep '^updated:' "$NOTE")"
fi

echo "=== test-portability: rill strip-entity-tags (sed_inplace) ==="

mkdir -p "$VAULT/projects/porta-proj"
printf -- '---\ntype: project\nid: porta-proj\nname: Portability fixture project\ndescription: Fixture entity for the portability test.\nstatus: active\n---\n\n# Portability fixture project\n' > "$VAULT/projects/porta-proj/_project.md"

NOTE_INSERT="$VAULT/knowledge/notes/porta-strip-insert.md"
printf -- '---\ncreated: 2026-01-01T00:00+09:00\ntype: insight\ntags: [porta-proj, testing]\n---\n\nStrip test: mentions line absent.\n' > "$NOTE_INSERT"

NOTE_REPLACE="$VAULT/knowledge/notes/porta-strip-replace.md"
printf -- '---\ncreated: 2026-01-01T00:00+09:00\ntype: insight\ntags: [porta-proj, testing]\nmentions: [people/porta-person]\n---\n\nStrip test: mentions line present.\n' > "$NOTE_REPLACE"

if "$RILL_BIN" strip-entity-tags "$NOTE_INSERT" "$NOTE_REPLACE" >/dev/null 2>&1; then
  pass "rill strip-entity-tags completes (rc=0)"
else
  fail "rill strip-entity-tags failed"
fi

if grep -q '^mentions: \[projects/porta-proj\]' "$NOTE_INSERT" && ! grep '^tags:' "$NOTE_INSERT" | grep -q 'porta-proj'; then
  pass "strip-entity-tags inserts mentions after tags (append form)"
else
  fail "strip-entity-tags insert branch: $(grep -E '^(tags|mentions):' "$NOTE_INSERT" | tr '\n' ' ')"
fi

if grep '^mentions:' "$NOTE_REPLACE" | grep -q 'projects/porta-proj' && grep '^mentions:' "$NOTE_REPLACE" | grep -q 'people/porta-person'; then
  pass "strip-entity-tags rewrites existing mentions line (substitute form)"
else
  fail "strip-entity-tags replace branch: $(grep -E '^(tags|mentions):' "$NOTE_REPLACE" | tr '\n' ' ')"
fi

echo "=== test-portability: briefing-context.sh (dual-mode stat) ==="

WS="$VAULT/workspace/2026-01-01-porta-ws"
mkdir -p "$WS"
printf -- '---\ncreated: 2026-01-01T09:00+09:00\ntype: workspace\nid: 2026-01-01-porta-ws\nname: Portability WS\nstatus: active\n---\n' > "$WS/_workspace.md"
printf -- '---\ncreated: 2026-01-01T10:00+09:00\ntopic: 2026-01-01-porta-ws\ntype: research\n---\n\nArtifact.\n' > "$WS/001-artifact.md"

VAULT_BRIEFING="$VAULT/.claude/commands/_lib/briefing-context.sh"
if [ ! -f "$VAULT_BRIEFING" ]; then
  # init distributes _lib scripts; fall back to a direct copy if the
  # manifest ever changes so this section keeps testing the stat path.
  mkdir -p "$(dirname "$VAULT_BRIEFING")"
  cp "$BRIEFING_LIB" "$VAULT_BRIEFING"
fi

BRIEFING_OUT="$TMP_ROOT/briefing-out.yaml"
if bash "$VAULT_BRIEFING" 2026-01-02 > "$BRIEFING_OUT" 2>"$TMP_ROOT/briefing-err.txt"; then
  pass "briefing-context.sh completes (rc=0)"
else
  fail "briefing-context.sh failed: $(head -3 "$TMP_ROOT/briefing-err.txt" | tr '\n' ' ')"
fi

if grep -q 'last_modified: [0-9]\{4\}-' "$BRIEFING_OUT"; then
  pass "briefing-context.sh resolves last_modified via native stat flavor"
else
  fail "last_modified not resolved: $(grep 'last_modified' "$BRIEFING_OUT" | tr '\n' ' ')"
fi

echo "==================================="
if [ "$FAIL_COUNT" -gt 0 ]; then
  echo "test-portability: $FAIL_COUNT FAILED, $PASS_COUNT passed"
  exit 1
fi
echo "test-portability: ALL PASSED ($PASS_COUNT)"
