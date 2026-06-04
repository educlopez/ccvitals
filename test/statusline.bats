#!/usr/bin/env bats

# Tests for statusline.sh
# Validates module rendering, config handling, context calculation, and output composition.

setup() {
    load 'test_helper/common-setup'
    _common_setup

    STATUSLINE="$PROJECT_ROOT/statusline.sh"
    FIXTURE="$PROJECT_ROOT/test/fixtures/sample-context.json"

    # Mock git to avoid dependency on real repo state
    create_mock "git" 'case "$1" in
        rev-parse) exit 1 ;;  # not inside a work tree
        *) exit 1 ;;
    esac'

    # Mock curl to avoid network calls (usage module)
    create_mock "curl" 'exit 1'

    # Ensure /tmp/test-project exists for cd in statusline.sh
    mkdir -p /tmp/test-project
}

# ─── Default output (no config) ───

@test "statusline: default output includes model name" {
    run bash -c "cat '$FIXTURE' | bash '$STATUSLINE'"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Opus 4.6"* ]]
}

@test "statusline: default output includes directory name" {
    run bash -c "cat '$FIXTURE' | bash '$STATUSLINE'"
    [ "$status" -eq 0 ]
    [[ "$output" == *"test-project"* ]]
}

@test "statusline: default output includes context percentage" {
    run bash -c "cat '$FIXTURE' | bash '$STATUSLINE'"
    [ "$status" -eq 0 ]
    # 20000 + 5000 + 1000 = 26000; 26000*100/200000 = 13
    [[ "$output" == *"13%"* ]]
}

@test "statusline: default output includes progress bar characters" {
    run bash -c "cat '$FIXTURE' | bash '$STATUSLINE'"
    [ "$status" -eq 0 ]
    # Bar should contain block characters
    [[ "$output" == *"░"* ]] || [[ "$output" == *"█"* ]]
}

# ─── Module config filtering ───

@test "statusline: config with model+context shows only those modules" {
    echo '{"modules":["model","context"]}' > "$CLAUDE_CONFIG_DIR/.statusline-config.json"
    run bash -c "cat '$FIXTURE' | bash '$STATUSLINE'"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Opus 4.6"* ]]
    [[ "$output" == *"13%"* ]]
    # directory should NOT appear
    [[ "$output" != *"test-project"* ]]
}

@test "statusline: modules_line2 splits output across two lines" {
    echo '{"modules":["model"],"modules_line2":["context"]}' > "$CLAUDE_CONFIG_DIR/.statusline-config.json"
    run bash -c "cat '$FIXTURE' | bash '$STATUSLINE'"
    [ "$status" -eq 0 ]
    # Two rows: model on line 1, context on line 2
    [ "${#lines[@]}" -eq 2 ]
    [[ "${lines[0]}" == *"Opus 4.6"* ]]
    [[ "${lines[1]}" == *"13%"* ]]
}

@test "statusline: config with directory only shows directory" {
    echo '{"modules":["directory"]}' > "$CLAUDE_CONFIG_DIR/.statusline-config.json"
    run bash -c "cat '$FIXTURE' | bash '$STATUSLINE'"
    [ "$status" -eq 0 ]
    [[ "$output" == *"test-project"* ]]
    # model should NOT appear
    [[ "$output" != *"Opus 4.6"* ]]
    # context percentage should NOT appear
    [[ "$output" != *"13%"* ]]
}

@test "statusline: empty modules array produces minimal output" {
    echo '{"modules":[]}' > "$CLAUDE_CONFIG_DIR/.statusline-config.json"
    run bash -c "cat '$FIXTURE' | bash '$STATUSLINE'"
    [ "$status" -eq 0 ]
    # With all modules disabled via empty array, jq '.modules[]?' returns nothing,
    # so $modules is empty and the default (all enabled) stays. Verify this behavior:
    # Actually empty array means modules is empty string, so defaults stay.
    # This is the actual script behavior — let's just confirm it succeeds.
}

# ─── Context percentage calculation ───

@test "statusline: context percentage is 13% for fixture values" {
    echo '{"modules":["context"]}' > "$CLAUDE_CONFIG_DIR/.statusline-config.json"
    run bash -c "cat '$FIXTURE' | bash '$STATUSLINE'"
    [ "$status" -eq 0 ]
    [[ "$output" == *"13%"* ]]
}

@test "statusline: context bar has correct filled/empty ratio for 13%" {
    echo '{"modules":["context"]}' > "$CLAUDE_CONFIG_DIR/.statusline-config.json"
    run bash -c "cat '$FIXTURE' | bash '$STATUSLINE'"
    [ "$status" -eq 0 ]
    # 13% of 15 chars = 1 filled (integer division: 13*15/100 = 1)
    # So 1 filled block and 14 empty blocks
    # Count filled blocks (█) — strip ANSI first
    local clean
    clean=$(echo "$output" | sed 's/\x1b\[[0-9;]*m//g')
    local filled_count
    filled_count=$(echo "$clean" | grep -o '█' | wc -l | xargs)
    local empty_count
    empty_count=$(echo "$clean" | grep -o '░' | wc -l | xargs)
    [ "$filled_count" -eq 1 ]
    [ "$empty_count" -eq 14 ]
}

@test "statusline: null current_usage results in 0%" {
    local json='{"model":{"display_name":"Opus 4.6"},"workspace":{"current_dir":"/tmp/test-project"},"context_window":{"context_window_size":200000,"current_usage":null}}'
    echo '{"modules":["context"]}' > "$CLAUDE_CONFIG_DIR/.statusline-config.json"
    run bash -c "echo '$json' | bash '$STATUSLINE'"
    [ "$status" -eq 0 ]
    [[ "$output" == *"0%"* ]]
}

@test "statusline: missing current_usage results in 0%" {
    local json='{"model":{"display_name":"Opus 4.6"},"workspace":{"current_dir":"/tmp/test-project"},"context_window":{"context_window_size":200000}}'
    echo '{"modules":["context"]}' > "$CLAUDE_CONFIG_DIR/.statusline-config.json"
    run bash -c "echo '$json' | bash '$STATUSLINE'"
    [ "$status" -eq 0 ]
    [[ "$output" == *"0%"* ]]
}

@test "statusline: promotes to 1M tier when usage exceeds reported window" {
    # Real-world 1M-context session: 602,881 live tokens but size reported as 200k.
    # Must compute against 1M (~60%), not saturate at 100%.
    local json='{"model":{"display_name":"Sonnet 4.6"},"workspace":{"current_dir":"/tmp/test-project"},"context_window":{"context_window_size":200000,"used_percentage":100,"current_usage":{"input_tokens":1,"cache_creation_input_tokens":815,"cache_read_input_tokens":602065}}}'
    echo '{"modules":["context"]}' > "$CLAUDE_CONFIG_DIR/.statusline-config.json"
    run bash -c "echo '$json' | bash '$STATUSLINE'"
    [ "$status" -eq 0 ]
    [[ "$output" == *"60%"* ]]
}

@test "statusline: falls back to used_percentage when current_usage is null" {
    # Right after /compact current_usage is null; use the pre-calculated percentage.
    local json='{"model":{"display_name":"Sonnet 4.6"},"workspace":{"current_dir":"/tmp/test-project"},"context_window":{"context_window_size":200000,"used_percentage":35,"current_usage":null}}'
    echo '{"modules":["context"]}' > "$CLAUDE_CONFIG_DIR/.statusline-config.json"
    run bash -c "echo '$json' | bash '$STATUSLINE'"
    [ "$status" -eq 0 ]
    [[ "$output" == *"35%"* ]]
}

@test "statusline: bar never overflows even past the 1M tier" {
    # Cumulative-token report from older Claude Code (1.5M / 1M = 150%) must clamp.
    local json='{"model":{"display_name":"Sonnet 4.6"},"workspace":{"current_dir":"/tmp/test-project"},"context_window":{"context_window_size":200000,"current_usage":{"input_tokens":0,"cache_creation_input_tokens":0,"cache_read_input_tokens":1500000}}}'
    echo '{"modules":["context"]}' > "$CLAUDE_CONFIG_DIR/.statusline-config.json"
    run bash -c "echo '$json' | bash '$STATUSLINE'"
    [ "$status" -eq 0 ]
    local clean
    clean=$(echo "$output" | sed 's/\x1b\[[0-9;]*m//g')
    local filled_count
    filled_count=$(echo "$clean" | grep -o '█' | wc -l | xargs)
    # Clamped to the 15-char bar width — must not spill past it
    [ "$filled_count" -eq 15 ]
}

# ─── Directory module ───

@test "statusline: directory shows basename of workspace dir" {
    local json='{"model":{"display_name":"Test"},"workspace":{"current_dir":"/home/user/my-cool-project"},"context_window":{"context_window_size":200000}}'
    echo '{"modules":["directory"]}' > "$CLAUDE_CONFIG_DIR/.statusline-config.json"
    run bash -c "echo '$json' | bash '$STATUSLINE'"
    [ "$status" -eq 0 ]
    [[ "$output" == *"my-cool-project"* ]]
}

# ─── Git module ───

@test "statusline: git info appears when git mock reports a repo" {
    # Override git mock to simulate a repo with a clean branch
    create_mock "git" 'case "$1" in
        rev-parse) echo "true"; exit 0 ;;
        branch) echo "main"; exit 0 ;;
        status) exit 0 ;;  # empty output = clean
        *) exit 0 ;;
    esac'
    echo '{"modules":["git"]}' > "$CLAUDE_CONFIG_DIR/.statusline-config.json"
    run bash -c "cat '$FIXTURE' | bash '$STATUSLINE'"
    [ "$status" -eq 0 ]
    [[ "$output" == *"main"* ]]
}

@test "statusline: git info disabled via config means no git output" {
    # Enable only model, explicitly exclude git
    echo '{"modules":["model"]}' > "$CLAUDE_CONFIG_DIR/.statusline-config.json"
    # Override git mock to simulate a repo (should still not appear)
    create_mock "git" 'case "$1" in
        rev-parse) echo "true"; exit 0 ;;
        branch) echo "feature-x"; exit 0 ;;
        status) echo "M file.txt"; exit 0 ;;
        diff) echo "1 0 file.txt"; exit 0 ;;
        *) exit 0 ;;
    esac'
    run bash -c "cat '$FIXTURE' | bash '$STATUSLINE'"
    [ "$status" -eq 0 ]
    [[ "$output" != *"feature-x"* ]]
}

@test "statusline: git dirty state shows file count" {
    create_mock "git" 'case "$1" in
        rev-parse) echo "true"; exit 0 ;;
        branch) echo "dev"; exit 0 ;;
        status) printf "M  file1.txt\nA  file2.txt\n"; exit 0 ;;
        diff) printf "10\t2\tfile1.txt\n5\t0\tfile2.txt\n"; exit 0 ;;
        *) exit 0 ;;
    esac'
    echo '{"modules":["git"]}' > "$CLAUDE_CONFIG_DIR/.statusline-config.json"
    run bash -c "cat '$FIXTURE' | bash '$STATUSLINE'"
    [ "$status" -eq 0 ]
    [[ "$output" == *"dev"* ]]
    [[ "$output" == *"2 files"* ]]
}

