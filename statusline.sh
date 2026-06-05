#!/usr/bin/env bash

# Claude Code Statusline — Real-time usage, context, and git info
# https://github.com/educlopez/ccvitals

STATUSLINE_VERSION="1.10.1"

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

# --- Per-project config override ---
# If a .ccvitals.json file exists at the workspace root, object-merge it over
# the global config (jq '*': keys present in the project file win — note that
# ARRAYS like "modules" are replaced wholesale, not unioned). All config reads
# below use the effective_config variable.
# Security: project values are only ever consumed as jq output (data), never
# passed to eval or executed.
_ws_root=$(printf '%s' "$input" | jq -r '.workspace.project_dir // .workspace.current_dir // empty' 2>/dev/null)
_global_json=""
if [ -f "$statusline_config" ]; then
    _global_json=$(cat "$statusline_config" 2>/dev/null)
    if ! printf '%s' "$_global_json" | jq empty 2>/dev/null; then
        echo "ccvitals: invalid JSON in $statusline_config — using defaults" >&2
        _global_json=""
    fi
fi
_proj_json=""
if [ -n "$_ws_root" ] && [ -f "$_ws_root/.ccvitals.json" ]; then
    _proj_json=$(cat "$_ws_root/.ccvitals.json" 2>/dev/null)
    printf '%s' "$_proj_json" | jq empty 2>/dev/null || _proj_json=""
fi
if [ -n "$_global_json" ] && [ -n "$_proj_json" ]; then
    effective_config=$(printf '%s\n%s' "$_global_json" "$_proj_json" | jq -s '.[0] * .[1]' 2>/dev/null)
elif [ -n "$_proj_json" ]; then
    # Project-only config works even without a global one
    effective_config="$_proj_json"
else
    effective_config="$_global_json"
fi
unset _ws_root _global_json _proj_json

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
mod_daily=false
mod_compactions=false
mod_tokens=false
mod_thinking=false
mod_mcp=false
mod_spend=false
mod_workflows=false

# Modules listed under "modules_line2" render on a second row (space-delimited
# set checked during composition). Empty = everything on one line.
line2_set=""

if [ -n "$effective_config" ]; then
    modules=$(printf '%s' "$effective_config" | jq -r '.modules[]?' 2>/dev/null)
    modules2=$(printf '%s' "$effective_config" | jq -r '.modules_line2[]?' 2>/dev/null)
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
                daily)     mod_daily=true ;;
                compactions) mod_compactions=true ;;
                tokens)    mod_tokens=true ;;
                thinking)   mod_thinking=true ;;
                mcp)        mod_mcp=true ;;
                spend)      mod_spend=true ;;
                workflows)  mod_workflows=true ;;
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
if [ -n "$effective_config" ]; then
    _theme=$(printf '%s' "$effective_config" | jq -r '.theme // empty' 2>/dev/null)
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
            _c_red=$(printf '%s' "$effective_config" | jq -r '.colors.red // empty' 2>/dev/null)
            _c_green=$(printf '%s' "$effective_config" | jq -r '.colors.green // empty' 2>/dev/null)
            _c_blue=$(printf '%s' "$effective_config" | jq -r '.colors.blue // empty' 2>/dev/null)
            _c_yellow=$(printf '%s' "$effective_config" | jq -r '.colors.yellow // empty' 2>/dev/null)
            _c_cyan=$(printf '%s' "$effective_config" | jq -r '.colors.cyan // empty' 2>/dev/null)
            _c_gray=$(printf '%s' "$effective_config" | jq -r '.colors.gray // empty' 2>/dev/null)
            _c_magenta=$(printf '%s' "$effective_config" | jq -r '.colors.magenta // empty' 2>/dev/null)
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

# --- Icon set resolution ---
# Resolve all icon glyphs into variables. Default = unicode (byte-identical to existing).
# ascii: plain ASCII fallback for terminals without unicode support.
# nerd: Nerd Font icons for richer display.
ICON_TOOLS="⚒"
ICON_AGENTS="◉"
ICON_TODOS="☑"
ICON_ETA="⌛"
ICON_TOKENS="⇅"
ICON_COMPACTIONS="↯"
ICON_MODE_FAST="⚡"
ICON_WARN="⚠"
ICON_BAR_FILL="█"
ICON_BAR_EMPTY="░"
ICON_AHEAD="↑"
ICON_BEHIND="↓"
ICON_THINKING="✦"
ICON_MCP="⬡"
ICON_WORKFLOWS="⟳"

if [ -n "$effective_config" ]; then
    _icons=$(printf '%s' "$effective_config" | jq -r '.icons // empty' 2>/dev/null)
    case "$_icons" in
        ascii)
            ICON_TOOLS="T:"
            ICON_AGENTS="A:"
            ICON_TODOS="[x]"
            ICON_ETA="eta"
            ICON_TOKENS="io"
            ICON_COMPACTIONS="cmp"
            ICON_MODE_FAST="!"
            ICON_WARN="(!)"
            ICON_BAR_FILL="#"
            ICON_BAR_EMPTY="-"
            ICON_AHEAD="+"
            ICON_BEHIND="-"
            ICON_THINKING="*"
            ICON_MCP="[mcp]"
            ICON_WORKFLOWS="wf:"
            ;;
        nerd)
            ICON_TOOLS=$''   # wrench
            ICON_AGENTS=$''  # robot
            ICON_TODOS=$''   # check
            ICON_ETA=$''     # clock
            ICON_TOKENS=$''  # exchange
            ICON_COMPACTIONS=$''  # history
            ICON_MODE_FAST=$''    # lightning
            ICON_WARN=$''    # warning triangle
            ICON_BAR_FILL="█"
            ICON_BAR_EMPTY="░"
            ICON_AHEAD=$''   # arrow up
            ICON_BEHIND=$''  # arrow down
            ICON_THINKING=$''  # sparkle/lightning fallback
            ICON_MCP=$''  # hexagon
            ICON_WORKFLOWS=$''  # refresh/sync
            ;;
        unicode|'')
            # Keep defaults above
            ;;
    esac
    unset _icons
fi

# --- Smart visibility config ---
# When smart=true, modules only appear when their value is notable (see below).
# Default: false — behavior identical to before this feature.
smart_mode=false
if [ -n "$effective_config" ]; then
    _sm=$(printf '%s' "$effective_config" | jq -r '.smart // false' 2>/dev/null)
    [ "$_sm" = "true" ] && smart_mode=true
    unset _sm
fi

# --- Responsive width config ---
# When responsive=true and COLUMNS is numeric, line1 is trimmed to fit.
# Only applies to non-powerline mode; powerline is skipped silently.
responsive_mode=false
if [ -n "$effective_config" ]; then
    _rsp=$(printf '%s' "$effective_config" | jq -r '.responsive // false' 2>/dev/null)
    [ "$_rsp" = "true" ] && responsive_mode=true
    unset _rsp
fi

# --- Powerline rendering ---
# Read powerline flag and optional separator glyph from config.
# All powerline variables default to empty so the non-powerline path is
# completely unaffected when the feature is absent/disabled.
PL_ON=false
PL_SEP=$'\xee\x82\xb0'  # default Nerd Font glyph U+E0B0 (UTF-8: ee 82 b0)
PL_BG_A=''         # background escape for even-indexed segments
PL_BG_B=''         # background escape for odd-indexed segments
PL_FG_A=''         # fg version of BG_A (for the separator glyph itself)
PL_FG_B=''         # fg version of BG_B

