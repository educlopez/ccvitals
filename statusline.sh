#!/usr/bin/env bash

# Claude Code Statusline — Real-time usage, context, and git info
# https://github.com/educlopez/ccvitals

STATUSLINE_VERSION="1.6.0"

# Read JSON input from stdin
input=$(cat)

# --- Load module config ---
config_dir="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
config_dir="${config_dir/#\~/$HOME}"
statusline_config="$config_dir/.statusline-config.json"

# --- Optional debug capture ---
# Touch "$config_dir/.statusline-debug" to dump the raw JSON Claude Code sends on
# stdin to "$config_dir/statusline-debug.json" (overwritten each render). Useful for
# diagnosing context/usage values. Remove the flag file to disable.
if [ -f "$config_dir/.statusline-debug" ]; then
    printf '%s\n' "$input" > "$config_dir/statusline-debug.json" 2>/dev/null
fi

# Default: core modules enabled; tool modules (rtk, codegraph) are opt-in
mod_directory=true
mod_model=true
mod_context=true
mod_usage=true
mod_git=true
mod_rtk=false
mod_codegraph=false
mod_lines=false
mod_mode=false
mod_cost=false
mod_duration=false
mod_speed=false
mod_vim=false
mod_agent=false
mod_pr=false
mod_weekly=false
mod_pace=false
mod_cache=false
mod_tools=false
mod_agents=false
mod_todos=false

# Modules listed under "modules_line2" render on a second row (space-delimited
# set checked during composition). Empty = everything on one line.
line2_set=""

if [ -f "$statusline_config" ]; then
    modules=$(jq -r '.modules[]?' "$statusline_config" 2>/dev/null)
    modules2=$(jq -r '.modules_line2[]?' "$statusline_config" 2>/dev/null)
    line2_set=$(printf '%s' "$modules2" | tr '\n' ' ')
    if [ -n "$modules" ] || [ -n "$modules2" ]; then
        # Disable all, then enable the union of both rows
        mod_directory=false
        mod_model=false
        mod_context=false
        mod_usage=false
        mod_git=false
        mod_rtk=false
        mod_codegraph=false
        mod_lines=false
        mod_mode=false
        while IFS= read -r mod; do
            case "$mod" in
                directory) mod_directory=true ;;
                model)     mod_model=true ;;
                context)   mod_context=true ;;
                usage)     mod_usage=true ;;
                git)       mod_git=true ;;
                rtk)       mod_rtk=true ;;
                codegraph) mod_codegraph=true ;;
                lines)     mod_lines=true ;;
                mode)      mod_mode=true ;;
                cost)      mod_cost=true ;;
                duration)  mod_duration=true ;;
                speed)     mod_speed=true ;;
                vim)       mod_vim=true ;;
                agent)     mod_agent=true ;;
                pr)        mod_pr=true ;;
                weekly)    mod_weekly=true ;;
                pace)      mod_pace=true ;;
                cache)     mod_cache=true ;;
                tools)     mod_tools=true ;;
                agents)    mod_agents=true ;;
                todos)     mod_todos=true ;;
            esac
        done <<< "$modules
$modules2"
    fi
fi

# Extract information from JSON
model_name=$(echo "$input" | jq -r '.model.display_name')
current_dir=$(echo "$input" | jq -r '.workspace.current_dir')

# --- Theme / Color resolution ---
# Convert a hex color string (#RRGGBB) to a truecolor ANSI escape sequence.
# Bash-3.2 compatible: uses printf %d with 0x prefix for hex→decimal conversion.
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
BLUE='\033[0;34m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
GRAY='\033[0;90m'
MAGENTA='\033[0;95m'
NC='\033[0m' # No Color

# Apply theme preset if configured. Falls back to defaults silently on any error.
if [ -f "$statusline_config" ]; then
    _theme=$(jq -r '.theme // empty' "$statusline_config" 2>/dev/null)
    case "$_theme" in
        pastel)
            RED=$(hex_to_ansi '#ee7975')
            GREEN=$(hex_to_ansi '#89f78e')
            BLUE=$(hex_to_ansi '#ba9af3')
            YELLOW=$(hex_to_ansi '#f4fa9e')
            CYAN=$(hex_to_ansi '#a5e8fa')
            GRAY=$(hex_to_ansi '#a1a1a1')
            MAGENTA=$(hex_to_ansi '#ef86c6')
            ;;
        tokyo-night)
            RED=$(hex_to_ansi '#f7768e')
            GREEN=$(hex_to_ansi '#9ece6a')
            BLUE=$(hex_to_ansi '#7aa2f7')
            YELLOW=$(hex_to_ansi '#e0af68')
            CYAN=$(hex_to_ansi '#7dcfff')
            GRAY=$(hex_to_ansi '#565f89')
            MAGENTA=$(hex_to_ansi '#bb9af7')
            ;;
        catppuccin)
            RED=$(hex_to_ansi '#f38ba8')
            GREEN=$(hex_to_ansi '#a6e3a1')
            BLUE=$(hex_to_ansi '#89b4fa')
            YELLOW=$(hex_to_ansi '#f9e2af')
            CYAN=$(hex_to_ansi '#94e2d5')
            GRAY=$(hex_to_ansi '#6c7086')
            MAGENTA=$(hex_to_ansi '#cba6f7')
            ;;
        dracula)
            RED=$(hex_to_ansi '#ff5555')
            GREEN=$(hex_to_ansi '#50fa7b')
            BLUE=$(hex_to_ansi '#6272a4')
            YELLOW=$(hex_to_ansi '#f1fa8c')
            CYAN=$(hex_to_ansi '#8be9fd')
            GRAY=$(hex_to_ansi '#6272a4')
            MAGENTA=$(hex_to_ansi '#ff79c6')
            ;;
        nord)
            RED=$(hex_to_ansi '#bf616a')
            GREEN=$(hex_to_ansi '#a3be8c')
            BLUE=$(hex_to_ansi '#81a1c1')
            YELLOW=$(hex_to_ansi '#ebcb8b')
            CYAN=$(hex_to_ansi '#88c0d0')
            GRAY=$(hex_to_ansi '#4c566a')
            MAGENTA=$(hex_to_ansi '#b48ead')
            ;;
        mono)
            RED='\033[1m'
            GREEN='\033[1m'
            BLUE='\033[1m'
            YELLOW='\033[1m'
            CYAN='\033[1m'
            GRAY='\033[0;37m'
            MAGENTA='\033[1m'
            ;;
        custom)
            # Apply per-color overrides; missing keys keep the default value
            _c_red=$(jq -r '.colors.red // empty' "$statusline_config" 2>/dev/null)
            _c_green=$(jq -r '.colors.green // empty' "$statusline_config" 2>/dev/null)
            _c_blue=$(jq -r '.colors.blue // empty' "$statusline_config" 2>/dev/null)
            _c_yellow=$(jq -r '.colors.yellow // empty' "$statusline_config" 2>/dev/null)
            _c_cyan=$(jq -r '.colors.cyan // empty' "$statusline_config" 2>/dev/null)
            _c_gray=$(jq -r '.colors.gray // empty' "$statusline_config" 2>/dev/null)
            _c_magenta=$(jq -r '.colors.magenta // empty' "$statusline_config" 2>/dev/null)
            [ -n "$_c_red" ]     && RED=$(hex_to_ansi "$_c_red")
            [ -n "$_c_green" ]   && GREEN=$(hex_to_ansi "$_c_green")
            [ -n "$_c_blue" ]    && BLUE=$(hex_to_ansi "$_c_blue")
            [ -n "$_c_yellow" ]  && YELLOW=$(hex_to_ansi "$_c_yellow")
            [ -n "$_c_cyan" ]    && CYAN=$(hex_to_ansi "$_c_cyan")
            [ -n "$_c_gray" ]    && GRAY=$(hex_to_ansi "$_c_gray")
            [ -n "$_c_magenta" ] && MAGENTA=$(hex_to_ansi "$_c_magenta")
            ;;
        default|'')
            # Keep legacy ANSI defaults defined above
            ;;
    esac
    unset _theme _c_red _c_green _c_blue _c_yellow _c_cyan _c_gray _c_magenta
