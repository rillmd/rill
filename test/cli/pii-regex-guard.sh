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
#              violation -- no allowlist applies.
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

mode="${1:-tree}"

scan_stdin() {
  local hits
  # grep exits 1 on no match; that is the clean case, not an error.
  hits="$(grep -nE "$PATTERN" || true)"
  if [ -n "$hits" ]; then
    printf '%s\n' "$hits" | sed 's/^/(stdin):/'
    echo "pii-regex-guard: email/phone/secret pattern in stdin (no allowlist applies here)" >&2
    return 1
  fi
  return 0
}

scan_tree() {
  local raw allowed apath aregex areason hit_path hit_line violations=0
  # -I skips binary files; git ls-files scopes to tracked files only.
  raw="$(git ls-files -z | xargs -0 grep -nHEI "$PATTERN" 2>/dev/null || true)"
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
    if [ "$stripped_any" -eq 1 ] && ! grep -qE "$PATTERN" <<< "$remainder"; then
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
