#!/usr/bin/env bats
# =============================================================================
# Tests: create_message() - envelope structure, required fields, defaults
# =============================================================================

setup() {
    load '../test_helper'
    setup_amp_env
    create_test_config "sender" "testorg"
    create_test_keys
    source_amp_helper
}

@test "create_message: returns valid JSON" {
    local msg
    msg=$(create_message "alice" "Test Subject" "Hello")
    echo "$msg" | jq . >/dev/null
}

@test "create_message: envelope has required fields" {
    local msg
    msg=$(create_message "alice" "Test Subject" "Hello")
    local has_version has_id has_from has_to has_subject
    has_version=$(echo "$msg" | jq -r '.envelope.version')
    has_id=$(echo "$msg" | jq -r '.envelope.id')
    has_from=$(echo "$msg" | jq -r '.envelope.from')
    has_to=$(echo "$msg" | jq -r '.envelope.to')
    has_subject=$(echo "$msg" | jq -r '.envelope.subject')

    assert_equal "$has_version" "amp/0.1"
    [[ "$has_id" == msg_* ]]
    assert_equal "$has_from" "sender@testorg.aimaestro.local"
    assert_equal "$has_subject" "Test Subject"
}

@test "create_message: defaults priority to normal" {
    local msg
    msg=$(create_message "alice" "Test" "Hello")
    local priority
    priority=$(echo "$msg" | jq -r '.envelope.priority')
    assert_equal "$priority" "normal"
}

@test "create_message: defaults type to notification" {
    local msg
    msg=$(create_message "alice" "Test" "Hello")
    local type
    type=$(echo "$msg" | jq -r '.payload.type')
    assert_equal "$type" "notification"
}

@test "create_message: accepts custom priority" {
    local msg
    msg=$(create_message "alice" "Test" "Hello" "notification" "urgent")
    local priority
    priority=$(echo "$msg" | jq -r '.envelope.priority')
    assert_equal "$priority" "urgent"
}

@test "create_message: accepts custom type" {
    local msg
    msg=$(create_message "alice" "Test" "Hello" "task")
    local type
    type=$(echo "$msg" | jq -r '.payload.type')
    assert_equal "$type" "task"
}

@test "create_message: sets body in payload.message" {
    local msg
    msg=$(create_message "alice" "Test" "My message body")
    local body
    body=$(echo "$msg" | jq -r '.payload.message')
    assert_equal "$body" "My message body"
}

@test "create_message: thread_id defaults to message id" {
    local msg
    msg=$(create_message "alice" "Test" "Hello")
    local msg_id thread_id
    msg_id=$(echo "$msg" | jq -r '.envelope.id')
    thread_id=$(echo "$msg" | jq -r '.envelope.thread_id')
    assert_equal "$thread_id" "$msg_id"
}

@test "create_message: in_reply_to defaults to null" {
    local msg
    msg=$(create_message "alice" "Test" "Hello")
    local reply_to
    reply_to=$(echo "$msg" | jq -r '.envelope.in_reply_to')
    assert_equal "$reply_to" "null"
}

@test "create_message: metadata has unread status" {
    local msg
    msg=$(create_message "alice" "Test" "Hello")
    local status
    status=$(echo "$msg" | jq -r '.metadata.status')
    assert_equal "$status" "unread"
}

@test "create_message: resolves short name to full address" {
    local msg
    msg=$(create_message "alice" "Test" "Hello")
    local to
    to=$(echo "$msg" | jq -r '.envelope.to')
    assert_equal "$to" "alice@testorg.aimaestro.local"
}