fi

# Get directory name (basename)
dir_name=$(basename "$current_dir")

# --- Context window ---
context_info=""
if [ "$mod_context" = true ]; then
    context_size=$(echo "$input" | jq -r '.context_window.context_window_size // 200000')

    # Token totals from the most recent API response (input-only, matching Claude Code's
    # own used_percentage accounting). Null-safe so a missing current_usage yields 0.
    current_tokens=$(echo "$input" | jq -r '
        (.context_window.current_usage.input_tokens // 0)
        + (.context_window.current_usage.cache_creation_input_tokens // 0)
        + (.context_window.current_usage.cache_read_input_tokens // 0)')

    # Detect the extended (1M) context tier. Claude Code can keep reporting
    # context_window_size as the 200k base even when the session actually runs on the 1M
    # window, so live usage may exceed it. Against 200k those percentages saturate at 100%
    # (Claude Code's own used_percentage also caps at 100), which pins the bar full. When
    # live tokens exceed the reported size, promote the effective window to 1M.
    if [ "${current_tokens:-0}" -gt "$context_size" ] 2>/dev/null; then
        context_size=1000000
    fi

    # Compute from live tokens (input-only, same formula as Claude Code's used_percentage,
    # and correct for both the 200k and 1M tiers). Fall back to the pre-calculated
    # used_percentage only when current_usage is unavailable — e.g. right after /compact,
    # before the next API call repopulates it.
    if [ "${current_tokens:-0}" -gt 0 ] 2>/dev/null; then
        context_percent=$((current_tokens * 100 / context_size))
    else
        used_pct=$(echo "$input" | jq -r '.context_window.used_percentage // empty')
        if [ -n "$used_pct" ]; then
            context_percent=$(printf '%.0f' "$used_pct")
        else
            context_percent=0
        fi
    fi

    # Build context progress bar (15 chars wide). Clamp fill so an over-budget or
    # cumulative-token report never spills past the bar width.
    bar_width=15
    filled=$((context_percent * bar_width / 100))
    [ "$filled" -gt "$bar_width" ] && filled=$bar_width
    [ "$filled" -lt 0 ] && filled=0
    empty=$((bar_width - filled))
    bar=""
    for ((i=0; i<filled; i++)); do bar+="█"; done
    for ((i=0; i<empty; i++)); do bar+="░"; done

    # Context-pressure alert based on how full the window is — consistent across the
    # 200k and 1M tiers (an absolute token threshold would false-alarm on 1M sessions).
    ctx_color="$NC"
    ctx_warn=""
    if [ "${context_percent:-0}" -ge 90 ] 2>/dev/null; then
        ctx_color="$RED"
        ctx_warn=" ${RED}⚠${NC}"
    fi

    # context_display: "percent" (default), "tokens", or "both"
    ctx_display=""
    if [ -f "$statusline_config" ]; then
        ctx_display=$(jq -r '.context_display // empty' "$statusline_config" 2>/dev/null)
    fi

    case "${ctx_display:-percent}" in
        tokens|both)
            # Format token counts: under 100k → one decimal k; 100k+ → integer k; 1M+ → M
            _fmt_k() {
                local n="$1"
                if [ "$n" -ge 1000000 ] 2>/dev/null; then
                    printf '%dM' "$((n / 1000000))"
                elif [ "$n" -ge 100000 ] 2>/dev/null; then
                    printf '%dk' "$((n / 1000))"
                elif [ "$n" -ge 1000 ] 2>/dev/null; then
                    # one decimal: e.g. 45200 -> 45.2k
                    local q=$((n / 100))
                    printf '%d.%dk' "$((q / 10))" "$((q % 10))"
                else
                    printf '%d' "$n"
                fi
            }
            tok_str="$(_fmt_k "${current_tokens:-0}")/$(_fmt_k "$context_size")"
            if [ "${ctx_display}" = "tokens" ]; then
                context_info="${GRAY}${bar}${NC} ${ctx_color}${tok_str}${NC}${ctx_warn}"
            else
                context_info="${GRAY}${bar}${NC} ${ctx_color}${tok_str} ${context_percent}%${NC}${ctx_warn}"
            fi
            ;;
        *)
            context_info="${GRAY}${bar}${NC} ${ctx_color}${context_percent}%${NC}${ctx_warn}"
            ;;
    esac
fi

# --- Usage/Quota fetch (cached) ---
usage_info=""
if [ "$mod_usage" = true ]; then
    cache_dir="$config_dir/.usage-cache"
    cache_file="$cache_dir/usage.json"
    last_good_file="$cache_dir/usage-last-good.json"
    cache_ttl=300         # seconds (5 min) — normal cache
    cache_failure_ttl=120 # seconds (2 min) — backoff for failed/rate-limited requests

    # Read credentials from macOS Keychain (Claude Code 2.x+)
    # Claude Code stores OAuth tokens in Keychain with profile-specific service names:
    #   ~/.claude           -> "Claude Code-credentials"
    #   custom config dir   -> "Claude Code-credentials-<sha256_prefix>"
    read_keychain_creds() {
        [ "$(uname)" != "Darwin" ] && return 1

        local keychain_service="Claude Code-credentials"
        local normalized_dir
        normalized_dir=$(cd "$config_dir" 2>/dev/null && pwd -P || echo "$config_dir")
        local default_dir
        default_dir=$(cd "$HOME/.claude" 2>/dev/null && pwd -P || echo "$HOME/.claude")

        if [ "$normalized_dir" != "$default_dir" ]; then
            local hash
            hash=$(printf '%s' "$config_dir" | shasum -a 256 | cut -c1-8)
            keychain_service="Claude Code-credentials-${hash}"
        fi

        local keychain_data
        keychain_data=$(/usr/bin/security find-generic-password -s "$keychain_service" -w 2>/dev/null)
        if [ -z "$keychain_data" ]; then
            # Fallback to legacy service name
            keychain_data=$(/usr/bin/security find-generic-password -s "Claude Code-credentials" -w 2>/dev/null)
        fi
        [ -z "$keychain_data" ] && return 1

        echo "$keychain_data"
    }

    fetch_usage() {
        local access_token=""
        local sub_type=""

        # Try macOS Keychain first (Claude Code 2.x+)
        local keychain_json
        keychain_json=$(read_keychain_creds)
        if [ -n "$keychain_json" ]; then
            access_token=$(echo "$keychain_json" | jq -r '.claudeAiOauth.accessToken // empty' 2>/dev/null)
            sub_type=$(echo "$keychain_json" | jq -r '.claudeAiOauth.subscriptionType // empty' 2>/dev/null)
        fi

        # Fallback to file-based credentials (older versions)
        if [ -z "$access_token" ]; then
            local creds_file="$config_dir/.credentials.json"
            [ ! -f "$creds_file" ] && creds_file="$HOME/.claude/.credentials.json"
            [ ! -f "$creds_file" ] && return 1

            access_token=$(jq -r '.claudeAiOauth.accessToken // empty' "$creds_file" 2>/dev/null)
            [ -z "$access_token" ] && return 1
            sub_type=$(jq -r '.claudeAiOauth.subscriptionType // empty' "$creds_file" 2>/dev/null)
        fi

        [ -z "$access_token" ] && return 1

        # Skip for API-only users (no quota system)
        case "$sub_type" in
            api|*api*) return 1 ;;
        esac


        # Call the usage API (capture headers + body to read retry-after on 429)
        local tmp_headers
        tmp_headers=$(mktemp)
        local response
        response=$(curl -s --max-time 10 -D "$tmp_headers" \
            -H "Authorization: Bearer $access_token" \
            -H "anthropic-beta: oauth-2025-04-20" \
            -H "User-Agent: ccvitals/$STATUSLINE_VERSION" \
            "https://api.anthropic.com/api/oauth/usage" 2>/dev/null)

        # Check for rate limit or failure
        local http_status
        http_status=$(head -1 "$tmp_headers" 2>/dev/null | grep -oE '[0-9]{3}' | head -1)

        if [ "$http_status" = "429" ] || [ -z "$response" ]; then
            # Read retry-after header for smart backoff
            local retry_after
            retry_after=$(grep -i '^retry-after:' "$tmp_headers" 2>/dev/null | grep -oE '[0-9]+' | head -1)
            rm -f "$tmp_headers"
            # Ensure minimum backoff (API may return retry-after: 0)
            [ -z "$retry_after" ] || [ "$retry_after" -lt "$cache_failure_ttl" ] 2>/dev/null && retry_after=$cache_failure_ttl
            cache_failure "$sub_type" "$retry_after"
            return 1
        fi
        rm -f "$tmp_headers"

        # Non-200 or invalid response
        if [ "$http_status" != "200" ]; then
            cache_failure "$sub_type" "$cache_failure_ttl"
            return 1
        fi

        # Validate response has expected structure
        if ! echo "$response" | jq -e '.five_hour or .seven_day' >/dev/null 2>&1; then
            cache_failure "$sub_type" "$cache_failure_ttl"
            return 1
        fi

        # Write cache + save as last known good
        mkdir -p "$cache_dir"
        jq -n --argjson data "$response" --arg ts "$(date +%s)" --arg plan "$sub_type" \
            '{data: $data, timestamp: ($ts | tonumber), plan: $plan, error: false}' > "$cache_file" 2>/dev/null
        cp "$cache_file" "$last_good_file" 2>/dev/null
    }

    # Cache failed API calls to prevent retry storms
    # $1 = plan, $2 = retry TTL in seconds (from retry-after header or default)
    cache_failure() {
        local plan="${1:-}"
        local retry_ttl="${2:-$cache_failure_ttl}"
        mkdir -p "$cache_dir"
        jq -n --arg ts "$(date +%s)" --arg plan "$plan" --arg ttl "$retry_ttl" \
            '{data: null, timestamp: ($ts | tonumber), plan: $plan, error: true, retry_ttl: ($ttl | tonumber)}' > "$cache_file" 2>/dev/null
    }

    # Render best available data: current cache if good, else last known good
    render_best_available() {
        if [ -f "$cache_file" ]; then
            local is_error
            is_error=$(jq -r '.error // false' "$cache_file" 2>/dev/null)
            if [ "$is_error" != "true" ]; then
                render_usage "$cache_file"
                return
            fi
        fi
        # Fallback to last known good data
        [ -f "$last_good_file" ] && render_usage "$last_good_file"
    }

    get_usage_display() {
        # Fast path: Claude Code provides rate_limits via stdin — render with zero
        # network and zero cache requirements. The plan badge comes from the last
        # successful API fetch if one exists; absent that it's simply omitted.
        local stdin_rl
        stdin_rl=$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty' 2>/dev/null)
        if [ -n "$stdin_rl" ]; then
            render_usage "$last_good_file"
            return
        fi

        local now=$(date +%s)

        # Check cache freshness (respect retry-after on failures)
        if [ -f "$cache_file" ]; then
            local cached_ts is_error ttl
            cached_ts=$(jq -r '.timestamp // 0' "$cache_file" 2>/dev/null)
            is_error=$(jq -r '.error // false' "$cache_file" 2>/dev/null)
            if [ "$is_error" = "true" ]; then
                ttl=$(jq -r '.retry_ttl // '"$cache_failure_ttl" "$cache_file" 2>/dev/null)
            else
                ttl=$cache_ttl
            fi
            local age=$(( now - cached_ts ))
            if [ "$age" -lt "$ttl" ]; then
                render_best_available
                return
            fi
        fi

        # Cache stale or missing — fetch in background, show best available now
        if [ -f "$cache_file" ]; then
            render_best_available
            fetch_usage &
        else
            # First run — fetch synchronously (one-time delay)
            fetch_usage
            render_best_available
        fi
    }

    render_usage() {
        local file="$1"
        local five_h seven_d plan_raw

        five_h=$(jq -r '.data.five_hour.utilization // empty' "$file" 2>/dev/null)
        seven_d=$(jq -r '.data.seven_day.utilization // empty' "$file" 2>/dev/null)
        plan_raw=$(jq -r '.plan // empty' "$file" 2>/dev/null)

        # Prefer stdin rate_limits when present (zero-latency, no network)
        local stdin_5h stdin_7d
        stdin_5h=$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty' 2>/dev/null)
        if [ -n "$stdin_5h" ]; then
            five_h="$stdin_5h"
        fi
        stdin_7d=$(echo "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty' 2>/dev/null)
        if [ -n "$stdin_7d" ]; then
            seven_d="$stdin_7d"
        fi

        [ -z "$five_h" ] && return

        # Derive plan display name
        local plan_name=""
        case "$plan_raw" in
            *max*|*Max*) plan_name="Max" ;;
            *pro*|*Pro*) plan_name="Pro" ;;
            *team*|*Team*) plan_name="Team" ;;
            *) plan_name="$plan_raw" ;;
        esac

        # Round to integer
        five_h=$(printf '%.0f' "$five_h")
        [ -n "$seven_d" ] && seven_d=$(printf '%.0f' "$seven_d")

        # Color based on usage level
        local color="$CYAN"
        if [ "$five_h" -ge 90 ]; then
            color="$RED"
        elif [ "$five_h" -ge 75 ]; then
            color="$MAGENTA"
        elif [ "$five_h" -ge 50 ]; then
            color="$YELLOW"
        fi

        # Build usage bar (10 chars)
        local u_bar_width=10
        local u_filled=$((five_h * u_bar_width / 100))
        [ "$u_filled" -gt "$u_bar_width" ] && u_filled=$u_bar_width
        local u_empty=$((u_bar_width - u_filled))
        local u_bar=""
        for ((i=0; i<u_filled; i++)); do u_bar+="█"; done
        for ((i=0; i<u_empty; i++)); do u_bar+="░"; done

        # Reset time for 5h window (prefer stdin rate_limits.five_hour.resets_at when present)
        local reset_str=""
        local reset_at
        reset_at=$(echo "$input" | jq -r '.rate_limits.five_hour.resets_at // empty' 2>/dev/null)
        if [ -z "$reset_at" ]; then
            reset_at=$(jq -r '.data.five_hour.resets_at // empty' "$file" 2>/dev/null)
        fi
        if [ -n "$reset_at" ]; then
            local reset_epoch=""
            # stdin resets_at is a unix epoch integer; cache file value is ISO date string
            case "$reset_at" in
                [0-9]*)
                    reset_epoch="$reset_at"
                    ;;
                *)
                    local clean_date
                    clean_date=$(echo "$reset_at" | sed -E 's/\.[0-9]+//; s/\+00:00$/Z/')
                    reset_epoch=$(TZ=UTC date -j -f "%Y-%m-%dT%H:%M:%SZ" "$clean_date" +%s 2>/dev/null \
                        || date -u -d "$clean_date" +%s 2>/dev/null)
                    ;;
            esac
            if [ -n "$reset_epoch" ]; then
                local remaining=$(( reset_epoch - $(date +%s) ))
                if [ "$remaining" -gt 0 ]; then
                    local hours=$((remaining / 3600))
                    local mins=$(( (remaining % 3600) / 60 ))
                    if [ "$hours" -gt 0 ]; then
                        reset_str=" ${GRAY}${hours}h${mins}m${NC}"
                    else
                        reset_str=" ${GRAY}${mins}m${NC}"
                    fi
                fi
            fi
        fi

        # Compose
        local display="${color}${u_bar}${NC} ${color}${five_h}%${NC}${reset_str}"

        # Add 7-day if above 70%
        if [ -n "$seven_d" ] && [ "$seven_d" -ge 70 ]; then
            local s_color="$CYAN"
            [ "$seven_d" -ge 90 ] && s_color="$RED"
            [ "$seven_d" -ge 75 ] && [ "$seven_d" -lt 90 ] && s_color="$MAGENTA"
            display="${display} ${GRAY}7d:${NC}${s_color}${seven_d}%${NC}"
        fi

        if [ -n "$plan_name" ]; then
            usage_info="${GRAY}${plan_name}${NC} ${display}"
        else
            usage_info="$display"
        fi
    }

    get_usage_display