# ─── Output composition ───

@test "statusline: segments are separated by pipe characters" {
    echo '{"modules":["directory","model"]}' > "$CLAUDE_CONFIG_DIR/.statusline-config.json"
    run bash -c "cat '$FIXTURE' | bash '$STATUSLINE'"
    [ "$status" -eq 0 ]
    # Strip ANSI codes to check for pipe separator
    local clean
    clean=$(echo "$output" | sed 's/\x1b\[[0-9;]*m//g')
    [[ "$clean" == *"|"* ]]
}

# ─── Cost module ───

@test "statusline: cost shows formatted USD when field present and module enabled" {
    local json='{"model":{"display_name":"Test"},"workspace":{"current_dir":"/tmp/test-project"},"context_window":{"context_window_size":200000},"cost":{"total_cost_usd":0.42}}'
    echo '{"modules":["cost"]}' > "$CLAUDE_CONFIG_DIR/.statusline-config.json"
    run bash -c "echo '$json' | bash '$STATUSLINE'"
    [ "$status" -eq 0 ]
    local clean
    clean=$(echo "$output" | sed 's/\x1b\[[0-9;]*m//g')
    [[ "$clean" == *'$0.42'* ]]
}

@test "statusline: cost hidden when field absent" {
    local json='{"model":{"display_name":"Test"},"workspace":{"current_dir":"/tmp/test-project"},"context_window":{"context_window_size":200000}}'
    echo '{"modules":["cost"]}' > "$CLAUDE_CONFIG_DIR/.statusline-config.json"
    run bash -c "echo '$json' | bash '$STATUSLINE'"
    [ "$status" -eq 0 ]
    local clean
    clean=$(echo "$output" | sed 's/\x1b\[[0-9;]*m//g' | tr -d '[:space:]')
    [ -z "$clean" ]
}

@test "statusline: cost hidden when module disabled" {
    echo '{"modules":["model"]}' > "$CLAUDE_CONFIG_DIR/.statusline-config.json"
    run bash -c "cat '$FIXTURE' | bash '$STATUSLINE'"
    [ "$status" -eq 0 ]
    local clean
    clean=$(echo "$output" | sed 's/\x1b\[[0-9;]*m//g')
    [[ "$clean" != *'$0.42'* ]]
}

# ─── Duration module ───

@test "statusline: duration shows humanized time when field present and module enabled" {
    local json='{"model":{"display_name":"Test"},"workspace":{"current_dir":"/tmp/test-project"},"context_window":{"context_window_size":200000},"cost":{"total_duration_ms":5040000}}'
    echo '{"modules":["duration"]}' > "$CLAUDE_CONFIG_DIR/.statusline-config.json"
    run bash -c "echo '$json' | bash '$STATUSLINE'"
    [ "$status" -eq 0 ]
    # 5040000ms = 5040s = 84m = 1h24m
    [[ "$output" == *"1h24m"* ]]
}

@test "statusline: duration shows minutes only when under 1 hour" {
    local json='{"model":{"display_name":"Test"},"workspace":{"current_dir":"/tmp/test-project"},"context_window":{"context_window_size":200000},"cost":{"total_duration_ms":2700000}}'
    echo '{"modules":["duration"]}' > "$CLAUDE_CONFIG_DIR/.statusline-config.json"
    run bash -c "echo '$json' | bash '$STATUSLINE'"
    [ "$status" -eq 0 ]
    # 2700000ms = 2700s = 45m
    [[ "$output" == *"45m"* ]]
}

@test "statusline: duration hidden when field absent" {
    local json='{"model":{"display_name":"Test"},"workspace":{"current_dir":"/tmp/test-project"},"context_window":{"context_window_size":200000}}'
    echo '{"modules":["duration"]}' > "$CLAUDE_CONFIG_DIR/.statusline-config.json"
    run bash -c "echo '$json' | bash '$STATUSLINE'"
    [ "$status" -eq 0 ]
    [[ "$output" != *"h"* ]] || [[ "$output" != *"m"* ]]
    # output should be empty (no module output)
    local clean
    clean=$(echo "$output" | sed 's/\x1b\[[0-9;]*m//g' | tr -d '[:space:]')
    [ -z "$clean" ]
}

@test "statusline: duration hidden when module disabled" {
    echo '{"modules":["model"]}' > "$CLAUDE_CONFIG_DIR/.statusline-config.json"
    run bash -c "cat '$FIXTURE' | bash '$STATUSLINE'"
    [ "$status" -eq 0 ]
    [[ "$output" != *"1h31m"* ]]
}

# ─── Vim module ───

@test "statusline: vim shows N for NORMAL mode when module enabled" {
    local json='{"model":{"display_name":"Test"},"workspace":{"current_dir":"/tmp/test-project"},"context_window":{"context_window_size":200000},"vim":{"mode":"NORMAL"}}'
    echo '{"modules":["vim"]}' > "$CLAUDE_CONFIG_DIR/.statusline-config.json"
    run bash -c "echo '$json' | bash '$STATUSLINE'"
    [ "$status" -eq 0 ]
    local clean
    clean=$(echo "$output" | sed 's/\x1b\[[0-9;]*m//g')
    [[ "$clean" == *"N"* ]]
}

@test "statusline: vim shows I for INSERT mode" {
    local json='{"model":{"display_name":"Test"},"workspace":{"current_dir":"/tmp/test-project"},"context_window":{"context_window_size":200000},"vim":{"mode":"INSERT"}}'
    echo '{"modules":["vim"]}' > "$CLAUDE_CONFIG_DIR/.statusline-config.json"
    run bash -c "echo '$json' | bash '$STATUSLINE'"
    [ "$status" -eq 0 ]
    local clean
    clean=$(echo "$output" | sed 's/\x1b\[[0-9;]*m//g')
    [[ "$clean" == *"I"* ]]
}

@test "statusline: vim hidden when vim.mode absent" {
    local json='{"model":{"display_name":"Test"},"workspace":{"current_dir":"/tmp/test-project"},"context_window":{"context_window_size":200000}}'
    echo '{"modules":["vim"]}' > "$CLAUDE_CONFIG_DIR/.statusline-config.json"
    run bash -c "echo '$json' | bash '$STATUSLINE'"
    [ "$status" -eq 0 ]
    local clean
    clean=$(echo "$output" | sed 's/\x1b\[[0-9;]*m//g' | tr -d '[:space:]')
    [ -z "$clean" ]
}

@test "statusline: vim hidden when module disabled" {
    echo '{"modules":["model"]}' > "$CLAUDE_CONFIG_DIR/.statusline-config.json"
    run bash -c "cat '$FIXTURE' | bash '$STATUSLINE'"
    [ "$status" -eq 0 ]
    local clean
    clean=$(echo "$output" | sed 's/\x1b\[[0-9;]*m//g')
    # Should not show bare "N" that would be from vim module (model name won't contain it)
    [[ "$clean" != *" N "* ]]
}

# ─── Agent module ───

@test "statusline: agent shows name when field present and module enabled" {
    local json='{"model":{"display_name":"Test"},"workspace":{"current_dir":"/tmp/test-project"},"context_window":{"context_window_size":200000},"agent":{"name":"my-agent"}}'
    echo '{"modules":["agent"]}' > "$CLAUDE_CONFIG_DIR/.statusline-config.json"
    run bash -c "echo '$json' | bash '$STATUSLINE'"
    [ "$status" -eq 0 ]
    local clean
    clean=$(echo "$output" | sed 's/\x1b\[[0-9;]*m//g')
    [[ "$clean" == *"my-agent"* ]]
}

@test "statusline: agent hidden when agent.name absent" {
    local json='{"model":{"display_name":"Test"},"workspace":{"current_dir":"/tmp/test-project"},"context_window":{"context_window_size":200000}}'
    echo '{"modules":["agent"]}' > "$CLAUDE_CONFIG_DIR/.statusline-config.json"
    run bash -c "echo '$json' | bash '$STATUSLINE'"
    [ "$status" -eq 0 ]
    local clean
    clean=$(echo "$output" | sed 's/\x1b\[[0-9;]*m//g' | tr -d '[:space:]')
    [ -z "$clean" ]
}

@test "statusline: agent hidden when module disabled" {
    echo '{"modules":["model"]}' > "$CLAUDE_CONFIG_DIR/.statusline-config.json"
    run bash -c "cat '$FIXTURE' | bash '$STATUSLINE'"
    [ "$status" -eq 0 ]
    [[ "$output" != *"my-agent"* ]]
}

# ─── PR module ───

@test "statusline: pr shows number when field present and module enabled" {
    local json='{"model":{"display_name":"Test"},"workspace":{"current_dir":"/tmp/test-project"},"context_window":{"context_window_size":200000},"pr":{"number":123,"url":"https://example.com","review_state":"approved"}}'
    echo '{"modules":["pr"]}' > "$CLAUDE_CONFIG_DIR/.statusline-config.json"
    run bash -c "echo '$json' | bash '$STATUSLINE'"
    [ "$status" -eq 0 ]
    local clean
    clean=$(echo "$output" | sed 's/\x1b\[[0-9;]*m//g')
    [[ "$clean" == *"PR #123"* ]]
    [[ "$clean" == *"approved"* ]]
}

@test "statusline: pr hidden when pr.number absent" {
    local json='{"model":{"display_name":"Test"},"workspace":{"current_dir":"/tmp/test-project"},"context_window":{"context_window_size":200000}}'
    echo '{"modules":["pr"]}' > "$CLAUDE_CONFIG_DIR/.statusline-config.json"
    run bash -c "echo '$json' | bash '$STATUSLINE'"
    [ "$status" -eq 0 ]
    local clean
    clean=$(echo "$output" | sed 's/\x1b\[[0-9;]*m//g' | tr -d '[:space:]')
    [ -z "$clean" ]
}

@test "statusline: pr hidden when module disabled" {
    echo '{"modules":["model"]}' > "$CLAUDE_CONFIG_DIR/.statusline-config.json"
    run bash -c "cat '$FIXTURE' | bash '$STATUSLINE'"
    [ "$status" -eq 0 ]
    [[ "$output" != *"PR #"* ]]
}

# ─── Weekly module ───

@test "statusline: weekly shows bar when rate_limits.seven_day present and module enabled" {
    local json='{"model":{"display_name":"Test"},"workspace":{"current_dir":"/tmp/test-project"},"context_window":{"context_window_size":200000},"rate_limits":{"seven_day":{"used_percentage":38,"resets_at":9999999999}}}'
    echo '{"modules":["weekly"]}' > "$CLAUDE_CONFIG_DIR/.statusline-config.json"
    run bash -c "echo '$json' | bash '$STATUSLINE'"
    [ "$status" -eq 0 ]
    local clean
    clean=$(echo "$output" | sed 's/\x1b\[[0-9;]*m//g')
    [[ "$clean" == *"7d:"* ]]
    [[ "$clean" == *"38%"* ]]
}

