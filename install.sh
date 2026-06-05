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

STATUSLINE_VERSION="1.11.0"

SCRIPT_NAME="statusline-command.sh"
SUBAGENT_SCRIPT_NAME="subagent-statusline.sh"

# Repo this installer lives in (statusline.sh sits next to it)
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd -P)"
SOURCE_SCRIPT="$REPO_DIR/statusline.sh"
SOURCE_SUBAGENT_SCRIPT="$REPO_DIR/subagent-statusline.sh"

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
MOD_DESC_10="Session cost   \$0.42"
MOD_DESC_11="Session time   1h23m"
MOD_DESC_12="Token speed    42 tok/s"
MOD_DESC_13="Vim mode       N / I / V / VL"
MOD_DESC_14="Agent name     @ my-agent"
MOD_DESC_15="PR status      PR #123 approved"
MOD_DESC_16="Weekly quota   7d: ████░░░░░░ 38% 4d2h"
MOD_DESC_17="Pace           pace +12%"
MOD_DESC_18="Cache TTL      cache 4m12s"
MOD_DESC_19="Tools in-flight  ⚒ Bash +2"
MOD_DESC_20="Agents running   ◉ code-reviewer"
MOD_DESC_21="Todos            ☑ 3/7"
MOD_DESC_22="Daily budget     Σ \$4.20"
MOD_DESC_23="Compactions      ↯ 2"
MOD_DESC_24="Session tokens   ⇅ 1.2M/45k"
MOD_DESC_25="Thinking effort  ✦ xhigh"
MOD_DESC_26="MCP servers      ⬡ 4"
MOD_DESC_27="Historical spend  7d \$12.40 · 30d \$48"
MOD_DESC_28="Workflows        ⟳ 1 wf"
MOD_DESC_29="Session title    § my-refactor"

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
        1)  echo "$MOD_DESC_1"  ;; 2)  echo "$MOD_DESC_2"  ;; 3)  echo "$MOD_DESC_3"  ;;
        4)  echo "$MOD_DESC_4"  ;; 5)  echo "$MOD_DESC_5"  ;; 6)  echo "$MOD_DESC_6"  ;;
        7)  echo "$MOD_DESC_7"  ;; 8)  echo "$MOD_DESC_8"  ;; 9)  echo "$MOD_DESC_9"  ;;
        10) echo "$MOD_DESC_10" ;; 11) echo "$MOD_DESC_11" ;; 12) echo "$MOD_DESC_12" ;;
        13) echo "$MOD_DESC_13" ;; 14) echo "$MOD_DESC_14" ;; 15) echo "$MOD_DESC_15" ;;
        16) echo "$MOD_DESC_16" ;; 17) echo "$MOD_DESC_17" ;; 18) echo "$MOD_DESC_18" ;;
        19) echo "$MOD_DESC_19" ;; 20) echo "$MOD_DESC_20" ;; 21) echo "$MOD_DESC_21" ;;
        22) echo "$MOD_DESC_22" ;; 23) echo "$MOD_DESC_23" ;; 24) echo "$MOD_DESC_24" ;;
        25) echo "$MOD_DESC_25" ;; 26) echo "$MOD_DESC_26" ;;
        27) echo "$MOD_DESC_27" ;; 28) echo "$MOD_DESC_28" ;;
        29) echo "$MOD_DESC_29" ;;
    esac
}