fi

# --- Cost module ---
cost_info=""
if [ "$mod_cost" = true ]; then
    cost_val=$(echo "$input" | jq -r '.cost.total_cost_usd // empty')
    if [ -n "$cost_val" ]; then
        # Format: $0.12 under $10 (2 decimal), else 1 decimal or integer
        cost_fmt=$(echo "$cost_val" | awk '{
            v = $1 + 0
            if (v < 10) { printf "$%.2f", v }
            else if (v < 100) { printf "$%.1f", v }
            else { printf "$%.0f", v }
        }')
        cost_info="${GRAY}${cost_fmt}${NC}"
    fi
fi

# --- Duration module ---
duration_info=""
if [ "$mod_duration" = true ]; then
    dur_ms=$(echo "$input" | jq -r '.cost.total_duration_ms // empty')
    if [ -n "$dur_ms" ] && [ "$dur_ms" -gt 0 ] 2>/dev/null; then
        dur_s=$((dur_ms / 1000))
        dur_mins=$((dur_s / 60))
        dur_hrs=$((dur_mins / 60))
        dur_days=$((dur_hrs / 24))
        if [ "$dur_days" -gt 0 ]; then
            leftover_hrs=$((dur_hrs - dur_days * 24))
            duration_info="${GRAY}${dur_days}d${leftover_hrs}h${NC}"
        elif [ "$dur_hrs" -gt 0 ]; then
            leftover_mins=$((dur_mins - dur_hrs * 60))
            duration_info="${GRAY}${dur_hrs}h${leftover_mins}m${NC}"
        else
            duration_info="${GRAY}${dur_mins}m${NC}"
        fi
    fi