if [ -n "$effective_config" ]; then
    _pl=$(printf '%s' "$effective_config" | jq -r '.powerline // false' 2>/dev/null)
    if [ "$_pl" = "true" ]; then
        PL_ON=true
        # Optional separator override
        _pl_sep=$(printf '%s' "$effective_config" | jq -r '.powerline_separator // empty' 2>/dev/null)
        [ -n "$_pl_sep" ] && PL_SEP="$_pl_sep"
        # Determine per-theme background shades
        _pl_theme=$(printf '%s' "$effective_config" | jq -r '.theme // "default"' 2>/dev/null)
        case "$_pl_theme" in
            pastel)
                PL_BG_A='\033[48;2;58;61;69m'
                PL_FG_A='\033[38;2;58;61;69m'
                PL_BG_B='\033[48;2;74;77;87m'
                PL_FG_B='\033[38;2;74;77;87m'
                ;;
            tokyo-night)
                PL_BG_A='\033[48;2;31;35;53m'
                PL_FG_A='\033[38;2;31;35;53m'
                PL_BG_B='\033[48;2;41;46;66m'
                PL_FG_B='\033[38;2;41;46;66m'
                ;;
            catppuccin)
                PL_BG_A='\033[48;2;49;50;68m'
                PL_FG_A='\033[38;2;49;50;68m'
                PL_BG_B='\033[48;2;69;71;90m'
                PL_FG_B='\033[38;2;69;71;90m'
                ;;
            dracula)
                PL_BG_A='\033[48;2;68;71;90m'
                PL_FG_A='\033[38;2;68;71;90m'
                PL_BG_B='\033[48;2;54;57;73m'
                PL_FG_B='\033[38;2;54;57;73m'
                ;;
            nord)
                PL_BG_A='\033[48;2;59;66;82m'
                PL_FG_A='\033[38;2;59;66;82m'
                PL_BG_B='\033[48;2;67;76;94m'
                PL_FG_B='\033[38;2;67;76;94m'
                ;;
            mono|default|'')
                PL_BG_A='\033[48;5;236m'
                PL_FG_A='\033[38;5;236m'
                PL_BG_B='\033[48;5;238m'
                PL_FG_B='\033[38;5;238m'
                ;;
            *)
                # custom or unknown: fall back to 256-color grays
                PL_BG_A='\033[48;5;236m'
                PL_FG_A='\033[38;5;236m'
                PL_BG_B='\033[48;5;238m'
                PL_FG_B='\033[38;5;238m'
                ;;
        esac
    fi
    unset _pl _pl_sep _pl_theme
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
    for ((i=0; i<filled; i++)); do bar+="${ICON_BAR_FILL}"; done
    for ((i=0; i<empty; i++)); do bar+="${ICON_BAR_EMPTY}"; done

    # Context-pressure alert based on how full the window is — consistent across the
    # 200k and 1M tiers (an absolute token threshold would false-alarm on 1M sessions).
    ctx_color="$NC"
    ctx_warn=""
    if [ "${context_percent:-0}" -ge 90 ] 2>/dev/null; then
        ctx_color="$RED"
        ctx_warn=" ${RED}${ICON_WARN}${NC}"
    fi

    # context_display: "percent" (default), "tokens", or "both"
    ctx_display=""
    if [ -n "$effective_config" ]; then
        ctx_display=$(printf '%s' "$effective_config" | jq -r '.context_display // empty' 2>/dev/null)
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
        for ((i=0; i<u_filled; i++)); do u_bar+="${ICON_BAR_FILL}"; done
        for ((i=0; i<u_empty; i++)); do u_bar+="${ICON_BAR_EMPTY}"; done

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
                *[!0-9]*)
                    # ISO date string (starts with a digit too — match on ANY
                    # non-digit instead, so "2026-06-04T…" lands here)
                    local clean_date
                    clean_date=$(echo "$reset_at" | sed -E 's/\.[0-9]+//; s/\+00:00$/Z/')
                    reset_epoch=$(TZ=UTC date -j -f "%Y-%m-%dT%H:%M:%SZ" "$clean_date" +%s 2>/dev/null \
                        || date -u -d "$clean_date" +%s 2>/dev/null)
                    ;;
                *)
                    # Pure digits — unix epoch
                    reset_epoch="$reset_at"
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
        # Apply session_budget coloring if configured
        _cb_budget=""
        if [ -n "$effective_config" ]; then
            _cb_budget=$(printf '%s' "$effective_config" | jq -r '.session_budget // empty' 2>/dev/null)
        fi
        if [ -n "$_cb_budget" ] && [ "$(printf '%s' "$_cb_budget" | awk '{print ($1+0>0)?1:0}')" = "1" ]; then
            _cb_pct=$(printf '%s %s' "$cost_val" "$_cb_budget" | awk '{v=$1/$2*100; printf "%.0f", v}' 2>/dev/null)
            _cb_bfmt=$(printf '%s' "$_cb_budget" | awk '{
                v = $1 + 0
                if (v < 10) { printf "$%.2f", v }
                else if (v < 100) { printf "$%.1f", v }
                else { printf "$%.0f", v }
            }')
            if [ "${_cb_pct:-0}" -ge 80 ] 2>/dev/null; then
                cost_info="${RED}${cost_fmt}/${_cb_bfmt}${NC}"
            elif [ "${_cb_pct:-0}" -ge 50 ] 2>/dev/null; then
                cost_info="${YELLOW}${cost_fmt}/${_cb_bfmt}${NC}"
            else
                cost_info="${GRAY}${cost_fmt}/${_cb_bfmt}${NC}"
            fi
            unset _cb_pct _cb_bfmt
        else
            cost_info="${GRAY}${cost_fmt}${NC}"
        fi
        unset _cb_budget
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
            pr_text="\033]8;;${pr_url}\007${CYAN}PR #${pr_num}${NC}\033]8;;\007"
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
        for ((i=0; i<w_filled; i++)); do w_bar+="${ICON_BAR_FILL}"; done
        for ((i=0; i<w_empty; i++)); do w_bar+="${ICON_BAR_EMPTY}"; done
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
        # weekly_split mode: show per-model breakdown when available from OAuth cache
        w_split_mode=false
        if [ -n "$effective_config" ]; then
            _ws=$(printf '%s' "$effective_config" | jq -r '.weekly_split // false' 2>/dev/null)
            [ "$_ws" = "true" ] && w_split_mode=true
            unset _ws
        fi
        if [ "$w_split_mode" = true ]; then
            w_cache_file="${config_dir}/.usage-cache/usage.json"
            w_opus=""
            w_sonnet=""
            if [ -f "$w_cache_file" ]; then
                w_opus_raw=$(jq -r '.data.seven_day_opus.utilization // empty' "$w_cache_file" 2>/dev/null)
                w_sonnet_raw=$(jq -r '.data.seven_day_sonnet.utilization // empty' "$w_cache_file" 2>/dev/null)
                if [ -n "$w_opus_raw" ] || [ -n "$w_sonnet_raw" ]; then
                    [ -n "$w_opus_raw" ]   && w_opus=$(printf '%.0f' "$w_opus_raw")
                    [ -n "$w_sonnet_raw" ] && w_sonnet=$(printf '%.0f' "$w_sonnet_raw")
                fi
            fi
            if [ -n "$w_opus" ] || [ -n "$w_sonnet" ]; then
                # Color per-model values using same thresholds
                _wc_opus="$CYAN"
                [ "${w_opus:-0}" -ge 50 ] 2>/dev/null && _wc_opus="$YELLOW"
                [ "${w_opus:-0}" -ge 75 ] 2>/dev/null && _wc_opus="$MAGENTA"
                [ "${w_opus:-0}" -ge 90 ] 2>/dev/null && _wc_opus="$RED"
                _wc_sonnet="$CYAN"
                [ "${w_sonnet:-0}" -ge 50 ] 2>/dev/null && _wc_sonnet="$YELLOW"
                [ "${w_sonnet:-0}" -ge 75 ] 2>/dev/null && _wc_sonnet="$MAGENTA"
                [ "${w_sonnet:-0}" -ge 90 ] 2>/dev/null && _wc_sonnet="$RED"
                w_split_str=""
                [ -n "$w_opus" ]   && w_split_str="${_wc_opus}O:${w_opus}%${NC}"
                if [ -n "$w_sonnet" ]; then
                    w_split_str="${w_split_str:+$w_split_str }${_wc_sonnet}S:${w_sonnet}%${NC}"
                fi
                weekly_info="${GRAY}7d${NC} ${w_split_str}${w_reset_str}"
            else
                weekly_info="${GRAY}7d:${NC} ${w_color}${w_bar}${NC} ${w_color}${weekly_pct}%${NC}${w_reset_str}"
            fi
        else
            weekly_info="${GRAY}7d:${NC} ${w_color}${w_bar}${NC} ${w_color}${weekly_pct}%${NC}${w_reset_str}"
        fi
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
    [ "$m_fast" = "true" ] && m_parts="${ICON_MODE_FAST}"
    [ -n "$m_effort" ] && m_parts="${m_parts}${m_parts:+ }${m_effort}"
    [ -n "$m_parts" ] && mode_info="${MAGENTA}${m_parts}${NC}"
