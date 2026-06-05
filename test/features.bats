#!/usr/bin/env bats

# Tests for Feature 1 (thinking module), Feature 2 (mcp module),
# and Feature 3 (git module extras).

setup() {
    load 'test_helper/common-setup'
    _common_setup

    STATUSLINE="$PROJECT_ROOT/statusline.sh"
    FIXTURE="$PROJECT_ROOT/test/fixtures/sample-context.json"

    # Default git mock: not inside a work tree
    create_mock "git" 'case "$1" in
        rev-parse) exit 1 ;;
        *) exit 1 ;;
    esac'

    # Mock curl to avoid network calls (usage module)
    create_mock "curl" 'exit 1'

    mkdir -p /tmp/test-project

    # Isolated HOME for MCP tests — prevents reading real ~/.claude.json
    MCP_HOME="$BATS_TEST_TMPDIR/home"
    mkdir -p "$MCP_HOME"
}

# Helpers
_strip_ansi() { echo "$1" | sed 's/\x1b\[[0-9;]*m//g'; }

# ════════════════════════════════════════════════════════════
# Feature 1: thinking module
# ════════════════════════════════════════════════════════════

@test "thinking: hidden by default (mod_thinking=false)" {
    # No config — default is mod_thinking=false
    local json='{"model":{"display_name":"Test"},"workspace":{"current_dir":"/tmp/test-project"},"context_window":{"context_window_size":200000},"effort":{"level":"xhigh"}}'
    run bash -c "echo '$json' | bash '$STATUSLINE'"
    [ "$status" -eq 0 ]
    # thinking icon should not appear without enabling the module
    [[ "$output" != *"✦"* ]]
}

@test "thinking: shows effort level when module enabled" {
    local json='{"model":{"display_name":"Test"},"workspace":{"current_dir":"/tmp/test-project"},"context_window":{"context_window_size":200000},"effort":{"level":"high"}}'
    echo '{"modules":["thinking"]}' > "$CLAUDE_CONFIG_DIR/.statusline-config.json"
    run bash -c "echo '$json' | bash '$STATUSLINE'"
    [ "$status" -eq 0 ]
    local clean
    clean=$(echo "$output" | sed 's/\x1b\[[0-9;]*m//g')
    [[ "$clean" == *"✦"* ]]
    [[ "$clean" == *"high"* ]]
}

@test "thinking: shows xhigh effort" {
    local json='{"model":{"display_name":"Test"},"workspace":{"current_dir":"/tmp/test-project"},"context_window":{"context_window_size":200000},"effort":{"level":"xhigh"}}'
    echo '{"modules":["thinking"]}' > "$CLAUDE_CONFIG_DIR/.statusline-config.json"
    run bash -c "echo '$json' | bash '$STATUSLINE'"
    [ "$status" -eq 0 ]
    local clean
    clean=$(echo "$output" | sed 's/\x1b\[[0-9;]*m//g')
    [[ "$clean" == *"✦ xhigh"* ]]
}

@test "thinking: shows medium effort" {
    local json='{"model":{"display_name":"Test"},"workspace":{"current_dir":"/tmp/test-project"},"context_window":{"context_window_size":200000},"effort":{"level":"medium"}}'
    echo '{"modules":["thinking"]}' > "$CLAUDE_CONFIG_DIR/.statusline-config.json"
    run bash -c "echo '$json' | bash '$STATUSLINE'"
    [ "$status" -eq 0 ]
    local clean
    clean=$(echo "$output" | sed 's/\x1b\[[0-9;]*m//g')
    [[ "$clean" == *"✦ medium"* ]]
}

@test "thinking: shows low effort" {
    local json='{"model":{"display_name":"Test"},"workspace":{"current_dir":"/tmp/test-project"},"context_window":{"context_window_size":200000},"effort":{"level":"low"}}'
    echo '{"modules":["thinking"]}' > "$CLAUDE_CONFIG_DIR/.statusline-config.json"
    run bash -c "echo '$json' | bash '$STATUSLINE'"
    [ "$status" -eq 0 ]
    local clean
    clean=$(echo "$output" | sed 's/\x1b\[[0-9;]*m//g')
    [[ "$clean" == *"✦ low"* ]]
}

@test "thinking: hidden when effort field absent" {
    local json='{"model":{"display_name":"Test"},"workspace":{"current_dir":"/tmp/test-project"},"context_window":{"context_window_size":200000}}'
    echo '{"modules":["thinking"]}' > "$CLAUDE_CONFIG_DIR/.statusline-config.json"
    run bash -c "echo '$json' | bash '$STATUSLINE'"
    [ "$status" -eq 0 ]
    local clean
    clean=$(echo "$output" | sed 's/\x1b\[[0-9;]*m//g' | tr -d '[:space:]')
    [ -z "$clean" ]
}

