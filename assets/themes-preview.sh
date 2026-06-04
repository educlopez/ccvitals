#!/usr/bin/env bash
# ccvitals — theme preview driver for assets/themes.tape (generates assets/themes.png).
# Renders one identical statusline per theme so the palettes can be compared.

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
fixture="$repo_root/test/fixtures/sample-context.json"

now=$(date +%s)

# Throwaway git repo so the git module renders
demo_repo=$(mktemp -d)/my-app
mkdir -p "$demo_repo"
(
    cd "$demo_repo"
    git init -q -b main
    git -c user.email=demo@ccvitals -c user.name=demo commit -q --allow-empty -m init
    printf 'export const answer = 42\n' > feature.ts
    printf 'body { margin: 0 }\n' > styles.css
)
trap 'rm -rf "${demo_repo%/*}"' EXIT

base_json=$(jq \
    --argjson fh "$((now + 7200))" \
    --arg dir "$demo_repo" \
    '.workspace.current_dir = $dir
     | .rate_limits.five_hour.resets_at = $fh' \
    "$fixture")

render_theme() { # $1 = theme name, $2 = "bare" to skip the label column
    local tmp
    tmp=$(mktemp -d)
    printf '{"modules":["directory","model","context","usage","git","mode","lines","cost"],"theme":"%s"}' "$1" \
        > "$tmp/.statusline-config.json"
    [ "${2:-}" != "bare" ] && printf '\033[1;37m%-14s\033[0m ' "$1"
    printf '%s' "$base_json" | CLAUDE_CONFIG_DIR="$tmp" "$repo_root/statusline.sh"
    rm -rf "$tmp"
    echo ""
}

if [ -n "${1:-}" ]; then
    # Single theme, no label — used by generate-theme-previews.sh
    render_theme "$1" bare
else
    for theme in default pastel tokyo-night catppuccin dracula nord mono; do
        render_theme "$theme"
    done
fi
