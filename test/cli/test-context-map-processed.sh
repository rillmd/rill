#!/bin/bash
# test/cli/test-context-map-processed.sh — Pure-shell tests for the two
# deterministic-plumbing commands added for /distill Step 1 + Step 2/5/7 and
# /close Phase 1 (fixed-cost elimination):
#
#   rill context-map   — people/orgs/projects one-line mappings + entity-ID
#                        list + Tier dict, frontmatter-only, 0 LLM tokens.
#   rill processed     — set / count / list / normalize on .processed files,
#                        last-wins reads, one-line-per-file, format-preserving.
#
# Regressions frozen here:
#   - context-map must IGNORE files without top-of-file frontmatter (container
#     CLAUDE.md / AGENTS.md whose bodies contain a fenced ```yaml --- example),
#     so they never leak as entities nor as phantom Tier-dict mentions.
#   - context-map output is deterministic (stable sort) modulo `computed_at`.
#   - processed reads are last-wins: an already-`extracted` file carrying a
#     stale `:organized` line is NOT re-selected (the re-processing hazard the
#     old append-style .processed produced).
#   - processed preserves both formats: `name:status` (rewrite in place) and
#     bare `name` (journal/think-outputs) — never adds a status to a bare line.
#
# Usage: bash test/cli/test-context-map-processed.sh
# Requires: bash, awk, find. No claude CLI, no network.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
RILL="$REPO_ROOT/bin/rill"

# shellcheck source=test/assertions/lib.sh
source "$SCRIPT_DIR/../assertions/lib.sh"

WORK="$(mktemp -d)"
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

assert_out_contains() {
  local haystack="$1" needle="$2" msg="$3"
  _TOTAL=$((_TOTAL + 1))
  if [[ "$haystack" == *"$needle"* ]]; then
    _PASS=$((_PASS + 1)); printf "  ${_GREEN}PASS${_NC}: %s\n" "$msg"
  else
    _FAIL=$((_FAIL + 1)); _FAILURES+=("$msg")
    printf "  ${_RED}FAIL${_NC}: %s\n" "$msg"; printf "    output was: %.400s\n" "$haystack"
  fi
}
assert_out_not_contains() {
  local haystack="$1" needle="$2" msg="$3"
  _TOTAL=$((_TOTAL + 1))
  if [[ "$haystack" != *"$needle"* ]]; then
    _PASS=$((_PASS + 1)); printf "  ${_GREEN}PASS${_NC}: %s\n" "$msg"
  else
    _FAIL=$((_FAIL + 1)); _FAILURES+=("$msg")
    printf "  ${_RED}FAIL${_NC}: %s\n" "$msg"
  fi
}

# --- Hermetic fixture vault -------------------------------------------------
VAULT="$WORK/vault"
mkdir -p "$VAULT"/knowledge/{people,orgs,notes} "$VAULT"/projects/phoenix
mkdir -p "$VAULT"/workspace "$VAULT"/tasks

# Real entities (top-of-file frontmatter).
cat > "$VAULT/knowledge/people/alex-chen.md" <<'EOF'
---
type: person
id: alex-chen
name: Alex Chen
aliases: [A. Chen, Chen]
company: acme
---
# Alex Chen
EOF
cat > "$VAULT/knowledge/orgs/acme.md" <<'EOF'
---
type: org
id: acme
name: Acme Corporation
aliases: [Acme, Acme Inc]
---
# Acme
EOF
cat > "$VAULT/projects/phoenix/_project.md" <<'EOF'
---
type: project
id: phoenix
name: Project Phoenix
status: active
tags: [infrastructure, migration]
---
# Project Phoenix
EOF

# Container instruction files (NO top frontmatter; a fenced ```yaml example
# with its own --- fences + a mentions line). These must be ignored entirely.
cat > "$VAULT/knowledge/people/CLAUDE.md" <<'EOF'
# knowledge/people/ conventions

Example frontmatter:

```yaml
---
type: person
name: Example Person   # Required
company: ghost-org
---
```
EOF
cp "$VAULT/knowledge/people/CLAUDE.md" "$VAULT/knowledge/orgs/AGENTS.md"
cat > "$VAULT/knowledge/notes/CLAUDE.md" <<'EOF'
# knowledge/notes/ conventions

```yaml
---
mentions: [orgs/ghost-org, people/ghost-person]
---
```
EOF

# Scope files that mention alex-chen 8 times (→ tier1) and acme 3 times (→ tier2).
i=1; while [ "$i" -le 8 ]; do
  cat > "$VAULT/knowledge/notes/note-$i.md" <<EOF
---
type: insight
mentions: [people/alex-chen]
---
# note $i
EOF
  i=$((i + 1))
done
i=1; while [ "$i" -le 3 ]; do
  cat > "$VAULT/workspace/ws-$i.md" <<EOF
---
type: workspace
mentions:
  - orgs/acme
---
# ws $i
EOF
  i=$((i + 1))
done