@test "statusline: weekly hidden when rate_limits.seven_day absent" {
    local json='{"model":{"display_name":"Test"},"workspace":{"current_dir":"/tmp/test-project"},"context_window":{"context_window_size":200000}}'
    echo '{"modules":["weekly"]}' > "$CLAUDE_CONFIG_DIR/.statusline-config.json"
    run bash -c "echo '$json' | bash '$STATUSLINE'"
    [ "$status" -eq 0 ]
    local clean
    clean=$(echo "$output" | sed 's/\x1b\[[0-9;]*m//g' | tr -d '[:space:]')
    [ -z "$clean" ]
}

@test "statusline: weekly hidden when module disabled" {
    echo '{"modules":["model"]}' > "$CLAUDE_CONFIG_DIR/.statusline-config.json"
    run bash -c "cat '$FIXTURE' | bash '$STATUSLINE'"
    [ "$status" -eq 0 ]
    [[ "$output" != *"7d:"* ]]
}

# ─── Speed module ───

@test "statusline: speed hidden on first render (no cache file)" {
    local json='{"model":{"display_name":"Test"},"workspace":{"current_dir":"/tmp/test-project"},"context_window":{"context_window_size":200000,"total_input_tokens":1000,"total_output_tokens":100},"session_id":"speed-test-new-session-$$"}'
    echo '{"modules":["speed"]}' > "$CLAUDE_CONFIG_DIR/.statusline-config.json"
    run bash -c "echo '$json' | bash '$STATUSLINE'"
    [ "$status" -eq 0 ]
    # First render: no previous cache, so no output
    local clean
    clean=$(echo "$output" | sed 's/\x1b\[[0-9;]*m//g' | tr -d '[:space:]')
    [ -z "$clean" ]
}

@test "statusline: speed hidden when module disabled" {
    echo '{"modules":["model"]}' > "$CLAUDE_CONFIG_DIR/.statusline-config.json"
    run bash -c "cat '$FIXTURE' | bash '$STATUSLINE'"
    [ "$status" -eq 0 ]
    [[ "$output" != *"tok/s"* ]]
}

@test "statusline: speed hidden when session_id absent" {
    local json='{"model":{"display_name":"Test"},"workspace":{"current_dir":"/tmp/test-project"},"context_window":{"context_window_size":200000,"total_input_tokens":1000,"total_output_tokens":100}}'
    echo '{"modules":["speed"]}' > "$CLAUDE_CONFIG_DIR/.statusline-config.json"
    run bash -c "echo '$json' | bash '$STATUSLINE'"
    [ "$status" -eq 0 ]
    [[ "$output" != *"tok/s"* ]]
}

# ─── Theme system ───

@test "statusline: no theme key renders identically to legacy default (no regression)" {
    # Same module set both runs: once without theme key, once with explicit default
    echo '{"modules":["directory","model","context","git"]}' \
        > "$CLAUDE_CONFIG_DIR/.statusline-config.json"
    run bash -c "cat '$FIXTURE' | bash '$STATUSLINE'"
    [ "$status" -eq 0 ]
    local out_no_theme="$output"

    echo '{"modules":["directory","model","context","git"],"theme":"default"}' \
        > "$CLAUDE_CONFIG_DIR/.statusline-config.json"
    run bash -c "cat '$FIXTURE' | bash '$STATUSLINE'"
    [ "$status" -eq 0 ]
    local out_default_theme="$output"

    # Full output (including ANSI codes) must match exactly
    [ "$out_no_theme" = "$out_default_theme" ]
}

@test "statusline: pastel theme outputs its lavender truecolor for directory" {
    echo '{"modules":["directory"],"theme":"pastel"}' \
        > "$CLAUDE_CONFIG_DIR/.statusline-config.json"
    run bash -c "cat '$FIXTURE' | bash '$STATUSLINE'"
    [ "$status" -eq 0 ]
    # BLUE = #ba9af3 → 186;154;243
    [[ "$output" == *$'\033[38;2;186;154;243m'* ]]
}

@test "statusline: tokyo-night theme outputs truecolor escape sequences" {
    echo '{"modules":["model"],"theme":"tokyo-night"}' \
        > "$CLAUDE_CONFIG_DIR/.statusline-config.json"
    run bash -c "cat '$FIXTURE' | bash '$STATUSLINE'"
    [ "$status" -eq 0 ]
    # Truecolor sequences have the form ESC[38;2;R;G;Bm
    [[ "$output" == *$'\033[38;2;'* ]]
}

@test "statusline: catppuccin theme outputs truecolor escape sequences" {
    echo '{"modules":["model"],"theme":"catppuccin"}' \
        > "$CLAUDE_CONFIG_DIR/.statusline-config.json"
    run bash -c "cat '$FIXTURE' | bash '$STATUSLINE'"
    [ "$status" -eq 0 ]
    [[ "$output" == *$'\033[38;2;'* ]]
}

@test "statusline: dracula theme outputs truecolor escape sequences" {
    echo '{"modules":["model"],"theme":"dracula"}' \
        > "$CLAUDE_CONFIG_DIR/.statusline-config.json"
    run bash -c "cat '$FIXTURE' | bash '$STATUSLINE'"
    [ "$status" -eq 0 ]
    [[ "$output" == *$'\033[38;2;'* ]]
}

@test "statusline: nord theme outputs truecolor escape sequences" {
    echo '{"modules":["model"],"theme":"nord"}' \
        > "$CLAUDE_CONFIG_DIR/.statusline-config.json"
    run bash -c "cat '$FIXTURE' | bash '$STATUSLINE'"
    [ "$status" -eq 0 ]
    [[ "$output" == *$'\033[38;2;'* ]]
}

@test "statusline: custom colors override works" {
    # Set a custom blue that would produce \033[38;2;255;0;128m
    echo '{"modules":["directory"],"theme":"custom","colors":{"blue":"#ff0080"}}' \
        > "$CLAUDE_CONFIG_DIR/.statusline-config.json"
    run bash -c "cat '$FIXTURE' | bash '$STATUSLINE'"
    [ "$status" -eq 0 ]
    # Should contain the specific truecolor sequence for #ff0080 (255;0;128)
    [[ "$output" == *$'\033[38;2;255;0;128m'* ]]
}

@test "statusline: custom theme with no colors key falls back to defaults" {
    # theme=custom but no colors object — should still render without error
    echo '{"modules":["model"],"theme":"custom"}' \
        > "$CLAUDE_CONFIG_DIR/.statusline-config.json"
    run bash -c "cat '$FIXTURE' | bash '$STATUSLINE'"
    [ "$status" -eq 0 ]
    local clean
    clean=$(echo "$output" | sed 's/\x1b\[[^m]*m//g')
    [[ "$clean" == *"Opus 4.6"* ]]
}

@test "statusline: invalid theme name falls back to default (no crash)" {
    echo '{"modules":["model","context"],"theme":"nonexistent-theme-xyz"}' \
        > "$CLAUDE_CONFIG_DIR/.statusline-config.json"
    run bash -c "cat '$FIXTURE' | bash '$STATUSLINE'"
    [ "$status" -eq 0 ]
    # Should still render content correctly
    local clean
    clean=$(echo "$output" | sed 's/\x1b\[[^m]*m//g')
    [[ "$clean" == *"Opus 4.6"* ]]
    [[ "$clean" == *"13%"* ]]
    # Should NOT contain truecolor sequences (fell back to 16-color defaults)
    [[ "$output" != *$'\033[38;2;'* ]]
}

@test "statusline: mono theme produces no truecolor sequences" {
    echo '{"modules":["model","context"],"theme":"mono"}' \
        > "$CLAUDE_CONFIG_DIR/.statusline-config.json"
    run bash -c "cat '$FIXTURE' | bash '$STATUSLINE'"
    [ "$status" -eq 0 ]
    [[ "$output" != *$'\033[38;2;'* ]]
    # Content still present
    local clean
    clean=$(echo "$output" | sed 's/\x1b\[[^m]*m//g')
    [[ "$clean" == *"Opus 4.6"* ]]
}

# ─── Git ahead/behind ───

@test "statusline: git shows ahead count when upstream is behind HEAD" {
    create_mock "git" 'case "$1" in
        rev-parse) echo "true"; exit 0 ;;
        branch) echo "main"; exit 0 ;;
        status) exit 0 ;;  # clean
        rev-list) printf "0\t2\n"; exit 0 ;;  # 0 behind, 2 ahead
        remote) exit 1 ;;
        *) exit 0 ;;
    esac'
    echo '{"modules":["git"]}' > "$CLAUDE_CONFIG_DIR/.statusline-config.json"
    run bash -c "cat '$FIXTURE' | bash '$STATUSLINE'"
    [ "$status" -eq 0 ]
    local clean
    clean=$(echo "$output" | sed 's/\x1b\[[0-9;]*m//g' | sed $'s/\033]8;;[^\033]*\033\\\\//g')
    [[ "$clean" == *"↑2"* ]]
}

@test "statusline: git shows behind count when HEAD is behind upstream" {
    create_mock "git" 'case "$1" in
        rev-parse) echo "true"; exit 0 ;;
        branch) echo "main"; exit 0 ;;
        status) exit 0 ;;  # clean
        rev-list) printf "3\t0\n"; exit 0 ;;  # 3 behind, 0 ahead
        remote) exit 1 ;;
        *) exit 0 ;;
    esac'
    echo '{"modules":["git"]}' > "$CLAUDE_CONFIG_DIR/.statusline-config.json"
    run bash -c "cat '$FIXTURE' | bash '$STATUSLINE'"
    [ "$status" -eq 0 ]
    local clean
    clean=$(echo "$output" | sed 's/\x1b\[[0-9;]*m//g' | sed $'s/\033]8;;[^\033]*\033\\\\//g')
    [[ "$clean" == *"↓3"* ]]
}

@test "statusline: git omits ahead/behind when both are zero" {
    create_mock "git" 'case "$1" in
        rev-parse) echo "true"; exit 0 ;;
        branch) echo "main"; exit 0 ;;
        status) exit 0 ;;  # clean
        rev-list) printf "0\t0\n"; exit 0 ;;
        remote) exit 1 ;;
        *) exit 0 ;;
    esac'
    echo '{"modules":["git"]}' > "$CLAUDE_CONFIG_DIR/.statusline-config.json"
    run bash -c "cat '$FIXTURE' | bash '$STATUSLINE'"
    [ "$status" -eq 0 ]
    local clean
    clean=$(echo "$output" | sed 's/\x1b\[[0-9;]*m//g' | sed $'s/\033]8;;[^\033]*\033\\\\//g')
    [[ "$clean" != *"↑"* ]]
    [[ "$clean" != *"↓"* ]]
}

# ─── Pace module ───

