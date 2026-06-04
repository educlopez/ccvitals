#!/usr/bin/env bats

# Tests for subagent-statusline.sh
# Validates per-task row rendering, JSON output contract, truncation, and edge cases.

setup() {
    load 'test_helper/common-setup'
    _common_setup

    SUBAGENT="$PROJECT_ROOT/subagent-statusline.sh"

    # Ensure test temp dirs exist
    mkdir -p "$CLAUDE_CONFIG_DIR"
}

# ─── Helper: sample payloads ───────────────────────────────────────────────────

_payload_two_tasks() {
    # task-1: running, long description, tokenCount=1234, cwd=/tmp/myproject
    # task-2: completed, short description, tokenCount=5200000, cwd=/tmp/other
    printf '%s' '{
        "columns": 80,
        "tasks": [
            {
                "id": "task-1",
                "name": "code-reviewer",
                "type": "agent",
                "status": "running",
                "description": "Reviewing the authentication module for security issues in the codebase",
                "label": "code-reviewer",
                "tokenCount": 1234,
                "cwd": "/home/user/myproject"
            },
            {
                "id": "task-2",
                "name": "formatter",
                "type": "agent",
                "status": "completed",
                "description": "Formatting complete",
                "label": "",
                "tokenCount": 5200000,
                "cwd": "/home/user/other"
            }
        ]
    }'
}

# ─── Output line count ─────────────────────────────────────────────────────────

@test "subagent: two tasks produce exactly 2 output lines" {
    run bash -c "_payload_two_tasks() { printf '%s' '{\"columns\":80,\"tasks\":[{\"id\":\"t1\",\"name\":\"a\",\"status\":\"running\",\"description\":\"d\",\"tokenCount\":0,\"cwd\":\"/tmp/x\"},{\"id\":\"t2\",\"name\":\"b\",\"status\":\"completed\",\"description\":\"e\",\"tokenCount\":0,\"cwd\":\"/tmp/y\"}]}'; }; _payload_two_tasks | bash '$SUBAGENT'"
    [ "$status" -eq 0 ]
    [ "$(echo "$output" | wc -l | xargs)" -eq 2 ]
}

# ─── Valid JSON per line ───────────────────────────────────────────────────────

@test "subagent: each output line is valid JSON with id and content" {
    local payload
    payload='{"columns":80,"tasks":[{"id":"task-1","name":"rv","status":"running","description":"desc","tokenCount":100,"cwd":"/tmp/p"},{"id":"task-2","name":"fm","status":"completed","description":"done","tokenCount":0,"cwd":"/tmp/q"}]}'
    run bash -c "echo '$payload' | bash '$SUBAGENT'"
    [ "$status" -eq 0 ]
    # Two lines of output
    local line_count
    line_count=$(echo "$output" | wc -l | xargs)
    [ "$line_count" -eq 2 ]
    # Each line: jq -e validates .id and .content exist
    while IFS= read -r line; do
        echo "$line" | jq -e '.id' > /dev/null
        echo "$line" | jq -e '.content' > /dev/null
    done <<< "$output"
}

# ─── Running task: CYAN icon ◐ ────────────────────────────────────────────────

@test "subagent: running task row contains CYAN escape and ◐ icon" {
    local payload
    payload='{"columns":80,"tasks":[{"id":"t1","name":"worker","status":"running","description":"doing work","tokenCount":0,"cwd":"/tmp/proj"}]}'
    run bash -c "echo '$payload' | bash '$SUBAGENT'"
    [ "$status" -eq 0 ]
    local content
    content=$(echo "$output" | jq -r '.content')
    # CYAN default escape \033[0;36m
    [[ "$content" == *$'\033[0;36m'* ]]
    # ◐ icon present
    [[ "$content" == *'◐'* ]]
}

# ─── Completed task: GREEN ✓ ──────────────────────────────────────────────────

@test "subagent: completed task row contains GREEN escape and ✓ icon" {
    local payload
    payload='{"columns":80,"tasks":[{"id":"t1","name":"done-task","status":"completed","description":"finished","tokenCount":0,"cwd":"/tmp/proj"}]}'
    run bash -c "echo '$payload' | bash '$SUBAGENT'"
    [ "$status" -eq 0 ]
    local content
    content=$(echo "$output" | jq -r '.content')
    # GREEN default escape \033[0;32m
    [[ "$content" == *$'\033[0;32m'* ]]
    # ✓ icon present
    [[ "$content" == *'✓'* ]]
}