get_mod_name() {
    case "$1" in
        1)  echo "directory" ;; 2)  echo "model"    ;; 3)  echo "context" ;;
        4)  echo "usage"     ;; 5)  echo "git"      ;; 6)  echo "rtk"     ;;
        7)  echo "codegraph" ;; 8)  echo "lines"    ;; 9)  echo "mode"    ;;
        10) echo "cost"      ;; 11) echo "duration" ;; 12) echo "speed"   ;;
        13) echo "vim"       ;; 14) echo "agent"    ;; 15) echo "pr"      ;;
        16) echo "weekly"    ;; 17) echo "pace"     ;; 18) echo "cache"   ;;
        19) echo "tools"     ;; 20) echo "agents"   ;; 21) echo "todos"   ;;
        22) echo "daily"     ;; 23) echo "compactions" ;; 24) echo "tokens" ;;
        25) echo "thinking"  ;; 26) echo "mcp" ;;
        27) echo "spend"     ;; 28) echo "workflows" ;;
        29) echo "session" ;;
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
                     codegraph, lines, mode, cost, duration, speed, vim,
                     agent, pr, weekly, pace, cache, tools, agents, todos,
                     daily, compactions, tokens,
                     thinking, mcp, spend, workflows, session
  --line2=LIST       Render these modules on a second row (comma-separated).
                     They are placed in modules_line2; the rest stay on line 1.
  --hooks            Register ccvitals-hook.sh in settings.json hooks
                     (SessionStart, MessageDisplay, TaskCreated, PostCompact, Stop)
                     Required for the session module and future hook-powered features.

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
  cost         Show session cost in USD (e.g. $0.42)
  duration     Show session wall-clock time (e.g. 1h23m)
  speed        Show token throughput (e.g. 42 tok/s)
  vim          Show vim mode indicator (N/I/V/VL)
  agent        Show active agent name
  pr           Show linked PR number and review state
  weekly       Show 7-day quota bar with reset countdown
  pace         Show burn-rate vs quota window (pace +12%)
  cache        Show prompt-cache freshness countdown
  tools        Show tools currently in flight (⚒ Bash +2)
  agents       Show active sub-agents (◉ code-reviewer)
  todos        Show latest TodoWrite progress (☑ 3/7)
  daily        Show cross-session daily spend (Σ \$4.20); opt-in
  compactions  Show compact_boundary count (↯ 2); opt-in
  tokens       Show cumulative session input/output tokens (⇅ 1.2M/45k); opt-in
  thinking     Show reasoning effort level with an icon (✦ xhigh); opt-in
  mcp          Show configured MCP server count (⬡ 4); opt-in
  spend        Show 7-day and 30-day historical spend (7d \$12.40 · 30d \$48); opt-in
  workflows    Show running Workflow orchestrations (⟳ 1 wf); opt-in
  session      Show session title from hooks (§ my-refactor); requires --hooks; opt-in

Hooks integration (opt-in):
  ./install.sh --hooks         wire up ccvitals-hook.sh into settings.json hooks
  ./uninstall.sh               removes hook entries written by ccvitals

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
INSTALL_HOOKS=false

for arg in "$@"; do
    case "$arg" in
        --help|-h) show_help ;;
        --force)   FORCE=true ;;
        --all)     SKIP_MENU=true; MODULES_ARG="directory,model,context,usage,git,rtk,codegraph,lines,mode,cost,duration,speed,vim,agent,pr,weekly,pace,cache,tools,agents,todos,daily,compactions,tokens,thinking,mcp,spend,workflows,session" ;;
        --modules=*) SKIP_MENU=true; MODULES_ARG="${arg#--modules=}" ;;
        --line2=*) LINE2_ARG="${arg#--line2=}" ;;
        --hooks)   INSTALL_HOOKS=true ;;
        --version) echo "ccvitals v$STATUSLINE_VERSION"; exit 0 ;;
    esac
done

# ─── Phase 1.3: Step counter ───

CURRENT_STEP=0
TOTAL_STEPS=6
[ "$INSTALL_HOOKS" = true ] && TOTAL_STEPS=7

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
subagent_script_dest="$config_dir/$SUBAGENT_SCRIPT_NAME"
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
    # From --modules or --all flag — drop unknown module names with a warning
    KNOWN_MODULES=" directory model context usage git rtk codegraph lines mode cost duration speed vim agent pr weekly pace cache tools agents todos daily compactions tokens thinking mcp spend workflows session "
    VALIDATED=""
    OLD_IFS="$IFS"; IFS=','
    for m in $MODULES_ARG; do
        case "$KNOWN_MODULES" in
            *" $m "*) VALIDATED="${VALIDATED:+$VALIDATED,}$m" ;;
            *) warn "Unknown module '$m' — skipping" ;;
        esac
    done
    IFS="$OLD_IFS"
    SELECTED_MODULES="$VALIDATED"
