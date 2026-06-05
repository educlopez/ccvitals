#!/usr/bin/env bats

# Tests for ccvitals-hook.sh (state writer) and the session module in statusline.sh.

setup() {
    load 'test_helper/common-setup'
    _common_setup

    HOOK="$PROJECT_ROOT/ccvitals-hook.sh"
    STATUSLINE="$PROJECT_ROOT/statusline.sh"
    FIXTURE="$PROJECT_ROOT/test/fixtures/sample-context.json"

    # Mock git/curl to avoid external dependencies
    create_mock "git" 'case "$1" in
        rev-parse) exit 1 ;;
        *) exit 1 ;;
    esac'
    create_mock "curl" 'exit 1'
    mkdir -p /tmp/test-project

    # State dir lives inside isolated CLAUDE_CONFIG_DIR
    export STATE_DIR="$CLAUDE_CONFIG_DIR/.ccvitals-state"
}

# ════════════════════════════════════════════════════════════
# Hook script: basic operation
# ════════════════════════════════════════════════════════════

@test "hook: exits 0 on SessionStart" {
    run bash "$HOOK" <<'EOF'
{"hook_event_name":"SessionStart","session_id":"test-sess-001"}
EOF
    [ "$status" -eq 0 ]
}

@test "hook: exits 0 on MessageDisplay" {
    run bash "$HOOK" <<'EOF'
{"hook_event_name":"MessageDisplay","session_id":"test-sess-001"}
EOF
    [ "$status" -eq 0 ]
}

@test "hook: exits 0 on TaskCreated" {
    run bash "$HOOK" <<'EOF'
{"hook_event_name":"TaskCreated","session_id":"test-sess-001"}
EOF
    [ "$status" -eq 0 ]
}

@test "hook: exits 0 on PostCompact" {
    run bash "$HOOK" <<'EOF'
{"hook_event_name":"PostCompact","session_id":"test-sess-001"}
EOF
    [ "$status" -eq 0 ]
}

@test "hook: exits 0 on Stop" {
    run bash "$HOOK" <<'EOF'
{"hook_event_name":"Stop","session_id":"test-sess-001"}
EOF
    [ "$status" -eq 0 ]
}