fi

# --- Speed module (tok/s using local cache keyed by session_id) ---
speed_info=""
if [ "$mod_speed" = true ]; then
    speed_session=$(echo "$input" | jq -r '.session_id // empty')
    sp_input=$(echo "$input" | jq -r '.context_window.total_input_tokens // 0')
    sp_output=$(echo "$input" | jq -r '.context_window.total_output_tokens // 0')
    if [ -n "$speed_session" ] && [ "${sp_input:-0}" -ge 0 ] 2>/dev/null; then
        sp_total=$((sp_input + sp_output))
        sp_now=$(date +%s)
        speed_cache_dir="$config_dir/.speed-cache"
        sp_file="$speed_cache_dir/speed-$(printf '%s' "$speed_session" | tr -dc 'a-zA-Z0-9_-' | cut -c1-40).txt"
        mkdir -p "$speed_cache_dir"
        sp_prev_tokens=""
        sp_prev_epoch=""
        if [ -f "$sp_file" ]; then
            sp_prev_tokens=$(cut -f1 "$sp_file" 2>/dev/null)
            sp_prev_epoch=$(cut -f2 "$sp_file" 2>/dev/null)
        fi
        if [ -n "$sp_prev_tokens" ] && [ -n "$sp_prev_epoch" ] && [ "$sp_prev_tokens" -ge 0 ] 2>/dev/null && [ "$sp_prev_epoch" -ge 0 ] 2>/dev/null; then
            sp_delta_tokens=$((sp_total - sp_prev_tokens))
            sp_delta_secs=$((sp_now - sp_prev_epoch))
            if [ "$sp_delta_tokens" -lt 0 ]; then
                # Context shrunk (compact) — reset baseline
                printf '%s\t%s\n' "$sp_total" "$sp_now" > "$sp_file"
            elif [ "$sp_delta_secs" -ge 1 ]; then
                sp_rate=$((sp_delta_tokens / sp_delta_secs))
                speed_info="${GRAY}${sp_rate} tok/s${NC}"
                printf '%s\t%s\n' "$sp_total" "$sp_now" > "$sp_file"
            fi
        else
            # First render or corrupt cache — write baseline, hide output
            printf '%s\t%s\n' "$sp_total" "$sp_now" > "$sp_file"
        fi
    fi
