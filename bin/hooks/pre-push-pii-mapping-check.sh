#!/bin/bash
# pre-push-pii-mapping-check.sh -- block pushes whose commits contain private
# vocabulary (real client/product names), read from an OUT-OF-REPO terms file.
#
# Role split (two hooks, two repos, two audiences):
#   - bin/hooks/pre-commit-pii-check.sh  = vault-content guard. Installed into
#     end-user VAULTS via `rill crypt init` / `rill crypt hook`; scans vault
#     files for emails/phones with the vault-local .rill/pii-allowlist.txt.
#   - THIS file = rillmd/rill SOURCE-REPO guard. Manually self-installed by a
#     contributor into this repo's .git/hooks; never distributed to vaults.
#     It scans pushed commits (added diff lines + commit messages) for the
#     contributor's private term list, which must never appear in this PUBLIC
#     repo -- so the list itself lives OUTSIDE the repo:
#       $RILL_DEV_PII_TERMS_FILE, or ~/.config/rill-dev/pii-terms.txt
#     (one term per line, # comments and blank lines ignored, matched
#     case-insensitively as fixed strings).
#     No terms file -> the hook is a no-op: the repo ships the MECHANISM only.
#
# Install (from the repo root):
#   ln -s ../../bin/hooks/pre-push-pii-mapping-check.sh .git/hooks/pre-push
#   (or cp; for worktrees, use `git rev-parse --git-path hooks`)
#
# stdin (per git pre-push contract): <local-ref> <local-sha> <remote-ref> <remote-sha>
# Exit: 0 allow push, 1 block push, 2 internal error.

set -euo pipefail

ZERO40="0000000000000000000000000000000000000000"

terms_file="${RILL_DEV_PII_TERMS_FILE:-$HOME/.config/rill-dev/pii-terms.txt}"
if [ ! -f "$terms_file" ]; then
  echo "pre-push-pii-mapping-check: no terms file at $terms_file -- skipping (mechanism-only mode)" >&2
  exit 0
fi

# Strip comments and blank lines; an empty pattern line would match everything.
terms="$(grep -vE '^[[:space:]]*(#|$)' "$terms_file" || true)"
if [ -z "$terms" ]; then
  echo "pre-push-pii-mapping-check: terms file is empty -- skipping" >&2
  exit 0
fi

blocked=0

scan_commit() {
  local sha="$1"
  local msg added
  msg="$(git log -1 --format=%B "$sha")"
  # Added diff lines only (strip the +++ file header); merges diff against
  # the first parent, which is what lands on the remote branch.
  added="$(git show --first-parent --format= "$sha" | grep '^+' | grep -v '^+++' || true)"
  if printf '%s\n%s\n' "$msg" "$added" | grep -iFq -- "$terms" 2>/dev/null; then
    echo "pre-push-pii-mapping-check: BLOCKED -- private term found in commit $sha ($(git log -1 --format=%s "$sha"))" >&2
    blocked=1
  fi
}

while read -r _local_ref local_sha _remote_ref remote_sha; do
  # Branch deletion: nothing new is pushed.
  [ "$local_sha" = "$ZERO40" ] && continue

  if [ "$remote_sha" = "$ZERO40" ]; then
    # New remote branch: no remote tip to diff against. Prefer the merge-base
    # with origin/main; fall back to "commits not already on any origin ref".
    base="$(git merge-base "$local_sha" origin/main 2>/dev/null || true)"
    if [ -n "$base" ]; then
      revs="$(git rev-list "$base..$local_sha")"
    else
      revs="$(git rev-list "$local_sha" --not --remotes=origin)"
    fi
  else
    revs="$(git rev-list "$remote_sha..$local_sha")"
  fi

  for sha in $revs; do
    scan_commit "$sha"
  done
done

if [ "$blocked" -ne 0 ]; then
  echo "pre-push-pii-mapping-check: push rejected -- remove the private term(s) (rewrite the commit/message) and retry" >&2
  exit 1
fi
exit 0
