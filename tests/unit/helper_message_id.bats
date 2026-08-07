#!/usr/bin/env bats
# =============================================================================
# Tests: generate_message_id() and validate_message_id()
# =============================================================================

setup() {
    load '../test_helper'
    setup_amp_env
    create_test_config
    source_amp_helper
}

# --- generate_message_id ---

@test "generate_message_id: starts with msg_ prefix" {
    local id
    id=$(generate_message_id)
    [[ "$id" == msg_* ]]
}

@test "generate_message_id: format is msg_<seconds>_<hex>" {
    local id
    id=$(generate_message_id)
    # msg_<digits>_<hex>
    [[ "$id" =~ ^msg_[0-9]+_[0-9a-f]+$ ]]
}

@test "generate_message_id: timestamp is in seconds (not milliseconds)" {
    local id
    id=$(generate_message_id)
    # Extract timestamp part
    local ts="${id#msg_}"
    ts="${ts%%_*}"
    # Seconds timestamps are 10 digits (until year 2286)
    # Millisecond timestamps would be 13 digits
    local len=${#ts}
    assert_equal "$len" "10"
}

@test "generate_message_id: two IDs are unique" {
    local id1 id2
    id1=$(generate_message_id)
    id2=$(generate_message_id)
    [ "$id1" != "$id2" ]
}

# --- validate_message_id ---

@test "validate_message_id: accepts valid ID with underscores" {
    run validate_message_id "msg_1706000000_abcdef12"
    assert_success
}

@test "validate_message_id: accepts valid ID with hyphens" {
    run validate_message_id "msg-1706000000-abcdef12"
    assert_success
}

@test "validate_message_id: rejects path traversal (../)" {
    run validate_message_id "../../../etc/passwd"
    assert_failure
}

@test "validate_message_id: rejects slashes" {
    run validate_message_id "msg_123_abc/../../etc"
    assert_failure
}

@test "validate_message_id: rejects dots" {
    run validate_message_id "msg_123.json"
    assert_failure
}

@test "validate_message_id: rejects empty string" {
    run validate_message_id ""
    assert_failure
}

@test "validate_message_id: rejects spaces" {
    run validate_message_id "msg 123 abc"
    assert_failure
}

@test "validate_message_id: rejects missing prefix" {
    run validate_message_id "1706000000_abcdef12"
    assert_failure
}
