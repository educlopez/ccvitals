#!/usr/bin/env bash
# ccvitals — regenerate the per-theme preview PNGs embedded in the README.
# Requires: vhs, ffmpeg.
#
# Usage: ./assets/generate-theme-previews.sh

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

mkdir -p assets/themes

for theme in default pastel tokyo-night catppuccin dracula nord mono; do
    tape=$(mktemp -t ccvitals-tape)
    cat > "$tape" <<EOF
Output assets/themes-scratch.gif
Set FontSize 16
Set Width 1280
Set Height 110
Set Padding 20
Set Theme "Catppuccin Mocha"
Hide
Type "clear && ./assets/themes-preview.sh ${theme}"
Enter
Sleep 3s
Show
Sleep 1s
EOF
    echo "[gen] $theme"
    vhs "$tape" >/dev/null 2>&1
    # Crop away the shell prompt line below the rendered statusline
    ffmpeg -y -loglevel error -sseof -0.3 -i assets/themes-scratch.gif \
        -vf "crop=iw:64:0:0" -update 1 -frames:v 1 "assets/themes/${theme}.png"
    rm -f "$tape" assets/themes-scratch.gif
done

echo "[ok] assets/themes/*.png regenerated"
