#!/usr/bin/env bash
set -euo pipefail

# ccvitals Installer (link mode)
# https://github.com/educlopez/ccvitals
#
# Run this from a cloned copy of the repo — it does NOT download anything.
# It symlinks the repo's statusline.sh into your Claude config dir so that
# `git pull` updates the statusline instantly (ideal for syncing machines).
#
# Usage:
#   git clone https://github.com/educlopez/ccvitals.git
#   cd ccvitals
#   ./install.sh                       # interactive module menu
#   ./install.sh --all                 # all modules, no menu
#   ./install.sh --modules=model,git   # specific modules
#   ./install.sh --force               # repair/overwrite an existing install
#   ./install.sh --help

STATUSLINE_VERSION="1.3.0"

SCRIPT_NAME="statusline-command.sh"

# Repo this installer lives in (statusline.sh sits next to it)
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd -P)"
SOURCE_SCRIPT="$REPO_DIR/statusline.sh"

# Module descriptions for interactive menu
MOD_DESC_1="Directory      my-project"
MOD_DESC_2="Model          Opus 4.6"
MOD_DESC_3="Context        ░░░░░░░░░░░░░░░ 12%"
MOD_DESC_4="Usage quota    Max ██████░░░░ 58% 3h42m"
MOD_DESC_5="Git status     (main | 3 files +42 -8)"
MOD_DESC_6="RTK savings    rtk 86.8%↓               (needs rtk)"
MOD_DESC_7="CodeGraph      ⬡ 11.7k ⚠3               (needs codegraph)"
MOD_DESC_8="Session lines  +264 -195"
MOD_DESC_9="Mode badge     ⚡ xhigh"

# ─── Phase 1.1: Color setup with NO_COLOR / TTY detection ───

RED=''
GREEN=''
YELLOW=''
CYAN=''
GRAY=''
BOLD=''
NC=''

setup_colors() {
    # Respect NO_COLOR (https://no-color.org/) and non-TTY stdout
    if [ -n "${NO_COLOR:-}" ] || [ ! -t 1 ]; then
        RED=''
        GREEN=''
        YELLOW=''
        CYAN=''
        GRAY=''
        BOLD=''
        NC=''
    else
        RED='\033[0;31m'
        GREEN='\033[0;32m'
        YELLOW='\033[0;33m'
        CYAN='\033[0;36m'
        GRAY='\033[0;90m'
        BOLD='\033[1m'
        NC='\033[0m'
    fi
}

setup_colors

# ─── Logging helpers ───

info()  { echo -e "${CYAN}[info]${NC} $1"; }
ok()    { echo -e "${GREEN}[ok]${NC} $1"; }
warn()  { echo -e "${YELLOW}[warn]${NC} $1"; }
error() { echo -e "${RED}[error]${NC} $1"; exit 1; }

# ─── Phase 1.2: Trap-based cleanup with file tracking ───

CREATED_FILES=()
INSTALL_SUCCESS=false

track_file() {
    CREATED_FILES+=("$1")
}

cleanup() {
    if [ "$INSTALL_SUCCESS" = true ]; then
        return
    fi
    # Non-zero exit: restore backups and remove created files/links
    for f in "${CREATED_FILES[@]+"${CREATED_FILES[@]}"}"; do
        if [ -e "${f}.backup" ]; then
            mv "${f}.backup" "$f" 2>/dev/null || true
        elif [ -e "$f" ] || [ -L "$f" ]; then
            rm -f "$f" 2>/dev/null || true
        fi
    done
}

trap cleanup EXIT

# ─── Module helpers ───

get_mod_desc() {
    case "$1" in
        1) echo "$MOD_DESC_1" ;; 2) echo "$MOD_DESC_2" ;; 3) echo "$MOD_DESC_3" ;;
        4) echo "$MOD_DESC_4" ;; 5) echo "$MOD_DESC_5" ;; 6) echo "$MOD_DESC_6" ;;
        7) echo "$MOD_DESC_7" ;; 8) echo "$MOD_DESC_8" ;; 9) echo "$MOD_DESC_9" ;;
    esac
}