fi

# --- Vim mode module ---
vim_info=""
if [ "$mod_vim" = true ]; then
    vim_mode=$(echo "$input" | jq -r '.vim.mode // empty')
    if [ -n "$vim_mode" ]; then
        case "$vim_mode" in
            "NORMAL")      vim_info="${GREEN}N${NC}" ;;
            "INSERT")      vim_info="${CYAN}I${NC}" ;;
            "VISUAL")      vim_info="${YELLOW}V${NC}" ;;
            "VISUAL LINE") vim_info="${MAGENTA}VL${NC}" ;;
            *)             vim_info="${GRAY}${vim_mode}${NC}" ;;
        esac
    fi
fi

# --- Agent module ---
agent_info=""
if [ "$mod_agent" = true ]; then
    agent_name=$(echo "$input" | jq -r '.agent.name // empty')
    [ -n "$agent_name" ] && agent_info="${CYAN}@ ${agent_name}${NC}"
fi

# --- PR module ---
pr_info=""
if [ "$mod_pr" = true ]; then
    pr_num=$(echo "$input" | jq -r '.pr.number // empty')
    if [ -n "$pr_num" ]; then
        pr_review=$(echo "$input" | jq -r '.pr.review_state // empty')
        pr_url=$(echo "$input" | jq -r '.pr.url // empty')
        pr_text="${CYAN}PR #${pr_num}${NC}"
        # OSC 8 hyperlink when URL present
        if [ -n "$pr_url" ]; then
            pr_text="\033]8;;${pr_url}\033\\${CYAN}PR #${pr_num}${NC}\033]8;;\033\\"
        fi
        pr_info="$pr_text"
        [ -n "$pr_review" ] && pr_info="${pr_info} ${GRAY}${pr_review}${NC}"
    fi
fi

