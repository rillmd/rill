#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
RILL_BIN="$REPO_ROOT/bin/rill"
TMP_ROOT="$(mktemp -d -t rill-codex-XXXXXX)"
trap 'rm -rf "$TMP_ROOT"' EXIT

export HOME="$TMP_ROOT/home"
export RILL_SOURCE="$REPO_ROOT"
mkdir -p "$HOME"
VAULT="$TMP_ROOT/vault"

"$RILL_BIN" init "$VAULT" --name codex-test --no-default >/dev/null

test -f "$VAULT/AGENTS.md"
test -f "$VAULT/inbox/AGENTS.md"
test -f "$VAULT/.codex/hooks.json"
test -f "$VAULT/.agents/skills/distill/SKILL.md"
test -f "$VAULT/.agents/skills/close/SKILL.md"

claude_count="$(find "$VAULT/.claude/skills" -name SKILL.md | wc -l | tr -d ' ')"
codex_count="$(find "$VAULT/.agents/skills" -name SKILL.md | wc -l | tr -d ' ')"
test "$claude_count" -eq "$codex_count"

printf '%s\n' '---' 'description: Personal test workflow' '---' '# Personal' \
  > "$VAULT/.claude/commands/personal-test.md"
"$RILL_BIN" update --vault codex-test >/dev/null
test -L "$VAULT/.agents/skills/personal-test/SKILL.md"

if printf '%s' '{"tool_input":{"file_path":"inbox/AGENTS.md"}}' \
  | (cd "$VAULT" && "$RILL_BIN" codex-hook pre-write) >/dev/null 2>&1; then
  echo "managed Codex write was not blocked" >&2
  exit 1
fi

printf '%s' '{"tool_input":{"file_path":"knowledge/notes/new.md"}}' \
  | (cd "$VAULT" && "$RILL_BIN" codex-hook pre-write)

(cd "$VAULT" && "$RILL_BIN" doctor codex)
echo "test-codex-projection: ALL PASSED"