get_mod_name() {
    case "$1" in
        1) echo "directory" ;; 2) echo "model" ;; 3) echo "context" ;;
        4) echo "usage" ;; 5) echo "git" ;; 6) echo "rtk" ;; 7) echo "codegraph" ;;
        8) echo "lines" ;; 9) echo "mode" ;;
    esac
}

# ─── Phase 2.1: --help flag ───

show_help() {
    cat <<HELPEOF
ccvitals v${STATUSLINE_VERSION} — A customizable statusline for Claude Code

This installer runs from a cloned copy of the repo and symlinks
statusline.sh into your Claude config dir. Update later with: git pull

Usage:
  git clone https://github.com/educlopez/ccvitals.git
  cd ccvitals
  ./install.sh [OPTIONS]

Options:
  --help, -h         Show this help message and exit
  --version          Show version and exit
  --force            Repair/overwrite an existing install (relink script,
                     overwrite the statusLine key in settings.json)
  --all              Install all modules without showing the interactive menu
  --modules=LIST     Install specific modules (comma-separated, no spaces)
                     Available: directory, model, context, usage, git, rtk,
                     codegraph, lines, mode
  --line2=LIST       Render these modules on a second row (comma-separated).
                     They are placed in modules_line2; the rest stay on line 1.

Examples:
  ./install.sh                          # interactive install
  ./install.sh --all                    # all modules, no menu
  ./install.sh --modules=directory,model
  ./install.sh --all --line2=context,usage,rtk,mode,lines   # two-line layout
  ./install.sh --force                  # repair an existing install

Modules:
  directory    Show current project directory name
  model        Show active Claude model (e.g. Opus 4.6)
  context      Show context window usage as a progress bar
  usage        Show usage quota with remaining time
  git          Show git branch, changed files, and diff stats
  rtk          Show RTK token-savings % (needs the rtk CLI)
  codegraph    Show CodeGraph index size + stale marker (needs codegraph CLI)
  lines        Show lines added/removed this session
  mode         Show reasoning effort level + fast-mode flag

Update:
  cd $REPO_DIR && git pull
  (the symlink picks up the new version automatically)

Uninstall:
  ./uninstall.sh
HELPEOF
    exit 0
}

# ─── Parse flags ───

FORCE=false
SKIP_MENU=false
MODULES_ARG=""
LINE2_ARG=""

for arg in "$@"; do
    case "$arg" in
        --help|-h) show_help ;;
        --force)   FORCE=true ;;
        --all)     SKIP_MENU=true; MODULES_ARG="directory,model,context,usage,git,rtk,codegraph,lines,mode" ;;
        --modules=*) SKIP_MENU=true; MODULES_ARG="${arg#--modules=}" ;;
        --line2=*) LINE2_ARG="${arg#--line2=}" ;;
        --version) echo "ccvitals v$STATUSLINE_VERSION"; exit 0 ;;
    esac
done

# ─── Phase 1.3: Step counter ───

CURRENT_STEP=0
TOTAL_STEPS=6

step() {
    CURRENT_STEP=$((CURRENT_STEP + 1))
    info "[${CURRENT_STEP}/${TOTAL_STEPS}] $1"
}

# ─── Phase 3.1: Pre-flight validation helpers ───

check_writable() {
    local target="$1"
    if [ -d "$target" ]; then
        if [ ! -w "$target" ]; then
            error "Directory is not writable: $target"
        fi
    else
        # Check parent directory
        local parent
        parent="$(dirname "$target")"
        if [ -d "$parent" ] && [ ! -w "$parent" ]; then
            error "Parent directory is not writable: $parent"
        fi
    fi
}

validate_json() {
    local file="$1"
    if [ -f "$file" ]; then
        if ! jq empty "$file" 2>/dev/null; then
            error "Invalid JSON in $file — fix it manually or remove it and re-run the installer"
        fi
    fi
}

