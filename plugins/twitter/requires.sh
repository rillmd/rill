#!/usr/bin/env bash
source "$(cd "$(dirname "$0")/.." && pwd)/_lib.sh"

require_dir "~/Library/Mobile Documents/com~apple~CloudDocs/Rill/tweet-urls" \
    "mkdir -p ~/Library/Mobile\\ Documents/com~apple~CloudDocs/Rill/tweet-urls"
requires_check