echo "=== context-map: output shape ==="
out="$(RILL_HOME="$VAULT" "$RILL" context-map 2>/dev/null)"
for h in "### People mapping" "### Orgs mapping" "### Projects mapping" "### Entity IDs" "### Tier dict" "computed_at:" "counts:" "tier_assignment:"; do
  assert_out_contains "$out" "$h" "context-map emits '$h'"
done

echo "=== context-map: mappings (real entities, formats) ==="
assert_out_contains "$out" "people/alex-chen: Alex Chen | aliases: A. Chen,Chen | company: acme" "people line has name+aliases+company"
assert_out_contains "$out" "orgs/acme: Acme Corporation (Acme,Acme Inc)" "orgs line has name+aliases"
assert_out_contains "$out" "projects/phoenix: Project Phoenix (active, tags: infrastructure,migration)" "projects line has status+tags"

echo "=== context-map: container files excluded (regression) ==="
assert_out_not_contains "$out" "people/CLAUDE" "CLAUDE.md not emitted as a person"
assert_out_not_contains "$out" "orgs/AGENTS" "AGENTS.md not emitted as an org"
assert_out_not_contains "$out" "Example Person" "fenced-example name did not leak"
assert_out_not_contains "$out" "ghost-org" "fenced-example mention did not leak (mapping or tier)"
assert_out_not_contains "$out" "ghost-person" "fenced-example mention did not leak (tier)"

echo "=== context-map: entity-ID coverage (3 real entities only) ==="
ids="$(printf '%s\n' "$out" | awk '/^### Entity IDs$/{f=1;next}/^### /{f=0}f&&/\//')"
assert_eq "$(printf '%s\n' "$ids" | grep -c .)" "3" "exactly 3 entity IDs (no containers)"

echo "=== context-map: Tier dict values ==="
assert_out_contains "$out" "people/alex-chen: tier1" "alex-chen (8 mentions) → tier1"
assert_out_contains "$out" "orgs/acme: tier2" "acme (3 mentions) → tier2"

echo "=== context-map: determinism (modulo computed_at) ==="
a="$(RILL_HOME="$VAULT" "$RILL" context-map 2>/dev/null | grep -v '^computed_at:')"
b="$(RILL_HOME="$VAULT" "$RILL" context-map 2>/dev/null | grep -v '^computed_at:')"
assert_true "[ \"$a\" = \"$b\" ]" "two runs byte-identical after dropping computed_at"

echo ""
echo "=== processed: status-bearing normalize (last-wins, one line per file) ==="
P="$WORK/p-status"
printf '%s\n' 'a.md:organized' 'b.md:organized' 'a.md:extracted' 'c.md:organized' 'b.md:extracted' > "$P"
"$RILL" processed normalize "$P"
assert_eq "$(wc -l < "$P" | tr -d ' ')" "3" "3 names → 3 lines"
assert_file_contains "$P" "a.md:extracted" "a.md keeps its last status (extracted)"
assert_file_contains "$P" "c.md:organized" "c.md unchanged (organized)"
assert_file_not_contains "$P" "a.md:organized" "stale a.md:organized removed"
assert_eq "$("$RILL" processed count "$P" organized)" "1" "count organized = 1 (c only)"
assert_eq "$("$RILL" processed count "$P" extracted)" "2" "count extracted = 2 (a,b)"

echo "=== processed: bare (journal) normalize preserves format ==="
Q="$WORK/p-bare"
printf '%s\n' 'x.md' 'y.md' 'x.md' 'z.md' > "$Q"
"$RILL" processed normalize "$Q"
assert_eq "$(wc -l < "$Q" | tr -d ' ')" "3" "deduped to 3 bare lines"
assert_eq "$(grep -c ':' "$Q")" "0" "no status introduced on bare lines"

echo "=== processed: last-wins reader prevents re-processing ==="
R="$WORK/p-lastwins"
printf '%s\n' 'g.md:organized' 'h.md:organized' 'g.md:extracted' > "$R"
assert_eq "$("$RILL" processed list "$R" --status organized)" "h.md" "list organized excludes already-extracted g"
assert_eq "$("$RILL" processed count "$R" organized)" "1" "count organized ignores stale g:organized"
assert_eq "$("$RILL" processed list "$R" --status extracted)" "g.md" "list extracted returns g"

echo "=== processed: set (rewrite with status / bare append) ==="
S="$WORK/p-set"
printf '%s\n' 'm.md:organized' 'm.md:organized' > "$S"
"$RILL" processed set "$S" m.md extracted
assert_eq "$(grep -c '^m.md' "$S")" "1" "set collapses duplicate m to one line"
assert_file_contains "$S" "m.md:extracted" "set rewrote m to extracted"
T2="$WORK/p-setbare"
printf '%s\n' 'j.md' > "$T2"
"$RILL" processed set "$T2" j.md
assert_eq "$(grep -c '^j.md$' "$T2")" "1" "set bare dedups j"
assert_eq "$(grep -c ':' "$T2")" "0" "set bare adds no status"
"$RILL" processed set "$T2" k.md
assert_eq "$(grep -c '^k.md$' "$T2")" "1" "set bare appends new k"

echo ""
report_results
