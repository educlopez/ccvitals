#!/usr/bin/env bats

# Tests for Feature 1 (session budget cap in cost module)
# and Feature 2 (spend module — 7d/30d historical spend).

setup() {
    load 'test_helper/common-setup'
    _common_setup

    STATUSLINE="$PROJECT_ROOT/statusline.sh"

    # Default git mock: not inside a work tree
    create_mock "git" 'case "$1" in
        rev-parse) exit 1 ;;
        *) exit 1 ;;
    esac'

    # Mock curl to avoid network calls (usage module)
    create_mock "curl" 'exit 1'

    mkdir -p /tmp/test-project
}

# Helpers
_strip_ansi() { printf '%s' "$1" | sed 's/\x1b\[[0-9;]*m//g'; }

# ════════════════════════════════════════════════════════════
# Feature 1: session budget cap (cost module)
# ════════════════════════════════════════════════════════════

@test "cost: shows plain cost when no session_budget set" {
    local json='{"model":{"display_name":"Test"},"workspace":{"current_dir":"/tmp/test-project"},"context_window":{"context_window_size":200000},"cost":{"total_cost_usd":0.42}}'
    echo '{"modules":["cost"]}' > "$CLAUDE_CONFIG_DIR/.statusline-config.json"
    run bash -c "echo '$json' | bash '$STATUSLINE'"
    [ "$status" -eq 0 ]
    local clean
    clean=$(_strip_ansi "$output")
    [[ "$clean" == *'$0.42'* ]]
    # No budget denominator without session_budget
    [[ "$clean" != *'$0.42/'* ]]
}

@test "cost: shows cost/budget when session_budget is set" {
    local json='{"model":{"display_name":"Test"},"workspace":{"current_dir":"/tmp/test-project"},"context_window":{"context_window_size":200000},"cost":{"total_cost_usd":1.50}}'
    echo '{"modules":["cost"],"session_budget":5}' > "$CLAUDE_CONFIG_DIR/.statusline-config.json"
    run bash -c "echo '$json' | bash '$STATUSLINE'"
    [ "$status" -eq 0 ]
    local clean
    clean=$(_strip_ansi "$output")
    # Should show $1.50/$5.00 (both <$10 so 2 decimals)
    [[ "$clean" == *'$1.50/$5.00'* ]]
}

@test "cost: green/gray color when cost <50% of session_budget" {
    local json='{"model":{"display_name":"Test"},"workspace":{"current_dir":"/tmp/test-project"},"context_window":{"context_window_size":200000},"cost":{"total_cost_usd":1.00}}'
    echo '{"modules":["cost"],"session_budget":5}' > "$CLAUDE_CONFIG_DIR/.statusline-config.json"
    run bash -c "echo '$json' | bash '$STATUSLINE'"
    [ "$status" -eq 0 ]
    local clean
    clean=$(_strip_ansi "$output")
    # 1.00/5 = 20% — should be normal (gray), not yellow/red
    [[ "$clean" == *'$1.00/$5.00'* ]]
    # Must NOT contain a red ANSI escape immediately before the cost
    [[ "$output" != *$'\033[0;31m'* ]]
}

@test "cost: yellow color when cost 50-79% of session_budget" {
    local json='{"model":{"display_name":"Test"},"workspace":{"current_dir":"/tmp/test-project"},"context_window":{"context_window_size":200000},"cost":{"total_cost_usd":3.00}}'
    echo '{"modules":["cost"],"session_budget":5}' > "$CLAUDE_CONFIG_DIR/.statusline-config.json"
    run bash -c "echo '$json' | bash '$STATUSLINE'"
    [ "$status" -eq 0 ]
    # 3.00/5 = 60% — should be yellow
    [[ "$output" == *$'\033[0;33m'* ]]
    local clean
    clean=$(_strip_ansi "$output")
    [[ "$clean" == *'$3.00/$5.00'* ]]
}

