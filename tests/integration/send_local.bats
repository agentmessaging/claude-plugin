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

@test "send_local: with the provider answering, the provider delivers and the sender writes no inbox" {
    mock_curl 200 '{"id":"msg_1_abc","status":"delivered","method":"local"}'
    run bash "${SCRIPTS_DIR}/amp-send.sh" "alice" "Via provider" "Body"
    assert_success
    assert_output --partial "Message sent via AMP routing"
    run get_curl_calls
    assert_output --partial "/route"
    [ -z "$(find "${RECIPIENT_DIR}/messages/inbox" -name 'msg_*.json')" ]
}

@test "send_local: provider not answering and the host has rules: refused, nothing written" {
    mkdir -p "${HOME}/.aimaestro"
    echo '{"version":1,"rules":[]}' > "${HOME}/.aimaestro/policy.json"
    run bash "${SCRIPTS_DIR}/amp-send.sh" "alice" "Blocked" "Body"
    assert_failure
    assert_output --partial "Not sent"
    [ -z "$(find "${RECIPIENT_DIR}/messages/inbox" -name 'msg_*.json')" ]
}

@test "send_local: a deleted rules file still counts while its saved copy is there" {
    mkdir -p "${HOME}/.aimaestro"
    echo '{"version":1,"rules":[]}' > "${HOME}/.aimaestro/policy.json.last-good"
    run bash "${SCRIPTS_DIR}/amp-send.sh" "alice" "Blocked" "Body"
    assert_failure
    [ -z "$(find "${RECIPIENT_DIR}/messages/inbox" -name 'msg_*.json')" ]
}

@test "send_local: provider not answering and no rules: written directly, and it says so" {
    run bash "${SCRIPTS_DIR}/amp-send.sh" "alice" "Direct" "Body"
    assert_success
    assert_output --partial "is not answering; delivering straight to the recipient's inbox"
    refute_output --partial "Failed to send"
}
