#!/usr/bin/env bash
# fetch-url-meta.sh — Extract OGP metadata from a URL
#
# Usage: fetch-url-meta.sh <url>
#
# Output: YAML with title and description to stdout
# Exit:   0=success, 1=bad args, 2=fetch failed

set -euo pipefail

if [ $# -eq 0 ] || [ -z "$1" ]; then
    echo "Usage: fetch-url-meta.sh <url>" >&2
    exit 1
fi

url="$1"

# Fetch HTML <head> section
html="$(curl -sL --max-time 10 -H 'User-Agent: Mozilla/5.0' "$url" 2>/dev/null | sed -n '/<[Hh][Ee][Aa][Dd]/,/<\/[Hh][Ee][Aa][Dd]>/p')" || true

if [ -z "$html" ]; then
    # Fallback: extract title from URL filename for non-HTML (e.g., PDF)
    filename="$(basename "$url" | sed 's/[?#].*//')"
    echo "title: \"${filename}\""
    echo "description: \"\""
    exit 0
fi

# Extract <title>
title="$(echo "$html" | sed -n 's/.*<title[^>]*>\([^<]*\)<\/title>.*/\1/p' | head -1)"

# Extract OGP meta tags (handle both attribute orderings)
og_title="$(echo "$html" | grep -oi 'property="og:title"[^>]*content="[^"]*"' | sed 's/.*content="\([^"]*\)".*/\1/' | head -1 || true)"
[ -z "$og_title" ] && og_title="$(echo "$html" | grep -oi 'content="[^"]*"[^>]*property="og:title"' | sed 's/.*content="\([^"]*\)".*/\1/' | head -1 || true)"

og_description="$(echo "$html" | grep -oi 'property="og:description"[^>]*content="[^"]*"' | sed 's/.*content="\([^"]*\)".*/\1/' | head -1 || true)"
[ -z "$og_description" ] && og_description="$(echo "$html" | grep -oi 'content="[^"]*"[^>]*property="og:description"' | sed 's/.*content="\([^"]*\)".*/\1/' | head -1 || true)"

# Fallback: try <meta name="description"> if OGP is missing
if [ -z "$og_description" ]; then
    og_description="$(echo "$html" | grep -oi 'name="description"[^>]*content="[^"]*"' | sed 's/.*content="\([^"]*\)".*/\1/' | head -1 || true)"
    [ -z "$og_description" ] && og_description="$(echo "$html" | grep -oi 'content="[^"]*"[^>]*name="description"' | sed 's/.*content="\([^"]*\)".*/\1/' | head -1 || true)"
fi

# Resolve title: og:title > <title>
display_title="${og_title:-$title}"
display_title="${display_title:-Untitled}"

# Escape double quotes for YAML output
escape_yaml() {
    echo "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

echo "title: \"$(escape_yaml "$display_title")\""
echo "description: \"$(escape_yaml "${og_description:-}")\""