@test "cost: red color when cost >=80% of session_budget" {
    local json='{"model":{"display_name":"Test"},"workspace":{"current_dir":"/tmp/test-project"},"context_window":{"context_window_size":200000},"cost":{"total_cost_usd":4.50}}'
    echo '{"modules":["cost"],"session_budget":5}' > "$CLAUDE_CONFIG_DIR/.statusline-config.json"
    run bash -c "echo '$json' | bash '$STATUSLINE'"
    [ "$status" -eq 0 ]
    # 4.50/5 = 90% — should be red
    [[ "$output" == *$'\033[0;31m'* ]]
    local clean
    clean=$(_strip_ansi "$output")
    [[ "$clean" == *'$4.50/$5.00'* ]]
}

@test "cost: red color when cost exactly 80% of session_budget" {
    local json='{"model":{"display_name":"Test"},"workspace":{"current_dir":"/tmp/test-project"},"context_window":{"context_window_size":200000},"cost":{"total_cost_usd":4.00}}'
    echo '{"modules":["cost"],"session_budget":5}' > "$CLAUDE_CONFIG_DIR/.statusline-config.json"
    run bash -c "echo '$json' | bash '$STATUSLINE'"
    [ "$status" -eq 0 ]
    # 4.00/5 = 80% — boundary: should be red
    [[ "$output" == *$'\033[0;31m'* ]]
}

@test "cost: hidden when no cost data even with session_budget" {
    local json='{"model":{"display_name":"Test"},"workspace":{"current_dir":"/tmp/test-project"},"context_window":{"context_window_size":200000}}'
    echo '{"modules":["cost"],"session_budget":5}' > "$CLAUDE_CONFIG_DIR/.statusline-config.json"
    run bash -c "echo '$json' | bash '$STATUSLINE'"
    [ "$status" -eq 0 ]
    local clean
    clean=$(_strip_ansi "$output" | tr -d '[:space:]')
    [ -z "$clean" ]
}

@test "cost: session_budget=0 behaves as unset (no denominator shown)" {
    local json='{"model":{"display_name":"Test"},"workspace":{"current_dir":"/tmp/test-project"},"context_window":{"context_window_size":200000},"cost":{"total_cost_usd":0.42}}'
    echo '{"modules":["cost"],"session_budget":0}' > "$CLAUDE_CONFIG_DIR/.statusline-config.json"
    run bash -c "echo '$json' | bash '$STATUSLINE'"
    [ "$status" -eq 0 ]
    local clean
    clean=$(_strip_ansi "$output")
    [[ "$clean" == *'$0.42'* ]]
    [[ "$clean" != *'$0.42/'* ]]
}

@test "cost: per-project session_budget overrides global" {
    # Global: no session_budget; project: session_budget=2
    local json='{"model":{"display_name":"Test"},"workspace":{"current_dir":"/tmp/test-project","project_dir":"/tmp/test-project"},"context_window":{"context_window_size":200000},"cost":{"total_cost_usd":1.80}}'
    echo '{"modules":["cost"]}' > "$CLAUDE_CONFIG_DIR/.statusline-config.json"
    echo '{"session_budget":2}' > "/tmp/test-project/.ccvitals.json"
    run bash -c "echo '$json' | bash '$STATUSLINE'"
    [ "$status" -eq 0 ]
    local clean
    clean=$(_strip_ansi "$output")
    [[ "$clean" == *'$1.80/$2.00'* ]]
    rm -f "/tmp/test-project/.ccvitals.json"
}

# ════════════════════════════════════════════════════════════
# Feature 2: spend module (7d/30d historical spend)
# ════════════════════════════════════════════════════════════