elif [ "$SKIP_MENU" = false ]; then
    # Try interactive menu
    CAN_INTERACT=false
    if [ -e /dev/tty ]; then
        CAN_INTERACT=true
    elif [ -t 0 ]; then
        CAN_INTERACT=true
    fi

    if [ "$CAN_INTERACT" = true ]; then
        # Track enabled state: 1=on, 0=off. Core modules on, tool/opt-in modules off.
        en_1=1; en_2=1; en_3=1; en_4=1; en_5=1
        en_6=0; en_7=0; en_8=0; en_9=0
        en_10=0; en_11=0; en_12=0; en_13=0; en_14=0; en_15=0; en_16=0
        en_17=0; en_18=0; en_19=0; en_20=0; en_21=0
        en_22=0; en_23=0; en_24=0
        en_25=0; en_26=0; en_27=0; en_28=0; en_29=0

        get_en() {
            case "$1" in
                1)  echo "$en_1"  ;; 2)  echo "$en_2"  ;; 3)  echo "$en_3"  ;;
                4)  echo "$en_4"  ;; 5)  echo "$en_5"  ;; 6)  echo "$en_6"  ;;
                7)  echo "$en_7"  ;; 8)  echo "$en_8"  ;; 9)  echo "$en_9"  ;;
                10) echo "$en_10" ;; 11) echo "$en_11" ;; 12) echo "$en_12" ;;
                13) echo "$en_13" ;; 14) echo "$en_14" ;; 15) echo "$en_15" ;;
                16) echo "$en_16" ;; 17) echo "$en_17" ;; 18) echo "$en_18" ;;
                19) echo "$en_19" ;; 20) echo "$en_20" ;; 21) echo "$en_21" ;;
                22) echo "$en_22" ;; 23) echo "$en_23" ;; 24) echo "$en_24" ;;
                25) echo "$en_25" ;; 26) echo "$en_26" ;; 27) echo "$en_27" ;;
                28) echo "$en_28" ;; 29) echo "$en_29" ;;
            esac
        }

        toggle() {
            case "$1" in
                1)  if [ "$en_1"  -eq 1 ]; then en_1=0;  else en_1=1;  fi ;;
                2)  if [ "$en_2"  -eq 1 ]; then en_2=0;  else en_2=1;  fi ;;
                3)  if [ "$en_3"  -eq 1 ]; then en_3=0;  else en_3=1;  fi ;;
                4)  if [ "$en_4"  -eq 1 ]; then en_4=0;  else en_4=1;  fi ;;
                5)  if [ "$en_5"  -eq 1 ]; then en_5=0;  else en_5=1;  fi ;;
                6)  if [ "$en_6"  -eq 1 ]; then en_6=0;  else en_6=1;  fi ;;
                7)  if [ "$en_7"  -eq 1 ]; then en_7=0;  else en_7=1;  fi ;;
                8)  if [ "$en_8"  -eq 1 ]; then en_8=0;  else en_8=1;  fi ;;
                9)  if [ "$en_9"  -eq 1 ]; then en_9=0;  else en_9=1;  fi ;;
                10) if [ "$en_10" -eq 1 ]; then en_10=0; else en_10=1; fi ;;
                11) if [ "$en_11" -eq 1 ]; then en_11=0; else en_11=1; fi ;;
                12) if [ "$en_12" -eq 1 ]; then en_12=0; else en_12=1; fi ;;
                13) if [ "$en_13" -eq 1 ]; then en_13=0; else en_13=1; fi ;;
                14) if [ "$en_14" -eq 1 ]; then en_14=0; else en_14=1; fi ;;
                15) if [ "$en_15" -eq 1 ]; then en_15=0; else en_15=1; fi ;;
                16) if [ "$en_16" -eq 1 ]; then en_16=0; else en_16=1; fi ;;
                17) if [ "$en_17" -eq 1 ]; then en_17=0; else en_17=1; fi ;;
                18) if [ "$en_18" -eq 1 ]; then en_18=0; else en_18=1; fi ;;
                19) if [ "$en_19" -eq 1 ]; then en_19=0; else en_19=1; fi ;;
                20) if [ "$en_20" -eq 1 ]; then en_20=0; else en_20=1; fi ;;
                21) if [ "$en_21" -eq 1 ]; then en_21=0; else en_21=1; fi ;;
                22) if [ "$en_22" -eq 1 ]; then en_22=0; else en_22=1; fi ;;
                23) if [ "$en_23" -eq 1 ]; then en_23=0; else en_23=1; fi ;;
                24) if [ "$en_24" -eq 1 ]; then en_24=0; else en_24=1; fi ;;
                25) if [ "$en_25" -eq 1 ]; then en_25=0; else en_25=1; fi ;;
                26) if [ "$en_26" -eq 1 ]; then en_26=0; else en_26=1; fi ;;
                27) if [ "$en_27" -eq 1 ]; then en_27=0; else en_27=1; fi ;;
                28) if [ "$en_28" -eq 1 ]; then en_28=0; else en_28=1; fi ;;
                29) if [ "$en_29" -eq 1 ]; then en_29=0; else en_29=1; fi ;;
            esac
        }

        draw_menu() {
            echo ""
            echo -e "${BOLD}ccvitals — Choose your modules:${NC}"
            echo ""
            for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29; do
                local desc
                desc=$(get_mod_desc "$i")
                if [ "$(get_en "$i")" -eq 1 ]; then
                    echo -e "  ${GREEN}[x]${NC} ${BOLD}${i})${NC} $desc"
                else
                    echo -e "  ${GRAY}[ ] ${i}) $desc${NC}"
                fi
            done
            echo ""
            echo -e "  Toggle: enter number (e.g. ${BOLD}4${NC}). Accept: ${BOLD}Enter${NC}. All: ${BOLD}a${NC}"
        }

        # ─── Phase 1.4: ANSI escapes instead of tput ───
        MENU_LINES=34
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
                    en_10=1; en_11=1; en_12=1; en_13=1; en_14=1; en_15=1; en_16=1
                    en_17=1; en_18=1; en_19=1; en_20=1; en_21=1
                    en_22=1; en_23=1; en_24=1
                    en_25=1; en_26=1; en_27=1; en_28=1; en_29=1
                    # Redraw using ANSI escapes (Phase 1.4)
                    for _ in $(seq 1 $((MENU_LINES + 1))); do
                        printf '\033[A\033[2K' 2>/dev/null || true
                    done
                    draw_menu
                    ;;
                [1-9]|1[0-9]|2[0-9])
                    toggle "$choice"
                    for _ in $(seq 1 $((MENU_LINES + 1))); do
                        printf '\033[A\033[2K' 2>/dev/null || true
                    done
                    draw_menu
                    ;;
                *)
                    echo -e "  ${YELLOW}Enter 1-29, 'a' for all, or Enter to confirm${NC}"
                    ;;
            esac
        done

        # Build selected modules string
        result=""
        for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29; do
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
                    [1-9]|1[0-9]|2[0-9])
                        if [ "$(get_en "$tok")" -eq 1 ]; then
                            n=$(get_mod_name "$tok")
                            if [ -n "$l2_result" ]; then l2_result="$l2_result,$n"; else l2_result="$n"; fi
                        fi
                        ;;
                esac
            done
            LINE2_MODULES="$l2_result"
        fi

        # Optional: install hooks (requires hook script)
        if [ "$INSTALL_HOOKS" = false ]; then
            echo ""
            echo -ne "  ${BOLD}Hooks integration?${NC} Wire ccvitals-hook.sh for session/turn tracking (y/N): "
            if read -r hooks_choice < /dev/tty 2>/dev/null; then
                case "$hooks_choice" in
                    y|Y|yes|YES) INSTALL_HOOKS=true; TOTAL_STEPS=7 ;;
                esac
            fi
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