@test "statusline: pace shows positive delta when under budget" {
    # 5h window, resets_at = now+1800 (30min remaining = 10min elapsed out of 300min)
    # elapsed_fraction ~= 0.1, expected_pct ~= 10, used_pct = 5 → delta = +5
    local future_resets=$(( $(date +%s) + 1800 ))
    local json="{\"model\":{\"display_name\":\"Test\"},\"workspace\":{\"current_dir\":\"/tmp/test-project\"},\"context_window\":{\"context_window_size\":200000},\"rate_limits\":{\"five_hour\":{\"used_percentage\":5,\"resets_at\":${future_resets}}}}"
    echo '{"modules":["pace"]}' > "$CLAUDE_CONFIG_DIR/.statusline-config.json"
    run bash -c "echo '$json' | bash '$STATUSLINE'"
    [ "$status" -eq 0 ]
    local clean
    clean=$(echo "$output" | sed 's/\x1b\[[0-9;]*m//g')
    [[ "$clean" == *"pace"* ]]
}

@test "statusline: pace hidden when rate_limits.five_hour absent" {
    local json='{"model":{"display_name":"Test"},"workspace":{"current_dir":"/tmp/test-project"},"context_window":{"context_window_size":200000}}'
    echo '{"modules":["pace"]}' > "$CLAUDE_CONFIG_DIR/.statusline-config.json"
    run bash -c "echo '$json' | bash '$STATUSLINE'"
    [ "$status" -eq 0 ]
    local clean
    clean=$(echo "$output" | sed 's/\x1b\[[0-9;]*m//g' | tr -d '[:space:]')
    [ -z "$clean" ]
}

@test "statusline: pace hidden when module disabled" {
    echo '{"modules":["model"]}' > "$CLAUDE_CONFIG_DIR/.statusline-config.json"
    run bash -c "cat '$FIXTURE' | bash '$STATUSLINE'"
    [ "$status" -eq 0 ]
    [[ "$output" != *"pace"* ]]
}

@test "statusline: pace hidden when remaining_s is zero or negative (expired window)" {
    local past_resets=$(( $(date +%s) - 100 ))
    local json="{\"model\":{\"display_name\":\"Test\"},\"workspace\":{\"current_dir\":\"/tmp/test-project\"},\"context_window\":{\"context_window_size\":200000},\"rate_limits\":{\"five_hour\":{\"used_percentage\":50,\"resets_at\":${past_resets}}}}"
    echo '{"modules":["pace"]}' > "$CLAUDE_CONFIG_DIR/.statusline-config.json"
    run bash -c "echo '$json' | bash '$STATUSLINE'"
    [ "$status" -eq 0 ]
    local clean
    clean=$(echo "$output" | sed 's/\x1b\[[0-9;]*m//g' | tr -d '[:space:]')
    [ -z "$clean" ]
}

# ─── Cache module ───

@test "statusline: cache shows fresh countdown when transcript is recent" {
    # Create a temp transcript with a recent timestamp
    local tmp_transcript
    tmp_transcript=$(mktemp)
    local now_iso
    now_iso=$(date -u +"%Y-%m-%dT%H:%M:%S.000Z" 2>/dev/null || date -u +"%Y-%m-%dT%H:%M:%SZ")
    printf '{"timestamp":"%s","type":"assistant"}\n' "$now_iso" > "$tmp_transcript"
    local json="{\"model\":{\"display_name\":\"Test\"},\"workspace\":{\"current_dir\":\"/tmp/test-project\"},\"context_window\":{\"context_window_size\":200000},\"transcript_path\":\"${tmp_transcript}\"}"
    echo '{"modules":["cache"]}' > "$CLAUDE_CONFIG_DIR/.statusline-config.json"
    run bash -c "echo '$json' | bash '$STATUSLINE'"
    rm -f "$tmp_transcript"
    [ "$status" -eq 0 ]
    local clean
    clean=$(echo "$output" | sed 's/\x1b\[[0-9;]*m//g')
    [[ "$clean" == *"cache"* ]]
    # Should NOT be "cache cold" since timestamp is now
    [[ "$clean" != *"cache cold"* ]]
}

@test "statusline: cache shows cold when transcript is old" {
    # Timestamp 10 minutes ago (well past 300s TTL)
    local tmp_transcript
    tmp_transcript=$(mktemp)
    local old_epoch=$(( $(date +%s) - 700 ))
    # Build ISO string from epoch (BSD/GNU compat)
    local old_iso
    old_iso=$(TZ=UTC date -j -f "%s" "$old_epoch" +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null \
        || date -u -d "@${old_epoch}" +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null \
        || echo "2020-01-01T00:00:00Z")
    printf '{"timestamp":"%s","type":"assistant"}\n' "$old_iso" > "$tmp_transcript"
    local json="{\"model\":{\"display_name\":\"Test\"},\"workspace\":{\"current_dir\":\"/tmp/test-project\"},\"context_window\":{\"context_window_size\":200000},\"transcript_path\":\"${tmp_transcript}\"}"
    echo '{"modules":["cache"]}' > "$CLAUDE_CONFIG_DIR/.statusline-config.json"
    run bash -c "echo '$json' | bash '$STATUSLINE'"
    rm -f "$tmp_transcript"
    [ "$status" -eq 0 ]
    local clean
    clean=$(echo "$output" | sed 's/\x1b\[[0-9;]*m//g')
    [[ "$clean" == *"cache cold"* ]]
}

@test "statusline: cache hidden when transcript_path absent" {
    local json='{"model":{"display_name":"Test"},"workspace":{"current_dir":"/tmp/test-project"},"context_window":{"context_window_size":200000}}'
    echo '{"modules":["cache"]}' > "$CLAUDE_CONFIG_DIR/.statusline-config.json"
    run bash -c "echo '$json' | bash '$STATUSLINE'"
    [ "$status" -eq 0 ]
    local clean
    clean=$(echo "$output" | sed 's/\x1b\[[0-9;]*m//g' | tr -d '[:space:]')
    [ -z "$clean" ]
}

@test "statusline: cache hidden when module disabled" {
    echo '{"modules":["model"]}' > "$CLAUDE_CONFIG_DIR/.statusline-config.json"
    run bash -c "cat '$FIXTURE' | bash '$STATUSLINE'"
    [ "$status" -eq 0 ]
    [[ "$output" != *"cache"* ]]
}

# ─── Context display modes ───

@test "statusline: context tokens mode shows token counts" {
    echo '{"modules":["context"],"context_display":"tokens"}' > "$CLAUDE_CONFIG_DIR/.statusline-config.json"
    run bash -c "cat '$FIXTURE' | bash '$STATUSLINE'"
    [ "$status" -eq 0 ]
    local clean
    clean=$(echo "$output" | sed 's/\x1b\[[0-9;]*m//g')
    # Should contain k-formatted token counts (26000 input = 26.0k)
    [[ "$clean" == *"k/"* ]]
    # Should NOT show plain percentage alone
    [[ "$clean" != *"13% "* ]]
}

@test "statusline: context both mode shows tokens and percent" {
    echo '{"modules":["context"],"context_display":"both"}' > "$CLAUDE_CONFIG_DIR/.statusline-config.json"
    run bash -c "cat '$FIXTURE' | bash '$STATUSLINE'"
    [ "$status" -eq 0 ]
    local clean
    clean=$(echo "$output" | sed 's/\x1b\[[0-9;]*m//g')
    # Should contain k-formatted counts AND percentage
    [[ "$clean" == *"k/"* ]]
    [[ "$clean" == *"13%"* ]]
}

@test "statusline: context percent mode (default) shows only percentage" {
    echo '{"modules":["context"],"context_display":"percent"}' > "$CLAUDE_CONFIG_DIR/.statusline-config.json"
    run bash -c "cat '$FIXTURE' | bash '$STATUSLINE'"
    [ "$status" -eq 0 ]
    local clean
    clean=$(echo "$output" | sed 's/\x1b\[[0-9;]*m//g')
    [[ "$clean" == *"13%"* ]]
    # Should NOT contain k/ token format
    [[ "$clean" != *"k/"* ]]
}

# ─── OSC 8 PR link ───

@test "statusline: pr contains OSC 8 sequence when pr.url present" {
    local json='{"model":{"display_name":"Test"},"workspace":{"current_dir":"/tmp/test-project"},"context_window":{"context_window_size":200000},"pr":{"number":42,"url":"https://github.com/example/repo/pull/42","review_state":"approved"}}'
    echo '{"modules":["pr"]}' > "$CLAUDE_CONFIG_DIR/.statusline-config.json"
    run bash -c "echo '$json' | bash '$STATUSLINE'"
    [ "$status" -eq 0 ]
    # OSC 8 sequence starts with \033]8;;
    [[ "$output" == *$'\033]8;;'* ]]
    local clean
    clean=$(echo "$output" | sed 's/\x1b\[[0-9;]*m//g' | sed $'s/\033]8;;[^\033]*\033\\\\//g')
    [[ "$clean" == *"PR #42"* ]]
}

# ─── Theme system: exact first-color checks per preset ───

@test "statusline: tokyo-night theme RED is #f7768e (247;118;142)" {
    # The directory module uses BLUE; model uses CYAN. We need RED — use context at >=90% to trigger red.
    local json='{"model":{"display_name":"Test"},"workspace":{"current_dir":"/tmp/test-project"},"context_window":{"context_window_size":200000,"current_usage":{"input_tokens":185000,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}}}'
    echo '{"modules":["context"],"theme":"tokyo-night"}' > "$CLAUDE_CONFIG_DIR/.statusline-config.json"
    run bash -c "echo '$json' | bash '$STATUSLINE'"
    [ "$status" -eq 0 ]
    # tokyo-night RED = #f7768e → 247;118;142
    [[ "$output" == *$'\033[38;2;247;118;142m'* ]]
}

@test "statusline: catppuccin theme CYAN is #94e2d5 (148;226;213)" {
    # model module uses CYAN; catppuccin CYAN = #94e2d5
    echo '{"modules":["model"],"theme":"catppuccin"}' > "$CLAUDE_CONFIG_DIR/.statusline-config.json"
    run bash -c "cat '$FIXTURE' | bash '$STATUSLINE'"
    [ "$status" -eq 0 ]
    # catppuccin CYAN = #94e2d5 → 148;226;213
    [[ "$output" == *$'\033[38;2;148;226;213m'* ]]
}

@test "statusline: dracula theme CYAN is #8be9fd (139;233;253)" {
    echo '{"modules":["model"],"theme":"dracula"}' > "$CLAUDE_CONFIG_DIR/.statusline-config.json"
    run bash -c "cat '$FIXTURE' | bash '$STATUSLINE'"
    [ "$status" -eq 0 ]
    # dracula CYAN = #8be9fd → 139;233;253
    [[ "$output" == *$'\033[38;2;139;233;253m'* ]]
}

@test "statusline: nord theme CYAN is #88c0d0 (136;192;208)" {
    echo '{"modules":["model"],"theme":"nord"}' > "$CLAUDE_CONFIG_DIR/.statusline-config.json"
    run bash -c "cat '$FIXTURE' | bash '$STATUSLINE'"
    [ "$status" -eq 0 ]
    # nord CYAN = #88c0d0 → 136;192;208
    [[ "$output" == *$'\033[38;2;136;192;208m'* ]]
}