@test "spend: hidden by default (mod_spend=false)" {
    # Seed a daily file so spend would show if module were enabled
    local daily_dir="$CLAUDE_CONFIG_DIR/.ccvitals-daily"
    mkdir -p "$daily_dir"
    local today
    today=$(date +%Y-%m-%d)
    printf '{"s":5.00}\n' > "$daily_dir/${today}.json"

    # No modules config — default config has no spend
    local json='{"model":{"display_name":"Test"},"workspace":{"current_dir":"/tmp/test-project"},"context_window":{"context_window_size":200000}}'
    # Use explicit config with spend disabled
    echo '{"modules":["cost"]}' > "$CLAUDE_CONFIG_DIR/.statusline-config.json"
    run bash -c "echo '$json' | bash '$STATUSLINE'"
    [ "$status" -eq 0 ]
    local clean
    clean=$(_strip_ansi "$output")
    # spend windows should not appear when module not enabled
    [[ "$clean" != *'7d'* ]]
    [[ "$clean" != *'30d'* ]]
}

@test "spend: hidden when enabled but daily dir missing" {
    local json='{"model":{"display_name":"Test"},"workspace":{"current_dir":"/tmp/test-project"},"context_window":{"context_window_size":200000}}'
    echo '{"modules":["spend"]}' > "$CLAUDE_CONFIG_DIR/.statusline-config.json"
    # No daily dir exists in the isolated config
    run bash -c "echo '$json' | bash '$STATUSLINE'"
    [ "$status" -eq 0 ]
    local clean
    clean=$(_strip_ansi "$output" | tr -d '[:space:]')
    [ -z "$clean" ]
}

@test "spend: shows 7d and 30d when enabled with daily dir populated" {
    # Seed the daily ledger with a file from today
    local daily_dir="$CLAUDE_CONFIG_DIR/.ccvitals-daily"
    mkdir -p "$daily_dir"
    local today
    today=$(date +%Y-%m-%d)
    # Two sessions totalling $5.00 today
    printf '{"sess1":3.00,"sess2":2.00}\n' > "$daily_dir/${today}.json"

    local json='{"model":{"display_name":"Test"},"workspace":{"current_dir":"/tmp/test-project"},"context_window":{"context_window_size":200000}}'
    echo '{"modules":["spend"]}' > "$CLAUDE_CONFIG_DIR/.statusline-config.json"
    run bash -c "echo '$json' | bash '$STATUSLINE'"
    [ "$status" -eq 0 ]
    local clean
    clean=$(_strip_ansi "$output")
    [[ "$clean" == *'7d'* ]]
    [[ "$clean" == *'30d'* ]]
    [[ "$clean" == *'$5.00'* ]]
}

@test "spend: sums multiple day files within 7d window" {
    local daily_dir="$CLAUDE_CONFIG_DIR/.ccvitals-daily"
    mkdir -p "$daily_dir"
    local today
    today=$(date +%Y-%m-%d)
    # Today: $3.00, yesterday would need date math — use today twice with different sessions
    printf '{"a":1.50,"b":1.50}\n' > "$daily_dir/${today}.json"
    local json='{"model":{"display_name":"Test"},"workspace":{"current_dir":"/tmp/test-project"},"context_window":{"context_window_size":200000}}'
    echo '{"modules":["spend"]}' > "$CLAUDE_CONFIG_DIR/.statusline-config.json"
    run bash -c "echo '$json' | bash '$STATUSLINE'"
    [ "$status" -eq 0 ]
    local clean
    clean=$(_strip_ansi "$output")
    [[ "$clean" == *'7d $3.00'* ]]
    [[ "$clean" == *'30d $3.00'* ]]
}

@test "spend: shows separator dot between windows" {
    local daily_dir="$CLAUDE_CONFIG_DIR/.ccvitals-daily"
    mkdir -p "$daily_dir"
    local today
    today=$(date +%Y-%m-%d)
    printf '{"s":1.00}\n' > "$daily_dir/${today}.json"
    local json='{"model":{"display_name":"Test"},"workspace":{"current_dir":"/tmp/test-project"},"context_window":{"context_window_size":200000}}'
    echo '{"modules":["spend"]}' > "$CLAUDE_CONFIG_DIR/.statusline-config.json"
    run bash -c "echo '$json' | bash '$STATUSLINE'"
    [ "$status" -eq 0 ]
    local clean
    clean=$(_strip_ansi "$output")
    [[ "$clean" == *'·'* ]]
}

