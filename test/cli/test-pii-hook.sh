#!/bin/bash
# test/cli/test-pii-hook.sh — PII pre-commit hook + `rill crypt hook`
#
# The pre-commit hook (ADR-047 D47-3) is the gate that keeps third-party
# contact PII out of non-encrypted vault files. The load-bearing properties:
#   - it blocks staged .md files containing unknown email addresses / phone
#     numbers outside the encrypted containers
#   - the vault-local allowlist (.rill/pii-allowlist.txt) suppresses values
#     that are not third-party PII (the owner's own addresses), so routine
#     commits are not blocked
#   - encrypted containers (knowledge/people|orgs, sales-crm data) are exempt
#   - with no LLM available, phone candidates fail safe (block, not pass)
#   - `rill crypt hook` installs the hook without requiring git-crypt
#
# All hook invocations run with PATH stripped to /usr/bin:/bin so no claude
# or codex CLI is reachable — tests are deterministic and offline.
#
# Usage: bash test/cli/test-pii-hook.sh
# Requires: bash, git. No claude CLI, no network.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
RILL="$REPO_ROOT/bin/rill"
HOOK="$REPO_ROOT/bin/hooks/pre-commit-pii-check.sh"

# shellcheck source=test/assertions/lib.sh
source "$SCRIPT_DIR/../assertions/lib.sh"

WORK="$(mktemp -d)"
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

VAULT="$WORK/vault"
mkdir -p "$VAULT"
git -C "$VAULT" init -q
git -C "$VAULT" config user.email "test@example.com"
git -C "$VAULT" config user.name "Test"
mkdir -p "$VAULT/.rill" "$VAULT/knowledge/notes" "$VAULT/knowledge/people" "$VAULT/workspace"

# Run the hook as git would: CWD = repo root. PATH excludes claude/codex.
run_hook() {
  local rc=0
  (cd "$VAULT" && PATH="/usr/bin:/bin" bash "$HOOK") > "$WORK/out.txt" 2>&1 || rc=$?
  echo "$rc"
}

stage() { git -C "$VAULT" add -A; }
unstage_all() { git -C "$VAULT" rm -rq --cached . 2>/dev/null || true; }
reset_tree() {
  unstage_all
  rm -rf "$VAULT/knowledge/notes" "$VAULT/knowledge/people" "$VAULT/workspace"
  mkdir -p "$VAULT/knowledge/notes" "$VAULT/knowledge/people" "$VAULT/workspace"
  rm -f "$VAULT/.rill/pii-allowlist.txt"
}

echo "=== no staged markdown ==="
reset_tree
rc="$(run_hook)"
assert_eq "$rc" "0" "empty staging area passes"

echo ""
echo "=== email detection ==="
reset_tree
echo "Contact: taro.yamada@client-corp.co.jp" > "$VAULT/knowledge/notes/meeting.md"
stage
rc="$(run_hook)"
assert_eq "$rc" "1" "unknown email outside containers blocks the commit"
assert_file_contains "$WORK/out.txt" "Email address pattern" "block message names the email finding"

echo "Contact: someone@example.com and noreply@service.io" > "$VAULT/knowledge/notes/meeting.md"
stage
rc="$(run_hook)"
assert_eq "$rc" "0" "example.com and noreply@ addresses are ignored"

reset_tree
echo "Contact: alex@partner-firm.com" > "$VAULT/knowledge/people/alex.md"
stage
rc="$(run_hook)"
assert_eq "$rc" "0" "email inside knowledge/people/ (encrypted container) passes"

reset_tree
echo "reach me at someone@real-company.net" > "$VAULT/workspace/notes.txt"
stage
rc="$(run_hook)"
assert_eq "$rc" "0" "non-markdown files are not scanned"

echo ""
echo "=== allowlist ==="
reset_tree
echo "Sent from owner@my-own-domain.jp" > "$VAULT/knowledge/notes/self-note.md"
stage
rc="$(run_hook)"
assert_eq "$rc" "1" "own address blocks before it is allowlisted"

cat > "$VAULT/.rill/pii-allowlist.txt" <<'EOF'
# vault owner's own addresses (tool configuration, not third-party PII)

owner@my-own-domain.jp
EOF
rc="$(run_hook)"
assert_eq "$rc" "0" "allowlisted address passes (comments and blank lines ignored)"

