#!/usr/bin/env bats
# =============================================================================
# Tests: get_message_route(), is_registered(), get_registration()
# =============================================================================

setup() {
    load '../test_helper'
    setup_amp_env
    create_test_config
    source_amp_helper
}

# --- get_message_route ---

@test "get_message_route: local address returns 'local'" {
    local route
    route=$(get_message_route "alice@testorg.aimaestro.local")
    assert_equal "$route" "local"
}

@test "get_message_route: short name returns 'local'" {
    local route
    route=$(get_message_route "alice")
    assert_equal "$route" "local"
}

@test "get_message_route: external address returns provider" {
    local route
    route=$(get_message_route "bob@acme.crabmail.ai")
    assert_equal "$route" "crabmail.ai"
}

@test "get_message_route: different external provider" {
    local route
    route=$(get_message_route "carol@corp.example.com")
    assert_equal "$route" "example.com"
}

@test "get_message_route: legacy local address returns 'local'" {
    local route
    route=$(get_message_route "agent@myteam.local")
    assert_equal "$route" "local"
}

# --- is_registered ---

@test "is_registered: returns false when no registration exists" {
    run is_registered "crabmail.ai"
    assert_failure
}

@test "is_registered: returns true when registration exists" {
    create_test_registration "crabmail.ai" "https://api.crabmail.ai" "test-key"
    run is_registered "crabmail.ai"
    assert_success
}

# --- get_registration ---

@test "get_registration: returns JSON when registration exists" {
    create_test_registration "crabmail.ai" "https://api.crabmail.ai" "test-key-456"
    local reg
    reg=$(get_registration "crabmail.ai")
    local api_key
    api_key=$(echo "$reg" | jq -r '.apiKey')
    assert_equal "$api_key" "test-key-456"
}

@test "get_registration: fails when no registration exists" {
    run get_registration "nonexistent.provider"
    assert_failure
}

@test "get_registration: returns correct apiUrl" {
    create_test_registration "crabmail.ai" "https://api.crabmail.ai" "key"
    local reg
    reg=$(get_registration "crabmail.ai")
    local api_url
    api_url=$(echo "$reg" | jq -r '.apiUrl')
    assert_equal "$api_url" "https://api.crabmail.ai"
}