@test "thinking: reads thinking_effort fallback field" {
    local json='{"model":{"display_name":"Test"},"workspace":{"current_dir":"/tmp/test-project"},"context_window":{"context_window_size":200000},"thinking_effort":"high"}'
    echo '{"modules":["thinking"]}' > "$CLAUDE_CONFIG_DIR/.statusline-config.json"
    run bash -c "echo '$json' | bash '$STATUSLINE'"
    [ "$status" -eq 0 ]
    local clean
    clean=$(echo "$output" | sed 's/\x1b\[[0-9;]*m//g')
    [[ "$clean" == *"✦"* ]]
    [[ "$clean" == *"high"* ]]
}

@test "thinking: smart mode hides low effort" {
    local json='{"model":{"display_name":"Test"},"workspace":{"current_dir":"/tmp/test-project"},"context_window":{"context_window_size":200000},"effort":{"level":"low"}}'
    echo '{"modules":["thinking"],"smart":true}' > "$CLAUDE_CONFIG_DIR/.statusline-config.json"
    run bash -c "echo '$json' | bash '$STATUSLINE'"
    [ "$status" -eq 0 ]
    local clean
    clean=$(echo "$output" | sed 's/\x1b\[[0-9;]*m//g' | tr -d '[:space:]')
    [ -z "$clean" ]
}

@test "thinking: smart mode hides medium effort" {
    local json='{"model":{"display_name":"Test"},"workspace":{"current_dir":"/tmp/test-project"},"context_window":{"context_window_size":200000},"effort":{"level":"medium"}}'
    echo '{"modules":["thinking"],"smart":true}' > "$CLAUDE_CONFIG_DIR/.statusline-config.json"
    run bash -c "echo '$json' | bash '$STATUSLINE'"
    [ "$status" -eq 0 ]
    local clean
    clean=$(echo "$output" | sed 's/\x1b\[[0-9;]*m//g' | tr -d '[:space:]')
    [ -z "$clean" ]
}

@test "thinking: smart mode shows high effort" {
    local json='{"model":{"display_name":"Test"},"workspace":{"current_dir":"/tmp/test-project"},"context_window":{"context_window_size":200000},"effort":{"level":"high"}}'
    echo '{"modules":["thinking"],"smart":true}' > "$CLAUDE_CONFIG_DIR/.statusline-config.json"
    run bash -c "echo '$json' | bash '$STATUSLINE'"
    [ "$status" -eq 0 ]
    local clean
    clean=$(echo "$output" | sed 's/\x1b\[[0-9;]*m//g')
    [[ "$clean" == *"✦"* ]]
}

@test "thinking: can coexist with mode module" {
    local json='{"model":{"display_name":"Test"},"workspace":{"current_dir":"/tmp/test-project"},"context_window":{"context_window_size":200000},"effort":{"level":"high"},"fast_mode":false}'
    echo '{"modules":["thinking","mode"]}' > "$CLAUDE_CONFIG_DIR/.statusline-config.json"
    run bash -c "echo '$json' | bash '$STATUSLINE'"
    [ "$status" -eq 0 ]
    local clean
    clean=$(echo "$output" | sed 's/\x1b\[[0-9;]*m//g')
    # Both modules should produce output
    [[ "$clean" == *"✦"* ]]
    [[ "$clean" == *"high"* ]]
}

# ════════════════════════════════════════════════════════════
# Feature 2: mcp module
# All MCP tests run with HOME="$MCP_HOME" to isolate from the real ~/.claude.json
# ════════════════════════════════════════════════════════════

@test "mcp: hidden by default (mod_mcp=false)" {
    # mod_mcp defaults to false — even if MCP files exist the icon won't show
    run env HOME="$MCP_HOME" bash -c "cat '$FIXTURE' | CLAUDE_CONFIG_DIR='$CLAUDE_CONFIG_DIR' bash '$STATUSLINE'"
    [ "$status" -eq 0 ]
    [[ "$output" != *"⬡"* ]]
}

@test "mcp: shows count from project .mcp.json (flat format)" {
    local ws_dir="$BATS_TEST_TMPDIR/ws-flat"
    mkdir -p "$ws_dir"
    # flat format: {serverName: config, ...}
    printf '{"server1":{"command":"npx","args":["-y","@mcp/server1"]},"server2":{"command":"python"}}\n' > "$ws_dir/.mcp.json"

    local json
    json=$(printf '{"model":{"display_name":"Test"},"workspace":{"current_dir":"%s","project_dir":"%s"},"context_window":{"context_window_size":200000}}' "$ws_dir" "$ws_dir")
    echo '{"modules":["mcp"]}' > "$CLAUDE_CONFIG_DIR/.statusline-config.json"
    run env HOME="$MCP_HOME" bash -c "echo '$json' | CLAUDE_CONFIG_DIR='$CLAUDE_CONFIG_DIR' bash '$STATUSLINE'"
    [ "$status" -eq 0 ]
    local clean
    clean=$(echo "$output" | sed 's/\x1b\[[0-9;]*m//g')
    [[ "$clean" == *"⬡ 2"* ]]
}