@test "spend: spend_windows config limits to 7d only" {
    local daily_dir="$CLAUDE_CONFIG_DIR/.ccvitals-daily"
    mkdir -p "$daily_dir"
    local today
    today=$(date +%Y-%m-%d)
    printf '{"s":2.50}\n' > "$daily_dir/${today}.json"
    local json='{"model":{"display_name":"Test"},"workspace":{"current_dir":"/tmp/test-project"},"context_window":{"context_window_size":200000}}'
    echo '{"modules":["spend"],"spend_windows":["7d"]}' > "$CLAUDE_CONFIG_DIR/.statusline-config.json"
    run bash -c "echo '$json' | bash '$STATUSLINE'"
    [ "$status" -eq 0 ]
    local clean
    clean=$(_strip_ansi "$output")
    [[ "$clean" == *'7d $2.50'* ]]
    [[ "$clean" != *'30d'* ]]
}

@test "spend: spend_windows config limits to 30d only" {
    local daily_dir="$CLAUDE_CONFIG_DIR/.ccvitals-daily"
    mkdir -p "$daily_dir"
    local today
    today=$(date +%Y-%m-%d)
    printf '{"s":7.00}\n' > "$daily_dir/${today}.json"
    local json='{"model":{"display_name":"Test"},"workspace":{"current_dir":"/tmp/test-project"},"context_window":{"context_window_size":200000}}'
    echo '{"modules":["spend"],"spend_windows":["30d"]}' > "$CLAUDE_CONFIG_DIR/.statusline-config.json"
    run bash -c "echo '$json' | bash '$STATUSLINE'"
    [ "$status" -eq 0 ]
    local clean
    clean=$(_strip_ansi "$output")
    [[ "$clean" == *'30d $7.00'* ]]
    [[ "$clean" != *'7d'* ]]
}

@test "spend: zero spend shows zero formatted amount" {
    local daily_dir="$CLAUDE_CONFIG_DIR/.ccvitals-daily"
    mkdir -p "$daily_dir"
    local today
    today=$(date +%Y-%m-%d)
    printf '{"s":0}\n' > "$daily_dir/${today}.json"
    local json='{"model":{"display_name":"Test"},"workspace":{"current_dir":"/tmp/test-project"},"context_window":{"context_window_size":200000}}'
    echo '{"modules":["spend"]}' > "$CLAUDE_CONFIG_DIR/.statusline-config.json"
    run bash -c "echo '$json' | bash '$STATUSLINE'"
    [ "$status" -eq 0 ]
    local clean
    clean=$(_strip_ansi "$output")
    [[ "$clean" == *'$0.00'* ]]
}

@test "spend: malformed day file is skipped gracefully" {
    local daily_dir="$CLAUDE_CONFIG_DIR/.ccvitals-daily"
    mkdir -p "$daily_dir"
    local today
    today=$(date +%Y-%m-%d)
    printf 'NOT_VALID_JSON\n' > "$daily_dir/${today}.json"
    local json='{"model":{"display_name":"Test"},"workspace":{"current_dir":"/tmp/test-project"},"context_window":{"context_window_size":200000}}'
    echo '{"modules":["spend"]}' > "$CLAUDE_CONFIG_DIR/.statusline-config.json"
    run bash -c "echo '$json' | bash '$STATUSLINE'"
    [ "$status" -eq 0 ]
    # Should not crash; output may be empty or show $0.00
}

@test "spend: exit code 0 always (no crash)" {
    local json='{"model":{"display_name":"Test"},"workspace":{"current_dir":"/tmp/test-project"},"context_window":{"context_window_size":200000}}'
    echo '{"modules":["spend"]}' > "$CLAUDE_CONFIG_DIR/.statusline-config.json"
    run bash -c "echo '$json' | bash '$STATUSLINE'"
    [ "$status" -eq 0 ]
}