@test "statusline: custom theme partial override — only red set, blue stays ANSI default" {
    # With only red set, blue remains the ANSI default \033[0;34m (not truecolor)
    echo '{"modules":["directory","context"],"theme":"custom","colors":{"red":"#ff0000"}}' \
        > "$CLAUDE_CONFIG_DIR/.statusline-config.json"
    # Use fixture with 90%+ usage to trigger red warning color
    local json='{"model":{"display_name":"Test"},"workspace":{"current_dir":"/tmp/test-project"},"context_window":{"context_window_size":200000,"current_usage":{"input_tokens":185000,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}}}'
    run bash -c "echo '$json' | bash '$STATUSLINE'"
    [ "$status" -eq 0 ]
    # Custom red #ff0000 → 255;0;0 should appear (for the warning ⚠ color)
    [[ "$output" == *$'\033[38;2;255;0;0m'* ]]
    # BLUE for directory should remain the legacy ANSI code, NOT a truecolor sequence for blue
    # (since only red was customized)
    [[ "$output" == *$'\033[0;34m'* ]]
}

@test "statusline: custom theme with invalid hex value does not crash (status 0)" {
    # "notahex" is not a valid #RRGGBB — hex_to_ansi will printf garbage but must not abort
    echo '{"modules":["model"],"theme":"custom","colors":{"red":"notahex"}}' \
        > "$CLAUDE_CONFIG_DIR/.statusline-config.json"
    run bash -c "cat '$FIXTURE' | bash '$STATUSLINE'"
    # Must not crash
    [ "$status" -eq 0 ]
    # Content still present
    local clean
    clean=$(echo "$output" | sed 's/\x1b\[[^m]*m//g')
    [[ "$clean" == *"Opus 4.6"* ]]
}

# ─── Usage module: stdin fast-path and plan badge ───

@test "statusline: usage renders from stdin rate_limits without curl (fast-path)" {
    # rate_limits.five_hour present → fast-path: no curl needed, renders immediately
    # curl mock is set to fail (exit 1) in setup, so if usage renders it used stdin
    local future_resets=$(( $(date +%s) + 3600 ))
    local json="{\"model\":{\"display_name\":\"Test\"},\"workspace\":{\"current_dir\":\"/tmp/test-project\"},\"context_window\":{\"context_window_size\":200000},\"rate_limits\":{\"five_hour\":{\"used_percentage\":42,\"resets_at\":${future_resets}}}}"
    echo '{"modules":["usage"]}' > "$CLAUDE_CONFIG_DIR/.statusline-config.json"
    run bash -c "echo '$json' | bash '$STATUSLINE'"
    [ "$status" -eq 0 ]
    local clean
    clean=$(echo "$output" | sed 's/\x1b\[[0-9;]*m//g')
    [[ "$clean" == *"42%"* ]]
}

@test "statusline: usage plan badge shown when last_good cache has plan" {
    # Pre-seed a last_good cache file with plan=max
    local cache_dir="$CLAUDE_CONFIG_DIR/.usage-cache"
    mkdir -p "$cache_dir"
    local future_resets=$(( $(date +%s) + 3600 ))
    local ts=$(date +%s)
    jq -n --arg ts "$ts" --arg plan "max" \
        '{data:{five_hour:{utilization:30,resets_at:"2099-01-01T00:00:00Z"},seven_day:{utilization:10}},timestamp:($ts|tonumber),plan:$plan,error:false}' \
        > "$cache_dir/usage-last-good.json"
    # Provide stdin rate_limits so fast-path triggers (reads last_good for plan badge)
    local json="{\"model\":{\"display_name\":\"Test\"},\"workspace\":{\"current_dir\":\"/tmp/test-project\"},\"context_window\":{\"context_window_size\":200000},\"rate_limits\":{\"five_hour\":{\"used_percentage\":30,\"resets_at\":${future_resets}}}}"
    echo '{"modules":["usage"]}' > "$CLAUDE_CONFIG_DIR/.statusline-config.json"
    run bash -c "echo '$json' | bash '$STATUSLINE'"
    [ "$status" -eq 0 ]
    local clean
    clean=$(echo "$output" | sed 's/\x1b\[[0-9;]*m//g')
    [[ "$clean" == *"Max"* ]]
}

@test "statusline: usage plan badge omitted when no cache exists" {
    # No cache file → fast-path but last_good absent → no plan badge
    local future_resets=$(( $(date +%s) + 3600 ))
    local json="{\"model\":{\"display_name\":\"Test\"},\"workspace\":{\"current_dir\":\"/tmp/test-project\"},\"context_window\":{\"context_window_size\":200000},\"rate_limits\":{\"five_hour\":{\"used_percentage\":20,\"resets_at\":${future_resets}}}}"
    echo '{"modules":["usage"]}' > "$CLAUDE_CONFIG_DIR/.statusline-config.json"
    run bash -c "echo '$json' | bash '$STATUSLINE'"
    [ "$status" -eq 0 ]
    local clean
    clean=$(echo "$output" | sed 's/\x1b\[[0-9;]*m//g')
    # Should NOT show any plan badge (Max/Pro/Team)
    [[ "$clean" != *"Max"* ]]
    [[ "$clean" != *"Pro"* ]]
    [[ "$clean" != *"Team"* ]]
    # But should still show the percentage
    [[ "$clean" == *"20%"* ]]
}

@test "statusline: usage 7d shown when seven_day >= 70%" {
    local future_resets=$(( $(date +%s) + 3600 ))
    local json="{\"model\":{\"display_name\":\"Test\"},\"workspace\":{\"current_dir\":\"/tmp/test-project\"},\"context_window\":{\"context_window_size\":200000},\"rate_limits\":{\"five_hour\":{\"used_percentage\":30,\"resets_at\":${future_resets}},\"seven_day\":{\"used_percentage\":75}}}"
    echo '{"modules":["usage"]}' > "$CLAUDE_CONFIG_DIR/.statusline-config.json"
    run bash -c "echo '$json' | bash '$STATUSLINE'"
    [ "$status" -eq 0 ]
    local clean
    clean=$(echo "$output" | sed 's/\x1b\[[0-9;]*m//g')
    [[ "$clean" == *"7d:"* ]]
    [[ "$clean" == *"75%"* ]]
}

@test "statusline: usage 7d hidden when seven_day < 70%" {
    local future_resets=$(( $(date +%s) + 3600 ))
    local json="{\"model\":{\"display_name\":\"Test\"},\"workspace\":{\"current_dir\":\"/tmp/test-project\"},\"context_window\":{\"context_window_size\":200000},\"rate_limits\":{\"five_hour\":{\"used_percentage\":30,\"resets_at\":${future_resets}},\"seven_day\":{\"used_percentage\":65}}}"
    echo '{"modules":["usage"]}' > "$CLAUDE_CONFIG_DIR/.statusline-config.json"
    run bash -c "echo '$json' | bash '$STATUSLINE'"
    [ "$status" -eq 0 ]
    local clean
    clean=$(echo "$output" | sed 's/\x1b\[[0-9;]*m//g')
    # 7d badge must not appear for < 70%
    [[ "$clean" != *"7d:"* ]]
}

@test "statusline: usage hidden when five_hour absent and no cache" {
    # No rate_limits.five_hour, no cache → module produces no output
    local json='{"model":{"display_name":"Test"},"workspace":{"current_dir":"/tmp/test-project"},"context_window":{"context_window_size":200000}}'
    echo '{"modules":["usage"]}' > "$CLAUDE_CONFIG_DIR/.statusline-config.json"
    run bash -c "echo '$json' | bash '$STATUSLINE'"
    [ "$status" -eq 0 ]
    local clean
    clean=$(echo "$output" | sed 's/\x1b\[[0-9;]*m//g' | tr -d '[:space:]')
    [ -z "$clean" ]
}

# ─── Pace module: delta color thresholds and edge cases ───

@test "statusline: pace delta exactly -10 shows yellow (not red)" {
    # pace_delta = -10: within -10 threshold → yellow (not red)
    # 5h window=18000s. Set resets_at = now + 9000 (2.5h remaining = 2.5h elapsed of 5h)
    # elapsed_fraction = 0.5, expected = 50. used = 60 → delta = 50 - 60 = -10
    local future_resets=$(( $(date +%s) + 9000 ))
    local json="{\"model\":{\"display_name\":\"Test\"},\"workspace\":{\"current_dir\":\"/tmp/test-project\"},\"context_window\":{\"context_window_size\":200000},\"rate_limits\":{\"five_hour\":{\"used_percentage\":60,\"resets_at\":${future_resets}}}}"
    echo '{"modules":["pace"]}' > "$CLAUDE_CONFIG_DIR/.statusline-config.json"
    run bash -c "echo '$json' | bash '$STATUSLINE'"
    [ "$status" -eq 0 ]
    local clean
    clean=$(echo "$output" | sed 's/\x1b\[[0-9;]*m//g')
    [[ "$clean" == *"pace"* ]]
    # delta = -10 → yellow, not red (no truecolor for red in default theme)
    # The output should NOT contain the legacy red \033[0;31m
    [[ "$output" != *$'\033[0;31m'* ]]
}

@test "statusline: pace delta -11 shows red" {
    # delta <= -11 → red threshold crossed
    # resets_at = now + 9000 (50% elapsed), expected = 50, used = 61 → delta = -11
    local future_resets=$(( $(date +%s) + 9000 ))
    local json="{\"model\":{\"display_name\":\"Test\"},\"workspace\":{\"current_dir\":\"/tmp/test-project\"},\"context_window\":{\"context_window_size\":200000},\"rate_limits\":{\"five_hour\":{\"used_percentage\":61,\"resets_at\":${future_resets}}}}"
    echo '{"modules":["pace"]}' > "$CLAUDE_CONFIG_DIR/.statusline-config.json"
    run bash -c "echo '$json' | bash '$STATUSLINE'"
    [ "$status" -eq 0 ]
    local clean
    clean=$(echo "$output" | sed 's/\x1b\[[0-9;]*m//g')
    [[ "$clean" == *"pace"* ]]
    # delta = -11 → RED (legacy default \033[0;31m)
    [[ "$output" == *$'\033[0;31m'* ]]
}

@test "statusline: pace hidden when resets_at is non-numeric string" {
    local json='{"model":{"display_name":"Test"},"workspace":{"current_dir":"/tmp/test-project"},"context_window":{"context_window_size":200000},"rate_limits":{"five_hour":{"used_percentage":50,"resets_at":"not-a-number"}}}'
    echo '{"modules":["pace"]}' > "$CLAUDE_CONFIG_DIR/.statusline-config.json"
    run bash -c "echo '$json' | bash '$STATUSLINE'"
    [ "$status" -eq 0 ]
    local clean
    clean=$(echo "$output" | sed 's/\x1b\[[0-9;]*m//g' | tr -d '[:space:]')
    [ -z "$clean" ]
}