@test "mcp: shows count from project .mcp.json (mcpServers format)" {
    local ws_dir="$BATS_TEST_TMPDIR/ws-mcp"
    mkdir -p "$ws_dir"
    printf '{"mcpServers":{"srv1":{},"srv2":{},"srv3":{}}}\n' > "$ws_dir/.mcp.json"

    local json
    json=$(printf '{"model":{"display_name":"Test"},"workspace":{"current_dir":"%s","project_dir":"%s"},"context_window":{"context_window_size":200000}}' "$ws_dir" "$ws_dir")
    echo '{"modules":["mcp"]}' > "$CLAUDE_CONFIG_DIR/.statusline-config.json"
    run env HOME="$MCP_HOME" bash -c "echo '$json' | CLAUDE_CONFIG_DIR='$CLAUDE_CONFIG_DIR' bash '$STATUSLINE'"
    [ "$status" -eq 0 ]
    local clean
    clean=$(echo "$output" | sed 's/\x1b\[[0-9;]*m//g')
    [[ "$clean" == *"⬡ 3"* ]]
}

@test "mcp: shows count from settings.json mcpServers" {
    printf '{"mcpServers":{"alpha":{},"beta":{}}}\n' > "$CLAUDE_CONFIG_DIR/settings.json"
    local json='{"model":{"display_name":"Test"},"workspace":{"current_dir":"/tmp/test-project"},"context_window":{"context_window_size":200000}}'
    echo '{"modules":["mcp"]}' > "$CLAUDE_CONFIG_DIR/.statusline-config.json"
    run env HOME="$MCP_HOME" bash -c "echo '$json' | CLAUDE_CONFIG_DIR='$CLAUDE_CONFIG_DIR' bash '$STATUSLINE'"
    [ "$status" -eq 0 ]
    local clean
    clean=$(echo "$output" | sed 's/\x1b\[[0-9;]*m//g')
    [[ "$clean" == *"⬡ 2"* ]]
}

@test "mcp: shows count from global ~/.claude.json mcpServers" {
    # Write a fake ~/.claude.json in the isolated HOME
    printf '{"mcpServers":{"global-a":{},"global-b":{}}}\n' > "$MCP_HOME/.claude.json"
    local json='{"model":{"display_name":"Test"},"workspace":{"current_dir":"/tmp/test-project"},"context_window":{"context_window_size":200000}}'
    echo '{"modules":["mcp"]}' > "$CLAUDE_CONFIG_DIR/.statusline-config.json"
    run env HOME="$MCP_HOME" bash -c "echo '$json' | CLAUDE_CONFIG_DIR='$CLAUDE_CONFIG_DIR' bash '$STATUSLINE'"
    [ "$status" -eq 0 ]
    local clean
    clean=$(echo "$output" | sed 's/\x1b\[[0-9;]*m//g')
    [[ "$clean" == *"⬡ 2"* ]]
}

@test "mcp: accumulates counts from multiple sources" {
    # settings.json: 1 server
    printf '{"mcpServers":{"global-srv":{}}}\n' > "$CLAUDE_CONFIG_DIR/settings.json"
    # project .mcp.json: 2 servers (flat format)
    local ws_dir="$BATS_TEST_TMPDIR/ws-multi"
    mkdir -p "$ws_dir"
    printf '{"proj-a":{},"proj-b":{}}\n' > "$ws_dir/.mcp.json"

    local json
    json=$(printf '{"model":{"display_name":"Test"},"workspace":{"current_dir":"%s","project_dir":"%s"},"context_window":{"context_window_size":200000}}' "$ws_dir" "$ws_dir")
    echo '{"modules":["mcp"]}' > "$CLAUDE_CONFIG_DIR/.statusline-config.json"
    run env HOME="$MCP_HOME" bash -c "echo '$json' | CLAUDE_CONFIG_DIR='$CLAUDE_CONFIG_DIR' bash '$STATUSLINE'"
    [ "$status" -eq 0 ]
    local clean
    clean=$(echo "$output" | sed 's/\x1b\[[0-9;]*m//g')
    [[ "$clean" == *"⬡ 3"* ]]
}

