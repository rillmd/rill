#!/usr/bin/env bash
# gw-slides.sh — Google Slides API operations
#
# Usage:
#   source plugins/google-workspace/lib/gw-auth.sh
#   source plugins/google-workspace/lib/gw-slides.sh
#   TOKEN=$(gw_get_token)
#
#   gw_slides_clone <template_id> "New Title"
#   gw_slides_replace_text <pres_id> "old text" "new text"
#   gw_slides_batch_replace <pres_id> replacements.json

set -euo pipefail

SLIDES_API="https://slides.googleapis.com/v1/presentations"
DRIVE_API="https://www.googleapis.com/drive/v3/files"

# Clone a presentation via Drive API
# Returns: new presentation ID
gw_slides_clone() {
    local template_id="$1"
    local title="$2"
    local token="${TOKEN:?TOKEN not set}"

    local response
    response=$(curl -s -X POST "${DRIVE_API}/${template_id}/copy" \
        -H "Authorization: Bearer $token" \
        -H "Content-Type: application/json" \
        -d "{\"name\": \"$title\"}")

    local new_id
    new_id=$(echo "$response" | python3 -c "import sys,json;print(json.load(sys.stdin).get('id',''))" 2>/dev/null)

    if [ -z "$new_id" ]; then
        echo "Error: Failed to clone presentation. Response: $response" >&2
        return 1
    fi

    echo "$new_id"
}

# Replace all occurrences of text in a presentation
gw_slides_replace_text() {
    local pres_id="$1"
    local old_text="$2"
    local new_text="$3"
    local token="${TOKEN:?TOKEN not set}"

    local body
    body=$(python3 -c "
import json
print(json.dumps({'requests': [{'replaceAllText': {
    'containsText': {'text': $(python3 -c "import json;print(json.dumps('$old_text'))"), 'matchCase': True},
    'replaceText': $(python3 -c "import json;print(json.dumps('$new_text'))")
}}]}))
")

    curl -s -X POST "${SLIDES_API}/${pres_id}:batchUpdate" \
        -H "Authorization: Bearer $token" \
        -H "Content-Type: application/json" \
        -d "$body"
}

# Batch replace text using a JSON file of replacements
# JSON format: [{"old": "old text", "new": "new text"}, ...]
gw_slides_batch_replace() {
    local pres_id="$1"
    local replacements_json="$2"
    local token="${TOKEN:?TOKEN not set}"

    local body
    body=$(python3 -c "
import json, sys

replacements = json.load(open('$replacements_json'))
requests = []
for r in replacements:
    requests.append({
        'replaceAllText': {
            'containsText': {'text': r['old'], 'matchCase': True},
            'replaceText': r['new']
        }
    })
print(json.dumps({'requests': requests}))
")

    local response
    response=$(curl -s -X POST "${SLIDES_API}/${pres_id}:batchUpdate" \
        -H "Authorization: Bearer $token" \
        -H "Content-Type: application/json" \
        -d "$body")

    echo "$response" | python3 -c "
import json, sys
resp = json.load(sys.stdin)
if 'error' in resp:
    print(f'ERROR: {resp[\"error\"][\"message\"]}', file=sys.stderr)
    sys.exit(1)
replies = resp.get('replies', [])
changed = sum(r.get('replaceAllText', {}).get('occurrencesChanged', 0) for r in replies)
print(f'{changed} replacement(s) applied across {len(replies)} rule(s)')
"
}

# Delete a slide element by objectId
gw_slides_delete_element() {
    local pres_id="$1"
    local object_id="$2"
    local token="${TOKEN:?TOKEN not set}"

    curl -s -X POST "${SLIDES_API}/${pres_id}:batchUpdate" \
        -H "Authorization: Bearer $token" \
        -H "Content-Type: application/json" \
        -d "{\"requests\": [{\"deleteObject\": {\"objectId\": \"$object_id\"}}]}"
}

# Get presentation URL from ID
gw_slides_url() {
    local pres_id="$1"
    echo "https://docs.google.com/presentation/d/${pres_id}/edit"
}