echo "owner@my-own-domain.jp and taro.yamada@client-corp.co.jp" > "$VAULT/knowledge/notes/self-note.md"
stage
rc="$(run_hook)"
assert_eq "$rc" "1" "non-allowlisted address still blocks alongside an allowlisted one"

reset_tree
printf '# allow\nann@corp-x.jp\n' > "$VAULT/.rill/pii-allowlist.txt"
echo "cc: joann@corp-x.jp" > "$VAULT/knowledge/notes/super.md"
stage
rc="$(run_hook)"
assert_eq "$rc" "1" "allowlist is whole-value: ann@ does not suppress joann@"

echo ""
echo "=== phone detection (no LLM in PATH) ==="
reset_tree
echo "TEL: 090-1234-5678" > "$VAULT/knowledge/notes/contact-note.md"
stage
rc="$(run_hook)"
assert_eq "$rc" "1" "phone pattern with no LLM available fails safe (blocks)"
assert_file_contains "$WORK/out.txt" "LLM unavailable" "fallback message says LLM was unavailable"

printf '# own numbers\n090-1234-5678\n' > "$VAULT/.rill/pii-allowlist.txt"
rc="$(run_hook)"
assert_eq "$rc" "0" "allowlisted phone number passes without invoking an LLM"

echo "own 090-1234-5678 / their 080-9999-8888" > "$VAULT/knowledge/notes/contact-note.md"
stage
rc="$(run_hook)"
assert_eq "$rc" "1" "allowlisted phone does not hide a second phone on the same line"

reset_tree
echo "created: 2026-07-31T10:00+09:00" > "$VAULT/knowledge/notes/dated.md"
stage
rc="$(run_hook)"
assert_eq "$rc" "0" "ISO dates do not match the phone patterns"

echo ""
echo "=== rill crypt hook (standalone install) ==="
rc=0
RILL_HOME="$VAULT" "$RILL" crypt hook > "$WORK/out.txt" 2>&1 || rc=$?
assert_eq "$rc" "0" "crypt hook exits 0 in a git repo"
assert_true "[ -L '$VAULT/.git/hooks/pre-commit' ]" "pre-commit symlink installed"
assert_true "[ -f \"\$(readlink '$VAULT/.git/hooks/pre-commit')\" ]" "symlink resolves to the hook script"

rc=0
RILL_HOME="$VAULT" "$RILL" crypt hook > "$WORK/out.txt" 2>&1 || rc=$?
assert_eq "$rc" "0" "re-running crypt hook is idempotent"

NOTGIT="$WORK/notgit"
mkdir -p "$NOTGIT"
rc=0
RILL_HOME="$NOTGIT" "$RILL" crypt hook > "$WORK/out.txt" 2>&1 || rc=$?
assert_true "[ $rc -ne 0 ]" "crypt hook fails outside a git repository"

FOREIGN="$WORK/foreign"
mkdir -p "$FOREIGN"
git -C "$FOREIGN" init -q
echo '#!/bin/sh' > "$FOREIGN/.git/hooks/pre-commit"
chmod +x "$FOREIGN/.git/hooks/pre-commit"
rc=0
RILL_HOME="$FOREIGN" "$RILL" crypt hook > "$WORK/out.txt" 2>&1 || rc=$?
assert_true "[ $rc -ne 0 ]" "existing non-symlink pre-commit hook is not overwritten"
assert_file_contains "$WORK/out.txt" "Manual installation needed" "manual-install guidance shown"

echo ""
echo "=== installed hook fires on a real commit ==="
echo "call me: someone@real-client.org" > "$VAULT/knowledge/notes/leak.md"
git -C "$VAULT" add -A
rc=0
(cd "$VAULT" && PATH="/usr/bin:/bin" git commit -q -m "leak test") > "$WORK/out.txt" 2>&1 || rc=$?
assert_true "[ $rc -ne 0 ]" "git commit is blocked by the installed hook"

rm -f "$VAULT/knowledge/notes/leak.md"
echo "clean note" > "$VAULT/knowledge/notes/clean.md"
git -C "$VAULT" add -A
rc=0
(cd "$VAULT" && PATH="/usr/bin:/bin" git commit -q -m "clean test") > "$WORK/out.txt" 2>&1 || rc=$?
assert_eq "$rc" "0" "clean commit goes through the installed hook"

report_results
