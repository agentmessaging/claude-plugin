#!/usr/bin/env bats
# =============================================================================
# Tests: save_to_inbox(), save_to_sent(), find_message_file(), list_inbox()
# =============================================================================

setup() {
    load '../test_helper'
    setup_amp_env
    create_test_config "testagent" "testorg"
    create_test_keys
    source_amp_helper
}

# --- save_to_inbox ---

@test "save_to_inbox: creates file in sender subdirectory" {
    local msg='{"envelope":{"id":"msg_1000_aa","from":"alice@testorg.aimaestro.local","to":"testagent@testorg.aimaestro.local","subject":"Hi","priority":"normal","signature":null},"payload":{"type":"notification","message":"Hello","context":null}}'
    local result
    result=$(save_to_inbox "$msg" "false")
    [ -f "$result" ]
    # Check sender subdirectory exists
    echo "$result" | grep -q "inbox/alice_testorg_aimaestro_local"
}

@test "save_to_inbox: replay protection rejects duplicate message ID" {
    local msg='{"envelope":{"id":"msg_1000_bb","from":"alice@testorg.aimaestro.local","to":"testagent@testorg.aimaestro.local","subject":"Hi","priority":"normal","signature":null},"payload":{"type":"notification","message":"Hello","context":null}}'

    # First save succeeds
    save_to_inbox "$msg" "false" >/dev/null

    # Second save should fail (replay)
    run save_to_inbox "$msg" "false"
    assert_failure
    assert_output --partial "Replay detected"
}

@test "save_to_inbox: adds received_at to local metadata" {
    local msg='{"envelope":{"id":"msg_1000_cc","from":"alice@testorg.aimaestro.local","to":"testagent@testorg.aimaestro.local","subject":"Hi","priority":"normal","signature":null},"payload":{"type":"notification","message":"Hello","context":null}}'
    local result
    result=$(save_to_inbox "$msg" "false")
    local received_at
    received_at=$(jq -r '.local.received_at' "$result")
    [ -n "$received_at" ]
    [ "$received_at" != "null" ]
}

@test "save_to_inbox: sets status to unread" {
    local msg='{"envelope":{"id":"msg_1000_dd","from":"alice@testorg.aimaestro.local","to":"testagent@testorg.aimaestro.local","subject":"Hi","priority":"normal","signature":null},"payload":{"type":"notification","message":"Hello","context":null}}'
    local result
    result=$(save_to_inbox "$msg" "false")
    local status
    status=$(jq -r '.local.status' "$result")
    assert_equal "$status" "unread"
}

# --- save_to_sent ---

@test "save_to_sent: creates file in recipient subdirectory" {
    local msg='{"envelope":{"id":"msg_2000_aa","from":"testagent@testorg.aimaestro.local","to":"bob@testorg.aimaestro.local","subject":"Reply","priority":"normal"},"payload":{"type":"notification","message":"Response","context":null}}'
    local result
    result=$(save_to_sent "$msg")
    [ -f "$result" ]
    echo "$result" | grep -q "sent/bob_testorg_aimaestro_local"
}

@test "save_to_sent: adds sent_at to local metadata" {
    local msg='{"envelope":{"id":"msg_2000_bb","from":"testagent@testorg.aimaestro.local","to":"bob@testorg.aimaestro.local","subject":"Reply","priority":"normal"},"payload":{"type":"notification","message":"Response","context":null}}'
    local result
    result=$(save_to_sent "$msg")
    local sent_at
    sent_at=$(jq -r '.local.sent_at' "$result")
    [ -n "$sent_at" ]
    [ "$sent_at" != "null" ]
}

# --- find_message_file ---

@test "find_message_file: finds message in sender subdirectory" {
    create_inbox_message "msg_3000_aa" "alice@testorg.aimaestro.local" "Test" "Hello"
    local result
    result=$(find_message_file "msg_3000_aa" "${AMP_DIR}/messages/inbox")
    [ -n "$result" ]
    [ -f "$result" ]
}

@test "find_message_file: finds message in flat structure (backward compat)" {
    # Create message directly in inbox root (old flat structure)
    echo '{"envelope":{"id":"msg_3000_bb"}}' > "${AMP_DIR}/messages/inbox/msg_3000_bb.json"
    local result
    result=$(find_message_file "msg_3000_bb" "${AMP_DIR}/messages/inbox")
    [ -n "$result" ]
}

@test "find_message_file: returns failure for nonexistent message" {
    run find_message_file "msg_9999_zz" "${AMP_DIR}/messages/inbox"
    assert_failure
}

@test "find_message_file: rejects invalid message ID" {
    run find_message_file "../../../etc/passwd" "${AMP_DIR}/messages/inbox"
    assert_failure
}

# --- list_inbox ---

@test "list_inbox: returns empty array when no messages" {
    local result
    result=$(list_inbox)
    assert_equal "$result" "[]"
}

@test "list_inbox: lists messages from sender subdirectories" {
    create_inbox_message "msg_4000_aa" "alice@testorg.aimaestro.local" "First" "Hello"
    create_inbox_message "msg_4001_bb" "bob@testorg.aimaestro.local" "Second" "Hi"

    local result
    result=$(list_inbox)
    local count
    count=$(echo "$result" | jq 'length')
    assert_equal "$count" "2"
}

@test "list_inbox: filters by status" {
    create_inbox_message "msg_5000_aa" "alice@testorg.aimaestro.local" "Unread" "Hello"

    # Mark one as read
    local msg_file
    msg_file=$(find_message_file "msg_5000_aa" "${AMP_DIR}/messages/inbox")
    jq '.local.status = "read"' "$msg_file" > "${msg_file}.tmp" && mv "${msg_file}.tmp" "$msg_file"

    create_inbox_message "msg_5001_bb" "bob@testorg.aimaestro.local" "Still Unread" "Hi"

    local unread
    unread=$(list_inbox "unread")
    local count
    count=$(echo "$unread" | jq 'length')
    assert_equal "$count" "1"
}

@test "list_inbox: returns messages sorted by timestamp (newest first)" {
    create_inbox_message "msg_4000_aa" "alice@testorg.aimaestro.local" "Older" "Hello"

    # Create a newer message with later timestamp
    local sender_dir
    sender_dir=$(echo "bob@testorg.aimaestro.local" | sed 's/[@.]/_/g' | sed 's/[^a-zA-Z0-9_-]//g')
    mkdir -p "${AMP_DIR}/messages/inbox/${sender_dir}"
    cat > "${AMP_DIR}/messages/inbox/${sender_dir}/msg_4001_bb.json" << 'EOF'
{"envelope":{"id":"msg_4001_bb","from":"bob@testorg.aimaestro.local","to":"testagent@testorg.aimaestro.local","subject":"Newer","priority":"normal","timestamp":"2025-01-02T12:00:00Z"},"payload":{"type":"notification","message":"Hi"},"local":{"status":"unread"}}
EOF

    local result
    result=$(list_inbox)
    local first_subject
    first_subject=$(echo "$result" | jq -r '.[0].envelope.subject')
    assert_equal "$first_subject" "Newer"
}