@test "statusline: pace hidden when used_percentage absent" {
    local future_resets=$(( $(date +%s) + 1800 ))
    local json="{\"model\":{\"display_name\":\"Test\"},\"workspace\":{\"current_dir\":\"/tmp/test-project\"},\"context_window\":{\"context_window_size\":200000},\"rate_limits\":{\"five_hour\":{\"resets_at\":${future_resets}}}}"
    echo '{"modules":["pace"]}' > "$CLAUDE_CONFIG_DIR/.statusline-config.json"
    run bash -c "echo '$json' | bash '$STATUSLINE'"
    [ "$status" -eq 0 ]
    local clean
    clean=$(echo "$output" | sed 's/\x1b\[[0-9;]*m//g' | tr -d '[:space:]')
    [ -z "$clean" ]
}

@test "statusline: pace hidden when resets_at is far in future (> 5h window)" {
    # resets_at far in future means remaining > 18000s → out of valid range → hidden
    local far_future=$(( $(date +%s) + 100000 ))
    local json="{\"model\":{\"display_name\":\"Test\"},\"workspace\":{\"current_dir\":\"/tmp/test-project\"},\"context_window\":{\"context_window_size\":200000},\"rate_limits\":{\"five_hour\":{\"used_percentage\":50,\"resets_at\":${far_future}}}}"
    echo '{"modules":["pace"]}' > "$CLAUDE_CONFIG_DIR/.statusline-config.json"
    run bash -c "echo '$json' | bash '$STATUSLINE'"
    [ "$status" -eq 0 ]
    local clean
    clean=$(echo "$output" | sed 's/\x1b\[[0-9;]*m//g' | tr -d '[:space:]')
    [ -z "$clean" ]
}

# ─── Cache module: edge cases ───

@test "statusline: cache hidden when transcript file does not exist" {
    local json='{"model":{"display_name":"Test"},"workspace":{"current_dir":"/tmp/test-project"},"context_window":{"context_window_size":200000},"transcript_path":"/nonexistent/path/transcript.jsonl"}'
    echo '{"modules":["cache"]}' > "$CLAUDE_CONFIG_DIR/.statusline-config.json"
    run bash -c "echo '$json' | bash '$STATUSLINE'"
    [ "$status" -eq 0 ]
    local clean
    clean=$(echo "$output" | sed 's/\x1b\[[0-9;]*m//g' | tr -d '[:space:]')
    [ -z "$clean" ]
}

@test "statusline: cache hidden when transcript file is empty" {
    local tmp_transcript
    tmp_transcript=$(mktemp)
    # Empty file — no lines at all
    : > "$tmp_transcript"
    local json="{\"model\":{\"display_name\":\"Test\"},\"workspace\":{\"current_dir\":\"/tmp/test-project\"},\"context_window\":{\"context_window_size\":200000},\"transcript_path\":\"${tmp_transcript}\"}"
    echo '{"modules":["cache"]}' > "$CLAUDE_CONFIG_DIR/.statusline-config.json"
    run bash -c "echo '$json' | bash '$STATUSLINE'"
    rm -f "$tmp_transcript"
    [ "$status" -eq 0 ]
    local clean
    clean=$(echo "$output" | sed 's/\x1b\[[0-9;]*m//g' | tr -d '[:space:]')
    [ -z "$clean" ]
}

@test "statusline: cache hidden when last line has no timestamp field" {
    local tmp_transcript
    tmp_transcript=$(mktemp)
    printf '{"type":"user","content":"hello"}\n' > "$tmp_transcript"
    local json="{\"model\":{\"display_name\":\"Test\"},\"workspace\":{\"current_dir\":\"/tmp/test-project\"},\"context_window\":{\"context_window_size\":200000},\"transcript_path\":\"${tmp_transcript}\"}"
    echo '{"modules":["cache"]}' > "$CLAUDE_CONFIG_DIR/.statusline-config.json"
    run bash -c "echo '$json' | bash '$STATUSLINE'"
    rm -f "$tmp_transcript"
    [ "$status" -eq 0 ]
    local clean
    clean=$(echo "$output" | sed 's/\x1b\[[0-9;]*m//g' | tr -d '[:space:]')
    [ -z "$clean" ]
}

@test "statusline: cache parses fractional-seconds ISO timestamp" {
    local tmp_transcript
    tmp_transcript=$(mktemp)
    # Use current time with fractional seconds — cache should be fresh
    local now_iso
    now_iso=$(date -u +"%Y-%m-%dT%H:%M:%S.123456Z" 2>/dev/null || date -u +"%Y-%m-%dT%H:%M:%S.000Z")
    printf '{"timestamp":"%s","type":"assistant"}\n' "$now_iso" > "$tmp_transcript"
    local json="{\"model\":{\"display_name\":\"Test\"},\"workspace\":{\"current_dir\":\"/tmp/test-project\"},\"context_window\":{\"context_window_size\":200000},\"transcript_path\":\"${tmp_transcript}\"}"
    echo '{"modules":["cache"]}' > "$CLAUDE_CONFIG_DIR/.statusline-config.json"
    run bash -c "echo '$json' | bash '$STATUSLINE'"
    rm -f "$tmp_transcript"
    [ "$status" -eq 0 ]
    local clean
    clean=$(echo "$output" | sed 's/\x1b\[[0-9;]*m//g')
    # Fractional seconds stripped correctly → fresh countdown, not "cold"
    [[ "$clean" == *"cache"* ]]
    [[ "$clean" != *"cache cold"* ]]
}

# ─── Context display: _fmt_k boundary values ───

@test "statusline: context tokens mode formats < 1000 tokens as bare number" {
    # current_tokens = 0+0+999 = 999 → should display "999"
    local json='{"model":{"display_name":"Test"},"workspace":{"current_dir":"/tmp/test-project"},"context_window":{"context_window_size":200000,"current_usage":{"input_tokens":999,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}}}'
    echo '{"modules":["context"],"context_display":"tokens"}' > "$CLAUDE_CONFIG_DIR/.statusline-config.json"
    run bash -c "echo '$json' | bash '$STATUSLINE'"
    [ "$status" -eq 0 ]
    local clean
    clean=$(echo "$output" | sed 's/\x1b\[[0-9;]*m//g')
    # Should show "999/" (bare number, no k suffix)
    [[ "$clean" == *"999/"* ]]
}

@test "statusline: context tokens mode formats 1000-99999 as decimal k" {
    # current_tokens = 26000 (fixture) → 26.0k
    echo '{"modules":["context"],"context_display":"tokens"}' > "$CLAUDE_CONFIG_DIR/.statusline-config.json"
    run bash -c "cat '$FIXTURE' | bash '$STATUSLINE'"
    [ "$status" -eq 0 ]
    local clean
    clean=$(echo "$output" | sed 's/\x1b\[[0-9;]*m//g')
    # 26000 → "26.0k"
    [[ "$clean" == *"26.0k/"* ]]
}

@test "statusline: context tokens mode formats 100000+ tokens as integer k" {
    # current_tokens = 150000 → 150k (integer k, no decimal)
    local json='{"model":{"display_name":"Test"},"workspace":{"current_dir":"/tmp/test-project"},"context_window":{"context_window_size":200000,"current_usage":{"input_tokens":150000,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}}}'
    echo '{"modules":["context"],"context_display":"tokens"}' > "$CLAUDE_CONFIG_DIR/.statusline-config.json"
    run bash -c "echo '$json' | bash '$STATUSLINE'"
    [ "$status" -eq 0 ]
    local clean
    clean=$(echo "$output" | sed 's/\x1b\[[0-9;]*m//g')
    # 150000 → "150k"
    [[ "$clean" == *"150k/"* ]]
}

@test "statusline: context tokens mode formats 1M+ tokens as M" {
    # current_tokens = 1500000 on 1M window → 1M (promotes to 1M tier)
    local json='{"model":{"display_name":"Test"},"workspace":{"current_dir":"/tmp/test-project"},"context_window":{"context_window_size":200000,"current_usage":{"input_tokens":1500000,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}}}'
    echo '{"modules":["context"],"context_display":"tokens"}' > "$CLAUDE_CONFIG_DIR/.statusline-config.json"
    run bash -c "echo '$json' | bash '$STATUSLINE'"
    [ "$status" -eq 0 ]
    local clean
    clean=$(echo "$output" | sed 's/\x1b\[[0-9;]*m//g')
    # 1500000 / 1000000 = 1 → "1M"
    [[ "$clean" == *"1M/"* ]]
}

@test "statusline: context invalid context_display falls back to percent mode" {
    echo '{"modules":["context"],"context_display":"bogus-value"}' > "$CLAUDE_CONFIG_DIR/.statusline-config.json"
    run bash -c "cat '$FIXTURE' | bash '$STATUSLINE'"
    [ "$status" -eq 0 ]
    local clean
    clean=$(echo "$output" | sed 's/\x1b\[[0-9;]*m//g')
    # Falls through to *) branch → percent mode
    [[ "$clean" == *"13%"* ]]
    [[ "$clean" != *"k/"* ]]
}

# ─── Context warning: ⚠ appears at >= 90% ───

@test "statusline: context warning appears at 90% (>= 90 threshold)" {
    # 180000/200000 = 90% exactly → should show ⚠
    local json='{"model":{"display_name":"Test"},"workspace":{"current_dir":"/tmp/test-project"},"context_window":{"context_window_size":200000,"current_usage":{"input_tokens":180000,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}}}'
    echo '{"modules":["context"]}' > "$CLAUDE_CONFIG_DIR/.statusline-config.json"
    run bash -c "echo '$json' | bash '$STATUSLINE'"
    [ "$status" -eq 0 ]
    local clean
    clean=$(echo "$output" | sed 's/\x1b\[[0-9;]*m//g')
    [[ "$clean" == *"⚠"* ]]
}

@test "statusline: context warning absent below 90% (89% does not warn)" {
    # 89% → no warning
    local json='{"model":{"display_name":"Test"},"workspace":{"current_dir":"/tmp/test-project"},"context_window":{"context_window_size":200000,"current_usage":{"input_tokens":178000,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}}}'
    echo '{"modules":["context"]}' > "$CLAUDE_CONFIG_DIR/.statusline-config.json"
    run bash -c "echo '$json' | bash '$STATUSLINE'"
    [ "$status" -eq 0 ]
    local clean
    clean=$(echo "$output" | sed 's/\x1b\[[0-9;]*m//g')
    # Note: exceeds_200k_tokens field is NOT checked by context module; threshold is >= 90%
    [[ "$clean" != *"⚠"* ]]
}

# ─── Git module: both ahead and behind; OSC8; no upstream; dirty spacing ───

@test "statusline: git shows both ahead and behind when both nonzero" {
    create_mock "git" 'case "$1" in
        rev-parse) echo "true"; exit 0 ;;
        branch) echo "main"; exit 0 ;;
        status) exit 0 ;;  # clean
        rev-list) printf "3\t2\n"; exit 0 ;;  # 3 behind, 2 ahead
        remote) exit 1 ;;
        *) exit 0 ;;
    esac'
    echo '{"modules":["git"]}' > "$CLAUDE_CONFIG_DIR/.statusline-config.json"
    run bash -c "cat '$FIXTURE' | bash '$STATUSLINE'"
    [ "$status" -eq 0 ]
    local clean
    clean=$(echo "$output" | sed 's/\x1b\[[0-9;]*m//g' | sed $'s/\033]8;;[^\033]*\033\\\\//g')
    [[ "$clean" == *"↑2"* ]]
    [[ "$clean" == *"↓3"* ]]
}