@test "mcp: hidden when no MCP config files present and zero count" {
    # No .mcp.json, no ~/.claude.json mcpServers, no settings.json mcpServers
    printf '{}\n' > "$CLAUDE_CONFIG_DIR/settings.json"
    local json='{"model":{"display_name":"Test"},"workspace":{"current_dir":"/tmp/test-project"},"context_window":{"context_window_size":200000}}'
    echo '{"modules":["mcp"]}' > "$CLAUDE_CONFIG_DIR/.statusline-config.json"
    run env HOME="$MCP_HOME" bash -c "echo '$json' | CLAUDE_CONFIG_DIR='$CLAUDE_CONFIG_DIR' bash '$STATUSLINE'"
    [ "$status" -eq 0 ]
    local clean
    clean=$(echo "$output" | sed 's/\x1b\[[0-9;]*m//g' | tr -d '[:space:]')
    [ -z "$clean" ]
}

@test "mcp: uses cache on second render (no re-parse)" {
    printf '{"mcpServers":{"s1":{},"s2":{},"s3":{}}}\n' > "$CLAUDE_CONFIG_DIR/settings.json"
    local json='{"model":{"display_name":"Test"},"workspace":{"current_dir":"/tmp/test-project"},"context_window":{"context_window_size":200000}}'
    echo '{"modules":["mcp"]}' > "$CLAUDE_CONFIG_DIR/.statusline-config.json"
    # First render — populates cache
    run env HOME="$MCP_HOME" bash -c "echo '$json' | CLAUDE_CONFIG_DIR='$CLAUDE_CONFIG_DIR' bash '$STATUSLINE'"
    [ "$status" -eq 0 ]
    [[ "$(echo "$output" | sed 's/\x1b\[[0-9;]*m//g')" == *"⬡ 3"* ]]
    # Second render — uses cache, still shows correct count
    run env HOME="$MCP_HOME" bash -c "echo '$json' | CLAUDE_CONFIG_DIR='$CLAUDE_CONFIG_DIR' bash '$STATUSLINE'"
    [ "$status" -eq 0 ]
    [[ "$(echo "$output" | sed 's/\x1b\[[0-9;]*m//g')" == *"⬡ 3"* ]]
}

# ════════════════════════════════════════════════════════════
# Feature 3: git module extras
# ════════════════════════════════════════════════════════════

# ── git_sha ──

@test "git extras: git_sha disabled by default" {
    create_mock "git" 'case "$1" in
        rev-parse)
            [ "$2" = "--is-inside-work-tree" ] && { echo "true"; exit 0; }
            [ "$2" = "--short" ] && { echo "abc1234"; exit 0; }
            exit 0 ;;
        branch) echo "main"; exit 0 ;;
        status) exit 0 ;;
        rev-list) exit 1 ;;
        remote) exit 1 ;;
        *) exit 0 ;;
    esac'
    echo '{"modules":["git"]}' > "$CLAUDE_CONFIG_DIR/.statusline-config.json"
    run bash -c "cat '$FIXTURE' | bash '$STATUSLINE'"
    [ "$status" -eq 0 ]
    local clean
    clean=$(echo "$output" | sed 's/\x1b\[[0-9;]*m//g')
    [[ "$clean" != *"abc1234"* ]]
}

@test "git extras: git_sha shows short SHA when enabled" {
    create_mock "git" 'case "$1" in
        rev-parse)
            [ "$2" = "--is-inside-work-tree" ] && { echo "true"; exit 0; }
            [ "$2" = "--git-dir" ] && { echo "/tmp/fake-git"; exit 0; }
            [ "$2" = "--short" ] && { echo "abc1234"; exit 0; }
            exit 0 ;;
        branch) echo "main"; exit 0 ;;
        status) exit 0 ;;
        rev-list) exit 1 ;;
        remote) exit 1 ;;
        stash) exit 0 ;;
        log) exit 1 ;;
        diff) exit 0 ;;
        *) exit 0 ;;
    esac'
    echo '{"modules":["git"],"git_sha":true}' > "$CLAUDE_CONFIG_DIR/.statusline-config.json"
    run bash -c "cat '$FIXTURE' | bash '$STATUSLINE'"
    [ "$status" -eq 0 ]
    local clean
    clean=$(echo "$output" | sed 's/\x1b\[[0-9;]*m//g')
    [[ "$clean" == *"abc1234"* ]]
}

# ── git_stash ──

