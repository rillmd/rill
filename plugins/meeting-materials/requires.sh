#!/usr/bin/env bash
source "$(cd "$(dirname "$0")/.." && pwd)/_lib.sh"

require_command gog "brew install steipete/tap/gogcli — needed for Google Drive upload"
require_auth "Google OAuth" "Run: gog auth add <email> --services drive"
requires_check
