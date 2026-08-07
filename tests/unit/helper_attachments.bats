#!/usr/bin/env bats
# =============================================================================
# Tests: generate_attachment_id(), is_mime_blocked(), format_file_size()
# =============================================================================

setup() {
    load '../test_helper'
    setup_amp_env
    create_test_config
    source_amp_helper
}

# --- generate_attachment_id ---

@test "generate_attachment_id: starts with att_ prefix" {
    local id
    id=$(generate_attachment_id)
    [[ "$id" == att_* ]]
}

@test "generate_attachment_id: has timestamp and hex suffix" {
    local id
    id=$(generate_attachment_id)
    [[ "$id" =~ ^att_[0-9]+_[0-9a-f]+$ ]]
}

@test "generate_attachment_id: two IDs are unique" {
    local id1 id2
    id1=$(generate_attachment_id)
    id2=$(generate_attachment_id)
    [ "$id1" != "$id2" ]
}

# --- is_mime_blocked ---

@test "is_mime_blocked: blocks executable types" {
    run is_mime_blocked "application/x-executable"
    assert_success
}

@test "is_mime_blocked: blocks shell scripts" {
    run is_mime_blocked "application/x-sh"
    assert_success
}

@test "is_mime_blocked: blocks shellscript type" {
    run is_mime_blocked "application/x-shellscript"
    assert_success
}

@test "is_mime_blocked: blocks Windows executables" {
    run is_mime_blocked "application/x-msdownload"
    assert_success
}

@test "is_mime_blocked: blocks Java archives" {
    run is_mime_blocked "application/java-archive"
    assert_success
}

@test "is_mime_blocked: allows PDF" {
    run is_mime_blocked "application/pdf"
    assert_failure
}

@test "is_mime_blocked: allows plain text" {
    run is_mime_blocked "text/plain"
    assert_failure
}

@test "is_mime_blocked: allows JSON" {
    run is_mime_blocked "application/json"
    assert_failure
}

@test "is_mime_blocked: allows images" {
    run is_mime_blocked "image/png"
    assert_failure
}

@test "is_mime_blocked: strips MIME parameters before checking" {
    run is_mime_blocked "application/x-sh; charset=utf-8"
    assert_success
}

@test "is_mime_blocked: case-insensitive check" {
    run is_mime_blocked "Application/X-SH"
    assert_success
}

# --- format_file_size ---

@test "format_file_size: bytes" {
    local result
    result=$(format_file_size 512)
    assert_equal "$result" "512 B"
}

@test "format_file_size: kilobytes" {
    local result
    result=$(format_file_size 10240)
    assert_equal "$result" "10.0 KB"
}

@test "format_file_size: megabytes" {
    local result
    result=$(format_file_size 5242880)
    assert_equal "$result" "5.0 MB"
}

@test "format_file_size: gigabytes" {
    local result
    result=$(format_file_size 2147483648)
    assert_equal "$result" "2.0 GB"
}
