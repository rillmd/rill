#!/usr/bin/env bash
# gw-auth.sh — Google Workspace OAuth token helper
#
# Usage:
#   source plugins/google-workspace/lib/gw-auth.sh
#   TOKEN=$(gw_get_token)
#
# Extracts refresh token from gogcli's macOS Keychain and exchanges it
# for a short-lived access token via Google's OAuth2 endpoint.
# Tokens expire in ~1 hour.

set -euo pipefail

# Get the default account email from gogcli
gw_get_account() {
    gog auth list --plain 2>/dev/null | head -1 | cut -f1
}

# Get an access token using gogcli's stored credentials
gw_get_token() {
    local account="${1:-$(gw_get_account)}"
    local creds_file="$HOME/Library/Application Support/gogcli/credentials.json"

    if [ ! -f "$creds_file" ]; then
        echo "Error: gogcli credentials not found at $creds_file" >&2
        return 1
    fi

    local client_id client_secret refresh_token
    client_id=$(python3 -c "import json;print(json.load(open('$creds_file'))['client_id'])")
    client_secret=$(python3 -c "import json;print(json.load(open('$creds_file'))['client_secret'])")
    refresh_token=$(security find-generic-password -s gogcli -a "token:default:${account}" -w 2>/dev/null \
        | python3 -c 'import sys,json;print(json.load(sys.stdin)["refresh_token"])')

    if [ -z "$refresh_token" ]; then
        echo "Error: Could not retrieve refresh token from Keychain for $account" >&2
        return 1
    fi

    local response
    response=$(curl -s -X POST https://oauth2.googleapis.com/token \
        -d "client_id=$client_id" \
        -d "client_secret=$client_secret" \
        -d "refresh_token=$refresh_token" \
        -d "grant_type=refresh_token")

    local token
    token=$(echo "$response" | python3 -c "import sys,json;print(json.load(sys.stdin).get('access_token',''))" 2>/dev/null)

    if [ -z "$token" ]; then
        echo "Error: Failed to get access token. Response: $response" >&2
        return 1
    fi

    echo "$token"
}
