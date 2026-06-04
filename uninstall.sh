#!/usr/bin/env bash
set -euo pipefail

# ccvitals Uninstaller
# https://github.com/educlopez/ccvitals

STATUSLINE_VERSION="1.8.1"

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
statusline_config="$config_dir/.statusline-config.json"
cache_dir="$config_dir/.usage-cache"

info "Claude config directory: $config_dir"

# --- Remove statusline script (regular file or symlink, even if dangling) ---
if [ -e "$script_file" ] || [ -L "$script_file" ]; then
    rm "$script_file"
    ok "Removed $script_file"
else
    warn "Statusline script not found at $script_file (already removed?)"
fi

# --- Remove module config ---
if [ -f "$statusline_config" ]; then
    rm "$statusline_config"
    ok "Removed $statusline_config"
else
    info "No module config found"
fi

# --- Remove statusLine key from settings.json ---
if [ -f "$settings_file" ]; then
    if jq -e '.statusLine' "$settings_file" >/dev/null 2>&1; then
        cp "$settings_file" "$settings_file.backup"
        jq 'del(.statusLine)' "$settings_file.backup" > "$settings_file"
        ok "Removed statusLine from settings.json"
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

# --- Done ---
echo ""
echo -e "${GREEN}ccvitals uninstalled successfully!${NC}"
echo ""
echo "  Restart Claude Code to apply changes."
echo ""