fi

# --- Thinking module (effort level only, complementary to mode module) ---
# Shows reasoning effort level with an icon. Hidden when field absent.
# Color: accent (MAGENTA) for high, CYAN for xhigh, GRAY for low/medium.
# NOTE: mode module also reads .effort.level — thinking shows effort alone
# (no fast-mode flag) so the two can coexist or be used independently.
thinking_info=""
if [ "$mod_thinking" = true ]; then
    th_effort=$(echo "$input" | jq -r '.effort.level // .thinking_effort // empty')
    if [ -n "$th_effort" ]; then
        case "$th_effort" in
            xhigh|xlarge) th_color="$CYAN" ;;
            high|large)   th_color="$MAGENTA" ;;
            *)            th_color="$GRAY" ;;
        esac
        thinking_info="${th_color}${ICON_THINKING} ${th_effort}${NC}"
    fi
fi

# --- MCP server count module ---
# Parses configured MCP server counts from:
#   1. .mcp.json in the workspace root (project-local servers)
#   2. ~/.claude.json mcpServers key (user-global servers)
#   3. ~/.claude/settings.json mcpServers key (settings-global servers)
# Uses mtime-based file caching so every render is a single stat + cat;
# only re-parses when any source file changes.
# Health checking via "claude mcp list" is too slow for the render path —
# count-only display is used. Document this limitation.
mcp_info=""
if [ "$mod_mcp" = true ]; then
    _mcp_cache_dir="$config_dir/.tool-cache"
    _mcp_cache_file="$_mcp_cache_dir/mcp-count.txt"
    _mcp_cache_mtime_file="$_mcp_cache_dir/mcp-count-mtime.txt"

    _mcp_ws=$(printf '%s' "$input" | jq -r '.workspace.project_dir // .workspace.current_dir // empty' 2>/dev/null)

    _mcp_proj_file=""
    if [ -n "$_mcp_ws" ] && [ -f "$_mcp_ws/.mcp.json" ]; then
        _mcp_proj_file="$_mcp_ws/.mcp.json"
    fi
    _mcp_global_json="$HOME/.claude.json"
    _mcp_settings_json="$config_dir/settings.json"

    # Fingerprint: concatenated mtime of every present source file.
    # stat -f %m = BSD (macOS); stat -c %Y = GNU/Linux.
    _mcp_fingerprint=""
    for _mcp_src in "$_mcp_proj_file" "$_mcp_global_json" "$_mcp_settings_json"; do
        [ -z "$_mcp_src" ] && continue
        [ -f "$_mcp_src" ] || continue
        _mcp_mtime=$(stat -f %m "$_mcp_src" 2>/dev/null || stat -c %Y "$_mcp_src" 2>/dev/null || echo 0)
        _mcp_fingerprint="${_mcp_fingerprint}:${_mcp_src}@${_mcp_mtime}"
    done

    _mcp_cached_fp=""
    _mcp_cached_count=""
    if [ -f "$_mcp_cache_mtime_file" ] && [ -f "$_mcp_cache_file" ]; then
        _mcp_cached_fp=$(cat "$_mcp_cache_mtime_file" 2>/dev/null)
        _mcp_cached_count=$(cat "$_mcp_cache_file" 2>/dev/null)
    fi

    if [ "$_mcp_cached_fp" = "$_mcp_fingerprint" ] && [ -n "$_mcp_cached_count" ]; then
        _mcp_total="$_mcp_cached_count"
    else
        _mcp_total=0

        # Project .mcp.json: supports both flat {name: config} and {mcpServers: {…}}
        if [ -n "$_mcp_proj_file" ]; then
            _mcp_n=$(jq -r 'if type == "object" then (if has("mcpServers") then (.mcpServers | keys | length) else (keys | length) end) else 0 end' "$_mcp_proj_file" 2>/dev/null || echo 0)
            _mcp_total=$(( _mcp_total + ${_mcp_n:-0} ))
        fi

        # ~/.claude.json: .mcpServers object
        if [ -f "$_mcp_global_json" ]; then
            _mcp_n=$(jq -r '(.mcpServers // {}) | keys | length' "$_mcp_global_json" 2>/dev/null || echo 0)
            _mcp_total=$(( _mcp_total + ${_mcp_n:-0} ))
        fi

        # ~/.claude/settings.json: .mcpServers object
        if [ -f "$_mcp_settings_json" ]; then
            _mcp_n=$(jq -r '(.mcpServers // {}) | keys | length' "$_mcp_settings_json" 2>/dev/null || echo 0)
            _mcp_total=$(( _mcp_total + ${_mcp_n:-0} ))
        fi

        mkdir -p "$_mcp_cache_dir"
        printf '%s
' "$_mcp_total" > "${_mcp_cache_file}.tmp"             && mv "${_mcp_cache_file}.tmp" "$_mcp_cache_file" 2>/dev/null
        printf '%s
' "$_mcp_fingerprint" > "${_mcp_cache_mtime_file}.tmp"             && mv "${_mcp_cache_mtime_file}.tmp" "$_mcp_cache_mtime_file" 2>/dev/null
    fi

    if [ "${_mcp_total:-0}" -gt 0 ] 2>/dev/null; then
        mcp_info="${CYAN}${ICON_MCP} ${_mcp_total}${NC}"
    fi

    unset _mcp_cache_dir _mcp_cache_file _mcp_cache_mtime_file
    unset _mcp_ws _mcp_proj_file _mcp_global_json _mcp_settings_json
    unset _mcp_fingerprint _mcp_src _mcp_mtime _mcp_cached_fp _mcp_cached_count
    unset _mcp_total _mcp_n
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
                    branch_text="\033]8;;https://${_host}/${_path}/tree/${branch}\007${YELLOW}${branch}${NC}\033]8;;\007"
                    ;;
                https://github.com/*|https://gitlab.com/*)
                    _url=$(printf '%s' "$origin_url" | sed 's/\.git$//')
                    branch_text="\033]8;;${_url}/tree/${branch}\007${YELLOW}${branch}${NC}\033]8;;\007"
                    ;;
            esac
        fi

        # Read sub-options from config (all default off)
        _git_op=false; _git_split=false; _git_sha=false
        _git_stash=false; _git_age=false
        if [ -n "$effective_config" ]; then
            _v=$(printf '%s' "$effective_config" | jq -r '.git_operation // false' 2>/dev/null)
            [ "$_v" = "true" ] && _git_op=true
            _v=$(printf '%s' "$effective_config" | jq -r '.git_status_split // false' 2>/dev/null)
            [ "$_v" = "true" ] && _git_split=true
            _v=$(printf '%s' "$effective_config" | jq -r '.git_sha // false' 2>/dev/null)
            [ "$_v" = "true" ] && _git_sha=true
            _v=$(printf '%s' "$effective_config" | jq -r '.git_stash // false' 2>/dev/null)
            [ "$_v" = "true" ] && _git_stash=true
            _v=$(printf '%s' "$effective_config" | jq -r '.git_age // false' 2>/dev/null)
            [ "$_v" = "true" ] && _git_age=true
            unset _v
        fi

        # git_operation: detect in-progress merge/rebase/cherry-pick/bisect
        _git_op_label=""
        if [ "$_git_op" = true ]; then
            _gd=$(git rev-parse --git-dir 2>/dev/null)
            if [ -n "$_gd" ]; then
                if [ -f "$_gd/MERGE_HEAD" ]; then
                    _git_op_label="MERGE"
                elif [ -d "$_gd/rebase-merge" ] || [ -d "$_gd/rebase-apply" ]; then
                    _git_op_label="REBASE"
                elif [ -f "$_gd/CHERRY_PICK_HEAD" ]; then
                    _git_op_label="CHERRY-PICK"
                elif [ -f "$_gd/BISECT_LOG" ]; then
                    _git_op_label="BISECT"
                fi
            fi
            unset _gd
        fi

        # Single git status --porcelain pass (reused for split counts)
        status_output=$(git status --porcelain 2>/dev/null)

        # git_status_split: count staged / unstaged / untracked separately
        # porcelain v1 format: XY filename
        #   X = index (staged) status, Y = worktree (unstaged) status
        #   '?' = untracked, '!' = ignored (we skip ignored)
        _staged=0; _unstaged=0; _untracked=0
        if [ "$_git_split" = true ] && [ -n "$status_output" ]; then
            while IFS= read -r _sl; do
                _xy="${_sl:0:2}"
                _x="${_xy:0:1}"
                _y="${_xy:1:1}"
                case "$_x" in
                    '?') _untracked=$(( _untracked + 1 )) ;;
                    ' ') ;;  # only worktree change
                    *)   _staged=$(( _staged + 1 )) ;;
                esac
                case "$_y" in
                    '?') ;;  # counted in x pass above
                    ' ') ;;
                    *)   [ "$_x" != '?' ] && _unstaged=$(( _unstaged + 1 )) ;;
                esac
            done <<EOF_STATUS