# --- Weekly quota module ---
weekly_info=""
if [ "$mod_weekly" = true ]; then
    # Prefer stdin rate_limits.seven_day when present (zero-latency)
    weekly_pct=$(echo "$input" | jq -r '(.rate_limits.seven_day.used_percentage // empty) | floor')
    weekly_resets=$(echo "$input" | jq -r '.rate_limits.seven_day.resets_at // empty')
    if [ -n "$weekly_pct" ]; then
        # Color
        w_color="$CYAN"
        [ "$weekly_pct" -ge 50 ] 2>/dev/null && w_color="$YELLOW"
        [ "$weekly_pct" -ge 75 ] 2>/dev/null && w_color="$MAGENTA"
        [ "$weekly_pct" -ge 90 ] 2>/dev/null && w_color="$RED"
        # Bar (10 chars, same style as usage module)
        w_bar_width=10
        w_filled=$((weekly_pct * w_bar_width / 100))
        [ "$w_filled" -gt "$w_bar_width" ] && w_filled=$w_bar_width
        w_empty=$((w_bar_width - w_filled))
        w_bar=""
        for ((i=0; i<w_filled; i++)); do w_bar+="█"; done
        for ((i=0; i<w_empty; i++)); do w_bar+="░"; done
        # Reset countdown
        w_reset_str=""
        case "$weekly_resets" in
            ''|*[!0-9]*) w_reset_epoch=0 ;;  # absent or ISO string — skip countdown
            *) w_reset_epoch=$weekly_resets ;;
        esac
        if [ -n "$weekly_resets" ]; then
            if [ "$w_reset_epoch" -gt 0 ] 2>/dev/null; then
                w_remaining=$(( w_reset_epoch - $(date +%s) ))
                if [ "$w_remaining" -gt 0 ]; then
                    w_days=$((w_remaining / 86400))
                    w_hrs=$(( (w_remaining % 86400) / 3600 ))
                    if [ "$w_days" -gt 0 ]; then
                        w_reset_str=" ${GRAY}${w_days}d${w_hrs}h${NC}"
                    elif [ "$w_hrs" -gt 0 ]; then
                        w_mins=$(( (w_remaining % 3600) / 60 ))
                        w_reset_str=" ${GRAY}${w_hrs}h${w_mins}m${NC}"
                    else
                        w_mins=$(( w_remaining / 60 ))
                        w_reset_str=" ${GRAY}${w_mins}m${NC}"
                    fi
                fi
            fi
        fi
        weekly_info="${GRAY}7d:${NC} ${w_color}${w_bar}${NC} ${w_color}${weekly_pct}%${NC}${w_reset_str}"
    fi
fi

# --- Tool modules (rtk, codegraph) ---
tool_cache_dir="$config_dir/.tool-cache"

# cached_run <cache_file> <ttl_seconds> <producer_fn>
# Prints the cached value when fresh. When stale, prints the stale value
# immediately and refreshes in the background; on first run fetches once
# synchronously. Keeps every render cheap regardless of the producer cost.
cached_run() {
    local cf="$1" ttl="$2" producer="$3"
    local now mtime age
    now=$(date +%s)
    if [ -f "$cf" ]; then
        mtime=$(stat -f %m "$cf" 2>/dev/null || stat -c %Y "$cf" 2>/dev/null || echo 0)
        age=$(( now - mtime ))
        if [ "$age" -lt "$ttl" ]; then
            cat "$cf"
            return
        fi
        cat "$cf"
        ( "$producer" > "$cf.tmp" 2>/dev/null && mv "$cf.tmp" "$cf" 2>/dev/null ) &
    else
        mkdir -p "$(dirname "$cf")"
        "$producer" > "$cf" 2>/dev/null
        cat "$cf"
    fi
}

# rtk: global token-savings percentage (cached 60s)
rtk_info=""
if [ "$mod_rtk" = true ] && command -v rtk >/dev/null 2>&1; then
    rtk_producer() {
        rtk gain 2>/dev/null | grep -m1 'Tokens saved' \
            | grep -oE '[0-9]+(\.[0-9]+)?%' | head -1
    }
    rtk_val=$(cached_run "$tool_cache_dir/rtk.txt" 60 rtk_producer)
    [ -n "$rtk_val" ] && rtk_info="${CYAN}rtk ${rtk_val}↓${NC}"
fi

