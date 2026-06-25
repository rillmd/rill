#!/usr/bin/env bash
# Google Meet Adapter — Sync Gemini meeting notes to inbox/meetings/
#
# Usage: rill sync google-meet
#        (or directly: bash plugins/google-meet/adapter.sh)

set -euo pipefail

PLUGIN_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${RILL_HOME}/plugins/_lib.sh"

# Check gog is available
if ! command -v gog &>/dev/null; then
    echo "Error: gogcli (gog) is not installed."
    echo "Install: brew install steipete/tap/gogcli"
    exit 1
fi

echo "Searching for Gemini meeting notes..."

# Gemini titles meeting notes by the account locale, so a single query misses the
# other locale's notes. Search the English and Japanese title suffixes and merge
# the results, deduping by document id (a doc that matches both is kept once).
#   English : "Notes by Gemini"
#   Japanese: "Gemini " followed by 5 kana (= "notes by"). Written as UTF-8 octal
#             escapes so this OSS file stays ASCII-only; the same literal is shown
#             in commands/sync-google-meet.md.
en_query="Notes by Gemini"
ja_query=$'Gemini \343\201\253\343\202\210\343\202\213\343\203\241\343\203\242'

_search_drive() {
    # $1 = query string. Emits raw gog --json output; non-zero exit on gog error.
    gog --json drive search "$1" --max 100 2>/dev/null
}

_emit_tsv() {
    # $1 = raw gog --json output. Emits "id<TAB>name<TAB>modifiedTime" per file.
    printf '%s' "$1" | python3 -c "
import json, sys
text = sys.stdin.read().strip()
if not text:
    sys.exit(0)
data = json.loads(text)
files = data if isinstance(data, list) else data.get('files', [])
for f in files:
    fid = f.get('id', '')
    name = f.get('name', '')
    modified = f.get('modifiedTime', '')
    print(f'{fid}\t{name}\t{modified}')
"
}

en_json="$(_search_drive "$en_query")" || {
    echo "Error: Failed to search Google Drive. Check authentication with 'gog auth list'."
    exit 1
}
ja_json="$(_search_drive "$ja_query")" || {
    echo "Error: Failed to search Google Drive. Check authentication with 'gog auth list'."
    exit 1
}

# Parse each result set separately so a parse failure in either surfaces (instead
# of being masked by a command group's last-command status), then concatenate and
# dedup by document id (first occurrence wins, input order preserved).
en_tsv="$(_emit_tsv "$en_json")" || {
    echo "Error: Failed to parse Drive search results (English query)."
    exit 1
}
ja_tsv="$(_emit_tsv "$ja_json")" || {
    echo "Error: Failed to parse Drive search results (Japanese query)."
    exit 1
}
docs_tsv="$(printf '%s\n%s\n' "$en_tsv" "$ja_tsv" | awk -F'\t' 'length($1) && !seen[$1]++')"

# Auto-rebuild meetings .index if missing (gitignored, may disappear after clone)
_ensure_meetings_index() {
    local index_file="$MEETINGS_DIR/.index"
    [ -f "$index_file" ] && return 0

    for f in "$MEETINGS_DIR"/*.md; do
        [ -f "$f" ] || continue
        local did
        did="$(sed -n '/^---$/,/^---$/{ s/^google-doc-id: *"\{0,1\}\([^"]*\)"\{0,1\}$/\1/p; }' "$f")"
        [ -n "$did" ] && echo -e "${did}\t$(basename "$f")" >> "$index_file"
    done
}

_ensure_meetings_index

count=0
skipped=0

# Parse JSON: extract id, name, modifiedTime
# Document names follow patterns like:
#   "Sunrise Hotel / Acme SaaS ... - 2026/02/16 10:58 JST - Notes by Gemini"
#   " 2026/02/16 11:35 JST meeting started at - Notes by Gemini"
while IFS=$'\t' read -r doc_id doc_name doc_modified; do
    [ -z "$doc_id" ] && continue

    # Defense-in-depth: check meetings index first
    if grep -q "^${doc_id}	" "$MEETINGS_DIR/.index" 2>/dev/null; then
        ((skipped++))
        continue
    fi

    # Primary check: plugin sync state
    if is_already_synced "$doc_id"; then
        ((skipped++))
        continue
    fi

    # Fetch document text
    doc_text="$(gog docs text "$doc_id" 2>/dev/null)" || {
        echo "  WARN: Failed to fetch document: $doc_name"
        continue
    }

    # Extract date, timestamp, and slug from document name
    parsed="$(echo "$doc_name" | python3 -c "
import sys, re
name = sys.stdin.read().strip()

# Extract date/time: '2026/02/16 10:58 JST'
m = re.search(r'(\d{4})/(\d{2})/(\d{2})\s+(\d{1,2}):(\d{2})\s*JST', name)
if m:
    y, mo, d, h, mi = m.groups()
    local_date = f'{y}-{mo}-{d}'
    created_ts = f'{y}-{mo}-{d}T{h.zfill(2)}:{mi}+09:00'
else:
    local_date = '_NONE_'
    created_ts = '_NONE_'

# Generate slug: remove the trailing Gemini-notes suffix (English 'Notes by
# Gemini' or the localized 'Gemini ...' form), date/time, 'meeting started at'
slug_text = name
slug_text = re.sub(r'\s*-\s*[^-]*Gemini[^-]*$', '', slug_text)
slug_text = re.sub(r'\d{4}/\d{2}/\d{2}\s+\d{1,2}:\d{2}\s*JST', '', slug_text)
slug_text = re.sub(r'meeting started at', '', slug_text, flags=re.IGNORECASE)
slug_text = slug_text.strip(' -/')

# Keep only ASCII for filename
slug_text = re.sub(r'[^a-zA-Z0-9 ]', '', slug_text)
slug_text = slug_text.strip().lower()
slug_text = re.sub(r'\s+', '-', slug_text)
slug_text = slug_text[:50].rstrip('-')
if not slug_text:
    slug_text = 'meeting'

print(f'{local_date}\t{created_ts}\t{slug_text}')
" 2>/dev/null)"

    local_date="$(echo "$parsed" | cut -f1)"
    created_ts="$(echo "$parsed" | cut -f2)"
    slug="$(echo "$parsed" | cut -f3)"

    # Fallback: use modifiedTime if no date found in name
    if [ "$local_date" = "_NONE_" ] || [ -z "$local_date" ]; then
        local_date="$(echo "$doc_modified" | cut -c1-10)"
        created_ts="$(echo "$doc_modified" | sed 's/\.[0-9]*Z$/+00:00/' | sed 's/Z$/+00:00/')"
    fi

    filename="${local_date}-${slug}.md"

    # Handle filename collision
    if [ -f "$MEETINGS_DIR/$filename" ]; then
        counter=2
        while [ -f "$MEETINGS_DIR/${local_date}-${slug}-${counter}.md" ]; do
            ((counter++))
        done
        filename="${local_date}-${slug}-${counter}.md"
    fi

    # Create source file
    extra_fm="original-source: \"Google Meet Gemini Notes\"
google-doc-id: \"$doc_id\""

    if create_source_file "$filename" "meeting" "$created_ts" "$extra_fm" "$doc_text"; then
        mark_synced "$doc_id" "$filename"
        echo -e "${doc_id}\t${filename}" >> "$MEETINGS_DIR/.index"
        ((count++))
    fi

done < <(printf '%s\n' "$docs_tsv")

echo ""
echo "Done: $count new, $skipped already synced"