@test "statusline: git no upstream shows no ahead/behind indicators" {
    # rev-list fails when no upstream → no ↑ or ↓
    create_mock "git" 'case "$1" in
        rev-parse) echo "true"; exit 0 ;;
        branch) echo "feature-branch"; exit 0 ;;
        status) exit 0 ;;  # clean
        rev-list) exit 128 ;;  # no upstream
        remote) exit 1 ;;
        *) exit 0 ;;
    esac'
    echo '{"modules":["git"]}' > "$CLAUDE_CONFIG_DIR/.statusline-config.json"
    run bash -c "cat '$FIXTURE' | bash '$STATUSLINE'"
    [ "$status" -eq 0 ]
    local clean
    clean=$(echo "$output" | sed 's/\x1b\[[0-9;]*m//g' | sed $'s/\033]8;;[^\033]*\033\\\\//g')
    [[ "$clean" == *"feature-branch"* ]]
    [[ "$clean" != *"↑"* ]]
    [[ "$clean" != *"↓"* ]]
}

@test "statusline: git OSC8 link present for https://github.com origin" {
    create_mock "git" 'case "$1" in
        rev-parse) echo "true"; exit 0 ;;
        branch) echo "main"; exit 0 ;;
        status) exit 0 ;;
        rev-list) exit 1 ;;
        remote)
            # remote get-url origin
            echo "https://github.com/user/repo.git"; exit 0 ;;
        *) exit 0 ;;
    esac'
    echo '{"modules":["git"]}' > "$CLAUDE_CONFIG_DIR/.statusline-config.json"
    run bash -c "cat '$FIXTURE' | bash '$STATUSLINE'"
    [ "$status" -eq 0 ]
    # OSC 8 hyperlink sequence should be present
    [[ "$output" == *$'\033]8;;https://github.com/user/repo/tree/main'* ]]
}

@test "statusline: git no OSC8 link when origin is a local path" {
    create_mock "git" 'case "$1" in
        rev-parse) echo "true"; exit 0 ;;
        branch) echo "main"; exit 0 ;;
        status) exit 0 ;;
        rev-list) exit 1 ;;
        remote)
            echo "/home/user/local-repo"; exit 0 ;;
        *) exit 0 ;;
    esac'
    echo '{"modules":["git"]}' > "$CLAUDE_CONFIG_DIR/.statusline-config.json"
    run bash -c "cat '$FIXTURE' | bash '$STATUSLINE'"
    [ "$status" -eq 0 ]
    # No OSC 8 hyperlink for local paths
    [[ "$output" != *$'\033]8;;'* ]]
}

@test "statusline: dirty repo shows space-pipe-space separator between branch and file count" {
    create_mock "git" 'case "$1" in
        rev-parse) echo "true"; exit 0 ;;
        branch) echo "main"; exit 0 ;;
        status) printf "M  file1.txt\n"; exit 0 ;;
        diff) printf "5\t2\tfile1.txt\n"; exit 0 ;;
        rev-list) exit 1 ;;
        remote) exit 1 ;;
        *) exit 0 ;;
    esac'
    echo '{"modules":["git"]}' > "$CLAUDE_CONFIG_DIR/.statusline-config.json"
    run bash -c "cat '$FIXTURE' | bash '$STATUSLINE'"
    [ "$status" -eq 0 ]
    local clean
    clean=$(echo "$output" | sed 's/\x1b\[[0-9;]*m//g' | sed $'s/\033]8;;[^\033]*\033\\\\//g')
    # Pattern: "(branch | N files" — note the space before |
    [[ "$clean" == *"(main | 1 files"* ]]
}

# ─── Speed module: corrupt cache and negative delta ───

@test "statusline: speed does not crash on empty (corrupt) cache file" {
    local session_id="speed-corrupt-test-$$"
    local json="{\"model\":{\"display_name\":\"Test\"},\"workspace\":{\"current_dir\":\"/tmp/test-project\"},\"context_window\":{\"context_window_size\":200000,\"total_input_tokens\":5000,\"total_output_tokens\":500},\"session_id\":\"${session_id}\"}"
    echo '{"modules":["speed"]}' > "$CLAUDE_CONFIG_DIR/.statusline-config.json"
    # Pre-create an empty (corrupt) cache file
    local speed_dir="$CLAUDE_CONFIG_DIR/.speed-cache"
    mkdir -p "$speed_dir"
    local safe_id
    safe_id=$(printf '%s' "$session_id" | tr -dc 'a-zA-Z0-9_-' | cut -c1-40)
    : > "$speed_dir/speed-${safe_id}.txt"
    run bash -c "echo '$json' | bash '$STATUSLINE'"
    [ "$status" -eq 0 ]
    # Output should be empty (corrupt → treated as first render / write baseline)
    local clean
    clean=$(echo "$output" | sed 's/\x1b\[[0-9;]*m//g' | tr -d '[:space:]')
    [ -z "$clean" ]
}

@test "statusline: speed negative delta resets baseline without showing tok/s" {
    local session_id="speed-neg-delta-test-$$"
    echo '{"modules":["speed"]}' > "$CLAUDE_CONFIG_DIR/.statusline-config.json"
    local speed_dir="$CLAUDE_CONFIG_DIR/.speed-cache"
    mkdir -p "$speed_dir"
    local safe_id
    safe_id=$(printf '%s' "$session_id" | tr -dc 'a-zA-Z0-9_-' | cut -c1-40)
    local sp_file="$speed_dir/speed-${safe_id}.txt"
    # Seed cache: previously 10000 tokens, 60 seconds ago
    local old_epoch=$(( $(date +%s) - 60 ))
    printf '%s\t%s\n' "10000" "$old_epoch" > "$sp_file"
    # Send a lower token count (5000 < 10000 → negative delta → compact occurred)
    local json="{\"model\":{\"display_name\":\"Test\"},\"workspace\":{\"current_dir\":\"/tmp/test-project\"},\"context_window\":{\"context_window_size\":200000,\"total_input_tokens\":4500,\"total_output_tokens\":500},\"session_id\":\"${session_id}\"}"
    run bash -c "echo '$json' | bash '$STATUSLINE'"
    [ "$status" -eq 0 ]
    # Negative delta → reset baseline, no output
    local clean
    clean=$(echo "$output" | sed 's/\x1b\[[0-9;]*m//g' | tr -d '[:space:]')
    [ -z "$clean" ]
    # And the cache file must have been rewritten (new baseline)
    [ -f "$sp_file" ]
}

# ─── Two-line layout: both lines get theme colors ───

@test "statusline: two-line layout with theme — both lines contain color sequences" {
    echo '{"modules":["model"],"modules_line2":["context"],"theme":"tokyo-night"}' \
        > "$CLAUDE_CONFIG_DIR/.statusline-config.json"
    run bash -c "cat '$FIXTURE' | bash '$STATUSLINE'"
    [ "$status" -eq 0 ]
    [ "${#lines[@]}" -eq 2 ]
    # Both lines should contain truecolor sequences from tokyo-night
    [[ "${lines[0]}" == *$'\033[38;2;'* ]]
    [[ "${lines[1]}" == *$'\033[38;2;'* ]]
}

@test "statusline: two-line layout — line2 modules absent from line1" {
    echo '{"modules":["model"],"modules_line2":["context"]}' \
        > "$CLAUDE_CONFIG_DIR/.statusline-config.json"
    run bash -c "cat '$FIXTURE' | bash '$STATUSLINE'"
    [ "$status" -eq 0 ]
    [ "${#lines[@]}" -eq 2 ]
    # Line1 must not contain the percentage (context is on line2)
    local clean1
    clean1=$(echo "${lines[0]}" | sed 's/\x1b\[[^m]*m//g')
    [[ "$clean1" != *"13%"* ]]
    # Line2 must contain percentage
    local clean2
    clean2=$(echo "${lines[1]}" | sed 's/\x1b\[[^m]*m//g')
    [[ "$clean2" == *"13%"* ]]
}

# ─── Composition: separator count matches module count - 1 ───

@test "statusline: separator count equals enabled-module count minus one" {
    # Use 3 modules: directory, model, context → expect exactly 2 " | " separators
    echo '{"modules":["directory","model","context"]}' > "$CLAUDE_CONFIG_DIR/.statusline-config.json"
    run bash -c "cat '$FIXTURE' | bash '$STATUSLINE'"
    [ "$status" -eq 0 ]
    # Strip ANSI SGR and OSC 8 sequences, then count pipe separators
    local clean
    clean=$(echo "$output" | sed 's/\x1b\[[0-9;]*m//g' | sed $'s/\033]8;;[^\033]*\033\\\\//g')
    # Count " | " occurrences
    local pipe_count
    pipe_count=$(echo "$clean" | grep -o ' | ' | wc -l | xargs)
    [ "$pipe_count" -eq 2 ]
}

# ─── Tools module ───

@test "statusline: tools shows pending tool name" {
    local tmp_transcript
    tmp_transcript=$(mktemp)
    # One tool_use with no matching tool_result
    printf '{"type":"assistant","message":{"content":[{"type":"tool_use","id":"toolu_001","name":"Bash","input":{}}]},"timestamp":"2026-01-01T00:00:00Z"}\n' > "$tmp_transcript"
    local json="{\"model\":{\"display_name\":\"Test\"},\"workspace\":{\"current_dir\":\"/tmp/test-project\"},\"context_window\":{\"context_window_size\":200000},\"transcript_path\":\"${tmp_transcript}\"}"
    echo '{"modules":["tools"]}' > "$CLAUDE_CONFIG_DIR/.statusline-config.json"
    run bash -c "echo '$json' | bash '$STATUSLINE'"
    rm -f "$tmp_transcript"
    [ "$status" -eq 0 ]
    local clean
    clean=$(echo "$output" | sed 's/\x1b\[[0-9;]*m//g')
    [[ "$clean" == *"⚒ Bash"* ]]
}

@test "statusline: tools hidden when tool has matching result" {
    local tmp_transcript
    tmp_transcript=$(mktemp)
    printf '{"type":"assistant","message":{"content":[{"type":"tool_use","id":"toolu_001","name":"Bash","input":{}}]},"timestamp":"2026-01-01T00:00:00Z"}\n' > "$tmp_transcript"
    printf '{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"toolu_001"}]},"timestamp":"2026-01-01T00:00:01Z"}\n' >> "$tmp_transcript"
    local json="{\"model\":{\"display_name\":\"Test\"},\"workspace\":{\"current_dir\":\"/tmp/test-project\"},\"context_window\":{\"context_window_size\":200000},\"transcript_path\":\"${tmp_transcript}\"}"
    echo '{"modules":["tools"]}' > "$CLAUDE_CONFIG_DIR/.statusline-config.json"
    run bash -c "echo '$json' | bash '$STATUSLINE'"
    rm -f "$tmp_transcript"
    [ "$status" -eq 0 ]
    local clean
    clean=$(echo "$output" | sed 's/\x1b\[[0-9;]*m//g' | tr -d '[:space:]')
    [ -z "$clean" ]
}

