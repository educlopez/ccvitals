#!/usr/bin/env bash
# ccvitals — demo driver for the VHS-recorded GIF (assets/demo.tape).
# Renders the statusline against fixture data in a few module configurations.
# Not installed anywhere; only used to regenerate assets/demo.gif.

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
fixture="$repo_root/test/fixtures/sample-context.json"

# Future reset times so the countdowns render
now=$(date +%s)
five_h_reset=$((now + 7200))      # 2h from now
seven_d_reset=$((now + 363600))   # 4d5h from now

# Throwaway git repo so the git module has something to show
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
    --argjson fh "$five_h_reset" \
    --argjson sd "$seven_d_reset" \
    --arg dir "$demo_repo" \
    '.workspace.current_dir = $dir
     | .rate_limits.five_hour.resets_at = $fh
     | .rate_limits.seven_day.resets_at = $sd
     | .agent.name = "code-reviewer"' \
    "$fixture")

render() { # $1 = config json
    local tmp
    tmp=$(mktemp -d)
    printf '%s' "$1" > "$tmp/.statusline-config.json"
    printf '%s' "$2" | CLAUDE_CONFIG_DIR="$tmp" "$repo_root/statusline.sh"
    rm -rf "$tmp"
}

label() { printf '\033[1;37m%s\033[0m\n' "$1"; }

label "❯ Essential — the defaults"
render '{"modules":["directory","model","context","usage","git"]}' "$base_json"
echo ""
sleep 3

label "❯ Everything — 16 modules, two-line layout"
render '{"modules":["directory","model","git","cost","duration","speed","vim","agent","pr"],
         "modules_line2":["context","usage","weekly","lines","mode"]}' "$base_json"
echo ""
sleep 3

pressure_json=$(printf '%s' "$base_json" | jq \
    '.context_window.current_usage.input_tokens = 178000
     | .context_window.current_usage.cache_creation_input_tokens = 5000
     | .context_window.current_usage.cache_read_input_tokens = 1000')

label "❯ Context pressure — it warns you before /compact does"
render '{"modules":["directory","model","context","usage"]}' "$pressure_json"
echo ""
sleep 3

label "❯ Themes — pastel, tokyo-night, catppuccin, dracula, nord"
for theme in pastel tokyo-night catppuccin dracula nord; do
    render "{\"modules\":[\"directory\",\"model\",\"context\",\"usage\",\"git\"],\"theme\":\"$theme\"}" "$base_json"
done
sleep 4
