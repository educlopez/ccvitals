#!/usr/bin/env bash
set -euo pipefail

# ccvitals Uninstaller
# https://github.com/educlopez/ccvitals

STATUSLINE_VERSION="1.11.0"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m'

info()  { echo -e "${CYAN}[info]${NC} $1"; }
ok()    { echo -e "${GREEN}[ok]${NC} $1"; }
warn()  { echo -e "${YELLOW}[warn]${NC} $1"; }

# --- Resolve config directory ---
config_dir="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
config_dir="${config_dir/#\~/$HOME}"
settings_file="$config_dir/settings.json"
script_file="$config_dir/statusline-command.sh"
subagent_script_file="$config_dir/subagent-statusline.sh"
statusline_config="$config_dir/.statusline-config.json"
cache_dir="$config_dir/.usage-cache"
state_dir="$config_dir/.ccvitals-state"

info "Claude config directory: $config_dir"

# --- Remove statusline script (regular file or symlink, even if dangling) ---
if [ -e "$script_file" ] || [ -L "$script_file" ]; then
    rm "$script_file"
    ok "Removed $script_file"
else
    warn "Statusline script not found at $script_file (already removed?)"
fi

# --- Remove subagent statusline script ---
if [ -e "$subagent_script_file" ] || [ -L "$subagent_script_file" ]; then
    rm "$subagent_script_file"
    ok "Removed $subagent_script_file"
else
    info "Subagent script not found at $subagent_script_file (already removed?)"
fi

# --- Remove module config ---
if [ -f "$statusline_config" ]; then
    rm "$statusline_config"
    ok "Removed $statusline_config"
else
    info "No module config found"
fi

# --- Remove statusLine and subagentStatusLine keys from settings.json ---
if [ -f "$settings_file" ]; then
    has_sl=$(jq -r 'if has("statusLine") or has("subagentStatusLine") then "yes" else "no" end' "$settings_file" 2>/dev/null)
    if [ "$has_sl" = "yes" ]; then
        cp "$settings_file" "$settings_file.backup"
        jq 'del(.statusLine) | del(.subagentStatusLine)' "$settings_file.backup" > "$settings_file"
        ok "Removed statusLine and subagentStatusLine from settings.json"
    else
        info "No statusLine key found in settings.json (already clean)"
    fi
else
    info "No settings.json found"
fi

# --- Remove cache directories ---
if [ -d "$cache_dir" ]; then
    rm -rf "$cache_dir"
    ok "Removed cache directory $cache_dir"
else
    info "No cache directory found"
fi

speed_cache_dir="$config_dir/.speed-cache"
if [ -d "$speed_cache_dir" ]; then
    rm -rf "$speed_cache_dir"
    ok "Removed speed cache directory $speed_cache_dir"
fi

# --- Remove ccvitals hook entries from settings.json ---
# Only removes entries whose .command contains "ccvitals-hook.sh".
# All other hook entries are preserved.
if [ -f "$settings_file" ]; then
    # Detection: traverse nested schema — each event array contains group objects
    # with an inner .hooks[] array. Check any inner command contains "ccvitals-hook".
    _has_hooks=$(jq -r '
        if .hooks then
            [.hooks | to_entries[] | .value[] | .hooks[]? | select(.command? and (.command | test("ccvitals-hook")))] | length
        else 0 end
    ' "$settings_file" 2>/dev/null)
    if [ "${_has_hooks:-0}" -gt 0 ] 2>/dev/null; then
        cp "$settings_file" "$settings_file.backup"
        # Fix 2: capture to var first, check non-empty, then write — avoids truncation
        # if jq fails (which would leave a 0-byte settings.json with no restore).
        _cleaned=$(jq '
            if .hooks then
                .hooks |= (
                    to_entries
                    | map(
                        # Within each group, remove inner hook entries whose command
                        # contains "ccvitals-hook"; drop the group if inner hooks is empty
                        .value |= map(
                            .hooks |= map(select(.command? | test("ccvitals-hook") | not))
                            | select((.hooks | length) > 0)
                        )
                      )
                    | map(select(.value | length > 0))
                    | if length == 0 then {} else from_entries end
                  )
                | if (.hooks | length) == 0 then del(.hooks) else . end
            else . end
        ' "$settings_file.backup" 2>/dev/null)
        if [ -n "$_cleaned" ]; then
            printf '%s\n' "$_cleaned" > "$settings_file"
            ok "Removed ccvitals hook entries from settings.json"
        else
            warn "Failed to clean hook entries from settings.json (jq error?) — restoring backup"
            cp "$settings_file.backup" "$settings_file" 2>/dev/null || true
        fi
        unset _cleaned
    else
        info "No ccvitals hook entries found in settings.json (already clean)"
    fi
    unset _has_hooks
fi

# --- Remove state directory ---
if [ -d "$state_dir" ]; then
    rm -rf "$state_dir"
    ok "Removed state directory $state_dir"
fi

# --- Done ---
echo ""
echo -e "${GREEN}ccvitals uninstalled successfully!${NC}"
echo ""
echo "  Restart Claude Code to apply changes."
echo ""