# ─── Phase 3.3: Smart jq install hints ───

suggest_jq_install() {
    local hint="install jq from https://jqlang.github.io/jq/download/"
    if command -v brew >/dev/null 2>&1; then
        hint="brew install jq"
    elif command -v apt-get >/dev/null 2>&1; then
        hint="sudo apt-get install -y jq"
    elif command -v dnf >/dev/null 2>&1; then
        hint="sudo dnf install -y jq"
    elif command -v pacman >/dev/null 2>&1; then
        hint="sudo pacman -S jq"
    elif command -v apk >/dev/null 2>&1; then
        hint="apk add jq"
    fi
    error "jq is required — install it with: $hint"
}

# ─── Phase 4.1: Step — Prerequisites ───

step "Checking prerequisites..."

command -v bash >/dev/null 2>&1 || error "bash is required"
command -v jq   >/dev/null 2>&1 || suggest_jq_install

# The source script must exist in this clone
[ -f "$SOURCE_SCRIPT" ] || error "statusline.sh not found next to this installer ($SOURCE_SCRIPT). Run ./install.sh from inside the cloned repo."

ok "All prerequisites found (bash, jq, repo source script)"

# ─── Resolve config directory ───

config_dir="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
config_dir="${config_dir/#\~/$HOME}"
settings_file="$config_dir/settings.json"
script_dest="$config_dir/$SCRIPT_NAME"
statusline_config="$config_dir/.statusline-config.json"

info "Claude config directory: $config_dir"
info "Linking from repo:        $SOURCE_SCRIPT"

# ─── Phase 3.1: Pre-flight validation ───

step "Validating environment..."

mkdir -p "$config_dir"
check_writable "$config_dir"
validate_json "$settings_file"

ok "Environment validated"

# ─── Determine selected modules ───

SELECTED_MODULES=""
LINE2_MODULES=""

if [ "$SKIP_MENU" = true ] && [ -n "$MODULES_ARG" ]; then
    # From --modules or --all flag
    SELECTED_MODULES="$MODULES_ARG"