# ─── Stopped task: RED ✗ ──────────────────────────────────────────────────────

@test "subagent: stopped task row contains RED escape and ✗ icon" {
    local payload
    payload='{"columns":80,"tasks":[{"id":"t1","name":"dead-task","status":"stopped","description":"stopped","tokenCount":0,"cwd":"/tmp/proj"}]}'
    run bash -c "echo '$payload' | bash '$SUBAGENT'"
    [ "$status" -eq 0 ]
    local content
    content=$(echo "$output" | jq -r '.content')
    [[ "$content" == *$'\033[0;31m'* ]]
    [[ "$content" == *'✗'* ]]
}

# ─── Unknown status: GRAY · ───────────────────────────────────────────────────

@test "subagent: unknown status row contains GRAY escape and · icon" {
    local payload
    payload='{"columns":80,"tasks":[{"id":"t1","name":"unknown-task","status":"queued","description":"waiting","tokenCount":0,"cwd":"/tmp/proj"}]}'
    run bash -c "echo '$payload' | bash '$SUBAGENT'"
    [ "$status" -eq 0 ]
    local content
    content=$(echo "$output" | jq -r '.content')
    [[ "$content" == *$'\033[0;90m'* ]]
    [[ "$content" == *'·'* ]]
}

# ─── Description truncation within columns ────────────────────────────────────