# codegraph: per-project index health, only when a .codegraph index exists (cached 15s)
cg_info=""
if [ "$mod_codegraph" = true ] && command -v codegraph >/dev/null 2>&1 && [ -d "$current_dir/.codegraph" ]; then
    cg_dir="$current_dir"
    cg_producer() {
        cd "$cg_dir" 2>/dev/null || return
        codegraph status --json 2>/dev/null | jq -r '
            if .initialized != true then empty
            else
                (.nodeCount // 0) as $n
                | (((.pendingChanges.added // 0) + (.pendingChanges.modified // 0) + (.pendingChanges.removed // 0))) as $p
                | (if $n >= 1000 then (((($n / 100) | floor) / 10) | tostring) + "k" else ($n | tostring) end) as $ns
                | "\($ns)\t\($p)"
            end' 2>/dev/null
    }
    cg_hash=$(printf '%s' "$cg_dir" | shasum -a 256 2>/dev/null | cut -c1-12)
    cg_line=$(cached_run "$tool_cache_dir/cg-$cg_hash.txt" 15 cg_producer)
    if [ -n "$cg_line" ]; then
        cg_nodes=$(printf '%s' "$cg_line" | cut -f1)
        cg_pending=$(printf '%s' "$cg_line" | cut -f2)
        cg_info="${CYAN}⬡ ${cg_nodes}${NC}"
        if [ "${cg_pending:-0}" -gt 0 ] 2>/dev/null; then
            cg_info="${cg_info} ${YELLOW}⚠${cg_pending}${NC}"
        fi
    fi
fi

# --- Session lines (cumulative agent edits this session, from stdin) ---
lines_info=""
if [ "$mod_lines" = true ]; then
    l_added=$(echo "$input" | jq -r '.cost.total_lines_added // 0')
    l_removed=$(echo "$input" | jq -r '.cost.total_lines_removed // 0')
    if { [ "${l_added:-0}" -gt 0 ] 2>/dev/null; } || { [ "${l_removed:-0}" -gt 0 ] 2>/dev/null; }; then
        [ "${l_added:-0}" -gt 0 ] 2>/dev/null && lines_info="${GREEN}+${l_added}${NC}"
        [ "${l_removed:-0}" -gt 0 ] 2>/dev/null && lines_info="${lines_info:+$lines_info }${RED}-${l_removed}${NC}"
    fi
fi

# --- Reasoning/mode badge (effort level + fast-mode flag, from stdin) ---
mode_info=""
if [ "$mod_mode" = true ]; then
    m_fast=$(echo "$input" | jq -r '.fast_mode // false')
    m_effort=$(echo "$input" | jq -r '.effort.level // empty')
    m_parts=""
    [ "$m_fast" = "true" ] && m_parts="⚡"
    [ -n "$m_effort" ] && m_parts="${m_parts}${m_parts:+ }${m_effort}"
    [ -n "$m_parts" ] && mode_info="${MAGENTA}${m_parts}${NC}"
fi

# --- Git info ---
git_info=""
if [ "$mod_git" = true ]; then
    cd "$current_dir" 2>/dev/null || cd /
    export GIT_OPTIONAL_LOCKS=0

    if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        branch=$(git branch --show-current 2>/dev/null || echo "detached")

        # Ahead/behind counts relative to upstream
        ab_ahead=""
        ab_behind=""
        ab_counts=$(git rev-list --left-right --count '@{upstream}...HEAD' 2>/dev/null)
        if [ -n "$ab_counts" ]; then
            ab_behind=$(printf '%s' "$ab_counts" | cut -f1)
            ab_ahead=$(printf '%s' "$ab_counts" | cut -f2)
            # Treat "0" as empty (suppress)
            [ "${ab_ahead:-0}" -eq 0 ]  2>/dev/null && ab_ahead=""
            [ "${ab_behind:-0}" -eq 0 ] 2>/dev/null && ab_behind=""
        fi

        # OSC 8 clickable branch link for GitHub/GitLab remotes
        branch_text="${YELLOW}${branch}${NC}"
        origin_url=$(git remote get-url origin 2>/dev/null)
        if [ -n "$origin_url" ]; then
            # Normalise git@host:owner/repo.git and https://host/owner/repo.git
            case "$origin_url" in
                git@github.com:*|git@gitlab.com:*)
                    _host=$(printf '%s' "$origin_url" | sed 's/git@\([^:]*\):.*/\1/')
                    _path=$(printf '%s' "$origin_url" | sed 's/git@[^:]*://; s/\.git$//')
                    branch_text="\033]8;;https://${_host}/${_path}/tree/${branch}\033\\${YELLOW}${branch}${NC}\033]8;;\033\\"
                    ;;
                https://github.com/*|https://gitlab.com/*)
                    _url=$(printf '%s' "$origin_url" | sed 's/\.git$//')
                    branch_text="\033]8;;${_url}/tree/${branch}\033\\${YELLOW}${branch}${NC}\033]8;;\033\\"
                    ;;
            esac
        fi

        status_output=$(git status --porcelain 2>/dev/null)

        if [ -n "$status_output" ]; then
            total_files=$(echo "$status_output" | wc -l | xargs)
            line_stats=$(git diff --numstat HEAD 2>/dev/null | awk '{added+=$1; removed+=$2} END {print added+0, removed+0}')
            added=$(echo "$line_stats" | cut -d' ' -f1)
            removed=$(echo "$line_stats" | cut -d' ' -f2)

            git_info="${YELLOW}(${NC}${branch_text} ${YELLOW}|${NC} ${GRAY}${total_files} files${NC}"
            [ "$added" -gt 0 ] && git_info="${git_info} ${GREEN}+${added}${NC}"
            [ "$removed" -gt 0 ] && git_info="${git_info} ${RED}-${removed}${NC}"
        else
            git_info="${YELLOW}(${NC}${branch_text}"
        fi

        # Append ahead/behind after branch (before closing paren)
        if [ -n "$ab_ahead" ]; then
            git_info="${git_info} ${GREEN}↑${ab_ahead}${NC}"
        fi
        if [ -n "$ab_behind" ]; then
            git_info="${git_info} ${YELLOW}↓${ab_behind}${NC}"
        fi
        git_info="${git_info}${YELLOW})${NC}"
    fi
fi

# --- Pace module (burn-rate vs 5h quota window) ---
pace_info=""
if [ "$mod_pace" = true ]; then
    pace_used=$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty' 2>/dev/null)
    pace_resets=$(echo "$input" | jq -r '.rate_limits.five_hour.resets_at // empty' 2>/dev/null)
    if [ -n "$pace_used" ] && [ -n "$pace_resets" ]; then
        # Only proceed when resets_at looks like a unix epoch integer
        case "$pace_resets" in
            ''|*[!0-9]*)
                pace_resets=""
                ;;
        esac
        if [ -n "$pace_resets" ]; then
            pace_now=$(date +%s)
            pace_window=18000  # 5 hours in seconds
            pace_remaining=$(( pace_resets - pace_now ))
            # Hide when remaining is out of valid range (corrupt / expired / future-reset)
            if [ "$pace_remaining" -gt 0 ] 2>/dev/null && [ "$pace_remaining" -le "$pace_window" ] 2>/dev/null; then
                pace_elapsed=$(( pace_window - pace_remaining ))
                # Integer math: elapsed * 100 / window
                pace_expected=$(( pace_elapsed * 100 / pace_window ))
                # Round used_pct to integer
                pace_used_int=$(printf '%.0f' "$pace_used")
                pace_delta=$(( pace_expected - pace_used_int ))
                # Format with sign
                if [ "$pace_delta" -ge 0 ] 2>/dev/null; then
                    pace_color="$GREEN"
                    pace_sign="+"
                elif [ "$pace_delta" -ge -10 ] 2>/dev/null; then
                    pace_color="$YELLOW"
                    pace_sign=""
                else
                    pace_color="$RED"
                    pace_sign=""
                fi
                pace_info="${pace_color}pace ${pace_sign}${pace_delta}%${NC}"
            fi
        fi
    fi
fi

# --- Cache module (prompt-cache freshness countdown) ---
cache_info=""
if [ "$mod_cache" = true ]; then
    cache_transcript=$(echo "$input" | jq -r '.transcript_path // empty' 2>/dev/null)
    if [ -n "$cache_transcript" ] && [ -f "$cache_transcript" ]; then
        # Read only the last line — tail seeks from EOF, no full-file read
        cache_last_line=$(tail -n 1 "$cache_transcript" 2>/dev/null)
        if [ -n "$cache_last_line" ]; then
            cache_ts=$(printf '%s' "$cache_last_line" | jq -r '.timestamp // empty' 2>/dev/null)
            if [ -n "$cache_ts" ]; then
                # Parse ISO8601 to epoch (BSD/GNU dual pattern, strip fractional seconds).
                # UTC forms (Z / +00:00 / -00:00 / bare) normalize to Z for BSD date -j;
                # non-UTC offsets fall through to GNU date -d, which honors them.
                cache_clean_ts=$(printf '%s' "$cache_ts" | sed -E 's/\.[0-9]+//; s/[+-]00:00$/Z/; s/([0-9]{2}:[0-9]{2}:[0-9]{2})$/\1Z/')
                cache_epoch=$(TZ=UTC date -j -f "%Y-%m-%dT%H:%M:%SZ" "$cache_clean_ts" +%s 2>/dev/null \
                    || date -u -d "$cache_clean_ts" +%s 2>/dev/null)
                if [ -n "$cache_epoch" ]; then
                    cache_now=$(date +%s)
                    cache_ttl=300  # Anthropic prompt cache TTL = 300s
                    cache_remaining=$(( cache_ttl - (cache_now - cache_epoch) ))
                    if [ "$cache_remaining" -gt 0 ] 2>/dev/null; then
                        # Format remaining time
                        if [ "$cache_remaining" -ge 60 ] 2>/dev/null; then
                            cm=$(( cache_remaining / 60 ))
                            cs=$(( cache_remaining % 60 ))
                            cache_time="${cm}m${cs}s"
                        else
                            cache_time="${cache_remaining}s"
                        fi
                        # Color based on urgency
                        if [ "$cache_remaining" -gt 120 ] 2>/dev/null; then
                            cache_color="$GREEN"
                        elif [ "$cache_remaining" -gt 30 ] 2>/dev/null; then
                            cache_color="$YELLOW"
                        else
                            cache_color="$RED"
                        fi
                        cache_info="${cache_color}cache ${cache_time}${NC}"
                    else
                        cache_info="${GRAY}cache cold${NC}"
                    fi
                fi
            fi
        fi
    fi
fi

# --- Transcript-based live modules (tools, agents, todos) ---
# ONE tail + ONE jq invocation; gated on at least one module being enabled.
tools_info=""
agents_info=""
todos_info=""
if [ "$mod_tools" = true ] || [ "$mod_agents" = true ] || [ "$mod_todos" = true ]; then
    _transcript=$(echo "$input" | jq -r '.transcript_path // empty' 2>/dev/null)
    if [ -n "$_transcript" ] && [ -f "$_transcript" ]; then
        # -R + line-wise fromjson: a truncated trailing line (transcript mid-write)
        # is dropped instead of aborting the whole parse like slurped -s would.
        _tsv=$(tail -n 300 "$_transcript" 2>/dev/null | jq -Rrs '
          [split("\n")[] | select(length > 0) | try fromjson catch empty] as $lines
          | ([$lines[] | select(.type=="assistant") | .message.content[]? | select(.type=="tool_use")]) as $uses
          | ([$lines[] | select(.type=="user") | .message.content[]? | select(.type=="tool_result") | .tool_use_id]) as $done
          | ($uses | map(select(.id as $i | $done | index($i) | not))) as $pending
          | ($pending | map(select(.name != "Task"))) as $ptools
          | ($pending | map(select(.name == "Task"))) as $pagents
          | ([$lines[] | select(.type=="assistant") | .message.content[]? | select(.type=="tool_use" and .name=="TodoWrite")] | last) as $todo
          | [
              ($ptools | length | tostring), ($ptools | first | .name // ""),
              ($pagents | length | tostring), ($pagents | first | (.input.subagent_type // .input.description // "") | .[0:20]),
              (if $todo then ($todo.input.todos | map(select(.status=="completed")) | length | tostring) else "-1" end),
              (if $todo then ($todo.input.todos | length | tostring) else "0" end)
            ] | join("\u001f")' 2>/dev/null)
        if [ -n "$_tsv" ]; then
            IFS=$'\037' read -r _pt_count _pt_first _pa_count _pa_first _td_done _td_total <<< "$_tsv"
            # tools module
            if [ "$mod_tools" = true ]; then
                if [ "${_pt_count:-0}" -ge 1 ] 2>/dev/null; then
                    if [ "${_pt_count:-0}" -eq 1 ]; then
                        tools_info="${CYAN}⚒ ${_pt_first}${NC}"
                    else
                        _pt_others=$(( _pt_count - 1 ))
                        tools_info="${CYAN}⚒ ${_pt_first} +${_pt_others}${NC}"
                    fi
                fi
            fi
            # agents module
            if [ "$mod_agents" = true ]; then
                if [ "${_pa_count:-0}" -ge 1 ] 2>/dev/null; then
                    if [ "${_pa_count:-0}" -eq 1 ]; then
                        agents_info="${MAGENTA}◉ ${_pa_first}${NC}"
                    else
                        agents_info="${MAGENTA}◉ ${_pa_count} agents${NC}"
                    fi
                fi
            fi
            # todos module
            if [ "$mod_todos" = true ]; then
                if [ "${_td_done:-0}" -ge 0 ] 2>/dev/null && [ "${_td_total:-0}" -gt 0 ] 2>/dev/null; then
                    if [ "${_td_done}" -eq "${_td_total}" ] 2>/dev/null; then
                        todos_info="${GREEN}☑ ${_td_done}/${_td_total}${NC}"
                    else
                        todos_info="${CYAN}☑ ${_td_done}/${_td_total}${NC}"
                    fi
                fi
            fi
        fi
    fi
fi

# --- Compose output ---
# Each module produced a bare chunk (no leading separator). Route every enabled
# chunk to line 1 or line 2 depending on whether its module name appears in
# modules_line2, then join chunks on each line with " | ".
SEP=" ${GRAY}|${NC} "
line1=""
line2=""

is_line2() { case " $line2_set " in *" $1 "*) return 0 ;; *) return 1 ;; esac; }

route() {  # $1 = module name, $2 = bare chunk
    [ -z "$2" ] && return
    if is_line2 "$1"; then
        line2="${line2:+$line2$SEP}$2"
    else
        line1="${line1:+$line1$SEP}$2"
    fi
}

[ "$mod_directory" = true ] && route directory "${BLUE}${dir_name}${NC}"
[ "$mod_model" = true ]     && route model "${CYAN}${model_name}${NC}"
route context  "$context_info"
route usage    "$usage_info"
route rtk      "$rtk_info"
route mode     "$mode_info"
route git      "$git_info"
route lines    "$lines_info"
route codegraph "$cg_info"
route cost     "$cost_info"
route duration "$duration_info"
route speed    "$speed_info"
route vim      "$vim_info"
route agent    "$agent_info"
route pr       "$pr_info"
route weekly   "$weekly_info"
route pace     "$pace_info"
route cache    "$cache_info"
route tools    "$tools_info"
route agents   "$agents_info"
route todos    "$todos_info"

if [ -n "$line2" ]; then
    printf '%b\n%b\n' "$line1" "$line2"
else
    echo -e "$line1"
fi
