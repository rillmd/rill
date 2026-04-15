#!/usr/bin/env bash
# plugins/_lib.sh — Shared library for Rill plugins
#
# Source this file from adapter.sh:
#   source "${RILL_HOME}/plugins/_lib.sh"

set -euo pipefail

# Resolve RILL_HOME from _lib.sh location (plugins/ parent)
_lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RILL_HOME="${RILL_HOME:-$(dirname "$_lib_dir")}"
SOURCES_DIR="$RILL_HOME/inbox/sources"
MEETINGS_DIR="$RILL_HOME/inbox/meetings"
WEBCLIPS_DIR="$RILL_HOME/inbox/web-clips"
TWEETS_DIR="$RILL_HOME/inbox/tweets"

# Return RILL_HOME path
rill_home() {
    echo "$RILL_HOME"
}

# Create a source file with proper frontmatter.
#
# Usage:
#   create_source_file "2026-02-18-meeting-notes.md" "meeting" "2026-02-18T10:00+09:00" \
#       'original-source: "Google Meet Gemini Notes"' "Content here..."
#
# Args:
#   $1 - filename (e.g., 2026-02-18-meeting-notes.md)
#   $2 - source-type (e.g., meeting, article, note)
#   $3 - created timestamp (ISO 8601)
#   $4 - extra frontmatter lines (newline-separated, without ---)
#   $5 - content body
#
# Returns: 0 on success, 1 if file already exists
create_source_file() {
    local filename="$1"
    local source_type="$2"
    local created="$3"
    local extra_frontmatter="$4"
    local content="$5"

    # Route to correct inbox subdirectory by source-type
    local dest_dir
    case "$source_type" in
        meeting)  dest_dir="$MEETINGS_DIR" ;;
        web-clip) dest_dir="$WEBCLIPS_DIR" ;;
        tweet)    dest_dir="$TWEETS_DIR" ;;
        *)        dest_dir="$SOURCES_DIR" ;;
    esac

    local filepath="$dest_dir/$filename"

    # Duplicate check
    if [ -f "$filepath" ]; then
        echo "SKIP: $filename already exists" >&2
        return 1
    fi

    mkdir -p "$dest_dir"

    {
        echo "---"
        echo "created: $created"
        echo "source-type: $source_type"
        if [ -n "$extra_frontmatter" ]; then
            echo "$extra_frontmatter"
        fi
        echo "---"
        echo ""
        echo "$content"
    } > "$filepath"

    echo "Created: ${filepath#$RILL_HOME/}"
    return 0
}

# Resolve .synced file path.
#
# New location: plugins/.state/{plugin_name}.synced (centralized state dir).
# Auto-migrates legacy path (PLUGIN_DIR/.synced) on first access.
#
# Requires PLUGIN_DIR to be set (done by adapter.sh before sourcing _lib.sh).
# Falls back to PLUGIN_DIR/.synced if PLUGIN_DIR is unset (e.g., requires.sh).
_resolve_synced_file() {
    local plugin_name
    if [ -n "${PLUGIN_DIR:-}" ]; then
        plugin_name="$(basename "$PLUGIN_DIR")"
    else
        echo "./.synced"
        return
    fi

    local state_dir="$RILL_HOME/plugins/.state"
    local new_path="$state_dir/${plugin_name}.synced"
    local legacy_path="$PLUGIN_DIR/.synced"

    # Auto-migrate: move legacy .synced to .state/ (one-time)
    if [ -f "$legacy_path" ] && [ ! -f "$new_path" ]; then
        mkdir -p "$state_dir"
        mv "$legacy_path" "$new_path"
    fi

    mkdir -p "$state_dir"
    echo "$new_path"
}

# Check if a sync key has already been synced.
#
# Usage:
#   if is_already_synced "$google_doc_id"; then echo "skip"; fi
#
# Args:
#   $1 - sync key (unique identifier, e.g., Google Doc ID)
#
# Reads .synced file from plugins/.state/{plugin_name}.synced.
is_already_synced() {
    local sync_key="$1"
    local synced_file
    synced_file="$(_resolve_synced_file)"

    if [ ! -f "$synced_file" ]; then
        return 1
    fi

    grep -q "^${sync_key}	" "$synced_file" 2>/dev/null
}

# Mark a sync key as synced.
#
# Usage:
#   mark_synced "$google_doc_id" "2026-02-18-meeting-notes.md"
#
# Args:
#   $1 - sync key
#   $2 - filename created
mark_synced() {
    local sync_key="$1"
    local filename="$2"
    local synced_file
    synced_file="$(_resolve_synced_file)"

    echo -e "${sync_key}\t${filename}\t$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$synced_file"
}

# --- Dependency checking (used by requires.sh) ---

_requires_failures=0

# Check that a command is available on PATH.
# Usage: require_command gog "brew install steipete/tap/gogcli"
require_command() {
    local cmd="$1" hint="$2"
    if command -v "$cmd" &>/dev/null; then
        printf "  ✓ command: %s\n" "$cmd"
    else
        printf "  ✗ command: %s — %s\n" "$cmd" "$hint"
        _requires_failures=$((_requires_failures + 1))
    fi
}

# Check that a directory exists.
# Usage: require_dir "~/Library/.../Rill/tweet-urls" "mkdir -p ..."
require_dir() {
    local dir="$1" hint="$2"
    local expanded="${dir/#\~/$HOME}"
    if [ -d "$expanded" ]; then
        printf "  ✓ directory: %s\n" "$dir"
    else
        printf "  ✗ directory: %s\n    → %s\n" "$dir" "${hint:-mkdir -p \"$dir\"}"
        _requires_failures=$((_requires_failures + 1))
    fi
}

# Display an auth check (informational only, does not block enable).
# Usage: require_auth "Google OAuth" "Run: gog auth add <email> --services drive,docs"
require_auth() {
    local desc="$1" hint="$2"
    printf "  ⚠ auth: %s (manual verification needed)\n    → %s\n" "$desc" "$hint"
}

# Finalize dependency check. Returns 0 if all met, 1 if any failed.
# Usage: requires_check  (call at the end of requires.sh)
requires_check() {
    if [ "$_requires_failures" -gt 0 ]; then
        echo ""
        echo "$_requires_failures dependency(s) not met."
        return 1
    else
        echo ""
        echo "All dependencies met."
        return 0
    fi
}