@test "git extras: git_stash hidden when stash is empty" {
    create_mock "git" 'case "$1" in
        rev-parse)
            [ "$2" = "--is-inside-work-tree" ] && { echo "true"; exit 0; }
            exit 0 ;;
        branch) echo "main"; exit 0 ;;
        status) exit 0 ;;
        stash) exit 0 ;;
        rev-list) exit 1 ;;
        remote) exit 1 ;;
        log) exit 1 ;;
        diff) exit 0 ;;
        *) exit 0 ;;
    esac'
    echo '{"modules":["git"],"git_stash":true}' > "$CLAUDE_CONFIG_DIR/.statusline-config.json"
    run bash -c "cat '$FIXTURE' | bash '$STATUSLINE'"
    [ "$status" -eq 0 ]
    local clean
    clean=$(echo "$output" | sed 's/\x1b\[[0-9;]*m//g')
    # stash indicator should not appear when stash is empty
    [[ "$clean" != *"≡"* ]]
}

@test "git extras: git_stash shows count when stash has entries" {
    create_mock "git" 'case "$1" in
        rev-parse)
            [ "$2" = "--is-inside-work-tree" ] && { echo "true"; exit 0; }
            [ "$2" = "--git-dir" ] && { echo "/tmp/fake-git"; exit 0; }
            exit 0 ;;
        branch) echo "main"; exit 0 ;;
        status) exit 0 ;;
        stash)
            printf "stash@{0}: On main: wip\nstash@{1}: On main: old\n"
            exit 0 ;;
        rev-list) exit 1 ;;
        remote) exit 1 ;;
        log) exit 1 ;;
        diff) exit 0 ;;
        *) exit 0 ;;
    esac'
    echo '{"modules":["git"],"git_stash":true}' > "$CLAUDE_CONFIG_DIR/.statusline-config.json"
    run bash -c "cat '$FIXTURE' | bash '$STATUSLINE'"
    [ "$status" -eq 0 ]
    local clean
    clean=$(echo "$output" | sed 's/\x1b\[[0-9;]*m//g')
    [[ "$clean" == *"≡2"* ]]
}

# ── git_age ──

@test "git extras: git_age shows time since last commit (hours)" {
    # Use a fixed timestamp 2 hours ago
    local ts
    ts=$(( $(date +%s) - 7200 ))
    create_mock "git" "case \"\$1\" in
        rev-parse)
            [ \"\$2\" = \"--is-inside-work-tree\" ] && { echo \"true\"; exit 0; }
            [ \"\$2\" = \"--git-dir\" ] && { echo \"/tmp/fake-git\"; exit 0; }
            exit 0 ;;
        branch) echo \"main\"; exit 0 ;;
        status) exit 0 ;;
        log) echo \"$ts\"; exit 0 ;;
        rev-list) exit 1 ;;
        remote) exit 1 ;;
        stash) exit 0 ;;
        diff) exit 0 ;;
        *) exit 0 ;;
    esac"
    echo '{"modules":["git"],"git_age":true}' > "$CLAUDE_CONFIG_DIR/.statusline-config.json"
    run bash -c "cat '$FIXTURE' | bash '$STATUSLINE'"
    [ "$status" -eq 0 ]
    local clean
    clean=$(echo "$output" | sed 's/\x1b\[[0-9;]*m//g')
    # 2 hours ago should show "2h"
    [[ "$clean" == *"2h"* ]]
}

@test "git extras: git_age shows minutes for recent commits" {
    local ts
    ts=$(( $(date +%s) - 300 ))
    create_mock "git" "case \"\$1\" in
        rev-parse)
            [ \"\$2\" = \"--is-inside-work-tree\" ] && { echo \"true\"; exit 0; }
            [ \"\$2\" = \"--git-dir\" ] && { echo \"/tmp/fake-git\"; exit 0; }
            exit 0 ;;
        branch) echo \"main\"; exit 0 ;;
        status) exit 0 ;;
        log) echo \"$ts\"; exit 0 ;;
        rev-list) exit 1 ;;
        remote) exit 1 ;;
        stash) exit 0 ;;
        diff) exit 0 ;;
        *) exit 0 ;;
    esac"
    echo '{"modules":["git"],"git_age":true}' > "$CLAUDE_CONFIG_DIR/.statusline-config.json"
    run bash -c "cat '$FIXTURE' | bash '$STATUSLINE'"
    [ "$status" -eq 0 ]
    local clean
    clean=$(echo "$output" | sed 's/\x1b\[[0-9;]*m//g')
    [[ "$clean" == *"5m"* ]]
}