$status_output
EOF_STATUS
        fi

        if [ -n "$status_output" ]; then
            total_files=$(echo "$status_output" | wc -l | xargs)
            line_stats=$(git diff --numstat HEAD 2>/dev/null | awk '{added+=$1; removed+=$2} END {print added+0, removed+0}')
            added=$(echo "$line_stats" | cut -d' ' -f1)
            removed=$(echo "$line_stats" | cut -d' ' -f2)

            if [ "$_git_split" = true ]; then
                # Split display: +staged ~unstaged ?untracked instead of N files
                _split_str=""
                [ "$_staged" -gt 0 ]   && _split_str="${_split_str}${_split_str:+ }${GREEN}+${_staged}${NC}"
                [ "$_unstaged" -gt 0 ] && _split_str="${_split_str}${_split_str:+ }${YELLOW}~${_unstaged}${NC}"
                [ "$_untracked" -gt 0 ] && _split_str="${_split_str}${_split_str:+ }${GRAY}?${_untracked}${NC}"
                git_info="${YELLOW}(${NC}${branch_text} ${YELLOW}|${NC} ${_split_str:-${GRAY}clean${NC}}"
            else
                git_info="${YELLOW}(${NC}${branch_text} ${YELLOW}|${NC} ${GRAY}${total_files} files${NC}"
                [ "$added" -gt 0 ] && git_info="${git_info} ${GREEN}+${added}${NC}"
                [ "$removed" -gt 0 ] && git_info="${git_info} ${RED}-${removed}${NC}"
            fi
        else
            git_info="${YELLOW}(${NC}${branch_text}"
        fi

        # Append ahead/behind after branch (before closing paren)
        if [ -n "$ab_ahead" ]; then
            git_info="${git_info} ${GREEN}${ICON_AHEAD}${ab_ahead}${NC}"
        fi
        if [ -n "$ab_behind" ]; then
            git_info="${git_info} ${YELLOW}${ICON_BEHIND}${ab_behind}${NC}"
        fi

        # git_sha: short commit SHA
        if [ "$_git_sha" = true ]; then
            _sha=$(git rev-parse --short HEAD 2>/dev/null)
            [ -n "$_sha" ] && git_info="${git_info} ${GRAY}${_sha}${NC}"
            unset _sha
        fi

        # git_stash: stash count (only when >0)
        if [ "$_git_stash" = true ]; then
            _stash_n=$(git stash list 2>/dev/null | wc -l | xargs)
            if [ "${_stash_n:-0}" -gt 0 ] 2>/dev/null; then
                git_info="${git_info} ${GRAY}≡${_stash_n}${NC}"
            fi
            unset _stash_n
        fi

        # git_age: time since last commit, compact (2h, 3d, 4w, etc.)
        if [ "$_git_age" = true ]; then
            _commit_ts=$(git log -1 --format=%ct 2>/dev/null)
            if [ -n "$_commit_ts" ]; then
                _now=$(date +%s)
                _age_s=$(( _now - _commit_ts ))
                if [ "$_age_s" -lt 3600 ]; then
                    _age_str="${GRAY}$(( _age_s / 60 ))m${NC}"
                elif [ "$_age_s" -lt 86400 ]; then
                    _age_str="${GRAY}$(( _age_s / 3600 ))h${NC}"
                elif [ "$_age_s" -lt 604800 ]; then
                    _age_str="${GRAY}$(( _age_s / 86400 ))d${NC}"
                else
                    _age_str="${GRAY}$(( _age_s / 604800 ))w${NC}"
                fi
                git_info="${git_info} ${_age_str}"
            fi
            unset _commit_ts _now _age_s _age_str
        fi

        git_info="${git_info}${YELLOW})${NC}"

        # Prepend git_operation banner when active (outside the parens, before the segment)
        if [ -n "$_git_op_label" ]; then
            git_info="${RED}${_git_op_label}${NC} ${git_info}"
        fi

        unset _git_op _git_split _git_sha _git_stash _git_age
        unset _git_op_label _staged _unstaged _untracked _split_str _sl _xy _x _y
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
                # Round used_pct to integer
                pace_used_int=$(printf '%.0f' "$pace_used")

                # Read pace_display config key
                pace_display_mode="delta"
                if [ -n "$effective_config" ]; then
                    _pd=$(printf '%s' "$effective_config" | jq -r '.pace_display // empty' 2>/dev/null)
                    [ -n "$_pd" ] && pace_display_mode="$_pd"
                    unset _pd
                fi

                if [ "$pace_display_mode" = "eta" ]; then
                    # ETA mode: estimate when quota exhausts
                    # burn rate = used_pct per second (integer * 1000 for precision)
                    if [ "$pace_elapsed" -gt 0 ] 2>/dev/null && [ "$pace_used_int" -gt 0 ] 2>/dev/null && [ "$pace_used_int" -lt 100 ] 2>/dev/null; then
                        # rate_milli = used_int * 1000 / elapsed_s  (milli-percent per second)
                        rate_milli=$(( pace_used_int * 1000 / pace_elapsed ))
                        if [ "$rate_milli" -eq 0 ]; then
                            # Burn rate too slow for integer precision — by definition the
                            # quota outlasts the window. Show safe instead of hiding.
                            pace_info="${GREEN}${ICON_ETA} ok${NC}"
                        fi
                        if [ "$rate_milli" -gt 0 ] 2>/dev/null; then
                            # exhaust_s = (100 - used_int) * 1000 / rate_milli
                            pace_exhaust_s=$(( (100 - pace_used_int) * 1000 / rate_milli ))
                            pace_eta_epoch=$(( pace_now + pace_exhaust_s ))
                            if [ "$pace_eta_epoch" -lt "$pace_resets" ] 2>/dev/null; then
                                # Quota dies before reset — show time
                                pace_eta_str=$(date -r "$pace_eta_epoch" +%H:%M 2>/dev/null \
                                    || date -d "@${pace_eta_epoch}" +%H:%M 2>/dev/null)
                                if [ -n "$pace_eta_str" ]; then
                                    pace_until_exhaust=$(( pace_eta_epoch - pace_now ))
                                    if [ "$pace_until_exhaust" -le 3600 ] 2>/dev/null; then
                                        pace_info="${RED}${ICON_ETA} ~${pace_eta_str}${NC}"
                                    else
                                        pace_info="${YELLOW}${ICON_ETA} ~${pace_eta_str}${NC}"
                                    fi
                                fi
                            else
                                # Safe — will not exhaust before reset
                                pace_info="${GREEN}${ICON_ETA} ok${NC}"
                            fi
                        fi
                    fi
                    # If rate is 0 or used is 0 or 100 — hide (same as delta mode hide conditions)
                else
                    # Delta mode (default)
                    # Integer math: elapsed * 100 / window
                    pace_expected=$(( pace_elapsed * 100 / pace_window ))
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

