#!/usr/bin/env bash
# test/cli/test-eval-distribution.sh -- eval/ input distribution + init/update
# manifest-parity regression tests
#
# Guards: `rill init` and `rill update` both distribute eval/concept.md
# (Category A -- always kept current, like SPEC.md) and seed
# eval/queries.yaml (Category B -- placed once, never clobbered by a later
# update -- it's /eval's required input, see skills/eval/SKILL.md Phase 1a
# and eval/queries.yaml's own "this is a sample, replace it" header). Also
# guards init/update manifest parity: init distributes SPEC.md (previously
# update-only) and creates inbox/think-outputs/ (previously init-only
# omission), and update backfills inbox/think-outputs/ for vaults that
# predate this fix.
#
# Pure shell, no claude invocation.
#
# Usage: bash test/cli/test-eval-distribution.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
RILL_BIN="$REPO_ROOT/bin/rill"

PASS_COUNT=0
FAIL_COUNT=0

pass() { PASS_COUNT=$((PASS_COUNT + 1)); echo "  ok: $1"; }
fail() { FAIL_COUNT=$((FAIL_COUNT + 1)); echo "  FAIL: $1"; }

# --- Sandbox (isolated HOME / RILL_SOURCE / RILL_HOME) -----------------
TMP_ROOT="$(mktemp -d -t rill-eval-dist-XXXXXX)"
cleanup() { rm -rf "$TMP_ROOT"; }
trap cleanup EXIT

export HOME="$TMP_ROOT/home"
mkdir -p "$HOME"
export RILL_SOURCE="$REPO_ROOT"
VAULT="$TMP_ROOT/vault"
mkdir -p "$VAULT"

MANAGED="$VAULT/.rill/managed-files.txt"

echo "=== test-eval-distribution: rill init distributes eval/ inputs ==="

if (cd "$VAULT" && "$RILL_BIN" init --name eval-dist-test --no-default >/dev/null 2>&1); then
  pass "rill init completes (rc=0)"
else
  fail "rill init failed"
fi

if [ -f "$VAULT/eval/concept.md" ]; then
  pass "eval/concept.md distributed by init"
else
  fail "eval/concept.md missing after init"
fi

if [ -f "$VAULT/eval/queries.yaml" ] && grep -qi "sample" "$VAULT/eval/queries.yaml"; then
  pass "eval/queries.yaml (sample) seeded by init"
else
  fail "eval/queries.yaml missing, or does not look like the sample, after init"
fi

if grep -Fxq "eval/concept.md" "$MANAGED"; then
  pass "eval/concept.md is Category A (listed in managed-files.txt)"
else
  fail "eval/concept.md not in managed-files.txt (would never refresh on update)"
fi

if ! grep -Fxq "eval/queries.yaml" "$MANAGED"; then
  pass "eval/queries.yaml is Category B (absent from managed-files.txt, so update won't overwrite it)"
else
  fail "eval/queries.yaml is in managed-files.txt (update would clobber user customization)"
fi

echo "=== test-eval-distribution: init/update manifest parity ==="

if [ -f "$VAULT/SPEC.md" ] && grep -Fxq "SPEC.md" "$MANAGED"; then
  pass "SPEC.md distributed and managed by init (parity with update)"
else
  fail "SPEC.md missing or not managed after init"
fi

if [ -d "$VAULT/inbox/think-outputs" ]; then
  pass "inbox/think-outputs/ created by init"
else
  fail "inbox/think-outputs/ missing after init"
fi

echo "=== test-eval-distribution: Category B survives rill update (user edits preserved) ==="

printf '\n- id: CUSTOM-1\n  query: "user customized this file"\n  type: factual\n  scope: narrow\n' >> "$VAULT/eval/queries.yaml"

export RILL_HOME="$VAULT"
if (cd "$VAULT" && "$RILL_BIN" update --vault eval-dist-test >/dev/null 2>&1); then
  pass "rill update completes (rc=0)"
else
  fail "rill update failed"
fi

if grep -q "CUSTOM-1" "$VAULT/eval/queries.yaml"; then
  pass "rill update did not overwrite user-customized eval/queries.yaml (Category B honored)"
else
  fail "rill update clobbered eval/queries.yaml (Category B invariant broken)"
fi

echo "=== test-eval-distribution: Category A is kept current by rill update ==="

printf '\nLOCAL EDIT THAT SHOULD BE REVERTED\n' >> "$VAULT/eval/concept.md"

if (cd "$VAULT" && "$RILL_BIN" update --vault eval-dist-test >/dev/null 2>&1); then
  pass "rill update completes again (rc=0)"
else
  fail "rill update (2nd run) failed"
fi

if ! grep -q "LOCAL EDIT THAT SHOULD BE REVERTED" "$VAULT/eval/concept.md" \
   && diff -q "$REPO_ROOT/eval/concept.md" "$VAULT/eval/concept.md" >/dev/null 2>&1; then
  pass "rill update overwrote eval/concept.md back to canonical source (Category A honored)"
else
  fail "eval/concept.md was not restored to canonical source content by rill update"
fi

echo "=== test-eval-distribution: rill update backfills eval/ + think-outputs/ for pre-existing vaults ==="

rm -rf "$VAULT/eval" "$VAULT/inbox/think-outputs"

if (cd "$VAULT" && "$RILL_BIN" update --vault eval-dist-test >/dev/null 2>&1); then
  pass "rill update completes on a vault missing eval/ entirely (rc=0)"
else
  fail "rill update failed when eval/ was entirely absent"
fi

if [ -f "$VAULT/eval/concept.md" ] && [ -f "$VAULT/eval/queries.yaml" ]; then
  pass "rill update retroactively backfills eval/ for a vault that never had it"
else
  fail "rill update did not backfill eval/ for a pre-existing vault"
fi

if grep -qi "sample" "$VAULT/eval/queries.yaml"; then
  pass "backfilled eval/queries.yaml is the clean sample (not stale content)"
else
  fail "backfilled eval/queries.yaml does not look like the sample"
fi

if [ -d "$VAULT/inbox/think-outputs" ]; then
  pass "rill update backfills inbox/think-outputs/ for a pre-existing vault"
else
  fail "rill update did not backfill inbox/think-outputs/"
fi

echo "==================================="
if [ "$FAIL_COUNT" -gt 0 ]; then
  echo "test-eval-distribution: $FAIL_COUNT FAILED, $PASS_COUNT passed"
  exit 1
fi
echo "test-eval-distribution: ALL PASSED ($PASS_COUNT)"