@test "subagent: long description is truncated so visible row fits within columns" {
    # 80-column terminal, long description
    local payload
    payload='{"columns":80,"tasks":[{"id":"t1","name":"reviewer","status":"running","description":"This is a very long description that exceeds the column limit and must be truncated to fit","tokenCount":1234,"cwd":"/home/user/myproject"}]}'
    run bash -c "echo '$payload' | bash '$SUBAGENT'"
    [ "$status" -eq 0 ]
    local content
    content=$(echo "$output" | jq -r '.content')
    # Strip ANSI SGR sequences to measure visible length
    local visible
    visible=$(printf '%s' "$content" | sed 's/\x1b\[[0-9;]*m//g')
    local vlen
    vlen=${#visible}
    [ "$vlen" -le 80 ]
}

@test "subagent: truncated description ends with ellipsis" {
    local payload
    payload='{"columns":80,"tasks":[{"id":"t1","name":"rv","status":"running","description":"This is a very long description that exceeds the column limit and must be truncated","tokenCount":500,"cwd":"/home/user/myproject"}]}'
    run bash -c "echo '$payload' | bash '$SUBAGENT'"
    [ "$status" -eq 0 ]
    local content
    content=$(echo "$output" | jq -r '.content')
    local visible
    visible=$(printf '%s' "$content" | sed 's/\x1b\[[0-9;]*m//g')
    # Visible text must fit
    [ "${#visible}" -le 80 ]
    # Must contain ellipsis (description was truncated)
    [[ "$content" == *'…'* ]]
}

# ─── Token formatting ─────────────────────────────────────────────────────────

@test "subagent: completed task tokenCount 5200000 renders as 5.2M" {
    local payload
    payload='{"columns":120,"tasks":[{"id":"t1","name":"fm","status":"completed","description":"done","tokenCount":5200000,"cwd":"/tmp/p"}]}'
    run bash -c "echo '$payload' | bash '$SUBAGENT'"
    [ "$status" -eq 0 ]
    local content
    content=$(echo "$output" | jq -r '.content')
    [[ "$content" == *'5.2M'* ]]
}

@test "subagent: running task tokenCount 1234 renders as 1.2k" {
    local payload
    payload='{"columns":120,"tasks":[{"id":"t1","name":"rv","status":"running","description":"reviewing","tokenCount":1234,"cwd":"/tmp/p"}]}'
    run bash -c "echo '$payload' | bash '$SUBAGENT'"
    [ "$status" -eq 0 ]
    local content
    content=$(echo "$output" | jq -r '.content')
    [[ "$content" == *'1.2k'* ]]
}

@test "subagent: tokenCount 0 omits token field from row" {
    local payload
    payload='{"columns":120,"tasks":[{"id":"t1","name":"rv","status":"running","description":"work","tokenCount":0,"cwd":"/tmp/p"}]}'
    run bash -c "echo '$payload' | bash '$SUBAGENT'"
    [ "$status" -eq 0 ]
    local content
    content=$(echo "$output" | jq -r '.content')
    # No "k" or "M" suffix should appear for zero tokens
    local visible
    visible=$(printf '%s' "$content" | sed 's/\x1b\[[0-9;]*m//g')
    [[ "$visible" != *'0k'* ]]
    [[ "$visible" != *'0M'* ]]
}

# ─── cwd basename ─────────────────────────────────────────────────────────────

@test "subagent: cwd basename appears in row content" {
    local payload
    payload='{"columns":120,"tasks":[{"id":"t1","name":"rv","status":"running","description":"work","tokenCount":0,"cwd":"/home/user/my-cool-project"}]}'
    run bash -c "echo '$payload' | bash '$SUBAGENT'"
    [ "$status" -eq 0 ]
    local content
    content=$(echo "$output" | jq -r '.content')
    local visible
    visible=$(printf '%s' "$content" | sed 's/\x1b\[[0-9;]*m//g')
    [[ "$visible" == *'my-cool-project'* ]]
}

# ─── Label preference over name ───────────────────────────────────────────────

@test "subagent: label is shown in preference to name when both present" {
    local payload
    payload='{"columns":120,"tasks":[{"id":"t1","name":"internal-name","status":"running","description":"work","label":"My Label","tokenCount":0,"cwd":"/tmp/p"}]}'
    run bash -c "echo '$payload' | bash '$SUBAGENT'"
    [ "$status" -eq 0 ]
    local content
    content=$(echo "$output" | jq -r '.content')
    local visible
    visible=$(printf '%s' "$content" | sed 's/\x1b\[[0-9;]*m//g')
    [[ "$visible" == *'My Label'* ]]
    [[ "$visible" != *'internal-name'* ]]
}

# ─── Edge cases ───────────────────────────────────────────────────────────────

@test "subagent: empty tasks array produces no output and exits 0" {
    run bash -c "echo '{\"columns\":80,\"tasks\":[]}' | bash '$SUBAGENT'"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "subagent: malformed stdin produces no output and exits 0" {
    run bash -c "echo 'not json at all' | bash '$SUBAGENT'"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "subagent: empty stdin produces no output and exits 0" {
    run bash -c "echo '' | bash '$SUBAGENT'"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "subagent: tasks key absent produces no output and exits 0" {
    run bash -c "echo '{\"columns\":80}' | bash '$SUBAGENT'"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

# ─── Theme awareness ──────────────────────────────────────────────────────────

@test "subagent: tokyo-night theme CYAN for running task is #7dcfff (125;207;255)" {
    echo '{"theme":"tokyo-night"}' > "$CLAUDE_CONFIG_DIR/.statusline-config.json"
    local payload
    payload='{"columns":120,"tasks":[{"id":"t1","name":"worker","status":"running","description":"work","tokenCount":0,"cwd":"/tmp/p"}]}'
    run bash -c "echo '$payload' | bash '$SUBAGENT'"
    [ "$status" -eq 0 ]
    local content
    content=$(echo "$output" | jq -r '.content')
    # tokyo-night CYAN = #7dcfff → 125;207;255
    [[ "$content" == *$'\033[38;2;125;207;255m'* ]]
}

@test "subagent: catppuccin theme GREEN for completed task is #a6e3a1 (166;227;161)" {
    echo '{"theme":"catppuccin"}' > "$CLAUDE_CONFIG_DIR/.statusline-config.json"
    local payload
    payload='{"columns":120,"tasks":[{"id":"t1","name":"done","status":"completed","description":"done","tokenCount":0,"cwd":"/tmp/p"}]}'
    run bash -c "echo '$payload' | bash '$SUBAGENT'"
    [ "$status" -eq 0 ]
    local content
    content=$(echo "$output" | jq -r '.content')
    # catppuccin GREEN = #a6e3a1 → 166;227;161
    [[ "$content" == *$'\033[38;2;166;227;161m'* ]]
}