# --- Transcript-based live modules (tools, agents, todos, workflows) ---
# ONE tail + ONE jq invocation; gated on at least one module being enabled.
#
# Feature: skill names — when tools_skill_names is true (default), a pending
# Skill tool invocation renders its .input.skill name instead of "Skill".
# MCP tool names (mcp__server__tool) are compacted to "server:tool".
#
# Feature: workflows module — detects pending Workflow tool_use entries
# (tool_use named "Workflow" with no matching tool_result yet) and shows
# "⟳ N wf" when running, hidden when none pending.
tools_info=""
agents_info=""
todos_info=""
workflows_info=""

# Read tools_skill_names config option (default: true)
_tools_skill_names=true
if [ -n "$effective_config" ]; then
    _tsn=$(printf '%s' "$effective_config" | jq -r 'if (.tools_skill_names == false or ((.tools_skill_names | type) == "string" and .tools_skill_names == "false")) then "false" else "true" end' 2>/dev/null)
    [ "$_tsn" = "false" ] && _tools_skill_names=false
    unset _tsn
fi

if [ "$mod_tools" = true ] || [ "$mod_agents" = true ] || [ "$mod_todos" = true ] || [ "$mod_workflows" = true ]; then
    _transcript=$(echo "$input" | jq -r '.transcript_path // empty' 2>/dev/null)
    if [ -n "$_transcript" ] && [ -f "$_transcript" ]; then
        # -R + line-wise fromjson: a truncated trailing line (transcript mid-write)
        # is dropped instead of aborting the whole parse like slurped -s would.
        _tsv=$(tail -n 300 "$_transcript" 2>/dev/null | jq -Rrs '
          [split("\n")[] | select(length > 0) | try fromjson catch empty] as $lines
          | ([$lines[] | select(.type=="assistant") | .message.content[]? | select(.type=="tool_use")]) as $uses
          | ([$lines[] | select(.type=="user") | .message.content[]? | select(.type=="tool_result") | .tool_use_id]) as $done
          | ($uses | map(select(.id as $i | $done | index($i) | not))) as $pending
          | ($pending | map(select(.name != "Task" and .name != "Workflow"))) as $ptools
          | ($pending | map(select(.name == "Task"))) as $pagents
          | ($pending | map(select(.name == "Workflow"))) as $pworkflows
          | ([$lines[] | select(.type=="assistant") | .message.content[]? | select(.type=="tool_use" and .name=="TodoWrite")] | last) as $todo
          | ($ptools | first | (
              if .name == "Skill" then (.input.skill // "Skill")
              else
                (.name // "") |
                if test("^mcp__") then
                  (split("__") | if length >= 3 then .[1] + ":" + .[2] else .[1] end)
                else . end
              end
            )) as $pt_first_label
          | [
              ($ptools | length | tostring), ($pt_first_label // ""),
              ($ptools | first | if .name == "Skill" then "skill" else "tool" end),
              ($ptools | first | .name // ""),
              ($pagents | length | tostring), ($pagents | first | (.input.subagent_type // .input.description // "") | .[0:20]),
              (if $todo then ($todo.input.todos | map(select(.status=="completed")) | length | tostring) else "-1" end),
              (if $todo then ($todo.input.todos | length | tostring) else "0" end),
              ($pworkflows | length | tostring)
            ] | join("")' 2>/dev/null)
        if [ -n "$_tsv" ]; then
            IFS=$'\037' read -r _pt_count _pt_first _pt_kind _pt_raw _pa_count _pa_first _td_done _td_total _pw_count <<< "$_tsv"
            # tools module
            if [ "$mod_tools" = true ]; then
                if [ "${_pt_count:-0}" -ge 1 ] 2>/dev/null; then
                    # Skill invocations: use skill name (YELLOW) when tools_skill_names=true,
                    # or fall back to the raw tool name "Skill" (CYAN) when disabled.
                    # Regular tools (including compacted MCP names) always use CYAN.
                    if [ "${_pt_kind:-tool}" = "skill" ]; then
                        if [ "$_tools_skill_names" = true ]; then
                            _pt_label="$_pt_first"
                            _pt_color="$YELLOW"
                        else
                            _pt_label="${_pt_raw:-Skill}"
                            _pt_color="$CYAN"
                        fi
                    else
                        _pt_label="$_pt_first"
                        _pt_color="$CYAN"
                    fi
                    if [ "${_pt_count:-0}" -eq 1 ]; then
                        tools_info="${_pt_color}${ICON_TOOLS} ${_pt_label}${NC}"
                    else
                        _pt_others=$(( _pt_count - 1 ))
                        tools_info="${_pt_color}${ICON_TOOLS} ${_pt_label} +${_pt_others}${NC}"
                    fi
                    unset _pt_color _pt_label
                fi
            fi
            # agents module
            if [ "$mod_agents" = true ]; then
                if [ "${_pa_count:-0}" -ge 1 ] 2>/dev/null; then
                    if [ "${_pa_count:-0}" -eq 1 ]; then
                        agents_info="${MAGENTA}${ICON_AGENTS} ${_pa_first}${NC}"
                    else
                        agents_info="${MAGENTA}${ICON_AGENTS} ${_pa_count} agents${NC}"
                    fi
                fi
            fi
            # todos module
            if [ "$mod_todos" = true ]; then
                if [ "${_td_done:-0}" -ge 0 ] 2>/dev/null && [ "${_td_total:-0}" -gt 0 ] 2>/dev/null; then
                    if [ "${_td_done}" -eq "${_td_total}" ] 2>/dev/null; then
                        todos_info="${GREEN}${ICON_TODOS} ${_td_done}/${_td_total}${NC}"
                    else
                        todos_info="${CYAN}${ICON_TODOS} ${_td_done}/${_td_total}${NC}"
                    fi
                fi
            fi
            # workflows module
            if [ "$mod_workflows" = true ]; then
                if [ "${_pw_count:-0}" -ge 1 ] 2>/dev/null; then
                    workflows_info="${CYAN}${ICON_WORKFLOWS} ${_pw_count} wf${NC}"
                fi
            fi
        fi
    fi
fi

# --- Daily budget module (cross-session spend today, opt-in) ---
daily_info=""
if [ "$mod_daily" = true ]; then
    _d_session=$(echo "$input" | jq -r '.session_id // empty' 2>/dev/null)
    _d_cost=$(echo "$input" | jq -r '.cost.total_cost_usd // empty' 2>/dev/null)
    if [ -n "$_d_session" ] && [ -n "$_d_cost" ]; then
        _d_dir="$config_dir/.ccvitals-daily"
        _d_today=$(date +%Y-%m-%d)
        _d_file="$_d_dir/${_d_today}.json"
        mkdir -p "$_d_dir"
        # Clean up day-files older than 7 days (guarded: only when dir exists)
        find "$_d_dir" -maxdepth 1 -name '*.json' -mtime +6 -delete 2>/dev/null || true
        # Read-modify-write: upsert this session's cost
        _d_existing="{}"
        [ -f "$_d_file" ] && _d_existing=$(cat "$_d_file" 2>/dev/null || echo '{}')
        # Sanitize session id for use as JSON key
        _d_safe_id=$(printf '%s' "$_d_session" | tr -dc 'a-zA-Z0-9_-' | cut -c1-60)
        _d_updated=$(printf '%s' "$_d_existing" | jq --arg sid "$_d_safe_id" --argjson cost "$_d_cost" \
            '.[$sid] = $cost' 2>/dev/null)
        if [ -n "$_d_updated" ]; then
            # tmp+mv: atomic replace so concurrent sessions never tear the file
            printf '%s\n' "$_d_updated" > "${_d_file}.tmp" 2>/dev/null \
                && mv "${_d_file}.tmp" "$_d_file" 2>/dev/null
            # Sum all sessions for today
            _d_total=$(printf '%s' "$_d_updated" | jq '[.[] | numbers] | add // 0' 2>/dev/null)
        else
            _d_total="0"
        fi
        # Format total
        _d_fmt=$(printf '%s' "${_d_total:-0}" | awk '{
            v = $1 + 0
            if (v < 10) { printf "$%.2f", v }
            else if (v < 100) { printf "$%.1f", v }
            else { printf "$%.0f", v }
        }')
        # Apply budget coloring if daily_budget configured
        _d_budget=""
        if [ -n "$effective_config" ]; then
            _d_budget=$(printf '%s' "$effective_config" | jq -r '.daily_budget // empty' 2>/dev/null)
        fi
        if [ -n "$_d_budget" ] && [ "$(printf '%s' "$_d_budget" | awk '{print ($1+0>0)?1:0}')" = "1" ]; then
            # Compute percentage: total / budget * 100
            _d_pct=$(printf '%s %s' "${_d_total:-0}" "$_d_budget" | awk '{v=$1/$2*100; printf "%.0f", v}' 2>/dev/null)
            _d_bfmt=$(printf '%s' "$_d_budget" | awk '{
                v = $1 + 0
                if (v < 10) { printf "$%.2f", v }
                else if (v < 100) { printf "$%.1f", v }
                else { printf "$%.0f", v }
            }')
            if [ "${_d_pct:-0}" -ge 100 ] 2>/dev/null; then
                daily_info="${RED}Σ ${_d_fmt}/${_d_bfmt}${NC}"
            elif [ "${_d_pct:-0}" -ge 80 ] 2>/dev/null; then
                daily_info="${MAGENTA}Σ ${_d_fmt}/${_d_bfmt}${NC}"
            elif [ "${_d_pct:-0}" -ge 50 ] 2>/dev/null; then
                daily_info="${YELLOW}Σ ${_d_fmt}/${_d_bfmt}${NC}"
            else
                daily_info="${GREEN}Σ ${_d_fmt}/${_d_bfmt}${NC}"
            fi
        else
            daily_info="${GRAY}Σ ${_d_fmt}${NC}"
        fi
    fi
fi

# --- Spend module (7-day and 30-day historical spend from daily ledger, opt-in) ---
# Reads the per-day ledger that the daily module maintains under
# ~/.claude/.ccvitals-daily/YYYY-MM-DD.json (dict of session_id -> cost_usd).
# Sums all day-files that fall within the 7d and 30d windows.
# Accumulation starts from install time — no backfill of pre-install transcripts.
# Config: spend_windows (array, default ["7d","30d"]), e.g. ["7d"] to show only 7-day.
# Cache: result is stored in .tool-cache/spend-result.txt keyed on a fingerprint of
# the ledger dir's per-file mtimes + today's date + windows config. On a cache hit,
# zero awk/jq spawns are needed.
spend_info=""
if [ "$mod_spend" = true ]; then
    _sp_dir="$config_dir/.ccvitals-daily"
    if [ -d "$_sp_dir" ]; then
        # Determine which windows to show
        _sp_windows="7d 30d"
        if [ -n "$effective_config" ]; then
            _sp_raw=$(printf '%s' "$effective_config" | jq -r '.spend_windows[]? // empty' 2>/dev/null)
            [ -n "$_sp_raw" ] && _sp_windows=$(printf '%s' "$_sp_raw" | tr '\n' ' ')
        fi
        _sp_today=$(date +%Y-%m-%d)
        # Build mtime fingerprint: today + windows config + mtime of each ledger file
        _sp_fingerprint="${_sp_today}:${_sp_windows}"
        for _sp_f in "$_sp_dir"/*.json; do
            [ -f "$_sp_f" ] || continue
            _sp_mtime=$(stat -f %m "$_sp_f" 2>/dev/null || stat -c %Y "$_sp_f" 2>/dev/null || echo 0)
            _sp_fingerprint="${_sp_fingerprint}:${_sp_f##*/}@${_sp_mtime}"
        done
        _sp_cache_dir="$config_dir/.tool-cache"
        _sp_cache_file="$_sp_cache_dir/spend-result.txt"
        _sp_cache_fp_file="$_sp_cache_dir/spend-result-mtime.txt"
        _sp_cached_fp=""
        _sp_cached_result=""
        if [ -f "$_sp_cache_fp_file" ] && [ -f "$_sp_cache_file" ]; then
            _sp_cached_fp=$(cat "$_sp_cache_fp_file" 2>/dev/null)
            _sp_cached_result=$(cat "$_sp_cache_file" 2>/dev/null)
        fi
        if [ "$_sp_cached_fp" = "$_sp_fingerprint" ] && [ -n "$_sp_cached_result" ]; then
            # Cache hit — zero awk/jq spawns
            spend_info="${GRAY}${_sp_cached_result}${NC}"
        else
            # Cache miss — compute sums
            # fmt helper (inline — same logic as daily)
            _sp_fmt() {
                printf '%s' "${1:-0}" | awk '{
                    v = $1 + 0
                    if (v < 10) { printf "$%.2f", v }
                    else if (v < 100) { printf "$%.1f", v }
                    else { printf "$%.0f", v }
                }'
            }
            _sp_result=""
            for _sp_win in $_sp_windows; do
                case "$_sp_win" in
                    7d)  _sp_days=7  ;;
                    30d) _sp_days=30 ;;
                    *)   continue ;;
                esac
                _sp_sum=0
                for _sp_f in "$_sp_dir"/*.json; do
                    [ -f "$_sp_f" ] || continue
                    # Extract YYYY-MM-DD from filename
                    _sp_fname="${_sp_f##*/}"
                    _sp_date="${_sp_fname%.json}"
                    # Compute age in days (pure awk date diff using epoch seconds via date)
                    _sp_age=$(printf '%s %s' "$_sp_today" "$_sp_date" | awk '{
                        split($1, a, "-"); split($2, b, "-")
                        y1=a[1]+0; m1=a[2]+0; d1=a[3]+0
                        y2=b[1]+0; m2=b[2]+0; d2=b[3]+0
                        # Days since epoch (Gregorian, simplified)
                        e1=y1*365+int(y1/4)-int(y1/100)+int(y1/400)+int((m1*306+5)/10)+d1
                        e2=y2*365+int(y2/4)-int(y2/100)+int(y2/400)+int((m2*306+5)/10)+d2
                        print e1-e2
                    }' 2>/dev/null || echo 999)
                    if [ "${_sp_age:-999}" -ge 0 ] && [ "${_sp_age:-999}" -lt "$_sp_days" ] 2>/dev/null; then
                        _sp_day_sum=$(jq '[.[] | numbers] | add // 0' "$_sp_f" 2>/dev/null || echo 0)
                        _sp_sum=$(printf '%s %s' "$_sp_sum" "$_sp_day_sum" | awk '{printf "%.6f", $1+$2}')
                    fi
                done
                _sp_fval=$(_sp_fmt "$_sp_sum")
                if [ -n "$_sp_result" ]; then
                    _sp_result="${_sp_result} · ${_sp_win} ${_sp_fval}"
                else
                    _sp_result="${_sp_win} ${_sp_fval}"
                fi
            done
            if [ -n "$_sp_result" ]; then
                spend_info="${GRAY}${_sp_result}${NC}"
                # Write cache atomically
                mkdir -p "$_sp_cache_dir"
                printf '%s' "$_sp_result" > "${_sp_cache_file}.tmp" \
                    && mv "${_sp_cache_file}.tmp" "$_sp_cache_file" 2>/dev/null
                printf '%s' "$_sp_fingerprint" > "${_sp_cache_fp_file}.tmp" \
                    && mv "${_sp_cache_fp_file}.tmp" "$_sp_cache_fp_file" 2>/dev/null
            fi
        fi
        unset _sp_dir _sp_windows _sp_raw _sp_today _sp_fingerprint _sp_mtime
        unset _sp_cache_dir _sp_cache_file _sp_cache_fp_file _sp_cached_fp _sp_cached_result
        unset _sp_result _sp_win _sp_days _sp_sum _sp_f _sp_fname _sp_date _sp_age _sp_day_sum _sp_fval
    fi
fi

# --- Compactions module (count compact_boundary entries, opt-in) ---
compactions_info=""
if [ "$mod_compactions" = true ]; then
    _comp_transcript=$(echo "$input" | jq -r '.transcript_path // empty' 2>/dev/null)
    if [ -n "$_comp_transcript" ] && [ -f "$_comp_transcript" ]; then
        _comp_count=$(grep -c '"subtype":"compact_boundary"' "$_comp_transcript" 2>/dev/null || echo 0)
        if [ "${_comp_count:-0}" -gt 0 ] 2>/dev/null; then
            compactions_info="${GRAY}${ICON_COMPACTIONS} ${_comp_count}${NC}"
        fi
    fi
fi

# --- Session tokens module (cumulative input/output, incremental cache, opt-in) ---
tokens_info=""
if [ "$mod_tokens" = true ]; then
    _tok_session=$(echo "$input" | jq -r '.session_id // empty' 2>/dev/null)
    _tok_transcript=$(echo "$input" | jq -r '.transcript_path // empty' 2>/dev/null)
    if [ -n "$_tok_session" ] && [ -n "$_tok_transcript" ] && [ -f "$_tok_transcript" ]; then
        _tok_cache_dir="$config_dir/.ccvitals-tokens"
        mkdir -p "$_tok_cache_dir"
        _tok_safe=$(printf '%s' "$_tok_session" | tr -dc 'a-zA-Z0-9_-' | cut -c1-40)
        _tok_file="$_tok_cache_dir/${_tok_safe}.txt"
        # Read current line count
        # grep -c '' counts the final line even without a trailing newline (wc -l misses it)
        _tok_cur_lines=$(grep -c '' "$_tok_transcript" 2>/dev/null)
        _tok_proc=0; _tok_total_in=0; _tok_total_out=0
        if [ -f "$_tok_file" ]; then
            _tok_proc=$(cut -f1 "$_tok_file" 2>/dev/null || echo 0)
            _tok_total_in=$(cut -f2 "$_tok_file" 2>/dev/null || echo 0)
            _tok_total_out=$(cut -f3 "$_tok_file" 2>/dev/null || echo 0)
        fi
        # Ensure numeric
        _tok_proc=${_tok_proc:-0}; _tok_total_in=${_tok_total_in:-0}; _tok_total_out=${_tok_total_out:-0}
        _tok_cur_lines=${_tok_cur_lines:-0}
        # Detect shrink (compact reset)
        if [ "$_tok_cur_lines" -lt "$_tok_proc" ] 2>/dev/null; then
            _tok_proc=0; _tok_total_in=0; _tok_total_out=0
        fi
        # Process new lines if any
        if [ "$_tok_cur_lines" -gt "$_tok_proc" ] 2>/dev/null; then
            _tok_new_start=$(( _tok_proc + 1 ))
            _tok_delta=$(tail -n "+${_tok_new_start}" "$_tok_transcript" 2>/dev/null | jq -Rs '
              [split("\n")[] | select(length>0) | try fromjson catch empty
               | select(.type=="assistant")
               | .message.usage // {}
               | {
                   i: ((.input_tokens // 0) + (.cache_creation_input_tokens // 0) + (.cache_read_input_tokens // 0)),
                   o: (.output_tokens // 0)
                 }
              ] | {in: (map(.i) | add // 0), out: (map(.o) | add // 0)}' 2>/dev/null)
            if [ -n "$_tok_delta" ]; then
                _d_in=$(printf '%s' "$_tok_delta" | jq -r '.in // 0' 2>/dev/null || echo 0)
                _d_out=$(printf '%s' "$_tok_delta" | jq -r '.out // 0' 2>/dev/null || echo 0)
                _tok_total_in=$(( _tok_total_in + _d_in ))
                _tok_total_out=$(( _tok_total_out + _d_out ))
            fi
            _tok_proc="$_tok_cur_lines"
            printf '%s\t%s\t%s\n' "$_tok_proc" "$_tok_total_in" "$_tok_total_out" > "${_tok_file}.tmp" \
                && mv "${_tok_file}.tmp" "$_tok_file"
        fi
        # Format using same _fmt_k logic (inline since _fmt_k is scoped inside context block)
        _fmtk() {
            local n="$1"
            if [ "${n:-0}" -ge 1000000 ] 2>/dev/null; then
                printf '%dM' "$(( n / 1000000 ))"
            elif [ "${n:-0}" -ge 100000 ] 2>/dev/null; then
                printf '%dk' "$(( n / 1000 ))"
            elif [ "${n:-0}" -ge 1000 ] 2>/dev/null; then
                local _q=$(( n / 100 ))
                printf '%d.%dk' "$(( _q / 10 ))" "$(( _q % 10 ))"
            else
                printf '%d' "${n:-0}"
            fi
        }
        _tok_in_str=$(_fmtk "$_tok_total_in")
        _tok_out_str=$(_fmtk "$_tok_total_out")
        tokens_info="${GRAY}${ICON_TOKENS} ${_tok_in_str}/${_tok_out_str}${NC}"
    fi
fi

# --- Compose output ---
# Each module produced a bare chunk (no leading separator). Route every enabled
# chunk to line 1 or line 2 depending on whether its module name appears in
# modules_line2, then join chunks on each line with " | ".
#
# When powerline mode is on, chunks are collected into arrays and rendered with
# background-shaded segments and U+E0B0 (or custom) separators.  The non-powerline
# path is untouched — it still uses the " | " join so output is byte-identical.
SEP=" ${GRAY}|${NC} "
line1=""
line2=""

# Powerline segment arrays (parallel: names1/chunks1 for line 1, same for line 2).
# Using space-delimited strings instead of arrays for bash 3.2 compatibility.
_pl_count1=0
_pl_count2=0
# Store chunks in indexed variables _pl_chunk1_N and _pl_chunk2_N (bash 3.2 safe).

is_line2() { case " $line2_set " in *" $1 "*) return 0 ;; *) return 1 ;; esac; }

route() {  # $1 = module name, $2 = bare chunk
    [ -z "$2" ] && return
    if [ "$PL_ON" = true ]; then
        if is_line2 "$1"; then
            eval "_pl_chunk2_${_pl_count2}=\$2"
            _pl_count2=$(( _pl_count2 + 1 ))
        else
            eval "_pl_chunk1_${_pl_count1}=\$2"
            _pl_count1=$(( _pl_count1 + 1 ))
        fi
    else
        if is_line2 "$1"; then
            line2="${line2:+$line2$SEP}$2"
        else
            line1="${line1:+$line1$SEP}$2"
        fi
    fi
}

# --- Smart visibility suppression ---
# When smart=true, hide modules whose current value isn't notable.
if [ "$smart_mode" = true ]; then
    # cost: hide when < $1.00
    if [ -n "$cost_info" ]; then
        _sv_cost=$(echo "$input" | jq -r '.cost.total_cost_usd // 0' 2>/dev/null)
        _sv_cost_int=$(printf '%.0f' "${_sv_cost:-0}" 2>/dev/null || echo 0)
        # compare as awk since it's a float
        _sv_cost_hide=$(printf '%s' "${_sv_cost:-0}" | awk '{print ($1+0 < 1.0) ? 1 : 0}')
        [ "$_sv_cost_hide" = "1" ] && cost_info=""
        unset _sv_cost _sv_cost_int _sv_cost_hide
    fi
    # cache: only show when remaining < 60s (or cold — "cache cold")
    if [ -n "$cache_info" ]; then
        # cache_info shows cold or "cache Xm Ys" / "cache Xs"
        # Hide when time remaining >= 60s (i.e., contains "m" in a pattern like "Xm")
        # We detect "cold" (show it) and <60s (show it); >=60s (hide it)
        # Match on ANSI-stripped text — the raw string contains color codes like
        # \033[0;32m whose "2m" would false-match the minutes pattern.
        _sv_cache_plain=$(printf '%s' "$cache_info" | sed -E 's/\\033\[[0-9;]*m//g')
        case "$_sv_cache_plain" in
            *cold*)  ;;  # keep — cold is notable
            *[0-9]m*) cache_info="" ;;  # "Xm Ys" form means >= 60s — hide
        esac
        unset _sv_cache_plain
    fi
    # pace (delta mode): only show when delta < 0 (burning fast)
    if [ -n "$pace_info" ]; then
        # In delta mode pace_info contains "pace +N%" (ahead) or "pace -N%" (behind) or "pace N%"
        # In ETA mode, always show (it's inherently smart)
        # Hide if it contains "pace +" (positive delta = ahead of pace = not notable)
        case "$pace_info" in
            *"pace +"*) pace_info="" ;;
        esac
    fi
    # context: only show when >= 50%
    if [ -n "$context_info" ]; then
        [ "${context_percent:-0}" -lt 50 ] 2>/dev/null && context_info=""
    fi
    # duration: only show when >= 1h
    if [ -n "$duration_info" ]; then
        _sv_dur_ms=$(echo "$input" | jq -r '.cost.total_duration_ms // 0' 2>/dev/null)
        _sv_dur_s=$(( ${_sv_dur_ms:-0} / 1000 ))
        [ "$_sv_dur_s" -lt 3600 ] 2>/dev/null && duration_info=""
        unset _sv_dur_ms _sv_dur_s
    fi
    # thinking: only show when effort is high or xhigh
    if [ -n "$thinking_info" ]; then
        case "$thinking_info" in
            *low*|*medium*) thinking_info="" ;;
        esac
    fi
    # mcp: always notable when present — no suppression
fi

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
route tools      "$tools_info"
route agents     "$agents_info"
route todos      "$todos_info"
route workflows  "$workflows_info"
route daily      "$daily_info"
route spend      "$spend_info"
route compactions "$compactions_info"
route tokens     "$tokens_info"
route thinking   "$thinking_info"
route mcp        "$mcp_info"

# --- Powerline render helper ---
# build_pl_line <count_var_prefix> <line_number>
# Iterates the stored chunks, alternates BG_A/BG_B, injects separator glyphs,
# and post-processes each chunk so internal \033[0m resets don't kill the bg.
build_pl_line() {
    local count="$1"
    local linenum="$2"
    local result=""
    local i=0
    local seg_bg seg_fg prev_bg_fg chunk seg_bg_esc
    prev_bg_fg=""
    while [ "$i" -lt "$count" ]; do
        # Alternate backgrounds: even index → A, odd → B
        if [ $(( i % 2 )) -eq 0 ]; then
            seg_bg="$PL_BG_A"
            seg_fg="$PL_FG_A"
        else
            seg_bg="$PL_BG_B"
            seg_fg="$PL_FG_B"
        fi
        # Retrieve chunk from indexed variable (bash 3.2 safe, no assoc arrays)
        eval "chunk=\$_pl_chunk${linenum}_${i}"
        # Post-process: replace every internal \033[0m (literal text, not ESC byte)
        # with \033[0m + seg_bg so the background survives internal color resets.
        # Chunks store literal backslash-escapes that printf %b expands later,
        # so we match the literal 8-char sequence \033[0m with sed.
        seg_bg_esc="${seg_bg//\\/\\\\}"   # escape backslashes for sed replacement
        seg_bg_esc="${seg_bg_esc//&/\\&}" # escape & (sed re-inserts the match)
        chunk=$(printf '%s' "$chunk" | sed "s/\\\\033[[]0m/\\\\033[0m${seg_bg_esc}/g")
        # Build separator glyph between segments (fg = prev bg color, bg = this bg)
        if [ "$i" -eq 0 ]; then
            # First segment — no preceding separator
            result="${result}${seg_bg} ${chunk} "
        else
            # Separator: fg = previous segment's bg color, bg = current segment's bg
            result="${result}${NC}${prev_bg_fg}${seg_bg}${PL_SEP} ${chunk} "
        fi
        prev_bg_fg="$seg_fg"
        i=$(( i + 1 ))
    done
    # Final separator: fg = last bg, terminal default bg (no background code)
    if [ "$count" -gt 0 ]; then
        result="${result}${NC}${prev_bg_fg}${PL_SEP}${NC}"
    fi
    printf '%s' "$result"
}

if [ "$PL_ON" = true ]; then
    line1=$(build_pl_line "$_pl_count1" 1)
    if [ "$_pl_count2" -gt 0 ]; then
        line2=$(build_pl_line "$_pl_count2" 2)
        printf '%b\n%b\n' "$line1" "$line2"
    else
        printf '%b\n' "$line1"
    fi
else
    # --- Responsive width ---
    # When responsive=true and COLUMNS is numeric, drop lowest-priority modules from
    # line1 until the visible length fits. Powerline mode is not supported (skipped above).
    # Priority order: drop first -> last (codegraph first, directory/model/context last).
    _resp_priority="thinking mcp codegraph rtk lines duration cost speed vim weekly daily spend tokens compactions pr agent mode cache pace tools agents todos workflows git usage context model directory"
    if [ "$responsive_mode" = true ] && [ -n "${COLUMNS:-}" ] && [ "${COLUMNS:-0}" -gt 0 ] 2>/dev/null; then
        # Compute visible length: strip ANSI CSI sequences (\033[...m) and OSC sequences (\033]...BEL),
        # then count CHARACTERS (wc -m) — bar glyphs like █ are 3 bytes but 1 column.
        _visible_len() {
            local _stripped
            _stripped=$(printf '%b' "$1" | sed 's/\x1b\[[0-9;]*[mKHJABCDGsufhl]//g; s/\x1b][^\x07]*\x07//g')
            printf '%s' "$_stripped" | wc -m | tr -d ' '
        }
        _line1_len=$(_visible_len "$line1")
        if [ "${_line1_len:-0}" -gt "${COLUMNS:-0}" ] 2>/dev/null; then
            for _drop_mod in $_resp_priority; do
                [ "${_line1_len:-0}" -le "${COLUMNS:-0}" ] 2>/dev/null && break
                # Blank the module's info variable and recompose line1 from scratch
                case "$_drop_mod" in
                    codegraph)  cg_info="" ;;
                    rtk)        rtk_info="" ;;
                    lines)      lines_info="" ;;
                    duration)   duration_info="" ;;
                    cost)       cost_info="" ;;
                    speed)      speed_info="" ;;
                    vim)        vim_info="" ;;
                    weekly)     weekly_info="" ;;
                    daily)      daily_info="" ;;
                    spend)      spend_info="" ;;
                    tokens)     tokens_info="" ;;
                    compactions) compactions_info="" ;;
                    pr)         pr_info="" ;;
                    agent)      agent_info="" ;;
                    mode)       mode_info="" ;;
                    cache)      cache_info="" ;;
                    pace)       pace_info="" ;;
                    tools)      tools_info="" ;;
                    agents)     agents_info="" ;;
                    todos)      todos_info="" ;;
                    workflows)  workflows_info="" ;;
                    git)        git_info="" ;;
                    usage)      usage_info="" ;;
                    context)    context_info="" ;;
                    model)      mod_model=false ;;
                    directory)  mod_directory=false ;;
                    thinking)   thinking_info="" ;;
                    mcp)        mcp_info="" ;;
                esac
                # Recompose line1
                line1=""
                _pl_count1=0
                [ "$mod_directory" = true ] && [ -n "$dir_name" ] && line1="${line1:+$line1$SEP}${BLUE}${dir_name}${NC}"
                [ "$mod_model" = true ] && [ -n "$model_name" ] && line1="${line1:+$line1$SEP}${CYAN}${model_name}${NC}"
                for _rc in context_info usage_info rtk_info mode_info git_info lines_info cg_info cost_info duration_info speed_info vim_info agent_info pr_info weekly_info pace_info cache_info tools_info agents_info todos_info workflows_info daily_info spend_info compactions_info tokens_info thinking_info mcp_info; do
                    _rc_val="${!_rc}"
                    if [ -n "$_rc_val" ]; then
                        # Only route to line1 (not line2)
                        _rc_modname="${_rc%_info}"
                        # check if this module is assigned to line2
                        case " $line2_set " in
                            *" ${_rc_modname} "*) ;;  # skip — it's on line2
                            *) line1="${line1:+$line1$SEP}${_rc_val}" ;;
                        esac
                    fi
                done
                _line1_len=$(_visible_len "$line1")
            done
        fi
        unset _resp_priority _drop_mod _rc _rc_val _rc_modname _line1_len
    fi

    if [ -n "$line2" ]; then
        printf '%b\n%b\n' "$line1" "$line2"
    else
        printf '%b\n' "$line1"
    fi
fi
