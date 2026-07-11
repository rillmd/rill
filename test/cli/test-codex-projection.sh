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

# --- Deny-rules file install (Tier 3 destructive-op port) ---
test -f "$VAULT/.codex/rules/rill-deny.rules"
grep -Fxq ".codex/rules/rill-deny.rules" "$VAULT/.rill/managed-files.txt"

# --- Root guidance table: every installed container directory has both a
# nested AGENTS.md twin and a row in the root AGENTS.md table pointing at
# it. This must stay in lockstep with bin/rill's subdir_claude list — a
# table row without an installed file (or vice versa) is a bug. ---
CONTAINER_DIRS=(
  "inbox"
  "inbox/journal"
  "inbox/meetings"
  "inbox/tweets"
  "inbox/web-clips"
  "inbox/sources"
  "knowledge/notes"
  "knowledge/people"
  "knowledge/orgs"
  "knowledge/self"
  "projects"
  "workspace"
  "tasks"
  "pages"
  "reports/daily"
  "reports/newsletter"
)
for dir in "${CONTAINER_DIRS[@]}"; do
  test -f "$VAULT/$dir/AGENTS.md"
  grep -Fq "| \`$dir/\` | \`$dir/CLAUDE.md\` |" "$VAULT/AGENTS.md"
done

# Root AGENTS.md must stay well under Codex's 32 KiB project_doc_max_bytes,
# and the task's own ~4 KB target.
agents_bytes="$(wc -c < "$VAULT/AGENTS.md" | tr -d ' ')"
test "$agents_bytes" -lt 4096

printf '%s\n' '---' 'description: Personal test workflow' '---' '# Personal' \
  > "$VAULT/.claude/commands/personal-test.md"
"$RILL_BIN" update --vault codex-test >/dev/null
test -L "$VAULT/.agents/skills/personal-test/SKILL.md"

# Deny rules must survive reprojection on `rill update` too.
test -f "$VAULT/.codex/rules/rill-deny.rules"
grep -Fxq ".codex/rules/rill-deny.rules" "$VAULT/.rill/managed-files.txt"

if printf '%s' '{"tool_input":{"file_path":"inbox/AGENTS.md"}}' \
  | (cd "$VAULT" && "$RILL_BIN" codex-hook pre-write) >/dev/null 2>&1; then
  echo "managed Codex write was not blocked" >&2
  exit 1
fi

printf '%s' '{"tool_input":{"file_path":"knowledge/notes/new.md"}}' \
  | (cd "$VAULT" && "$RILL_BIN" codex-hook pre-write)

# --- execpolicy functional checks (only when the codex binary is present —
# never required; CI and many dev machines won't have it). ---
if command -v codex &>/dev/null; then
  deny_check="$(codex execpolicy check --rules "$VAULT/.codex/rules/rill-deny.rules" \
    -- git push --force origin main 2>&1 || true)"
  case "$deny_check" in
    *'"decision":"forbidden"'*) ;;
    *)
      echo "codex execpolicy did not forbid 'git push --force origin main'" >&2
      echo "$deny_check" >&2
      exit 1
      ;;
  esac

  reset_check="$(codex execpolicy check --rules "$VAULT/.codex/rules/rill-deny.rules" \
    -- git reset --hard HEAD~1 2>&1 || true)"
  case "$reset_check" in
    *'"decision":"forbidden"'*) ;;
    *)
      echo "codex execpolicy did not forbid 'git reset --hard HEAD~1'" >&2
      echo "$reset_check" >&2
      exit 1
      ;;
  esac

  admin_check="$(codex execpolicy check --rules "$VAULT/.codex/rules/rill-deny.rules" \
    -- gh pr merge --admin 5 2>&1 || true)"
  case "$admin_check" in
    *'"decision":"forbidden"'*) ;;
    *)
      echo "codex execpolicy did not forbid 'gh pr merge --admin 5'" >&2
      echo "$admin_check" >&2
      exit 1
      ;;
  esac

  for allowed_cmd in "git status" "git push origin feature/x" "rill push"; do
    allow_check="$(codex execpolicy check --rules "$VAULT/.codex/rules/rill-deny.rules" \
      -- $allowed_cmd 2>&1 || true)"
    case "$allow_check" in
      *'"decision":"forbidden"'*)
        echo "codex execpolicy incorrectly forbade '$allowed_cmd'" >&2
        echo "$allow_check" >&2
        exit 1
        ;;
      *) ;;
    esac
  done
fi

(cd "$VAULT" && "$RILL_BIN" doctor codex)
echo "test-codex-projection: ALL PASSED"
