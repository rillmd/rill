#!/usr/bin/env bash
# Twitter Adapter — Sync tweet URLs from iCloud Drive to inbox/tweets/
#
# Usage: rill sync twitter
#        (or directly: bash plugins/twitter/adapter.sh)
#
# Pipeline:
#   iPhone Share Sheet → iOS Shortcut → save URL to iCloud Drive/Rill/tweet-urls/*.txt
#   rill sync twitter → read URL → rill clip <url> → inbox/tweets/

set -euo pipefail

PLUGIN_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${RILL_HOME}/plugins/_lib.sh"

ICLOUD_DIR="$HOME/Library/Mobile Documents/com~apple~CloudDocs/Rill/tweet-urls"

if [ ! -d "$ICLOUD_DIR" ]; then
    echo "Error: iCloud Drive folder not found: $ICLOUD_DIR"
    echo "Create it with: mkdir -p \"$ICLOUD_DIR\""
    exit 1
fi

echo "Scanning iCloud Drive/Rill/tweet-urls/..."

count=0
skipped=0
errors=0

for file in "$ICLOUD_DIR"/*.txt; do
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

    # Read URL from first non-empty line
    url="$(grep -m1 '.' "$file" 2>/dev/null | tr -d '[:space:]' || true)"

    if [ -z "$url" ]; then
        echo "WARN: Empty file, skipping: $filename"
        mark_synced "$filename" "skipped:empty"
        continue
    fi

    # Delegate to rill clip (handles tweet detection, FixTweet API, file creation)
    echo "Processing: $filename → $url"
    if rill clip "$url"; then
        mark_synced "$filename" "$url"
        ((count++))
    else
        echo "ERROR: Failed to clip $url from $filename"
        ((errors++))
    fi
done

echo ""
echo "Done: $count clipped, $skipped already synced, $errors errors"