elif [ "$SKIP_MENU" = false ]; then
    # Try interactive menu
    CAN_INTERACT=false
    if [ -e /dev/tty ]; then
        CAN_INTERACT=true
    elif [ -t 0 ]; then
        CAN_INTERACT=true
    fi

    if [ "$CAN_INTERACT" = true ]; then
        # Track enabled state: 1=on, 0=off. Core modules on, tool modules off.
        en_1=1; en_2=1; en_3=1; en_4=1; en_5=1; en_6=0; en_7=0; en_8=0; en_9=0

        get_en() {
            case "$1" in
                1) echo "$en_1" ;; 2) echo "$en_2" ;; 3) echo "$en_3" ;;
                4) echo "$en_4" ;; 5) echo "$en_5" ;; 6) echo "$en_6" ;;
                7) echo "$en_7" ;; 8) echo "$en_8" ;; 9) echo "$en_9" ;;
            esac
        }

        toggle() {
            case "$1" in
                1) if [ "$en_1" -eq 1 ]; then en_1=0; else en_1=1; fi ;;
                2) if [ "$en_2" -eq 1 ]; then en_2=0; else en_2=1; fi ;;
                3) if [ "$en_3" -eq 1 ]; then en_3=0; else en_3=1; fi ;;
                4) if [ "$en_4" -eq 1 ]; then en_4=0; else en_4=1; fi ;;
                5) if [ "$en_5" -eq 1 ]; then en_5=0; else en_5=1; fi ;;
                6) if [ "$en_6" -eq 1 ]; then en_6=0; else en_6=1; fi ;;
                7) if [ "$en_7" -eq 1 ]; then en_7=0; else en_7=1; fi ;;
                8) if [ "$en_8" -eq 1 ]; then en_8=0; else en_8=1; fi ;;
                9) if [ "$en_9" -eq 1 ]; then en_9=0; else en_9=1; fi ;;
            esac
        }

        draw_menu() {
            echo ""
            echo -e "${BOLD}ccvitals — Choose your modules:${NC}"
            echo ""
            for i in 1 2 3 4 5 6 7 8 9; do
                local desc
                desc=$(get_mod_desc "$i")
                if [ "$(get_en "$i")" -eq 1 ]; then
                    echo -e "  ${GREEN}[x]${NC} ${BOLD}$i)${NC} $desc"
                else
                    echo -e "  ${GRAY}[ ] $i) $desc${NC}"
                fi
            done
            echo ""
            echo -e "  Toggle: enter number (e.g. ${BOLD}4${NC}). Accept: ${BOLD}Enter${NC}. All: ${BOLD}a${NC}"
        }

        # ─── Phase 1.4: ANSI escapes instead of tput ───
        MENU_LINES=14
        draw_menu

        while true; do
            echo -ne "  > "
            if ! read -r choice < /dev/tty 2>/dev/null; then
                # Can't read from tty, use all defaults
                break
            fi

            case "$choice" in
                "")
                    break
                    ;;
                a|A)
                    en_1=1; en_2=1; en_3=1; en_4=1; en_5=1; en_6=1; en_7=1; en_8=1; en_9=1
                    # Redraw using ANSI escapes (Phase 1.4)
                    for _ in $(seq 1 $((MENU_LINES + 1))); do
                        printf '\033[A\033[2K' 2>/dev/null || true
                    done
                    draw_menu
                    ;;
                [1-9])
                    toggle "$choice"
                    for _ in $(seq 1 $((MENU_LINES + 1))); do
                        printf '\033[A\033[2K' 2>/dev/null || true
                    done
                    draw_menu
                    ;;
                *)
                    echo -e "  ${YELLOW}Enter 1-9, 'a' for all, or Enter to confirm${NC}"
                    ;;
            esac
        done

        # Build selected modules string
        result=""
        for i in 1 2 3 4 5 6 7 8 9; do
            if [ "$(get_en "$i")" -eq 1 ]; then
                name=$(get_mod_name "$i")
                if [ -n "$result" ]; then
                    result="$result,$name"
                else
                    result="$name"
                fi
            fi
        done
        SELECTED_MODULES="$result"

        # Optional second line: pick which enabled modules drop to row 2
        echo ""
        echo -ne "  ${BOLD}Second line?${NC} numbers for line 2 (e.g. 3 4 6), or Enter for one line: "
        if read -r l2_choice < /dev/tty 2>/dev/null && [ -n "$l2_choice" ]; then
            l2_result=""
            for tok in $l2_choice; do
                case "$tok" in
                    [1-9])
                        if [ "$(get_en "$tok")" -eq 1 ]; then
                            n=$(get_mod_name "$tok")
                            if [ -n "$l2_result" ]; then l2_result="$l2_result,$n"; else l2_result="$n"; fi
                        fi
                        ;;
                esac
            done
            LINE2_MODULES="$l2_result"
        fi
    else
        # Non-interactive, no flags: default all
        SELECTED_MODULES="directory,model,context,usage,git"
    fi
fi

# Explicit --line2 flag wins over (or supplies, in non-interactive mode) the second row
[ -n "$LINE2_ARG" ] && LINE2_MODULES="$LINE2_ARG"

# Fallback
if [ -z "$SELECTED_MODULES" ]; then
    SELECTED_MODULES="directory,model,context,usage,git"
fi

echo ""
info "Selected modules: $(echo "$SELECTED_MODULES" | tr ',' ' ')"

# ─── Step — Link statusline script ───

step "Linking statusline script..."

link_ok=false
if [ -L "$script_dest" ]; then
    # Already a symlink — check where it points
    current_target="$(readlink "$script_dest" 2>/dev/null || true)"
    if [ "$current_target" = "$SOURCE_SCRIPT" ]; then
        ok "Already linked to this repo — nothing to relink"
        link_ok=true
    else
        warn "Existing symlink points elsewhere: $current_target"
        rm -f "$script_dest"
    fi
