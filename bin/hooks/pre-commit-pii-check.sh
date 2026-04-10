#!/usr/bin/env bash
set -euo pipefail

# PII leak detection for non-encrypted files (ADR-047)
# Checks staged files for phone numbers and email addresses
# outside of git-crypt encrypted directories.
#
# Phone detection: broad global patterns + LLM verification to reduce false positives.
# Email detection: regex with known-safe exclusions.

STAGED_FILES=$(git diff --cached --name-only --diff-filter=ACM | grep '\.md$' || true)
[ -z "$STAGED_FILES" ] && exit 0

# Filter out encrypted directories and non-PKM files
CHECK_FILES=$(echo "$STAGED_FILES" | grep -v \
  -e '^knowledge/people/' \
  -e '^knowledge/orgs/' \
  -e '^plugins/sales-crm/data/' \
  -e '^app/' \
  -e '^docs/' \
  || true)
[ -z "$CHECK_FILES" ] && exit 0

FOUND=0
PHONE_CANDIDATES=""

while IFS= read -r file; do
  [ -z "$file" ] && continue
  CONTENT=$(git show ":$file" 2>/dev/null || true)
  [ -z "$CONTENT" ] && continue

  # --- Phone number detection (global) ---
  # Broad patterns:
  #   +XX-XXXX-XXXX (international)
  #   0X0-XXXX-XXXX (Japanese mobile)
  #   0X-XXXX-XXXX / 0XX-XXX-XXXX (Japanese landline)
  #   (XXX) XXX-XXXX (US/CA)
  #   XXX-XXX-XXXX, XXX.XXX.XXXX (US/CA without parens)
  PHONE_LINES=$(echo "$CONTENT" | grep -En \
    -e '\+[0-9]{1,3}[- .][0-9]{1,4}[- .][0-9]{3,4}' \
    -e '0[0-9]{1,4}-[0-9]{1,4}-[0-9]{3,4}' \
    -e '\([0-9]{2,4}\) ?[0-9]{3,4}[- .][0-9]{3,4}' \
    || true)

  if [ -n "$PHONE_LINES" ]; then
    while IFS= read -r line; do
      PHONE_CANDIDATES="${PHONE_CANDIDATES}${file}:${line}"$'\n'
    done <<< "$PHONE_LINES"
  fi

  # --- Email detection ---
  EMAILS=$(echo "$CONTENT" | grep -Eo '[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}' || true)
  if [ -n "$EMAILS" ]; then
    CLEAN=$(echo "$EMAILS" | grep -Ev 'noreply@|example\.|@anthropic\.com|^git@' || true)
    if [ -n "$CLEAN" ]; then
      echo "⚠️  Email address pattern in: $file"
      echo "    $CLEAN"
      FOUND=1
    fi
  fi
done <<< "$CHECK_FILES"

# --- LLM verification for phone candidates ---
if [ -n "$PHONE_CANDIDATES" ]; then
  PHONE_CANDIDATES="${PHONE_CANDIDATES%$'\n'}"  # trim trailing newline

  # Check if claude CLI is available
  if command -v claude &>/dev/null; then
    LLM_RESULT=$(claude -p --model haiku "You are a PII detection assistant. Analyze the following lines from Markdown files and determine if any contain real phone numbers (personal or business contact numbers that identify a specific person or organization).

NOT phone numbers: dates (2026-03-16), timestamps (094504), file IDs (001-initial-review), version numbers, port numbers, ZIP codes, generic example numbers.

Lines to check:
$PHONE_CANDIDATES

Reply ONLY with either:
- \"FOUND\" followed by the specific lines that contain real phone numbers
- \"NONE\" if no real phone numbers are found

Be strict: only flag actual contact phone numbers." 2>/dev/null || echo "ERROR")

    if echo "$LLM_RESULT" | grep -q "^FOUND"; then
      echo "⚠️  Phone number detected (LLM verified):"
      echo "$LLM_RESULT" | tail -n +2 | sed 's/^/    /'
      FOUND=1
    fi
    # NONE or ERROR → no block
  else
    # No claude CLI: fall back to showing candidates as warnings
    echo "⚠️  Possible phone number patterns (LLM unavailable for verification):"
    echo "$PHONE_CANDIDATES" | sed 's/^/    /'
    FOUND=1
  fi
fi

if [ "$FOUND" -eq 1 ]; then
  echo ""
  echo "PII found in non-encrypted files. Move to knowledge/people/ (encrypted)."
  echo "Bypass: git commit --no-verify"
  exit 1
fi