# ─── Step — Link subagent statusline script ───

subagent_link_ok=false
if [ -L "$subagent_script_dest" ]; then
    current_subagent_target="$(readlink "$subagent_script_dest" 2>/dev/null || true)"
    if [ "$current_subagent_target" = "$SOURCE_SUBAGENT_SCRIPT" ]; then
        ok "Subagent script already linked to this repo — nothing to relink"
        subagent_link_ok=true
    else
        warn "Existing subagent symlink points elsewhere: $current_subagent_target"
        rm -f "$subagent_script_dest"
    fi
elif [ -e "$subagent_script_dest" ]; then
    mv "$subagent_script_dest" "$subagent_script_dest.backup"
    info "Backed up existing subagent script to $subagent_script_dest.backup"
fi

if [ "$subagent_link_ok" = false ]; then
    ln -s "$SOURCE_SUBAGENT_SCRIPT" "$subagent_script_dest"
    track_file "$subagent_script_dest"
    ok "Symlinked $subagent_script_dest -> $SOURCE_SUBAGENT_SCRIPT"
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
subagent_setting="{\"type\":\"command\",\"command\":\"bash $subagent_script_dest\"}"

if [ -f "$settings_file" ]; then
    existing=$(jq -r '.statusLine // empty' "$settings_file" 2>/dev/null)
    if [ -n "$existing" ] && [ "$FORCE" = false ]; then
        info "statusLine already configured in settings.json (use --force to overwrite)"
    else
        cp "$settings_file" "$settings_file.backup"
        info "Backed up settings.json to settings.json.backup"
        _updated=$(jq --argjson sl "$statusline_setting" --argjson sa "$subagent_setting" \
            '.statusLine = $sl | .subagentStatusLine = $sa' "$settings_file.backup" 2>/dev/null)
        if [ -n "$_updated" ]; then
            printf '%s\n' "$_updated" > "$settings_file"
            track_file "$settings_file"
            ok "Updated settings.json with statusLine and subagentStatusLine configuration"
        else
            warn "settings.json appears malformed (jq error) — skipping statusLine update, file untouched"
            cp "$settings_file.backup" "$settings_file" 2>/dev/null || true
        fi
        unset _updated
    fi