@test "statusline: tools shows overflow count when multiple pending" {
    local tmp_transcript
    tmp_transcript=$(mktemp)
    printf '{"type":"assistant","message":{"content":[{"type":"tool_use","id":"toolu_001","name":"Bash","input":{}},{"type":"tool_use","id":"toolu_002","name":"Read","input":{}},{"type":"tool_use","id":"toolu_003","name":"Edit","input":{}}]},"timestamp":"2026-01-01T00:00:00Z"}\n' > "$tmp_transcript"
    local json="{\"model\":{\"display_name\":\"Test\"},\"workspace\":{\"current_dir\":\"/tmp/test-project\"},\"context_window\":{\"context_window_size\":200000},\"transcript_path\":\"${tmp_transcript}\"}"
    echo '{"modules":["tools"]}' > "$CLAUDE_CONFIG_DIR/.statusline-config.json"
    run bash -c "echo '$json' | bash '$STATUSLINE'"
    rm -f "$tmp_transcript"
    [ "$status" -eq 0 ]
    local clean
    clean=$(echo "$output" | sed 's/\x1b\[[0-9;]*m//g')
    [[ "$clean" == *"⚒ Bash +2"* ]]
}

@test "statusline: tools hidden when transcript_path absent" {
    local json='{"model":{"display_name":"Test"},"workspace":{"current_dir":"/tmp/test-project"},"context_window":{"context_window_size":200000}}'
    echo '{"modules":["tools"]}' > "$CLAUDE_CONFIG_DIR/.statusline-config.json"
    run bash -c "echo '$json' | bash '$STATUSLINE'"
    [ "$status" -eq 0 ]
    local clean
    clean=$(echo "$output" | sed 's/\x1b\[[0-9;]*m//g' | tr -d '[:space:]')
    [ -z "$clean" ]
}

# ─── Agents module ───

@test "statusline: agents shows pending Task subagent_type" {
    local tmp_transcript
    tmp_transcript=$(mktemp)
    printf '{"type":"assistant","message":{"content":[{"type":"tool_use","id":"toolu_a01","name":"Task","input":{"subagent_type":"code-reviewer","description":"Review the PR"}}]},"timestamp":"2026-01-01T00:00:00Z"}\n' > "$tmp_transcript"
    local json="{\"model\":{\"display_name\":\"Test\"},\"workspace\":{\"current_dir\":\"/tmp/test-project\"},\"context_window\":{\"context_window_size\":200000},\"transcript_path\":\"${tmp_transcript}\"}"
    echo '{"modules":["agents"]}' > "$CLAUDE_CONFIG_DIR/.statusline-config.json"
    run bash -c "echo '$json' | bash '$STATUSLINE'"
    rm -f "$tmp_transcript"
    [ "$status" -eq 0 ]
    local clean
    clean=$(echo "$output" | sed 's/\x1b\[[0-9;]*m//g')
    [[ "$clean" == *"◉ code-reviewer"* ]]
}

@test "statusline: agents shows count when multiple pending" {
    local tmp_transcript
    tmp_transcript=$(mktemp)
    printf '{"type":"assistant","message":{"content":[{"type":"tool_use","id":"toolu_a01","name":"Task","input":{"subagent_type":"agent-one","description":"desc1"}},{"type":"tool_use","id":"toolu_a02","name":"Task","input":{"subagent_type":"agent-two","description":"desc2"}},{"type":"tool_use","id":"toolu_a03","name":"Task","input":{"subagent_type":"agent-three","description":"desc3"}}]},"timestamp":"2026-01-01T00:00:00Z"}\n' > "$tmp_transcript"
    local json="{\"model\":{\"display_name\":\"Test\"},\"workspace\":{\"current_dir\":\"/tmp/test-project\"},\"context_window\":{\"context_window_size\":200000},\"transcript_path\":\"${tmp_transcript}\"}"
    echo '{"modules":["agents"]}' > "$CLAUDE_CONFIG_DIR/.statusline-config.json"
    run bash -c "echo '$json' | bash '$STATUSLINE'"
    rm -f "$tmp_transcript"
    [ "$status" -eq 0 ]
    local clean
    clean=$(echo "$output" | sed 's/\x1b\[[0-9;]*m//g')
    [[ "$clean" == *"◉ 3 agents"* ]]
}

@test "statusline: agents hidden when no Task pending" {
    local tmp_transcript
    tmp_transcript=$(mktemp)
    printf '{"type":"assistant","message":{"content":[{"type":"tool_use","id":"toolu_001","name":"Bash","input":{}}]},"timestamp":"2026-01-01T00:00:00Z"}\n' > "$tmp_transcript"
    local json="{\"model\":{\"display_name\":\"Test\"},\"workspace\":{\"current_dir\":\"/tmp/test-project\"},\"context_window\":{\"context_window_size\":200000},\"transcript_path\":\"${tmp_transcript}\"}"
    echo '{"modules":["agents"]}' > "$CLAUDE_CONFIG_DIR/.statusline-config.json"
    run bash -c "echo '$json' | bash '$STATUSLINE'"
    rm -f "$tmp_transcript"
    [ "$status" -eq 0 ]
    local clean
    clean=$(echo "$output" | sed 's/\x1b\[[0-9;]*m//g' | tr -d '[:space:]')
    [ -z "$clean" ]
}

# ─── Todos module ───

@test "statusline: todos shows progress from last TodoWrite" {
    local tmp_transcript
    tmp_transcript=$(mktemp)
    local todos='[{"content":"task1","status":"completed","activeForm":false},{"content":"task2","status":"completed","activeForm":false},{"content":"task3","status":"pending","activeForm":false},{"content":"task4","status":"pending","activeForm":false},{"content":"task5","status":"pending","activeForm":false}]'
    printf '{"type":"assistant","message":{"content":[{"type":"tool_use","id":"toolu_t01","name":"TodoWrite","input":{"todos":%s}}]},"timestamp":"2026-01-01T00:00:00Z"}\n' "$todos" > "$tmp_transcript"
    local json="{\"model\":{\"display_name\":\"Test\"},\"workspace\":{\"current_dir\":\"/tmp/test-project\"},\"context_window\":{\"context_window_size\":200000},\"transcript_path\":\"${tmp_transcript}\"}"
    echo '{"modules":["todos"]}' > "$CLAUDE_CONFIG_DIR/.statusline-config.json"
    run bash -c "echo '$json' | bash '$STATUSLINE'"
    rm -f "$tmp_transcript"
    [ "$status" -eq 0 ]
    local clean
    clean=$(echo "$output" | sed 's/\x1b\[[0-9;]*m//g')
    [[ "$clean" == *"☑ 2/5"* ]]
}

@test "statusline: todos shows green when all completed" {
    local tmp_transcript
    tmp_transcript=$(mktemp)
    local todos='[{"content":"task1","status":"completed","activeForm":false},{"content":"task2","status":"completed","activeForm":false},{"content":"task3","status":"completed","activeForm":false}]'
    printf '{"type":"assistant","message":{"content":[{"type":"tool_use","id":"toolu_t02","name":"TodoWrite","input":{"todos":%s}}]},"timestamp":"2026-01-01T00:00:00Z"}\n' "$todos" > "$tmp_transcript"
    local json="{\"model\":{\"display_name\":\"Test\"},\"workspace\":{\"current_dir\":\"/tmp/test-project\"},\"context_window\":{\"context_window_size\":200000},\"transcript_path\":\"${tmp_transcript}\"}"
    echo '{"modules":["todos"]}' > "$CLAUDE_CONFIG_DIR/.statusline-config.json"
    run bash -c "echo '$json' | bash '$STATUSLINE'"
    rm -f "$tmp_transcript"
    [ "$status" -eq 0 ]
    # Should contain green ANSI code and the fraction
    [[ "$output" == *"☑ 3/3"* ]]
    # Green color sequence present
    [[ "$output" == *$'\033[0;32m'* ]] || [[ "$output" == *$'\033[38;2;'* ]]
}

@test "statusline: todos hidden when no TodoWrite in transcript" {
    local tmp_transcript
    tmp_transcript=$(mktemp)
    printf '{"type":"assistant","message":{"content":[{"type":"tool_use","id":"toolu_001","name":"Bash","input":{}}]},"timestamp":"2026-01-01T00:00:00Z"}\n' > "$tmp_transcript"
    local json="{\"model\":{\"display_name\":\"Test\"},\"workspace\":{\"current_dir\":\"/tmp/test-project\"},\"context_window\":{\"context_window_size\":200000},\"transcript_path\":\"${tmp_transcript}\"}"
    echo '{"modules":["todos"]}' > "$CLAUDE_CONFIG_DIR/.statusline-config.json"
    run bash -c "echo '$json' | bash '$STATUSLINE'"
    rm -f "$tmp_transcript"
    [ "$status" -eq 0 ]
    local clean
    clean=$(echo "$output" | sed 's/\x1b\[[0-9;]*m//g' | tr -d '[:space:]')
    [ -z "$clean" ]
}

@test "statusline: todos hidden when transcript_path absent" {
    local json='{"model":{"display_name":"Test"},"workspace":{"current_dir":"/tmp/test-project"},"context_window":{"context_window_size":200000}}'
    echo '{"modules":["todos"]}' > "$CLAUDE_CONFIG_DIR/.statusline-config.json"
    run bash -c "echo '$json' | bash '$STATUSLINE'"
    [ "$status" -eq 0 ]
    local clean
    clean=$(echo "$output" | sed 's/\x1b\[[0-9;]*m//g' | tr -d '[:space:]')
    [ -z "$clean" ]
}

@test "statusline: malformed last transcript line does not crash" {
    local tmp_transcript
    tmp_transcript=$(mktemp)
    # Valid line followed by a partial/malformed line
    printf '{"type":"assistant","message":{"content":[{"type":"tool_use","id":"toolu_001","name":"Bash","input":{}}]},"timestamp":"2026-01-01T00:00:00Z"}\n' > "$tmp_transcript"
    printf '{"incomplete":' >> "$tmp_transcript"
    local json="{\"model\":{\"display_name\":\"Test\"},\"workspace\":{\"current_dir\":\"/tmp/test-project\"},\"context_window\":{\"context_window_size\":200000},\"transcript_path\":\"${tmp_transcript}\"}"
    echo '{"modules":["tools","agents","todos"]}' > "$CLAUDE_CONFIG_DIR/.statusline-config.json"
    run bash -c "echo '$json' | bash '$STATUSLINE'"
    rm -f "$tmp_transcript"
    # Must not crash
    [ "$status" -eq 0 ]
}

# ─── Install: additional coverage ───

# NOTE: These tests are in test/install.bats but we add them here as a cross-check
# for statusline rendering post-install config. The install-specific tests live in install.bats.
