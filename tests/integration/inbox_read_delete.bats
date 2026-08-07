#!/usr/bin/env bats
# =============================================================================
# Integration Tests: amp-inbox.sh, amp-read.sh, amp-delete.sh lifecycle
# =============================================================================

setup() {
    load '../test_helper'
    setup_amp_env
    create_test_config "testagent" "testorg"
    create_test_keys

    # Populate inbox with test messages
    create_inbox_message "msg_1000_aa" "alice@testorg.aimaestro.local" "First Message" "Hello from Alice"
    create_inbox_message "msg_1001_bb" "bob@testorg.aimaestro.local" "Second Message" "Hello from Bob"
}

# --- amp-inbox.sh ---

@test "inbox: lists messages" {
    run bash "${SCRIPTS_DIR}/amp-inbox.sh"
    assert_success
    assert_output --partial "First Message"
    assert_output --partial "Second Message"
}

@test "inbox: --json returns valid JSON" {
    run bash "${SCRIPTS_DIR}/amp-inbox.sh" --json
    assert_success
    # Parse as JSON to verify
    echo "$output" | jq . >/dev/null
}

@test "inbox: --json returns correct count" {
    run bash "${SCRIPTS_DIR}/amp-inbox.sh" --json
    assert_success
    local count
    count=$(echo "$output" | jq 'length')
    assert_equal "$count" "2"
}

@test "inbox: shows unread count" {
    run bash "${SCRIPTS_DIR}/amp-inbox.sh"
    assert_success
    assert_output --partial "2"
}

# --- amp-read.sh ---

@test "read: displays message content" {
    run bash "${SCRIPTS_DIR}/amp-read.sh" "msg_1000_aa"
    assert_success
    assert_output --partial "Hello from Alice"
}

@test "read: marks message as read" {
    bash "${SCRIPTS_DIR}/amp-read.sh" "msg_1000_aa" >/dev/null 2>&1

    # Check message status
    local msg_file
    msg_file=$(find "${AMP_DIR}/messages/inbox" -name "msg_1000_aa.json" | head -1)
    local status
    status=$(jq -r '.local.status // .metadata.status' "$msg_file")
    assert_equal "$status" "read"
}

@test "read: rejects invalid message ID" {
    run bash "${SCRIPTS_DIR}/amp-read.sh" "../../../etc/passwd"
    assert_failure
    assert_output --partial "Invalid message ID"
}

@test "read: reports not found for nonexistent message" {
    run bash "${SCRIPTS_DIR}/amp-read.sh" "msg_9999_zz"
    assert_failure
    assert_output --partial "not found"
}

# --- amp-delete.sh ---

@test "delete: removes message from inbox" {
    run bash "${SCRIPTS_DIR}/amp-delete.sh" "msg_1000_aa" --force
    assert_success

    # Verify file is gone
    local msg_file
    msg_file=$(find "${AMP_DIR}/messages/inbox" -name "msg_1000_aa.json" 2>/dev/null | head -1)
    [ -z "$msg_file" ]
}

@test "delete: rejects invalid message ID" {
    run bash "${SCRIPTS_DIR}/amp-delete.sh" "../../../etc/passwd" --force
    assert_failure
}

@test "delete: fails for nonexistent message" {
    run bash "${SCRIPTS_DIR}/amp-delete.sh" "msg_9999_zz" --force
    assert_failure
}

# --- Full lifecycle ---

@test "lifecycle: send → inbox → read → delete" {
    # This test starts fresh with just the pre-created messages
    # Verify messages are in inbox
    run bash "${SCRIPTS_DIR}/amp-inbox.sh" --json
    assert_success
    local initial_count
    initial_count=$(echo "$output" | jq 'length')
    assert_equal "$initial_count" "2"

    # Read first message
    run bash "${SCRIPTS_DIR}/amp-read.sh" "msg_1000_aa"
    assert_success

    # Delete first message
    run bash "${SCRIPTS_DIR}/amp-delete.sh" "msg_1000_aa" --force
    assert_success

    # Inbox should have 1 message
    run bash "${SCRIPTS_DIR}/amp-inbox.sh" --json
    assert_success
    local final_count
    final_count=$(echo "$output" | jq 'length')
    assert_equal "$final_count" "1"
}
