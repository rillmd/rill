#!/usr/bin/env bash
# shellcheck source=plugins/_lib.sh
source "$(cd "$(dirname "$0")/.." && pwd)/_lib.sh"

# shellcheck disable=SC2088  # intentional: require_dir expands ~ itself (see plugins/_lib.sh)
require_dir "~/Library/Mobile Documents/com~apple~CloudDocs/Rill/tweet-urls" \
    "mkdir -p ~/Library/Mobile\\ Documents/com~apple~CloudDocs/Rill/tweet-urls"
requires_check
