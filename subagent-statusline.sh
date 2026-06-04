#!/usr/bin/env bash
# subagent-statusline.sh — per-subagent row renderer for Claude Code
# https://github.com/educlopez/ccvitals
#
# Reads the subagentStatusLine JSON payload from stdin (one tick).
# Emits one JSON line per task: {"id":"<task-id>","content":"<ANSI string>"}
# Omitting a task keeps Claude Code's default row.
#
# Contract (June 2026):
#   stdin fields: all base statusLine fields + columns (int) + tasks[]
#   tasks[]: {id, name, type, status, description, label, startTime,
#              tokenCount, tokenSamples, cwd}
#   stdout: one {"id":..., "content":...} JSON line per task to override
#
# Requirements: bash 3.2+, jq

set -euo pipefail

# ─── Config / theme resolution ───────────────────────────────────────────────

config_dir="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
config_dir="${config_dir/#\~/$HOME}"
statusline_config="$config_dir/.statusline-config.json"

# Convert #RRGGBB → truecolor ANSI fg escape (bash 3.2 compatible)
hex_to_ansi() {
    local hex="${1#'#'}"
    local r g b
    r=$(printf '%d' "0x${hex:0:2}")
    g=$(printf '%d' "0x${hex:2:2}")
    b=$(printf '%d' "0x${hex:4:2}")
    printf '\033[38;2;%d;%d;%dm' "$r" "$g" "$b"
}

# Default (legacy ANSI) color values
RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
GRAY='\033[0;90m'
NC='\033[0m'

# Apply theme preset if configured
if [ -f "$statusline_config" ]; then
    _theme=$(jq -r '.theme // empty' "$statusline_config" 2>/dev/null)
    case "$_theme" in
        pastel)
            RED=$(hex_to_ansi '#ee7975')
            GREEN=$(hex_to_ansi '#89f78e')
            CYAN=$(hex_to_ansi '#a5e8fa')
            GRAY=$(hex_to_ansi '#a1a1a1')
            ;;
        tokyo-night)
            RED=$(hex_to_ansi '#f7768e')
            GREEN=$(hex_to_ansi '#9ece6a')
            CYAN=$(hex_to_ansi '#7dcfff')
            GRAY=$(hex_to_ansi '#565f89')
            ;;
        catppuccin)
            RED=$(hex_to_ansi '#f38ba8')
            GREEN=$(hex_to_ansi '#a6e3a1')
            CYAN=$(hex_to_ansi '#94e2d5')
            GRAY=$(hex_to_ansi '#6c7086')
            ;;
        dracula)
            RED=$(hex_to_ansi '#ff5555')
            GREEN=$(hex_to_ansi '#50fa7b')
            CYAN=$(hex_to_ansi '#8be9fd')
            GRAY=$(hex_to_ansi '#6272a4')
            ;;
        nord)
            RED=$(hex_to_ansi '#bf616a')
            GREEN=$(hex_to_ansi '#a3be8c')
            CYAN=$(hex_to_ansi '#88c0d0')
            GRAY=$(hex_to_ansi '#4c566a')
            ;;
        mono)
            RED='\033[1m'
            GREEN='\033[1m'
            CYAN='\033[1m'
            GRAY='\033[0;37m'
            ;;
        custom)
            _c_red=$(jq -r '.colors.red // empty' "$statusline_config" 2>/dev/null)
            _c_green=$(jq -r '.colors.green // empty' "$statusline_config" 2>/dev/null)
            _c_cyan=$(jq -r '.colors.cyan // empty' "$statusline_config" 2>/dev/null)
            _c_gray=$(jq -r '.colors.gray // empty' "$statusline_config" 2>/dev/null)
            [ -n "$_c_red" ]   && RED=$(hex_to_ansi "$_c_red")
            [ -n "$_c_green" ] && GREEN=$(hex_to_ansi "$_c_green")
            [ -n "$_c_cyan" ]  && CYAN=$(hex_to_ansi "$_c_cyan")
            [ -n "$_c_gray" ]  && GRAY=$(hex_to_ansi "$_c_gray")
            unset _c_red _c_green _c_cyan _c_gray
            ;;
        default|'') ;;
    esac
    unset _theme
fi

# Materialize color strings with real ESC bytes for embedding in content
NC_E=$(printf "$NC")
RED_E=$(printf "$RED")
GREEN_E=$(printf "$GREEN")
CYAN_E=$(printf "$CYAN")
GRAY_E=$(printf "$GRAY")

# ─── Helpers ─────────────────────────────────────────────────────────────────

# Format a token count as k/M: 0→"", 999→"999", 1500→"1.5k", 1200000→"1.2M"
_fmt_tokens() {
    local n="$1"
    if [ -z "$n" ] || ! printf '%d' "$n" >/dev/null 2>&1; then
        echo ""
        return
    fi
    n=$(printf '%d' "$n")
    if [ "$n" -le 0 ]; then
        echo ""
    elif [ "$n" -ge 1000000 ]; then
        local m_int m_frac
        m_int=$(( n / 1000000 ))
        m_frac=$(( (n % 1000000) / 100000 ))
        echo "${m_int}.${m_frac}M"
    elif [ "$n" -ge 1000 ]; then
        local k_int k_frac
        k_int=$(( n / 1000 ))
        k_frac=$(( (n % 1000) / 100 ))
        echo "${k_int}.${k_frac}k"
    else
        echo "${n}"
    fi
}