else
    jq -n --argjson sl "$statusline_setting" --argjson sa "$subagent_setting" \
        '{statusLine: $sl, subagentStatusLine: $sa}' > "$settings_file"
    track_file "$settings_file"
    ok "Created settings.json with statusLine and subagentStatusLine configuration"
fi

# ─── Step — Wire hooks (opt-in) ───

if [ "$INSTALL_HOOKS" = true ]; then
    step "Wiring ccvitals hooks into settings.json..."

    HOOK_SCRIPT="$REPO_DIR/ccvitals-hook.sh"
    if [ ! -f "$HOOK_SCRIPT" ]; then
        warn "ccvitals-hook.sh not found at $HOOK_SCRIPT — skipping hooks wiring"
    else
        hook_cmd="bash $HOOK_SCRIPT"

        # Events to register
        hook_events="SessionStart MessageDisplay TaskCreated PostCompact Stop"

        # Build the wrapper group entry: {"hooks":[{"type":"command","command":"<cmd>"}]}
        # This matches Claude Code's actual settings.json hooks schema where each event
        # array contains group objects with an inner "hooks" array.
        wrapper_entry=$(jq -n --arg cmd "$hook_cmd" '{hooks:[{type:"command",command:$cmd}]}')

        if [ -f "$settings_file" ]; then
            cp "$settings_file" "$settings_file.backup"
            info "Backed up settings.json to settings.json.backup"

            # Merge wrapper group into each event's array.
            # Dedup check: an event already has our hook if any existing group's inner
            # .hooks[] contains an entry whose .command matches ours.
            # Preserves all user groups untouched; only appends our group if missing.
            _merged=$(jq \
                --argjson wrapper "$wrapper_entry" \
                --arg cmd "$hook_cmd" \
                --argjson events '["SessionStart","MessageDisplay","TaskCreated","PostCompact","Stop"]' \
                '
                . as $root
                | reduce $events[] as $ev (
                    $root;
                    if (.hooks[$ev] | type) == "array" then
                        if (.hooks[$ev] | map(.hooks[]? | select(.command == $cmd)) | length) > 0 then
                            # Already registered inside a group — leave untouched
                            .
                        else
                            .hooks[$ev] += [$wrapper]
                        end
                    else
                        # No existing array for this event — create it
                        .hooks[$ev] = [$wrapper]
                    end
                  )
                ' "$settings_file.backup" 2>/dev/null)

            if [ -n "$_merged" ]; then
                printf '%s\n' "$_merged" > "$settings_file"
                track_file "$settings_file"
                ok "Registered ccvitals-hook.sh for events: $hook_events"
            else
                warn "Failed to merge hook entries into settings.json (jq error?) — hooks not wired"
                cp "$settings_file.backup" "$settings_file" 2>/dev/null || true
            fi
            unset _merged
        else
            # No settings.json yet — create it with hooks only
            _new=$(jq -n --argjson wrapper "$wrapper_entry" \
                --argjson events '["SessionStart","MessageDisplay","TaskCreated","PostCompact","Stop"]' \
                '
                reduce $events[] as $ev (
                    {};
                    .hooks[$ev] = [$wrapper]
                )
                ' 2>/dev/null)
            if [ -n "$_new" ]; then
                printf '%s\n' "$_new" > "$settings_file"
                track_file "$settings_file"
                ok "Created settings.json with ccvitals hook entries"
            else
                warn "Failed to create settings.json with hook entries (jq error?) — hooks not wired"
            fi
            unset _new
        fi
    fi
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
echo "    Script:         $script_dest (symlink -> $SOURCE_SCRIPT)"
echo "    Subagent script: $subagent_script_dest (symlink -> $SOURCE_SUBAGENT_SCRIPT)"
echo "    Config:         $statusline_config"
echo "    Settings:       $settings_file (statusLine + subagentStatusLine keys)"
if [ "$INSTALL_HOOKS" = true ]; then
echo "    Hooks:          ccvitals-hook.sh wired for SessionStart, MessageDisplay, TaskCreated, PostCompact, Stop"
fi
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
