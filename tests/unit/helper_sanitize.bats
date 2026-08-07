#!/usr/bin/env bats
# =============================================================================
# Tests: sanitize_address_for_path(), sanitize_filename()
# =============================================================================

setup() {
    load '../test_helper'
    setup_amp_env
    create_test_config
    source_amp_helper
}

# --- sanitize_address_for_path ---

@test "sanitize_address_for_path: replaces @ and . with underscores" {
    local result
    result=$(sanitize_address_for_path "alice@acme.aimaestro.local")
    assert_equal "$result" "alice_acme_aimaestro_local"
}

@test "sanitize_address_for_path: strips special characters" {
    local result
    result=$(sanitize_address_for_path "alice+tag@acme.local")
    assert_equal "$result" "alicetag_acme_local"
}

@test "sanitize_address_for_path: keeps hyphens" {
    local result
    result=$(sanitize_address_for_path "my-agent@my-org.local")
    assert_equal "$result" "my-agent_my-org_local"
}

# --- sanitize_filename ---

@test "sanitize_filename: passes through safe filenames" {
    local result
    result=$(sanitize_filename "document.pdf")
    assert_equal "$result" "document.pdf"
}

@test "sanitize_filename: strips path components" {
    local result
    result=$(sanitize_filename "/etc/passwd")
    assert_equal "$result" "passwd"
}

@test "sanitize_filename: rejects encoded path separators (%2F)" {
    local result
    result=$(sanitize_filename "file%2Fname.txt")
    assert_equal "$result" "unnamed_file"
}

@test "sanitize_filename: rejects encoded backslash (%5C)" {
    local result
    result=$(sanitize_filename "file%5Cname.txt")
    assert_equal "$result" "unnamed_file"
}

@test "sanitize_filename: rejects null bytes (%00)" {
    local result
    result=$(sanitize_filename "file%00name.txt")
    assert_equal "$result" "unnamed_file"
}

@test "sanitize_filename: replaces unsafe characters with underscores" {
    local result
    result=$(sanitize_filename "file name (1).txt")
    assert_equal "$result" "file_name__1_.txt"
}

@test "sanitize_filename: strips leading dots" {
    local result
    result=$(sanitize_filename ".hidden")
    assert_equal "$result" "hidden"
}

@test "sanitize_filename: strips trailing dots" {
    local result
    result=$(sanitize_filename "file.")
    assert_equal "$result" "file"
}

@test "sanitize_filename: enforces 255 character limit" {
    # Create a filename longer than 255 chars
    local long_name
    long_name=$(printf 'a%.0s' {1..260})
    long_name="${long_name}.txt"
    local result
    result=$(sanitize_filename "$long_name")
    [ ${#result} -le 255 ]
}

@test "sanitize_filename: preserves extension when truncating" {
    local long_name
    long_name=$(printf 'a%.0s' {1..260})
    long_name="${long_name}.pdf"
    local result
    result=$(sanitize_filename "$long_name")
    [[ "$result" == *.pdf ]]
}

@test "sanitize_filename: prepends underscore to reserved names (CON)" {
    local result
    result=$(sanitize_filename "CON.txt")
    assert_equal "$result" "_CON.txt"
}

@test "sanitize_filename: prepends underscore to reserved names (NUL)" {
    local result
    result=$(sanitize_filename "NUL")
    assert_equal "$result" "_NUL"
}

@test "sanitize_filename: reserved name check is case-insensitive" {
    local result
    result=$(sanitize_filename "con.txt")
    assert_equal "$result" "_con.txt"
}

@test "sanitize_filename: returns unnamed_file for empty result" {
    local result
    result=$(sanitize_filename "...")
    assert_equal "$result" "unnamed_file"
}
