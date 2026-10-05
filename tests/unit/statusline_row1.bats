#!/usr/bin/env bats
# The status line's first row names the agent: name, AMP address and folder,
# then the unread count. In a narrow pane it is shortened, never wrapped.

setup() {
    load '../test_helper'
    setup_amp_env
    UUID="11111111-2222-3333-4444-555555555555"
    mkdir -p "${HOME}/.agent-messaging/agents/${UUID}/messages/inbox"
    cat > "${HOME}/.agent-messaging/agents/${UUID}/config.json" <<JSON
{"agent":{"name":"web-agent","address":"web-agent@acme.aimaestro.local"}}
JSON
    export AMP_AGENT_ID="$UUID"
    DIR="${HOME}/work/sites/acme"
    mkdir -p "$DIR"
}

# Run the script the way Claude Code does: JSON on stdin, COLUMNS in the env.
run_line() {
    local cols="$1"
    printf '{"model":{"display_name":"Opus"},"context_window":{"used_percentage":10,"total_input_tokens":20000},"cost":{"total_cost_usd":0.5},"workspace":{"current_dir":"%s"}}' "$DIR" \
        | COLUMNS="$cols" bash "${SCRIPTS_DIR}/amp-statusline.sh"
}

@test "row 1 shows name, address and folder, with the home directory as ~" {
    run run_line 200
    assert_success
    assert_line --index 0 "web-agent · web-agent@acme.aimaestro.local · ~/work/sites/acme | 0 unread"
}

@test "row 2 keeps the model, context and cost" {
    run run_line 200
    assert_line --index 1 --partial "Opus | ctx"
    assert_line --index 1 --partial '$0.50'
}

@test "a narrow pane shortens the folder to its last two parts first" {
    run run_line 70
    assert_line --index 0 "web-agent · web-agent@acme.aimaestro.local · …/sites/acme | 0 unread"
}

@test "narrower still drops the folder, then the name" {
    run run_line 60
    assert_line --index 0 "web-agent · web-agent@acme.aimaestro.local | 0 unread"
    run run_line 50
    assert_line --index 0 "web-agent@acme.aimaestro.local | 0 unread"
}

@test "no COLUMNS means no shortening" {
    run bash -c 'printf "{\"workspace\":{\"current_dir\":\"%s\"}}" "$1" | env -u COLUMNS bash "$2/amp-statusline.sh"' _ "$DIR" "$SCRIPTS_DIR"
    assert_line --index 0 --partial "~/work/sites/acme"
}

@test "the unread count is still shown" {
    echo '{"local":{"status":"unread"}}' > "${HOME}/.agent-messaging/agents/${UUID}/messages/inbox/m1.json"
    run run_line 200
    assert_line --index 0 --partial "2 unread" || assert_line --index 0 --partial "1 unread"
}

@test "an agent with no address still shows the not-configured notice" {
    export AMP_AGENT_ID="99999999-0000-0000-0000-000000000000"
    run run_line 200
    assert_line --index 0 "AMP: not configured (run amp-init)"
}

@test "the compact recommendation on row 2 is unchanged" {
    run bash -c 'printf "{\"context_window\":{\"used_percentage\":12,\"total_input_tokens\":160000},\"workspace\":{\"current_dir\":\"%s\"}}" "$1" | COLUMNS=200 bash "$2/amp-statusline.sh"' _ "$DIR" "$SCRIPTS_DIR"
    assert_line --index 1 --partial "160k (12%) · /compact soon"
}
