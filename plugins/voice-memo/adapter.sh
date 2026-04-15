#!/usr/bin/env bash
# Voice Memo Adapter — Sync transcribed voice memos from iCloud Drive to inbox/journal/
#
# Usage: rill sync voice-memo
#        (or directly: bash plugins/voice-memo/adapter.sh)
#
# Pipeline:
#   iPhone Shortcut → transcribe → save to iCloud Drive/Rill/voice-memos/ (.txt)
#   rill sync voice-memo → copy to inbox/journal/ as .md

set -euo pipefail

PLUGIN_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${RILL_HOME}/plugins/_lib.sh"

JOURNAL_DIR="$RILL_HOME/inbox/journal"
ICLOUD_DIR="$HOME/Library/Mobile Documents/com~apple~CloudDocs/Rill/voice-memos"

if [ ! -d "$ICLOUD_DIR" ]; then
    echo "Error: iCloud Drive folder not found: $ICLOUD_DIR"
    echo "Create it with: mkdir -p \"$ICLOUD_DIR\""
    exit 1
fi

echo "Scanning iCloud Drive/Rill/voice-memos/..."

count=0
skipped=0

for file in "$ICLOUD_DIR"/*.md "$ICLOUD_DIR"/*.txt; do
    [ -f "$file" ] || continue

    filename="$(basename "$file")"

    # Skip dotfiles and temp files
    [[ "$filename" == .* ]] && continue
    [[ "$filename" == *~* ]] && continue

    # Check if already synced
    if is_already_synced "$filename"; then
        ((skipped++))
        continue
    fi

    # Determine journal filename: same base name but always .md
    local_filename="${filename%.*}.md"

    # Idempotency: skip if file already exists (same timestamp = same memo)
    if [ -f "$JOURNAL_DIR/$local_filename" ]; then
        echo "SKIP: $local_filename already exists in journal"
        mark_synced "$filename" "skipped:exists:$local_filename"
        ((skipped++))
        continue
    fi

    cp "$file" "$JOURNAL_DIR/$local_filename"
    echo "Created: inbox/journal/$local_filename"

    mark_synced "$filename" "$local_filename"
    ((count++))
done

echo ""
echo "Done: $count new, $skipped already synced"
