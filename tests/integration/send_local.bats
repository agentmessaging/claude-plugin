#!/usr/bin/env bats
# =============================================================================
# Integration Tests: Local send end-to-end
# =============================================================================

setup() {
    load '../test_helper'
    setup_amp_env
    create_test_config "sender" "testorg"
    create_test_keys

    # Set up a local recipient
    local recipient_uuid="test-uuid-alice"
    RECIPIENT_DIR="${HOME}/.agent-messaging/agents/${recipient_uuid}"
    mkdir -p "${RECIPIENT_DIR}/messages/inbox"
    mkdir -p "${RECIPIENT_DIR}/keys"
    cat > "${RECIPIENT_DIR}/config.json" << 'EOF'
{"version":"1.1","agent":{"name":"alice","tenant":"testorg","address":"alice@testorg.aimaestro.local"}}
EOF
    echo '{"alice":"test-uuid-alice"}' > "${HOME}/.agent-messaging/agents/.index.json"

    # Local registration so we enter the registered code path
    create_local_registration "http://localhost:99999/api/v1" "test-api-key"
}

@test "send_local: message appears in recipient inbox" {
    run bash "${SCRIPTS_DIR}/amp-send.sh" "alice" "Hello" "Hi Alice"
    assert_success

    local msg_files
    msg_files=$(find "${RECIPIENT_DIR}/messages/inbox" -name "msg_*.json" | head -1)
    [ -n "$msg_files" ]
}

@test "send_local: message has correct subject" {
    run bash "${SCRIPTS_DIR}/amp-send.sh" "alice" "Test Subject" "Body text"
    assert_success

    local msg_file
    msg_file=$(find "${RECIPIENT_DIR}/messages/inbox" -name "msg_*.json" | head -1)
    local subject
    subject=$(jq -r '.envelope.subject' "$msg_file")
    assert_equal "$subject" "Test Subject"
}

@test "send_local: message has valid signature" {
    run bash "${SCRIPTS_DIR}/amp-send.sh" "alice" "Signed" "This is signed"
    assert_success

    local msg_file
    msg_file=$(find "${RECIPIENT_DIR}/messages/inbox" -name "msg_*.json" | head -1)
    local sig
    sig=$(jq -r '.envelope.signature' "$msg_file")
    [ -n "$sig" ]
    [ "$sig" != "null" ]
}

@test "send_local: sent copy exists" {
    run bash "${SCRIPTS_DIR}/amp-send.sh" "alice" "Sent Copy" "Check sent"
    assert_success

    local sent_files
    sent_files=$(find "${AMP_DIR}/messages/sent" -name "msg_*.json" | head -1)
    [ -n "$sent_files" ]
}

@test "send_local: priority flag passes through" {
    run bash "${SCRIPTS_DIR}/amp-send.sh" "alice" "Urgent" "Please help" --priority urgent
    assert_success
    assert_output --partial "Priority: urgent"
}

@test "send_local: type flag passes through" {
    run bash "${SCRIPTS_DIR}/amp-send.sh" "alice" "Task" "Do this" --type task
    assert_success
    assert_output --partial "Type:     task"
}

@test "send_local: recipient message has unread status" {
    run bash "${SCRIPTS_DIR}/amp-send.sh" "alice" "Status Test" "Body"
    assert_success

    local msg_file
    msg_file=$(find "${RECIPIENT_DIR}/messages/inbox" -name "msg_*.json" | head -1)
    local status
    status=$(jq -r '.local.status' "$msg_file")
    assert_equal "$status" "unread"
}
