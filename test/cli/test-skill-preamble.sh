#!/bin/bash
# test/cli/test-skill-preamble.sh — Skill language-preamble consistency check
#
# Every skills/*/SKILL.md must carry the canonical language preamble exactly
# once, byte-for-byte, with no skill exempt. History: the preamble used to
# restate the language rule's exception list per skill, and the copies
# drifted as the rule evolved (2026-06: /newsletter lacked the preamble
# entirely and imported English vocabulary from web sources; 2026-07: /focus
# carried a stale copy without the translation-quality escape hatch, which
# produced invented literal calques). The preamble is now a pure pointer —
# language content lives in .claude/rules/rill-core.md (Language Rules) and
# the vault's personal-*.md overrides. This test freezes that shape:
#
#   - exactly one canonical preamble line per skill, every skill covered
#   - no reintroduced copy of the old restated exception list
#   - rill-core.md keeps the Translation quality bullet the pointer targets
#
# Sub-agent style_guide strings (close / distill / retrospective) are the
# one legitimate exception: they stay self-contained because coordinators
# string-match sentinel values in sub-agent output, and each skill's
# sentinel list differs. Their shared translation-quality tail must still
# match byte-for-byte across skills (second fixture below) so the three
# copies cannot drift apart the way the preamble copies did.
#
# To change the preamble wording: update
# test/fixtures/skill-language-preamble.txt and apply the same change to
# every skills/*/SKILL.md in one pass — never edit one skill alone.
#
# Usage: bash test/cli/test-skill-preamble.sh
# Requires: bash, grep. No claude CLI needed.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# shellcheck source=test/assertions/lib.sh
source "$SCRIPT_DIR/../assertions/lib.sh"

# The canonical line lives in a fixture, not inline: it contains backticks
# and apostrophes, which macOS bash 3.2 mis-parses inside quoted here-doc
# command substitutions.
FIXTURE="$SCRIPT_DIR/../fixtures/skill-language-preamble.txt"
CANONICAL="$(cat "$FIXTURE")"

TAIL_FIXTURE="$SCRIPT_DIR/../fixtures/style-guide-translation-tail.txt"
STYLE_TAIL="$(cat "$TAIL_FIXTURE")"

# The old preamble restated the exception list per skill; this exact clause
# must never come back (content belongs in rill-core.md / personal-*.md).
STALE_CLAUSE="Exceptions (only): tokens inside backticks or code blocks, proper nouns, ASCII acronyms"

if [[ -z "$CANONICAL" || -z "$STYLE_TAIL" ]]; then
  echo "FAIL: fixture $FIXTURE or $TAIL_FIXTURE is missing or empty"
  exit 1
fi

echo "== Skill language-preamble consistency =="

for skill_file in "$REPO_ROOT"/skills/*/SKILL.md; do
  skill_name="$(basename "$(dirname "$skill_file")")"

  # -x: whole-line match, so appending extra prose to the canonical line
  # (or burying it inside a longer line) is caught as drift.
  canonical_count="$(grep -cxF -- "$CANONICAL" "$skill_file" || true)"
  assert_eq "$canonical_count" "1" \
    "/$skill_name carries the canonical language preamble exactly once"

  stale_count="$(grep -cF -- "$STALE_CLAUSE" "$skill_file" || true)"
  assert_eq "$stale_count" "0" \
    "/$skill_name does not restate the old exception list"

  style_guide_count="$(grep -cF -- "style_guide=" "$skill_file" || true)"
  tail_count="$(grep -cF -- "$STYLE_TAIL" "$skill_file" || true)"
  assert_eq "$tail_count" "$style_guide_count" \
    "/$skill_name style_guide blocks carry the shared translation tail verbatim"
done

core_rule="$REPO_ROOT/.claude/rules/rill-core.md"
assert_true "grep -qF -- '**Translation quality**' '$core_rule'" \
  "rill-core.md defines the Translation quality bullet the preamble points to"

report_results