@test "hook: exits 0 on malformed JSON without crashing" {
    run bash "$HOOK" <<'EOF'
{not valid json at all!!!
EOF
    [ "$status" -eq 0 ]
}

@test "hook: exits 0 on empty stdin" {
    run bash "$HOOK" < /dev/null
    [ "$status" -eq 0 ]
}

@test "hook: produces no stdout output" {
    run bash "$HOOK" <<'EOF'
{"hook_event_name":"MessageDisplay","session_id":"test-sess-001"}
EOF
    [ -z "$output" ]
}

# ════════════════════════════════════════════════════════════
# Hook script: state file creation and content
# ════════════════════════════════════════════════════════════

@test "hook: creates state file for session" {
    printf '{"hook_event_name":"SessionStart","session_id":"test-sess-100"}' \
        | CLAUDE_CONFIG_DIR="$CLAUDE_CONFIG_DIR" bash "$HOOK"
    [ -f "$STATE_DIR/test-sess-100.json" ]
}

@test "hook: state file contains last_event field" {
    printf '{"hook_event_name":"SessionStart","session_id":"test-sess-101"}' \
        | CLAUDE_CONFIG_DIR="$CLAUDE_CONFIG_DIR" bash "$HOOK"
    local ev
    ev=$(jq -r '.last_event' "$STATE_DIR/test-sess-101.json")
    [ "$ev" = "SessionStart" ]
}

@test "hook: state file contains last_event_at epoch" {
    printf '{"hook_event_name":"SessionStart","session_id":"test-sess-102"}' \
        | CLAUDE_CONFIG_DIR="$CLAUDE_CONFIG_DIR" bash "$HOOK"
    local ts
    ts=$(jq -r '.last_event_at' "$STATE_DIR/test-sess-102.json")
    # Should be a positive integer
    [ "${ts:-0}" -gt 0 ] 2>/dev/null
}

@test "hook: MessageDisplay increments message_count from 0 to 1" {
    printf '{"hook_event_name":"MessageDisplay","session_id":"test-sess-200"}' \
        | CLAUDE_CONFIG_DIR="$CLAUDE_CONFIG_DIR" bash "$HOOK"
    local count
    count=$(jq -r '.message_count' "$STATE_DIR/test-sess-200.json")
    [ "$count" = "1" ]
}

@test "hook: MessageDisplay increments message_count across multiple calls" {
    local sid="test-sess-201"
    # Send 3 messages
    printf '{"hook_event_name":"MessageDisplay","session_id":"%s"}' "$sid" \
        | CLAUDE_CONFIG_DIR="$CLAUDE_CONFIG_DIR" bash "$HOOK"
    printf '{"hook_event_name":"MessageDisplay","session_id":"%s"}' "$sid" \
        | CLAUDE_CONFIG_DIR="$CLAUDE_CONFIG_DIR" bash "$HOOK"
    printf '{"hook_event_name":"MessageDisplay","session_id":"%s"}' "$sid" \
        | CLAUDE_CONFIG_DIR="$CLAUDE_CONFIG_DIR" bash "$HOOK"
    local count
    count=$(jq -r '.message_count' "$STATE_DIR/${sid}.json")
    [ "$count" = "3" ]
}

@test "hook: TaskCreated increments tasks_created from 0 to 1" {
    printf '{"hook_event_name":"TaskCreated","session_id":"test-sess-300"}' \
        | CLAUDE_CONFIG_DIR="$CLAUDE_CONFIG_DIR" bash "$HOOK"
    local tasks
    tasks=$(jq -r '.tasks_created' "$STATE_DIR/test-sess-300.json")
    [ "$tasks" = "1" ]
}

@test "hook: TaskCreated increments tasks_created across multiple calls" {
    local sid="test-sess-301"
    printf '{"hook_event_name":"TaskCreated","session_id":"%s"}' "$sid" \
        | CLAUDE_CONFIG_DIR="$CLAUDE_CONFIG_DIR" bash "$HOOK"
    printf '{"hook_event_name":"TaskCreated","session_id":"%s"}' "$sid" \
        | CLAUDE_CONFIG_DIR="$CLAUDE_CONFIG_DIR" bash "$HOOK"
    local tasks
    tasks=$(jq -r '.tasks_created' "$STATE_DIR/${sid}.json")
    [ "$tasks" = "2" ]
}

@test "hook: SessionStart with session title stores session_title" {
    printf '{"hook_event_name":"SessionStart","session_id":"test-sess-400","session":{"title":"my-refactor"}}' \
        | CLAUDE_CONFIG_DIR="$CLAUDE_CONFIG_DIR" bash "$HOOK"
    local title
    title=$(jq -r '.session_title' "$STATE_DIR/test-sess-400.json")
    [ "$title" = "my-refactor" ]
}

@test "hook: hookSpecificOutput.sessionTitle is captured" {
    printf '{"hook_event_name":"SessionStart","session_id":"test-sess-401","hookSpecificOutput":{"sessionTitle":"hook-title"}}' \
        | CLAUDE_CONFIG_DIR="$CLAUDE_CONFIG_DIR" bash "$HOOK"
    local title
    title=$(jq -r '.session_title' "$STATE_DIR/test-sess-401.json")
    [ "$title" = "hook-title" ]
}

@test "hook: non-SessionStart event does not overwrite existing session_title with empty" {
    local sid="test-sess-402"
    # First: SessionStart sets the title
    printf '{"hook_event_name":"SessionStart","session_id":"%s","session":{"title":"kept-title"}}' "$sid" \
        | CLAUDE_CONFIG_DIR="$CLAUDE_CONFIG_DIR" bash "$HOOK"
    # Then: MessageDisplay has no title — must not clear it
    printf '{"hook_event_name":"MessageDisplay","session_id":"%s"}' "$sid" \
        | CLAUDE_CONFIG_DIR="$CLAUDE_CONFIG_DIR" bash "$HOOK"
    local title
    title=$(jq -r '.session_title' "$STATE_DIR/${sid}.json")
    [ "$title" = "kept-title" ]
}

@test "hook: atomicity — state file is valid JSON after write" {
    local sid="test-sess-500"
    printf '{"hook_event_name":"MessageDisplay","session_id":"%s"}' "$sid" \
        | CLAUDE_CONFIG_DIR="$CLAUDE_CONFIG_DIR" bash "$HOOK"
    jq empty "$STATE_DIR/${sid}.json"
    [ "$?" -eq 0 ]
}

@test "hook: no stray .tmp files after successful write" {
    local sid="test-sess-501"
    printf '{"hook_event_name":"MessageDisplay","session_id":"%s"}' "$sid" \
        | CLAUDE_CONFIG_DIR="$CLAUDE_CONFIG_DIR" bash "$HOOK"
    local tmp_count
    tmp_count=$(find "$STATE_DIR" -name "*.tmp.*" 2>/dev/null | wc -l | tr -d ' ')
    [ "${tmp_count:-0}" -eq 0 ]
}

@test "hook: session_id with special chars is sanitised safely" {
    # session_id containing path-unsafe chars — hook must not error
    run bash "$HOOK" <<'EOF'
{"hook_event_name":"SessionStart","session_id":"../../etc/passwd"}
EOF
    [ "$status" -eq 0 ]
    # The sanitised id should not create a file outside the state dir
    [ ! -f "$CLAUDE_CONFIG_DIR/../etc/passwd" ]
}

# ════════════════════════════════════════════════════════════
# Session module: display
# ════════════════════════════════════════════════════════════

_make_state() {
    local sid="$1"
    local title="$2"
    local count="${3:-0}"
    mkdir -p "$STATE_DIR"
    jq -n --arg t "$title" --argjson c "$count" \
        '{last_event:"MessageDisplay",last_event_at:1748000000,session_title:$t,message_count:$c}' \
        > "$STATE_DIR/${sid}.json"
}

_fixture_with_sid() {
    local sid="$1"
    jq --arg s "$sid" '.session_id = $s' "$FIXTURE"
}

@test "session module: hidden when mod_session=false (default)" {
    _make_state "test-session-123" "my-refactor" 5
    run bash -c "cat '$FIXTURE' | bash '$STATUSLINE'"
    [ "$status" -eq 0 ]
    # Default modules don't include session, so title should not appear
    [[ "$output" != *"§"* ]]
}

@test "session module: shows title when state file present and mod_session=true" {
    local sid="sess-mod-001"
    _make_state "$sid" "my-refactor" 0
    echo '{"modules":["session"]}' > "$CLAUDE_CONFIG_DIR/.statusline-config.json"
    run bash -c "_fixture_with_sid() { jq --arg s \"\$1\" '.session_id = \$s' '$FIXTURE'; }; _fixture_with_sid '$sid' | bash '$STATUSLINE'"
    [ "$status" -eq 0 ]
    [[ "$output" == *"§"* ]]
    [[ "$output" == *"my-refactor"* ]]
}

@test "session module: hidden when no state file" {
    # session_id in fixture has no matching state file
    echo '{"modules":["session"]}' > "$CLAUDE_CONFIG_DIR/.statusline-config.json"
    run bash -c "cat '$FIXTURE' | bash '$STATUSLINE'"
    [ "$status" -eq 0 ]
    [[ "$output" != *"§"* ]]
}

@test "session module: hidden when state file has no session_title" {
    local sid="sess-mod-002"
    mkdir -p "$STATE_DIR"
    printf '{"last_event":"SessionStart","last_event_at":1748000000,"message_count":3}\n' \
        > "$STATE_DIR/${sid}.json"
    echo '{"modules":["session"]}' > "$CLAUDE_CONFIG_DIR/.statusline-config.json"
    run bash -c "jq --arg s '$sid' '.session_id = \$s' '$FIXTURE' | bash '$STATUSLINE'"
    [ "$status" -eq 0 ]
    [[ "$output" != *"§"* ]]
}

@test "session module: session_turns shows turn counter when enabled" {
    local sid="sess-mod-003"
    _make_state "$sid" "code-review" 7
    echo '{"modules":["session"],"session_turns":true}' > "$CLAUDE_CONFIG_DIR/.statusline-config.json"
    run bash -c "jq --arg s '$sid' '.session_id = \$s' '$FIXTURE' | bash '$STATUSLINE'"
    [ "$status" -eq 0 ]
    [[ "$output" == *"§"* ]]
    [[ "$output" == *"code-review"* ]]
    [[ "$output" == *"·7"* ]]
}

@test "session module: session_turns hidden when false (default)" {
    local sid="sess-mod-004"
    _make_state "$sid" "code-review" 9
    echo '{"modules":["session"]}' > "$CLAUDE_CONFIG_DIR/.statusline-config.json"
    run bash -c "jq --arg s '$sid' '.session_id = \$s' '$FIXTURE' | bash '$STATUSLINE'"
    [ "$status" -eq 0 ]
    [[ "$output" == *"§"* ]]
    [[ "$output" != *"·9"* ]]
}

@test "session module: session_turns hidden when count is 0" {
    local sid="sess-mod-005"
    _make_state "$sid" "zero-turns" 0
    echo '{"modules":["session"],"session_turns":true}' > "$CLAUDE_CONFIG_DIR/.statusline-config.json"
    run bash -c "jq --arg s '$sid' '.session_id = \$s' '$FIXTURE' | bash '$STATUSLINE'"
    [ "$status" -eq 0 ]
    [[ "$output" == *"§"* ]]
    [[ "$output" != *"·0"* ]]
}

@test "session module: exits 0 with malformed state file" {
    local sid="sess-mod-006"
    mkdir -p "$STATE_DIR"
    printf 'not valid json\n' > "$STATE_DIR/${sid}.json"
    echo '{"modules":["session"]}' > "$CLAUDE_CONFIG_DIR/.statusline-config.json"
    run bash -c "jq --arg s '$sid' '.session_id = \$s' '$FIXTURE' | bash '$STATUSLINE'"
    [ "$status" -eq 0 ]
}

# ════════════════════════════════════════════════════════════
# Install / uninstall hooks wiring
# ════════════════════════════════════════════════════════════

@test "install --hooks: registers hook entry in settings.json for SessionStart" {
    # Run installer with --hooks --modules=session (non-interactive)
    run bash "$PROJECT_ROOT/install.sh" --hooks --modules=session
    [ "$status" -eq 0 ]
    # Nested schema: event array contains group objects with inner .hooks[]
    local has_hook
    has_hook=$(jq -r '
        if (.hooks.SessionStart | type) == "array" then
            [.hooks.SessionStart[] | .hooks[]? | select(.command? | test("ccvitals-hook"))] | length
        else 0 end
    ' "$CLAUDE_CONFIG_DIR/settings.json")
    [ "${has_hook:-0}" -gt 0 ] 2>/dev/null
}

@test "install --hooks: registers hook entry for MessageDisplay" {
    run bash "$PROJECT_ROOT/install.sh" --hooks --modules=session
    [ "$status" -eq 0 ]
    local has_hook
    has_hook=$(jq -r '
        if (.hooks.MessageDisplay | type) == "array" then
            [.hooks.MessageDisplay[] | .hooks[]? | select(.command? | test("ccvitals-hook"))] | length
        else 0 end
    ' "$CLAUDE_CONFIG_DIR/settings.json")
    [ "${has_hook:-0}" -gt 0 ] 2>/dev/null
}

@test "install --hooks: registers hook entry for TaskCreated" {
    run bash "$PROJECT_ROOT/install.sh" --hooks --modules=session
    [ "$status" -eq 0 ]
    local has_hook
    has_hook=$(jq -r '
        if (.hooks.TaskCreated | type) == "array" then
            [.hooks.TaskCreated[] | .hooks[]? | select(.command? | test("ccvitals-hook"))] | length
        else 0 end
    ' "$CLAUDE_CONFIG_DIR/settings.json")
    [ "${has_hook:-0}" -gt 0 ] 2>/dev/null
}

@test "install --hooks: merges without clobbering existing hooks (nested schema)" {
    # Pre-populate settings.json with a user hook group (nested schema)
    mkdir -p "$CLAUDE_CONFIG_DIR"
    printf '{"hooks":{"SessionStart":[{"hooks":[{"type":"command","command":"echo user-hook"}]}]}}\n' \
        > "$CLAUDE_CONFIG_DIR/settings.json"
    run bash "$PROJECT_ROOT/install.sh" --hooks --modules=session --force
    [ "$status" -eq 0 ]
    # User group's inner command must survive
    local user_hook_count ccvitals_hook_count
    user_hook_count=$(jq -r '[.hooks.SessionStart[] | .hooks[]? | select(.command == "echo user-hook")] | length' "$CLAUDE_CONFIG_DIR/settings.json")
    ccvitals_hook_count=$(jq -r '[.hooks.SessionStart[] | .hooks[]? | select(.command? | test("ccvitals-hook"))] | length' "$CLAUDE_CONFIG_DIR/settings.json")
    [ "${user_hook_count:-0}" -gt 0 ] 2>/dev/null
    [ "${ccvitals_hook_count:-0}" -gt 0 ] 2>/dev/null
}

@test "install --hooks: idempotent — does not duplicate hook entries on re-run" {
    run bash "$PROJECT_ROOT/install.sh" --hooks --modules=session
    [ "$status" -eq 0 ]
    run bash "$PROJECT_ROOT/install.sh" --hooks --modules=session --force
    [ "$status" -eq 0 ]
    local count
    count=$(jq -r '[.hooks.SessionStart[] | .hooks[]? | select(.command? | test("ccvitals-hook"))] | length' "$CLAUDE_CONFIG_DIR/settings.json")
    [ "$count" = "1" ]
}

@test "install --hooks: creates valid nested-schema file when settings.json absent" {
    # Ensure no settings.json exists
    rm -f "$CLAUDE_CONFIG_DIR/settings.json"
    run bash "$PROJECT_ROOT/install.sh" --hooks --modules=session
    [ "$status" -eq 0 ]
    # File must exist and be valid JSON
    [ -f "$CLAUDE_CONFIG_DIR/settings.json" ]
    jq empty "$CLAUDE_CONFIG_DIR/settings.json"
    [ "$?" -eq 0 ]
    # Must use nested schema for SessionStart
    local has_hook
    has_hook=$(jq -r '[.hooks.SessionStart[] | .hooks[]? | select(.command? | test("ccvitals-hook"))] | length' "$CLAUDE_CONFIG_DIR/settings.json")
    [ "${has_hook:-0}" -gt 0 ] 2>/dev/null
}

@test "install --hooks: does not destroy malformed settings.json" {
    # Write invalid JSON as settings.json
    mkdir -p "$CLAUDE_CONFIG_DIR"
    printf 'THIS IS NOT JSON\n' > "$CLAUDE_CONFIG_DIR/settings.json"
    # Installer may exit non-zero when it detects malformed JSON — that is acceptable.
    # The critical invariant is that the file content must not be zeroed out / destroyed.
    run bash "$PROJECT_ROOT/install.sh" --hooks --modules=session --force
    # Original malformed content must be preserved (not zeroed out), regardless of exit code
    local content
    content=$(cat "$CLAUDE_CONFIG_DIR/settings.json")
    [ -n "$content" ]
}

@test "uninstall: removes ccvitals hook entries from settings.json" {
    # Install with hooks first
    run bash "$PROJECT_ROOT/install.sh" --hooks --modules=session
    [ "$status" -eq 0 ]
    # Then uninstall
    run bash "$PROJECT_ROOT/uninstall.sh"
    [ "$status" -eq 0 ]
    # ccvitals hook entries must be gone from inner hooks arrays
    local remaining
    remaining=$(jq -r '
        if .hooks then
            [.hooks | to_entries[] | .value[] | .hooks[]? | select(.command? | test("ccvitals-hook"))] | length
        else 0 end
    ' "$CLAUDE_CONFIG_DIR/settings.json" 2>/dev/null || echo 0)
    [ "${remaining:-0}" -eq 0 ] 2>/dev/null
}

@test "uninstall: preserves user hooks when removing ccvitals entries (nested schema)" {
    # Pre-populate with a user hook group (nested schema) alongside ccvitals
    mkdir -p "$CLAUDE_CONFIG_DIR"
    printf '{"hooks":{"SessionStart":[{"hooks":[{"type":"command","command":"echo user-hook"}]}]}}\n' \
        > "$CLAUDE_CONFIG_DIR/settings.json"
    # Install hooks (this adds a ccvitals group alongside the user group)
    run bash "$PROJECT_ROOT/install.sh" --hooks --modules=session --force
    [ "$status" -eq 0 ]
    # Uninstall
    run bash "$PROJECT_ROOT/uninstall.sh"
    [ "$status" -eq 0 ]
    # User group's inner command must survive
    local user_count
    user_count=$(jq -r '[.hooks.SessionStart[] | .hooks[]? | select(.command == "echo user-hook")] | length' "$CLAUDE_CONFIG_DIR/settings.json" 2>/dev/null || echo 0)
    [ "${user_count:-0}" -gt 0 ] 2>/dev/null
}

@test "uninstall: removes .ccvitals-state directory" {
    mkdir -p "$STATE_DIR"
    printf '{"session_title":"test"}\n' > "$STATE_DIR/test-sess.json"
    run bash "$PROJECT_ROOT/uninstall.sh"
    [ "$status" -eq 0 ]
    [ ! -d "$STATE_DIR" ]
}

@test "uninstall: handles missing state dir gracefully" {
    # State dir does not exist — should not error
    run bash "$PROJECT_ROOT/uninstall.sh"
    [ "$status" -eq 0 ]
}