# ─── Main: read stdin ─────────────────────────────────────────────────────────

input=$(cat)

# Bail gracefully on empty or non-JSON input
if [ -z "$input" ]; then
    exit 0
fi

# Validate JSON and extract top-level fields
columns=$(printf '%s' "$input" | jq -r '.columns // 80' 2>/dev/null) || exit 0
task_count=$(printf '%s' "$input" | jq -r 'if .tasks then (.tasks | length) else 0 end' 2>/dev/null) || exit 0

if [ -z "$task_count" ] || [ "$task_count" -eq 0 ] 2>/dev/null; then
    exit 0
fi

# Validate columns is numeric
if ! printf '%d' "$columns" >/dev/null 2>&1; then
    columns=80
fi
columns=$(printf '%d' "$columns")

# Extract all tasks in one jq pass.
# Each task is emitted as: id\x1fname\x1fstatus\x1fdescription\x1flabel\x1ftokens\x1fcwd
# Tasks are separated by newlines. Fields that contain newlines are stripped.
US=$'\x1f'
tasks_raw=$(printf '%s' "$input" | jq -r --arg us $'\x1f' '
    .tasks[] |
    [
        (.id          // "" | gsub("\n";"") | gsub($us;"")),
        (.name        // "" | gsub("\n";"") | gsub($us;"")),
        (.status      // "" | gsub("\n";"") | gsub($us;"")),
        (.description // "" | gsub("\n";"") | gsub($us;"")),
        (.label       // "" | gsub("\n";"") | gsub($us;"")),
        ((.tokenCount // 0) | tostring),
        (.cwd         // "" | gsub("\n";"") | gsub($us;""))
    ] | join($us)
' 2>/dev/null) || exit 0

if [ -z "$tasks_raw" ]; then
    exit 0
fi

# ─── Render each task ─────────────────────────────────────────────────────────

while IFS=$'\x1f' read -r t_id t_name t_status t_desc t_label t_tokens t_cwd; do
    # Skip rows with no id
    [ -z "$t_id" ] && continue

    # Status icon and color
    case "$t_status" in
        running)
            icon='◐'
            color_e="$CYAN_E"
            ;;
        completed)
            icon='✓'
            color_e="$GREEN_E"
            ;;
        stopped|failed)
            icon='✗'
            color_e="$RED_E"
            ;;
        *)
            icon='·'
            color_e="$GRAY_E"
            ;;
    esac

    # Label or name (prefer label)
    display_name="$t_label"
    [ -z "$display_name" ] && display_name="$t_name"
    [ -z "$display_name" ] && display_name="$t_id"

    # cwd basename
    cwd_base=""
    if [ -n "$t_cwd" ]; then
        cwd_base="${t_cwd##*/}"
    fi

    # Token count formatted
    tok_str=""
    if [ -n "$t_tokens" ]; then
        tok_str=$(_fmt_tokens "$t_tokens")
    fi

    # Compute available width for description (plain chars)
    # Layout: "icon name  [desc  ][tok  ][cwd]"
    # icon=1 + sp=1 + name + sp=2 (before desc) + desc + sp=2 (before tok) + tok + sp=2 (before cwd) + cwd
    fixed_len=$(( 1 + 1 + ${#display_name} ))
    suffix_plain=""
    [ -n "$tok_str" ]  && suffix_plain="${suffix_plain}  ${tok_str}"
    [ -n "$cwd_base" ] && suffix_plain="${suffix_plain}  ${cwd_base}"
    suffix_len=${#suffix_plain}

    # desc_budget: what fits between name and suffix, minus 2 leading spaces
    desc_budget=$(( columns - fixed_len - 2 - suffix_len ))

    # Truncate description to fit
    desc_display=""
    if [ -n "$t_desc" ] && [ "$desc_budget" -gt 3 ]; then
        if [ "${#t_desc}" -le "$desc_budget" ]; then
            desc_display="$t_desc"
        else
            # Leave room for ellipsis (1 byte)
            desc_display="${t_desc:0:$(( desc_budget - 1 ))}…"
        fi
    fi

    # Build content string with real ANSI escape bytes
    content="${color_e}${icon}${NC_E} ${display_name}"
    if [ -n "$desc_display" ]; then
        content="${content}  ${GRAY_E}${desc_display}${NC_E}"
    fi
    if [ -n "$tok_str" ]; then
        content="${content}  ${GRAY_E}${tok_str}${NC_E}"
    fi
    if [ -n "$cwd_base" ]; then
        content="${content}  ${GRAY_E}${cwd_base}${NC_E}"
    fi

    # Emit compact JSON line — jq -cn --arg safely encodes the ANSI bytes
    jq -cn --arg id "$t_id" --arg content "$content" \
        '{"id": $id, "content": $content}'

done <<EOF
$tasks_raw
EOF

exit 0
