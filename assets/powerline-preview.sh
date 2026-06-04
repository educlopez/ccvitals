#!/usr/bin/env bash
cd "$(dirname "$0")/.."
now=$(date +%s)
for theme in pastel tokyo-night dracula; do
  tmp=$(mktemp -d)
  printf '{"modules":["directory","model","context","usage","git","cost","mode"],"theme":"%s","powerline":true}' "$theme" > "$tmp/.statusline-config.json"
  printf '%-13s ' "$theme"
  jq --argjson fh $((now+7200)) '.rate_limits.five_hour.resets_at = $fh' test/fixtures/sample-context.json | CLAUDE_CONFIG_DIR="$tmp" ./statusline.sh
  rm -rf "$tmp"; echo ""
done