@test "git extras: git_age shows days for older commits" {
    local ts
    ts=$(( $(date +%s) - 172800 ))
    create_mock "git" "case \"\$1\" in
        rev-parse)
            [ \"\$2\" = \"--is-inside-work-tree\" ] && { echo \"true\"; exit 0; }
            [ \"\$2\" = \"--git-dir\" ] && { echo \"/tmp/fake-git\"; exit 0; }
            exit 0 ;;
        branch) echo \"main\"; exit 0 ;;
        status) exit 0 ;;
        log) echo \"$ts\"; exit 0 ;;
        rev-list) exit 1 ;;
        remote) exit 1 ;;
        stash) exit 0 ;;
        diff) exit 0 ;;
        *) exit 0 ;;
    esac"
    echo '{"modules":["git"],"git_age":true}' > "$CLAUDE_CONFIG_DIR/.statusline-config.json"
    run bash -c "cat '$FIXTURE' | bash '$STATUSLINE'"
    [ "$status" -eq 0 ]
    local clean
    clean=$(echo "$output" | sed 's/\x1b\[[0-9;]*m//g')
    [[ "$clean" == *"2d"* ]]
}

# ── git_status_split ──

@test "git extras: git_status_split shows staged/unstaged/untracked counts" {
    create_mock "git" 'case "$1" in
        rev-parse)
            [ "$2" = "--is-inside-work-tree" ] && { echo "true"; exit 0; }
            [ "$2" = "--git-dir" ] && { echo "/tmp/fake-git"; exit 0; }
            exit 0 ;;
        branch) echo "feat"; exit 0 ;;
        status)
            # 2 staged (M, A), 1 unstaged (modified), 1 untracked
            printf "M  file1.txt\nA  file2.txt\n M file3.txt\n?? new.txt\n"
            exit 0 ;;
        diff)
            printf "5\t2\tfile1.txt\n3\t0\tfile2.txt\n1\t1\tfile3.txt\n"
            exit 0 ;;
        rev-list) exit 1 ;;
        remote) exit 1 ;;
        stash) exit 0 ;;
        log) exit 1 ;;
        *) exit 0 ;;
    esac'
    echo '{"modules":["git"],"git_status_split":true}' > "$CLAUDE_CONFIG_DIR/.statusline-config.json"
    run bash -c "cat '$FIXTURE' | bash '$STATUSLINE'"
    [ "$status" -eq 0 ]
    local clean
    clean=$(echo "$output" | sed 's/\x1b\[[0-9;]*m//g')
    [[ "$clean" == *"+2"* ]]
    [[ "$clean" == *"~1"* ]]
    [[ "$clean" == *"?1"* ]]
    # Should NOT show "N files" in split mode
    [[ "$clean" != *"files"* ]]
}

@test "git extras: git_status_split clean tree shows branch only (no files)" {
    create_mock "git" 'case "$1" in
        rev-parse)
            [ "$2" = "--is-inside-work-tree" ] && { echo "true"; exit 0; }
            [ "$2" = "--git-dir" ] && { echo "/tmp/fake-git"; exit 0; }
            exit 0 ;;
        branch) echo "main"; exit 0 ;;
        status) exit 0 ;;
        diff) exit 0 ;;
        rev-list) exit 1 ;;
        remote) exit 1 ;;
        stash) exit 0 ;;
        log) exit 1 ;;
        *) exit 0 ;;
    esac'
    echo '{"modules":["git"],"git_status_split":true}' > "$CLAUDE_CONFIG_DIR/.statusline-config.json"
    run bash -c "cat '$FIXTURE' | bash '$STATUSLINE'"
    [ "$status" -eq 0 ]
    local clean
    clean=$(echo "$output" | sed 's/\x1b\[[0-9;]*m//g')
    [[ "$clean" == *"main"* ]]
    # no file counts in split mode for a clean tree
    [[ "$clean" != *"files"* ]]
}

@test "git extras: git_status_split default (false) still shows N files" {
    create_mock "git" 'case "$1" in
        rev-parse)
            [ "$2" = "--is-inside-work-tree" ] && { echo "true"; exit 0; }
            exit 0 ;;
        branch) echo "main"; exit 0 ;;
        status) printf "M  file1.txt\nA  file2.txt\n"; exit 0 ;;
        diff) printf "3\t1\tfile1.txt\n"; exit 0 ;;
        rev-list) exit 1 ;;
        remote) exit 1 ;;
        *) exit 0 ;;
    esac'
    echo '{"modules":["git"]}' > "$CLAUDE_CONFIG_DIR/.statusline-config.json"
    run bash -c "cat '$FIXTURE' | bash '$STATUSLINE'"
    [ "$status" -eq 0 ]
    local clean
    clean=$(echo "$output" | sed 's/\x1b\[[0-9;]*m//g')
    [[ "$clean" == *"2 files"* ]]
}

# ── git_operation ──