elif [ -e "$script_dest" ]; then
    # A real file is in the way
    if [ "$FORCE" = true ]; then
        mv "$script_dest" "$script_dest.backup"
        info "Backed up existing script to $script_dest.backup"
    else
        # Preserve the file as a backup anyway — symlink is the new source of truth
        mv "$script_dest" "$script_dest.backup"
        warn "Replaced existing file (backup at $script_dest.backup) — use git to track future changes"
    fi
fi

if [ "$link_ok" = false ]; then
    ln -s "$SOURCE_SCRIPT" "$script_dest"
    track_file "$script_dest"
    ok "Symlinked $script_dest -> $SOURCE_SCRIPT"
fi

# ─── Step — Write module config ───

step "Writing module configuration..."

# Build config. Modules in LINE2_MODULES go under "modules_line2" (row 2);
# the rest stay under "modules" (row 1). Without a second row, only "modules".
modules_json=$(jq -n \
    --arg sel "$SELECTED_MODULES" \
    --arg l2 "$LINE2_MODULES" '
    ($sel | split(",") | map(select(length > 0))) as $all
    | ($l2  | split(",") | map(select(length > 0))) as $two
    | ($two | map(select(. as $m | $all | index($m)))) as $two_valid
    | { modules: ($all - $two_valid) }
      + (if ($two_valid | length) > 0 then { modules_line2: $two_valid } else {} end)
')
echo "$modules_json" > "$statusline_config"
track_file "$statusline_config"
if echo "$modules_json" | jq -e '.modules_line2' >/dev/null 2>&1; then
    ok "Module config saved to $statusline_config (two-line layout)"
else
    ok "Module config saved to $statusline_config"
fi

# ─── Step — Configure settings.json ───

step "Configuring settings.json..."

statusline_setting="{\"type\":\"command\",\"command\":\"bash $script_dest\"}"

if [ -f "$settings_file" ]; then
    existing=$(jq -r '.statusLine // empty' "$settings_file" 2>/dev/null)
    if [ -n "$existing" ] && [ "$FORCE" = false ]; then
        info "statusLine already configured in settings.json (use --force to overwrite)"
    else
        cp "$settings_file" "$settings_file.backup"
        info "Backed up settings.json to settings.json.backup"
        jq --argjson sl "$statusline_setting" '.statusLine = $sl' "$settings_file.backup" > "$settings_file"
        track_file "$settings_file"
        ok "Updated settings.json with statusLine configuration"
    fi
else
    jq -n --argjson sl "$statusline_setting" '{statusLine: $sl}' > "$settings_file"
    track_file "$settings_file"
    ok "Created settings.json with statusLine configuration"
fi

# ─── Step — Done ───

step "Finishing up..."

# ─── Phase 3.2: Claude Code process detection ───
if command -v pgrep >/dev/null 2>&1; then
    if pgrep -f "claude" >/dev/null 2>&1 || pgrep -x "claude" >/dev/null 2>&1; then
        echo ""
        warn "${BOLD}Claude Code appears to be running.${NC}"
        warn "Restart Claude Code for changes to take effect."
    fi
fi

INSTALL_SUCCESS=true

echo ""
echo -e "${GREEN}ccvitals v${STATUSLINE_VERSION} installed successfully!${NC}"
echo ""
echo "  What was installed:"
echo "    Script:   $script_dest (symlink -> $SOURCE_SCRIPT)"
echo "    Config:   $statusline_config"
echo "    Settings: $settings_file (statusLine key)"
echo ""
echo "  Enabled modules: $(echo "$SELECTED_MODULES" | tr ',' ' ')"
echo ""
echo "  To update later:   cd $REPO_DIR && git pull"
echo "  To change modules: re-run ./install.sh --force or edit $statusline_config"
echo ""
echo "  Restart Claude Code to see the statusline."
echo ""
echo "  To uninstall:      ./uninstall.sh"
echo ""
