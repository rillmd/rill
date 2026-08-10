#!/bin/bash
# pii-regex-guard.sh -- block emails / phone numbers / secret-shaped strings
# outside the allowlist.
#
# Generic patterns ONLY -- this guard carries no private vocabulary; the
# private-terms scan lives in bin/hooks/pre-push-pii-mapping-check.sh, which
# reads its terms from an out-of-repo file (see that file's header).
#
# Modes:
#   (default)  Tree mode. Scan every git-tracked text file; a hit is a
#              violation unless test/pii-regex-allowlist.txt has an entry with
#              (1) a path equal to the file AND (2) an ERE matching the line.
#   --stdin    Read raw text from stdin (e.g. commit messages). ANY hit is a
#              violation -- the path allowlist does not apply.
#
# Built-in noreply exemption (both modes): an email hit whose FULL match is a
# known non-personal noreply address is never a violation. Claude Code stamps
# every commit with "Co-Authored-By: ... <noreply@anthropic.com>", and GitHub
# squash merges add "Co-authored-by: ... <user@users.noreply.github.com>" --
# without this exemption every such PR fails the commit-message scan. These
# addresses are undeliverable by design and identify no mailbox. The check is
# full-match-anchored, so an address that merely extends a safe local part or
# puts "noreply" on another domain still fails; phone/secret hits are never
# exempt, including a phone/secret smuggled inside a safe-shaped address.
#
# Allowlist format (same contract as test/cjk-allowlist.txt):
#   <path><TAB><line-regex (ERE)><TAB><reason>
#
# Exit codes: 0 clean, 1 violations, 2 usage error.

set -euo pipefail

# Paths (allowlist, git ls-files) are repo-root-relative; run from anywhere.
cd "$(git rev-parse --show-toplevel)"

ALLOWLIST="test/pii-regex-allowlist.txt"

EMAIL_RE='[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}'
# Phone formats mirror bin/hooks/pre-commit-pii-check.sh (international with
# -/space/dot separators, JP 0-prefixed, US/CA parenthesized) plus the generic
# hyphenated shape used by the repo-wide push-guard scans.
PHONE_RE='\b[0-9]{2,4}-[0-9]{2,4}-[0-9]{4}\b|\+[0-9]{1,3}([- .][0-9]{1,4}){1,3}[- .][0-9]{3,4}|\b0[0-9]{1,4}-[0-9]{1,4}-[0-9]{3,4}\b|\([0-9]{2,4}\) ?[0-9]{3,4}[- .][0-9]{3,4}'
# sk- covers hyphenated OpenAI key families (sk-proj-..., sk-svcacct-...).
SECRET_RE='AKIA[0-9A-Z]{16}|\bgh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|-----BEGIN [A-Z ]*PRIVATE KEY-----|xox[baprs]-[A-Za-z0-9-]{10,}|\bsk-[A-Za-z0-9_-]{20,}'
PATTERN="$EMAIL_RE|$PHONE_RE|$SECRET_RE"

# See "Built-in noreply exemption" in the header. Anchored so only a hit that
# IS one of these addresses in full (not one merely containing/extending one)
# passes.
SAFE_NOREPLY_RE='^(noreply@anthropic\.com|[A-Za-z0-9._%+-]+@users\.noreply\.github\.com)$'

# 0 iff every PATTERN match on the line ($1) is a safe noreply address.
line_all_safe() {
  local m
  while IFS= read -r m; do
    [[ $m =~ $SAFE_NOREPLY_RE ]] || return 1
    # The combined PATTERN is leftmost-longest, so an email match can shadow
    # a phone/secret match overlapping it (e.g. a token as the local part of
    # a users.noreply address). Re-scan the matched address on its own.
    if grep -qE "$PHONE_RE|$SECRET_RE" <<< "$m"; then return 1; fi
  done < <(grep -oE "$PATTERN" <<< "$1")
  return 0
}

mode="${1:-tree}"

scan_stdin() {
  local hits line violations=0
  # grep exits 1 on no match; that is the clean case, not an error.
  hits="$(grep -nE "$PATTERN" || true)"
  [ -z "$hits" ] && return 0
  while IFS= read -r line; do
    line_all_safe "${line#*:}" && continue
    printf '(stdin):%s\n' "$line"
    violations=$((violations + 1))
  done <<< "$hits"
  if [ "$violations" -gt 0 ]; then
    echo "pii-regex-guard: email/phone/secret pattern in stdin (only the built-in noreply exemption applies here)" >&2
    return 1
  fi
  return 0
}

scan_tree() {
  local raw allowed apath aregex areason hit_path hit_line violations=0
  # -I skips binary files; git ls-files scopes to tracked files only.
  # -e/-- keep a pattern or filename starting with '-' from being parsed as
  # an option; grep errors go to stderr (visible in CI) instead of /dev/null.
  raw="$(git ls-files -z | xargs -0 grep -nHEI -e "$PATTERN" -- || true)"
  [ -z "$raw" ] && return 0

  # Load allowlist entries into parallel arrays (skip comments / blanks).
  local -a paths=() regexes=() reasons=() used=()
  if [ -f "$ALLOWLIST" ]; then
    while IFS=$'\t' read -r apath aregex areason; do
      case "$apath" in ''|\#*) continue ;; esac
      if [ -z "$aregex" ] || [ -z "$areason" ]; then
        echo "pii-regex-guard: malformed allowlist entry for '$apath' (need <path><TAB><regex><TAB><reason>)" >&2
        return 2
      fi
      paths+=("$apath"); regexes+=("$aregex"); reasons+=("$areason"); used+=(0)
    done < "$ALLOWLIST"
  fi

  while IFS= read -r line; do
    hit_path="${line%%:*}"
    hit_line="${line#*:}"; hit_line="${hit_line#*:}"  # strip path: and lineno:
    # Built-in noreply exemption: value-safe regardless of path.
    line_all_safe "$hit_line" && continue
    # Per-value allowlisting: strip every allowlisted match from the line,
    # then re-scan the remainder. A real secret sharing a line with an
    # allowlisted placeholder therefore still fails.
    allowed=0
    local i remainder stripped_any=0
    remainder="$hit_line"
    for i in "${!paths[@]}"; do
      [ "$hit_path" = "${paths[$i]}" ] || continue
      while [[ $remainder =~ ${regexes[$i]} ]]; do
        [ -z "${BASH_REMATCH[0]}" ] && break  # zero-length match: nothing to strip
        remainder="${remainder/"${BASH_REMATCH[0]}"/}"
        used[i]=1; stripped_any=1
      done
    done
    # Clean iff everything left after stripping is at most safe-noreply.
    if [ "$stripped_any" -eq 1 ] && line_all_safe "$remainder"; then
      allowed=1
    fi
    if [ "$allowed" -eq 0 ]; then
      printf '%s\n' "$line"
      violations=$((violations + 1))
    fi
  done <<< "$raw"

  local i
  for i in "${!paths[@]}"; do
    if [ "${used[$i]}" -eq 0 ]; then
      echo "pii-regex-guard: note: unused allowlist entry ${paths[$i]} / ${regexes[$i]} (${reasons[$i]})" >&2
    fi
  done

  if [ "$violations" -gt 0 ]; then
    echo "pii-regex-guard: $violations unallowlisted hit(s); add to $ALLOWLIST only if the value is a deliberate placeholder" >&2
    return 1
  fi
  return 0
}

case "$mode" in
  tree)    scan_tree ;;
  --stdin) scan_stdin ;;
  *)       echo "usage: $0 [--stdin]" >&2; exit 2 ;;
esac