@test "git extras: git_operation hidden by default (no banner)" {
    # Even inside a merge, the banner should not show when option is disabled
    local fake_git_dir
    fake_git_dir="$BATS_TEST_TMPDIR/fake-git-op"
    mkdir -p "$fake_git_dir"
    touch "$fake_git_dir/MERGE_HEAD"

    create_mock "git" "case \"\$1\" in
        rev-parse)
            [ \"\$2\" = \"--is-inside-work-tree\" ] && { echo \"true\"; exit 0; }
            [ \"\$2\" = \"--git-dir\" ] && { echo \"$fake_git_dir\"; exit 0; }
            exit 0 ;;
        branch) echo \"main\"; exit 0 ;;
        status) exit 0 ;;
        rev-list) exit 1 ;;
        remote) exit 1 ;;
        stash) exit 0 ;;
        log) exit 1 ;;
        diff) exit 0 ;;
        *) exit 0 ;;
    esac"
    echo '{"modules":["git"]}' > "$CLAUDE_CONFIG_DIR/.statusline-config.json"
    run bash -c "cat '$FIXTURE' | bash '$STATUSLINE'"
    [ "$status" -eq 0 ]
    local clean
    clean=$(echo "$output" | sed 's/\x1b\[[0-9;]*m//g')
    [[ "$clean" != *"MERGE"* ]]
}

@test "git extras: git_operation shows MERGE when MERGE_HEAD present" {
    local fake_git_dir
    fake_git_dir="$BATS_TEST_TMPDIR/fake-git-merge"
    mkdir -p "$fake_git_dir"
    touch "$fake_git_dir/MERGE_HEAD"

    create_mock "git" "case \"\$1\" in
        rev-parse)
            [ \"\$2\" = \"--is-inside-work-tree\" ] && { echo \"true\"; exit 0; }
            [ \"\$2\" = \"--git-dir\" ] && { echo \"$fake_git_dir\"; exit 0; }
            exit 0 ;;
        branch) echo \"main\"; exit 0 ;;
        status) exit 0 ;;
        rev-list) exit 1 ;;
        remote) exit 1 ;;
        stash) exit 0 ;;
        log) exit 1 ;;
        diff) exit 0 ;;
        *) exit 0 ;;
    esac"
    echo '{"modules":["git"],"git_operation":true}' > "$CLAUDE_CONFIG_DIR/.statusline-config.json"
    run bash -c "cat '$FIXTURE' | bash '$STATUSLINE'"
    [ "$status" -eq 0 ]
    local clean
    clean=$(echo "$output" | sed 's/\x1b\[[0-9;]*m//g')
    [[ "$clean" == *"MERGE"* ]]
}

@test "git extras: git_operation shows REBASE when rebase-merge dir present" {
    local fake_git_dir
    fake_git_dir="$BATS_TEST_TMPDIR/fake-git-rebase"
    mkdir -p "$fake_git_dir/rebase-merge"

    create_mock "git" "case \"\$1\" in
        rev-parse)
            [ \"\$2\" = \"--is-inside-work-tree\" ] && { echo \"true\"; exit 0; }
            [ \"\$2\" = \"--git-dir\" ] && { echo \"$fake_git_dir\"; exit 0; }
            exit 0 ;;
        branch) echo \"main\"; exit 0 ;;
        status) exit 0 ;;
        rev-list) exit 1 ;;
        remote) exit 1 ;;
        stash) exit 0 ;;
        log) exit 1 ;;
        diff) exit 0 ;;
        *) exit 0 ;;
    esac"
    echo '{"modules":["git"],"git_operation":true}' > "$CLAUDE_CONFIG_DIR/.statusline-config.json"
    run bash -c "cat '$FIXTURE' | bash '$STATUSLINE'"
    [ "$status" -eq 0 ]
    local clean
    clean=$(echo "$output" | sed 's/\x1b\[[0-9;]*m//g')
    [[ "$clean" == *"REBASE"* ]]
}

@test "git extras: git_operation shows CHERRY-PICK when CHERRY_PICK_HEAD present" {
    local fake_git_dir
    fake_git_dir="$BATS_TEST_TMPDIR/fake-git-cherry"
    mkdir -p "$fake_git_dir"
    touch "$fake_git_dir/CHERRY_PICK_HEAD"

    create_mock "git" "case \"\$1\" in
        rev-parse)
            [ \"\$2\" = \"--is-inside-work-tree\" ] && { echo \"true\"; exit 0; }
            [ \"\$2\" = \"--git-dir\" ] && { echo \"$fake_git_dir\"; exit 0; }
            exit 0 ;;
        branch) echo \"main\"; exit 0 ;;
        status) exit 0 ;;
        rev-list) exit 1 ;;
        remote) exit 1 ;;
        stash) exit 0 ;;
        log) exit 1 ;;
        diff) exit 0 ;;
        *) exit 0 ;;
    esac"
    echo '{"modules":["git"],"git_operation":true}' > "$CLAUDE_CONFIG_DIR/.statusline-config.json"
    run bash -c "cat '$FIXTURE' | bash '$STATUSLINE'"
    [ "$status" -eq 0 ]
    local clean
    clean=$(echo "$output" | sed 's/\x1b\[[0-9;]*m//g')
    [[ "$clean" == *"CHERRY-PICK"* ]]
}

