#!/usr/bin/env bats
# =============================================================================
# Integration Tests: amp-register.sh flow
# =============================================================================

setup() {
    load '../test_helper'
    setup_amp_env
    create_test_config "testagent" "testorg"
    create_test_keys
}

@test "register_flow: requires --provider flag" {
    run bash "${SCRIPTS_DIR}/amp-register.sh"
    assert_failure
    assert_output --partial "provider"
}

@test "register_flow: known provider (crabmail) requires user key" {
    run bash "${SCRIPTS_DIR}/amp-register.sh" --provider crabmail.ai
    assert_failure
    assert_output --partial "user-key"
}

@test "register_flow: validates user key format (uk_ prefix)" {
    mock_curl "400" '{"error":"Invalid user key"}'
    run bash "${SCRIPTS_DIR}/amp-register.sh" --provider crabmail.ai --user-key "not_a_valid_key"
    # Should fail because key doesn't have uk_ prefix
    assert_failure
}

@test "register_flow: successful registration creates file" {
    mock_curl "200" '{"api_key":"ak_test123","address":"testagent@testorg.crabmail.ai","agent_id":"ext-123","provider":{"name":"crabmail.ai","endpoint":"https://api.crabmail.ai/v1"}}'

    run bash "${SCRIPTS_DIR}/amp-register.sh" --provider crabmail.ai --user-key "uk_testkey123"
    assert_success

    # Check registration file was created
    [ -f "${AMP_DIR}/registrations/crabmail.ai.json" ]
}

@test "register_flow: registration file has correct permissions" {
    mock_curl "200" '{"api_key":"ak_test123","address":"testagent@testorg.crabmail.ai","agent_id":"ext-123","provider":{"name":"crabmail.ai","endpoint":"https://api.crabmail.ai/v1"}}'

    run bash "${SCRIPTS_DIR}/amp-register.sh" --provider crabmail.ai --user-key "uk_testkey123"
    assert_success

    # Check permissions (should be 600 - owner read/write only).
    # GNU stat (-c) first, BSD/macOS stat (-f) as fallback: on Linux `stat -f`
    # does NOT fail (it prints filesystem status and exits 0), so a BSD-first
    # order never reaches the GNU fallback and the assert compares garbage.
    local perms
    perms=$(stat -c '%a' "${AMP_DIR}/registrations/crabmail.ai.json" 2>/dev/null || stat -f '%Lp' "${AMP_DIR}/registrations/crabmail.ai.json" 2>/dev/null)
    assert_equal "$perms" "600"
}

@test "register_flow: refuses re-register without --force" {
    # Create existing registration
    create_test_registration "crabmail.ai" "https://api.crabmail.ai" "existing-key"

    run bash "${SCRIPTS_DIR}/amp-register.sh" --provider crabmail.ai --user-key "uk_newkey"
    assert_success
    assert_output --partial "Already registered"
}

@test "register_flow: --force allows re-registration" {
    create_test_registration "crabmail.ai" "https://api.crabmail.ai" "old-key"

    mock_curl "200" '{"api_key":"ak_newkey","address":"testagent@testorg.crabmail.ai","agent_id":"ext-456","provider":{"name":"crabmail.ai","endpoint":"https://api.crabmail.ai/v1"}}'

    run bash "${SCRIPTS_DIR}/amp-register.sh" --provider crabmail.ai --user-key "uk_newkey" --force
    assert_success
}
