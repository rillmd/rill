#!/usr/bin/env bash
# .claude/commands/_lib/briefing-context.sh
# Data collection script called by /briefing Phase 1
# Performs mechanical aggregation only — interpretation is left to the AI
#
# Usage: bash .claude/commands/_lib/briefing-context.sh [YYYY-MM-DD] [HH:MM]
#   $1: Target date (default: today)
#   $2: Day boundary time (default: 03:00)
#
# Output: YAML to stdout

set -euo pipefail

# Resolve RILL_HOME from script location (.claude/commands/_lib/ → repo root)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RILL_HOME="$(cd "$SCRIPT_DIR/../../.." && pwd)"

# --- Arguments ---
TARGET_DATE="${1:-$(date +%Y-%m-%d)}"
DAY_BOUNDARY="${2:-03:00}"

# --- Activity window calculation ---
# "Yesterday" = from (TARGET_DATE - 1) at DAY_BOUNDARY to TARGET_DATE at DAY_BOUNDARY
# Example: target=2026-03-23, boundary=03:00
#   window start: 2026-03-22T03:00
#   window end:   2026-03-23T03:00
if date -v-1d +%Y 2>/dev/null >&2; then
    # macOS date
    PREV_DATE=$(date -j -v-1d -f "%Y-%m-%d" "$TARGET_DATE" "+%Y-%m-%d")
else
    # GNU date
    PREV_DATE=$(date -d "$TARGET_DATE - 1 day" +%Y-%m-%d)
fi

WINDOW_START="${PREV_DATE}T${DAY_BOUNDARY}"
WINDOW_END="${TARGET_DATE}T${DAY_BOUNDARY}"

# --- Helper: count files matching date in frontmatter created field ---
# Checks if frontmatter `created:` timestamp falls within the activity window
file_in_window() {
    local file="$1"
    local created
    created=$(grep -m1 '^created:' "$file" 2>/dev/null | sed 's/^created: *//' | tr -d '"' || echo "")
    if [ -z "$created" ]; then
        return 1
    fi
    # Extract date portion (YYYY-MM-DD) from ISO timestamp
    local file_date="${created:0:10}"
    local file_time="${created:11:5}"
    [ -z "$file_time" ] && file_time="00:00"

    # Compare against window (string comparison, works with HH:MM format)
    if [ "$file_date" = "$PREV_DATE" ] && [ ! "$file_time" \< "$DAY_BOUNDARY" ]; then
        return 0
    elif [ "$file_date" = "$TARGET_DATE" ] && [ "$file_time" \< "$DAY_BOUNDARY" ]; then
        return 0
    fi
    return 1
}

# --- Workspaces ---
active_count=0
completed_count=0
on_hold_count=0
active_details=""

for ws_dir in "$RILL_HOME"/workspace/*/; do
    [ -d "$ws_dir" ] || continue
    ws_id=$(basename "$ws_dir")

    # Find metadata file
    ws_meta=""
    for candidate in _workspace.md _session.md _project.md; do
        if [ -f "$ws_dir/$candidate" ]; then
            ws_meta="$ws_dir/$candidate"
            break
        fi
    done
    [ -z "$ws_meta" ] && continue

    # Extract status
    status=$(grep -m1 '^status:' "$ws_meta" 2>/dev/null | sed 's/^status: *//' | tr -d '"' || echo "unknown")

    case "$status" in
        active)
            active_count=$((active_count + 1))
            # Calculate days old from directory date prefix
            dir_date="${ws_id:0:10}"
            if [[ "$dir_date" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
                if date -v-1d +%Y 2>/dev/null >&2; then
                    days_old=$(( ( $(date -j -f "%Y-%m-%d" "$TARGET_DATE" "+%s") - $(date -j -f "%Y-%m-%d" "$dir_date" "+%s") ) / 86400 ))
                else
                    days_old=$(( ( $(date -d "$TARGET_DATE" +%s) - $(date -d "$dir_date" +%s) ) / 86400 ))
                fi
            else
                days_old=-1
            fi
            # Last modified (most recent file in workspace)
            last_mod=$(find "$ws_dir" -name '*.md' -maxdepth 1 -exec stat -f '%m %N' {} + 2>/dev/null | sort -rn | head -1 | awk '{print $1}')
            if [ -n "$last_mod" ]; then
                if date -v-1d +%Y 2>/dev/null >&2; then
                    last_mod_date=$(date -j -f '%s' "$last_mod" +%Y-%m-%d 2>/dev/null || echo "unknown")
                else
                    last_mod_date=$(date -d "@$last_mod" +%Y-%m-%d 2>/dev/null || echo "unknown")
                fi
            else
                last_mod_date="unknown"
            fi
            # Artifact count
            artifact_count=$(find "$ws_dir" -maxdepth 1 -name '[0-9][0-9][0-9]-*.md' 2>/dev/null | wc -l | tr -d ' ')
            active_details="${active_details}    - id: ${ws_id}
      days_old: ${days_old}
      last_modified: ${last_mod_date}
      artifacts: ${artifact_count}
"
            ;;
        completed)
            completed_count=$((completed_count + 1))
            ;;
        on-hold)
            on_hold_count=$((on_hold_count + 1))
            ;;
    esac
done

