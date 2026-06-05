#!/usr/bin/env bash
# ccvitals-hook.sh — state writer for Claude Code hook events
# https://github.com/educlopez/ccvitals
#
# Registered in ~/.claude/settings.json hooks for:
#   SessionStart, MessageDisplay, TaskCreated, PostCompact, Stop
#
# Reads event JSON from stdin, maintains a per-session state file at:
#   ~/.claude/.ccvitals-state/<session_id>.json
#
# State file schema:
#   {
#     "last_event": "MessageDisplay",
#     "last_event_at": 1748000000,
#     "session_title": "my-refactor",
#     "message_count": 12,
#     "tasks_created": 3
#   }
#
# Rules:
#   - Always exit 0 — never crash Claude Code
#   - Never print to stdout — Claude Code may interpret hook stdout
#   - Atomic writes: write to .tmp then mv
#   - jq is required; if absent, exit silently

# --- Safety: never let errors propagate to caller ---
set +e
set +u

# --- Require jq ---
if ! command -v jq >/dev/null 2>&1; then
    exit 0
fi

# --- Read config dir (mirrors statusline.sh / install.sh) ---
config_dir="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
config_dir="${config_dir/#\~/$HOME}"
state_dir="${config_dir}/.ccvitals-state"

# --- Read stdin (single pass) ---
raw_input=$(cat 2>/dev/null)
if [ -z "$raw_input" ]; then
    exit 0
fi

# --- Extract key fields via single jq invocation ---
# Fields present across all events:
#   hook_event_name  — e.g. "SessionStart"
#   session_id       — e.g. "abc123-..."
# Per-event fields extracted opportunistically (null/empty when absent):
#   session_title    — from SessionStart hookSpecificOutput or session.title
parsed=$(printf '%s' "$raw_input" | jq -r '
    [
        (.hook_event_name // ""),
        (.session_id // ""),
        (.session.title // .hookSpecificOutput.sessionTitle // ""),
        (.session.title // "")
    ] | join("\t")
' 2>/dev/null)

if [ -z "$parsed" ]; then
    exit 0
fi

# --- Split tab-delimited fields (bash 3.2 safe: no IFS= read -a) ---
hook_event=$(printf '%s' "$parsed" | cut -f1)
session_id=$(printf '%s' "$parsed" | cut -f2)
session_title_raw=$(printf '%s' "$parsed" | cut -f3)

# --- Validate session_id is usable as a filename ---
if [ -z "$session_id" ]; then
    exit 0
fi

# Sanitise: keep only safe chars, cap at 80 chars
safe_id=$(printf '%s' "$session_id" | tr -dc 'a-zA-Z0-9_-' | cut -c1-80)
if [ -z "$safe_id" ]; then
    exit 0
fi

# --- Ensure state dir exists ---
mkdir -p "$state_dir" 2>/dev/null || exit 0

# --- Opportunistic cleanup: remove state files older than 48h (only on SessionStart) ---
if [ "$hook_event" = "SessionStart" ]; then
    find "$state_dir" -maxdepth 1 -name '*.json' -mtime +2 -delete 2>/dev/null || true
fi

state_file="${state_dir}/${safe_id}.json"
tmp_file="${state_file}.tmp.$$"

# --- Read existing state (or start fresh) ---
existing="{}"
if [ -f "$state_file" ]; then
    existing=$(cat "$state_file" 2>/dev/null || echo '{}')
    # Ensure it's valid JSON
    if ! printf '%s' "$existing" | jq -e . >/dev/null 2>&1; then
        existing="{}"
    fi
fi

# --- Build updated state ---
now=$(date +%s 2>/dev/null || echo '0')

# Sanitise session title: strip control characters, cap at 120 chars
session_title_safe=""
if [ -n "$session_title_raw" ]; then
    session_title_safe=$(printf '%s' "$session_title_raw" | tr -d '\000-\037\177' | cut -c1-120)
fi

updated=$(printf '%s' "$existing" | jq \
    --arg event   "$hook_event" \
    --argjson now "$now" \
    --arg title   "$session_title_safe" \
    '
    # Always update last_event and timestamp
    . as $base
    | $base
      + {last_event: $event, last_event_at: $now}
    # Increment message_count on MessageDisplay
    | if $event == "MessageDisplay" then
        .message_count = (($base.message_count // 0) + 1)
      else . end
    # Increment tasks_created on TaskCreated
    | if $event == "TaskCreated" then
        .tasks_created = (($base.tasks_created // 0) + 1)
      else . end
    # Set session_title when we have one (never overwrite with empty)
    | if ($title | length) > 0 then
        .session_title = $title
      else . end
    ' 2>/dev/null)

if [ -z "$updated" ]; then
    exit 0
fi

# --- Atomic write ---
if printf '%s\n' "$updated" > "$tmp_file" 2>/dev/null; then
    mv "$tmp_file" "$state_file" 2>/dev/null || rm -f "$tmp_file" 2>/dev/null
else
    rm -f "$tmp_file" 2>/dev/null
fi

exit 0
