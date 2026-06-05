#!/usr/bin/env bats

# Tests for install.sh
# Validates flags, module configuration, settings.json handling, and update mode.

setup() {
    load 'test_helper/common-setup'
    _common_setup

    INSTALLER="$PROJECT_ROOT/install.sh"

    # Mock curl: instead of downloading from GitHub, copy local statusline.sh
    create_mock "curl" "
        # Parse the -o flag to find the output file
        out_file=\"\"
        for arg in \"\$@\"; do
            if [ -n \"\$next_is_out\" ]; then
                out_file=\"\$arg\"
                next_is_out=\"\"
                continue
            fi
            case \"\$arg\" in
                -o) next_is_out=1 ;;
            esac
        done
        if [ -n \"\$out_file\" ]; then
            cp \"$PROJECT_ROOT/statusline.sh\" \"\$out_file\"
        fi
        exit 0
    "

    # Mock pgrep to not detect running claude processes
    create_mock "pgrep" 'exit 1'
}

# ─── Help and version flags ───

@test "install: --help prints usage and exits 0" {
    run bash "$INSTALLER" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
    [[ "$output" == *"--force"* ]]
    [[ "$output" == *"--modules"* ]]
}

@test "install: -h also prints help" {
    run bash "$INSTALLER" -h
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "install: --version prints version and exits 0" {
    run bash "$INSTALLER" --version
    [ "$status" -eq 0 ]
    [[ "$output" == *"ccvitals v"* ]]
}

@test "install: --help takes priority over other flags" {
    # --help should print help and exit, regardless of other flags
    run bash "$INSTALLER" --force --help --all
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
}

# ─── Module configuration ───

@test "install: --modules=model,context creates correct config JSON" {
    run bash "$INSTALLER" --modules=model,context
    [ "$status" -eq 0 ]

    # Verify config file exists and has correct modules
    [ -f "$CLAUDE_CONFIG_DIR/.statusline-config.json" ]
    local modules
    modules=$(jq -r '.modules | sort | join(",")' "$CLAUDE_CONFIG_DIR/.statusline-config.json")
    [ "$modules" = "context,model" ]
}

@test "install: --all creates config with all 28 modules" {
    run bash "$INSTALLER" --all
    [ "$status" -eq 0 ]

    [ -f "$CLAUDE_CONFIG_DIR/.statusline-config.json" ]
    local count
    count=$(jq '.modules | length' "$CLAUDE_CONFIG_DIR/.statusline-config.json")
    [ "$count" -eq 28 ]

    # Verify all module names are present (core + tool/session/new modules)
    local modules
    modules=$(jq -r '.modules | sort | join(",")' "$CLAUDE_CONFIG_DIR/.statusline-config.json")
    [ "$modules" = "agent,agents,cache,codegraph,compactions,context,cost,daily,directory,duration,git,lines,mcp,mode,model,pace,pr,rtk,speed,spend,thinking,todos,tokens,tools,usage,vim,weekly,workflows" ]
}

@test "install: --line2 splits modules into a second row" {
    run bash "$INSTALLER" --modules=model,context,git --line2=context
    [ "$status" -eq 0 ]

    local line1 line2
    line1=$(jq -r '.modules | sort | join(",")' "$CLAUDE_CONFIG_DIR/.statusline-config.json")
    line2=$(jq -r '.modules_line2 | sort | join(",")' "$CLAUDE_CONFIG_DIR/.statusline-config.json")
    [ "$line1" = "git,model" ]
    [ "$line2" = "context" ]
}

@test "install: without --line2 no modules_line2 key is written" {
    run bash "$INSTALLER" --modules=model,git
    [ "$status" -eq 0 ]
    run jq -e '.modules_line2' "$CLAUDE_CONFIG_DIR/.statusline-config.json"
    [ "$status" -ne 0 ]
}

# ─── Settings.json handling ───

@test "install: fresh install creates settings.json with statusLine key" {
    run bash "$INSTALLER" --all
    [ "$status" -eq 0 ]

    [ -f "$CLAUDE_CONFIG_DIR/settings.json" ]
    local sl_type
    sl_type=$(jq -r '.statusLine.type' "$CLAUDE_CONFIG_DIR/settings.json")
    [ "$sl_type" = "command" ]
}

@test "install: preserves existing keys in settings.json" {
    # Create pre-existing settings.json with a custom key
    mkdir -p "$CLAUDE_CONFIG_DIR"
    echo '{"customKey": "customValue", "anotherKey": 42}' > "$CLAUDE_CONFIG_DIR/settings.json"

    run bash "$INSTALLER" --all --force
    [ "$status" -eq 0 ]

    # statusLine should be added
    local sl_type
    sl_type=$(jq -r '.statusLine.type' "$CLAUDE_CONFIG_DIR/settings.json")
    [ "$sl_type" = "command" ]

    # Original keys should be preserved
    local custom
    custom=$(jq -r '.customKey' "$CLAUDE_CONFIG_DIR/settings.json")
    [ "$custom" = "customValue" ]

    local another
    another=$(jq -r '.anotherKey' "$CLAUDE_CONFIG_DIR/settings.json")
    [ "$another" = "42" ]
}

@test "install: backup is created when modifying existing settings.json" {
    mkdir -p "$CLAUDE_CONFIG_DIR"
    echo '{"existingKey": true}' > "$CLAUDE_CONFIG_DIR/settings.json"

    run bash "$INSTALLER" --all --force
    [ "$status" -eq 0 ]

    # Backup file should exist
    [ -f "$CLAUDE_CONFIG_DIR/settings.json.backup" ]
}

# ─── Force and skip behavior ───

@test "install: --force overwrites existing script" {
    mkdir -p "$CLAUDE_CONFIG_DIR"
    echo "old-content" > "$CLAUDE_CONFIG_DIR/statusline-command.sh"

    run bash "$INSTALLER" --all --force
    [ "$status" -eq 0 ]

    # Script should be overwritten (no longer "old-content")
    local content
    content=$(head -1 "$CLAUDE_CONFIG_DIR/statusline-command.sh")
    [[ "$content" == "#!/usr/bin/env bash" ]]
}

@test "install: existing real file is backed up and replaced with a symlink" {
    mkdir -p "$CLAUDE_CONFIG_DIR"
    echo "original-content" > "$CLAUDE_CONFIG_DIR/statusline-command.sh"

    run bash "$INSTALLER" --all
    [ "$status" -eq 0 ]

    # The installed path is now a symlink into the repo
    [ -L "$CLAUDE_CONFIG_DIR/statusline-command.sh" ]

    # The displaced file is preserved as a backup
    [ -f "$CLAUDE_CONFIG_DIR/statusline-command.sh.backup" ]
    local backup
    backup=$(cat "$CLAUDE_CONFIG_DIR/statusline-command.sh.backup")
    [ "$backup" = "original-content" ]

    [[ "$output" == *"backup"* ]]
}

# ─── Idempotency (symlink workflow) ───

@test "install: re-running detects the existing symlink and relinks cleanly" {
    # First install creates the symlink
    run bash "$INSTALLER" --all
    [ "$status" -eq 0 ]
    [ -L "$CLAUDE_CONFIG_DIR/statusline-command.sh" ]

    # Second run detects the correct symlink and leaves it in place
    run bash "$INSTALLER" --all
    [ "$status" -eq 0 ]
    [ -L "$CLAUDE_CONFIG_DIR/statusline-command.sh" ]
    [[ "$output" == *"Already linked"* ]]

    # No spurious backup is created on the idempotent run
    [ ! -f "$CLAUDE_CONFIG_DIR/statusline-command.sh.backup" ]
}

# ─── NO_COLOR ───

@test "install: NO_COLOR=1 produces output without ANSI escape codes" {
    run env NO_COLOR=1 bash "$INSTALLER" --all
    [ "$status" -eq 0 ]

    # Output should not contain the ESC character (0x1b) used in ANSI sequences.
    # Use printf to produce a literal ESC byte and check it does not appear.
    local esc
    esc=$(printf '\033')
    [[ "$output" != *"$esc"* ]]
}

# ─── Single module ───

@test "install: --modules=git creates config with only git" {
    run bash "$INSTALLER" --modules=git
    [ "$status" -eq 0 ]

    [ -f "$CLAUDE_CONFIG_DIR/.statusline-config.json" ]
    local count
    count=$(jq '.modules | length' "$CLAUDE_CONFIG_DIR/.statusline-config.json")
    [ "$count" -eq 1 ]

    local module
    module=$(jq -r '.modules[0]' "$CLAUDE_CONFIG_DIR/.statusline-config.json")
    [ "$module" = "git" ]
}

# ─── Script is executable ───

@test "install: installed script is executable" {
    run bash "$INSTALLER" --all --force
    [ "$status" -eq 0 ]

    [ -x "$CLAUDE_CONFIG_DIR/statusline-command.sh" ]
}

# ─── Success message ───

@test "install: success message shows installed paths" {
    run bash "$INSTALLER" --all
    [ "$status" -eq 0 ]

    [[ "$output" == *"installed successfully"* ]]
    [[ "$output" == *"statusline-command.sh"* ]]
    [[ "$output" == *".statusline-config.json"* ]]
    [[ "$output" == *"settings.json"* ]]
}

# ─── Specific module selection ───

@test "install: --modules=pace,cache writes exactly those two modules" {
    run bash "$INSTALLER" --modules=pace,cache
    [ "$status" -eq 0 ]

    [ -f "$CLAUDE_CONFIG_DIR/.statusline-config.json" ]
    local count
    count=$(jq '.modules | length' "$CLAUDE_CONFIG_DIR/.statusline-config.json")
    [ "$count" -eq 2 ]
    local modules
    modules=$(jq -r '.modules | sort | join(",")' "$CLAUDE_CONFIG_DIR/.statusline-config.json")
    [ "$modules" = "cache,pace" ]
}

@test "install: --line2 subset moves those modules to modules_line2 from line1" {
    # All 3 in --modules; 2 of them go to line2. line1 should have only the 1 remainder.
    run bash "$INSTALLER" --modules=model,context,git --line2=model,context
    [ "$status" -eq 0 ]

    local line1 line2
    line1=$(jq -r '.modules | sort | join(",")' "$CLAUDE_CONFIG_DIR/.statusline-config.json")
    line2=$(jq -r '.modules_line2 | sort | join(",")' "$CLAUDE_CONFIG_DIR/.statusline-config.json")
    [ "$line1" = "git" ]
    [ "$line2" = "context,model" ]
}

@test "install: --modules with unknown module name warns and drops it" {
    run bash "$INSTALLER" --modules=model,unknownmodulexyz
    [ "$status" -eq 0 ]
    [ -f "$CLAUDE_CONFIG_DIR/.statusline-config.json" ]
    # Known module kept, unknown dropped with a warning
    local modules
    modules=$(jq -r '.modules | sort | join(",")' "$CLAUDE_CONFIG_DIR/.statusline-config.json")
    [[ "$modules" == *"model"* ]]
    [[ "$modules" != *"unknownmodulexyz"* ]]
    [[ "$output" == *"Unknown module"* ]]
}

@test "install: --force overwrites existing .statusline-config.json" {
    # Create existing config with different modules
    mkdir -p "$CLAUDE_CONFIG_DIR"
    echo '{"modules":["model"]}' > "$CLAUDE_CONFIG_DIR/.statusline-config.json"

    run bash "$INSTALLER" --force --modules=context,git
    [ "$status" -eq 0 ]

    # Config should now have the new modules, not the old one
    local modules
    modules=$(jq -r '.modules | sort | join(",")' "$CLAUDE_CONFIG_DIR/.statusline-config.json")
    [ "$modules" = "context,git" ]
}

@test "install: --force overwrites existing statusLine in settings.json" {
    mkdir -p "$CLAUDE_CONFIG_DIR"
    echo '{"statusLine":{"type":"command","command":"old-command"},"keep":"me"}' \
        > "$CLAUDE_CONFIG_DIR/settings.json"

    run bash "$INSTALLER" --force --all
    [ "$status" -eq 0 ]

    # statusLine command should now reference the new script
    local cmd
    cmd=$(jq -r '.statusLine.command' "$CLAUDE_CONFIG_DIR/settings.json")
    [[ "$cmd" == *"statusline-command.sh"* ]]
    # Other keys preserved
    local keep
    keep=$(jq -r '.keep' "$CLAUDE_CONFIG_DIR/settings.json")
    [ "$keep" = "me" ]
}