@test "git extras: git_operation shows BISECT when BISECT_LOG present" {
    local fake_git_dir
    fake_git_dir="$BATS_TEST_TMPDIR/fake-git-bisect"
    mkdir -p "$fake_git_dir"
    touch "$fake_git_dir/BISECT_LOG"

    create_mock "git" "case \"\$1\" in
        rev-parse)
            [ \"\$2\" = \"--is-inside-work-tree\" ] && { echo \"true\"; exit 0; }
            [ \"\$2\" = \"--git-dir\" ] && { echo \"$fake_git_dir\"; exit 0; }
            exit 0 ;;
        branch) echo \"main\"; exit 0 ;;
        status) exit 0 ;;
        rev-list) exit 1 ;;
        remote) exit 1 ;;
        stash) exit 0 ;;
        log) exit 1 ;;
        diff) exit 0 ;;
        *) exit 0 ;;
    esac"
    echo '{"modules":["git"],"git_operation":true}' > "$CLAUDE_CONFIG_DIR/.statusline-config.json"
    run bash -c "cat '$FIXTURE' | bash '$STATUSLINE'"
    [ "$status" -eq 0 ]
    local clean
    clean=$(echo "$output" | sed 's/\x1b\[[0-9;]*m//g')
    [[ "$clean" == *"BISECT"* ]]
}

@test "git extras: git_operation shows nothing for clean state" {
    local fake_git_dir
    fake_git_dir="$BATS_TEST_TMPDIR/fake-git-clean"
    mkdir -p "$fake_git_dir"
    # No MERGE_HEAD, no rebase dirs, etc.

    create_mock "git" "case \"\$1\" in
        rev-parse)
            [ \"\$2\" = \"--is-inside-work-tree\" ] && { echo \"true\"; exit 0; }
            [ \"\$2\" = \"--git-dir\" ] && { echo \"$fake_git_dir\"; exit 0; }
            exit 0 ;;
        branch) echo \"main\"; exit 0 ;;
        status) exit 0 ;;
        rev-list) exit 1 ;;
        remote) exit 1 ;;
        stash) exit 0 ;;
        log) exit 1 ;;
        diff) exit 0 ;;
        *) exit 0 ;;
    esac"
    echo '{"modules":["git"],"git_operation":true}' > "$CLAUDE_CONFIG_DIR/.statusline-config.json"
    run bash -c "cat '$FIXTURE' | bash '$STATUSLINE'"
    [ "$status" -eq 0 ]
    local clean
    clean=$(echo "$output" | sed 's/\x1b\[[0-9;]*m//g')
    # No operation banner — just branch
    [[ "$clean" != *"MERGE"* ]]
    [[ "$clean" != *"REBASE"* ]]
    [[ "$clean" != *"CHERRY-PICK"* ]]
    [[ "$clean" != *"BISECT"* ]]
}

# ── multiple git extras together ──

@test "git extras: multiple options can be enabled simultaneously" {
    local fake_git_dir
    fake_git_dir="$BATS_TEST_TMPDIR/fake-git-multi"
    mkdir -p "$fake_git_dir"
    local ts
    ts=$(( $(date +%s) - 3700 ))

    create_mock "git" "case \"\$1\" in
        rev-parse)
            [ \"\$2\" = \"--is-inside-work-tree\" ] && { echo \"true\"; exit 0; }
            [ \"\$2\" = \"--git-dir\" ] && { echo \"$fake_git_dir\"; exit 0; }
            [ \"\$2\" = \"--short\" ] && { echo \"def5678\"; exit 0; }
            exit 0 ;;
        branch) echo \"main\"; exit 0 ;;
        status) exit 0 ;;
        stash) printf \"stash@{0}: wip\n\"; exit 0 ;;
        log) echo \"$ts\"; exit 0 ;;
        rev-list) exit 1 ;;
        remote) exit 1 ;;
        diff) exit 0 ;;
        *) exit 0 ;;
    esac"
    echo '{"modules":["git"],"git_sha":true,"git_stash":true,"git_age":true}' > "$CLAUDE_CONFIG_DIR/.statusline-config.json"
    run bash -c "cat '$FIXTURE' | bash '$STATUSLINE'"
    [ "$status" -eq 0 ]
    local clean
    clean=$(echo "$output" | sed 's/\x1b\[[0-9;]*m//g')
    [[ "$clean" == *"def5678"* ]]
    [[ "$clean" == *"≡1"* ]]
    # ~1 hour ago
    [[ "$clean" == *"1h"* ]]
}