# --- Inbox counts ---
inbox_yaml=""
for inbox_sub in journal tweets web-clips meetings sources; do
    inbox_dir="$RILL_HOME/inbox/$inbox_sub"
    [ -d "$inbox_dir" ] || continue

    total=$(find "$inbox_dir" -maxdepth 1 -name '*.md' 2>/dev/null | wc -l | tr -d ' ')
    processed_file="$inbox_dir/.processed"
    if [ -f "$processed_file" ]; then
        processed=$(grep -c '[^[:space:]]' "$processed_file" 2>/dev/null || echo "0")
        processed=$(echo "$processed" | tr -d '[:space:]')
    else
        processed=0
    fi
    total=$(echo "$total" | tr -d '[:space:]')
    unprocessed=$((total - processed))
    [ $unprocessed -lt 0 ] && unprocessed=0
    inbox_yaml="${inbox_yaml}  ${inbox_sub}: { total: ${total}, processed: ${processed}, unprocessed: ${unprocessed} }
"
done

# --- Journals in activity window ---
journals_in_window=""
journal_dir="$RILL_HOME/inbox/journal"
if [ -d "$journal_dir" ]; then
    for jfile in "$journal_dir"/*.md; do
        [ -f "$jfile" ] || continue
        fname=$(basename "$jfile")
        # Extract date from filename (YYYY-MM-DD-HHmmss.md)
        file_date="${fname:0:10}"
        file_time="${fname:11:2}:${fname:13:2}"
        if [ "$file_date" = "$PREV_DATE" ] && [ ! "$file_time" \< "$DAY_BOUNDARY" ]; then
            journals_in_window="${journals_in_window}  - ${fname}
"
        elif [ "$file_date" = "$TARGET_DATE" ] && [ "$file_time" \< "$DAY_BOUNDARY" ]; then
            journals_in_window="${journals_in_window}  - ${fname}
"
        fi
    done
fi

# --- Knowledge notes created in activity window ---
knowledge_in_window=""
knowledge_dir="$RILL_HOME/knowledge/notes"
if [ -d "$knowledge_dir" ]; then
    for kfile in "$knowledge_dir"/*.md; do
        [ -f "$kfile" ] || continue
        if file_in_window "$kfile"; then
            knowledge_in_window="${knowledge_in_window}  - $(basename "$kfile")
"
        fi
    done
fi

# --- Tag health (live grep) ---
tag_counts=""
over_50=""
if [ -d "$knowledge_dir" ]; then
    # Extract all tags from frontmatter, count occurrences
    tag_counts=$(grep -h '^tags:' "$knowledge_dir"/*.md 2>/dev/null \
        | sed 's/^tags: *\[//; s/\].*//; s/, */\n/g' \
        | grep -v '^$' \
        | sort | uniq -c | sort -rn \
        | head -10)

    over_50=$(echo "$tag_counts" | awk '$1 > 50 {print "  - { tag: \"" $2 "\", count: " $1 " }"}')
fi
top_5=$(echo "$tag_counts" | head -5 | awk '{print "  - { tag: \"" $2 "\", count: " $1 " }"}')

# --- Task tickets (tasks/*.md) ---
ticket_open=0
ticket_waiting=0
ticket_overdue=0
ticket_due_soon=""
ticket_files=""

for tfile in "$RILL_HOME"/tasks/*.md; do
    [ -f "$tfile" ] || continue
    fname=$(basename "$tfile")
    t_status=$(grep -m1 '^status:' "$tfile" 2>/dev/null | sed 's/^status: *//' | tr -d '"' || echo "")
    case "$t_status" in
        open) ticket_open=$((ticket_open + 1)) ;;
        waiting) ticket_waiting=$((ticket_waiting + 1)) ;;
        *) continue ;;  # draft/done/cancelled/someday — skip
    esac
    # Check due date
    t_due=$(grep -m1 '^due:' "$tfile" 2>/dev/null | sed 's/^due: *//' | tr -d '"' || echo "")
    if [ -n "$t_due" ]; then
        if [ "$t_due" \< "$TARGET_DATE" ]; then
            ticket_overdue=$((ticket_overdue + 1))
        elif [ "$t_due" \< "$(date -j -v+8d -f "%Y-%m-%d" "$TARGET_DATE" "+%Y-%m-%d" 2>/dev/null || date -d "$TARGET_DATE + 7 days" +%Y-%m-%d 2>/dev/null)" ]; then
            ticket_due_soon="${ticket_due_soon}  - { file: \"${fname}\", due: \"${t_due}\" }
"
        fi
    fi
    ticket_files="${ticket_files}  - ${fname}
"
done

# --- Output YAML ---
cat <<EOF
target_date: ${TARGET_DATE}
day_boundary: "${DAY_BOUNDARY}"
activity_window:
  start: "${WINDOW_START}"
  end: "${WINDOW_END}"
workspaces:
  active: ${active_count}
  completed: ${completed_count}
  on_hold: ${on_hold_count}
  active_details:
${active_details:-    []}
inbox:
${inbox_yaml:-  none: {}}
journals_in_window:
${journals_in_window:-  []}
knowledge_created_in_window:
${knowledge_in_window:-  []}
tag_health:
  top_5:
${top_5:-    []}
  over_50:
${over_50:-    []}
task_tickets:
  open: ${ticket_open}
  waiting: ${ticket_waiting}
  overdue: ${ticket_overdue}
  due_soon:
${ticket_due_soon:-    []}
  files:
${ticket_files:-    []}
EOF
