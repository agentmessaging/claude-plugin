#!/usr/bin/env bats
# =============================================================================
# Integration Tests: amp-init.sh flow
# =============================================================================

setup() {
    load '../test_helper'
    setup_amp_env

    # amp-init.sh reassigns AMP_DIR to a UUID-based path under HOME
    # Set HOME so it creates dirs there
    mkdir -p "${HOME}/.agent-messaging/agents"

    # Mock curl for auto-registration (AI Maestro unreachable)
    mock_curl "000" ""
}

@test "init_flow: creates config.json with --name" {
    run bash "${SCRIPTS_DIR}/amp-init.sh" --name "testbot" --tenant "myorg"
    assert_success
    assert_output --partial "testbot"

    # Find the config file in the agents dir
    local config_file
    config_file=$(find "${HOME}/.agent-messaging/agents" -name "config.json" | head -1)
    [ -n "$config_file" ]
    local name
    name=$(jq -r '.agent.name' "$config_file")
    assert_equal "$name" "testbot"
}

@test "init_flow: generates Ed25519 keypair" {
    run bash "${SCRIPTS_DIR}/amp-init.sh" --name "keytest" --tenant "myorg"
    assert_success

    # Find the keys directory
    local private_key
    private_key=$(find "${HOME}/.agent-messaging/agents" -name "private.pem" | head -1)
    [ -n "$private_key" ]
    [ -f "$private_key" ]

    local public_key
    public_key=$(find "${HOME}/.agent-messaging/agents" -name "public.pem" | head -1)
    [ -n "$public_key" ]
    [ -f "$public_key" ]
}

@test "init_flow: creates IDENTITY.md" {
    run bash "${SCRIPTS_DIR}/amp-init.sh" --name "idtest" --tenant "myorg"
    assert_success

    local identity_file
    identity_file=$(find "${HOME}/.agent-messaging/agents" -name "IDENTITY.md" | head -1)
    [ -n "$identity_file" ]
    [ -f "$identity_file" ]
}

@test "init_flow: validates agent name format" {
    run bash "${SCRIPTS_DIR}/amp-init.sh" --name "invalid name!" --tenant "myorg"
    assert_failure
    assert_output --partial "Invalid agent name"
}

@test "init_flow: rejects name starting with special char" {
    run bash "${SCRIPTS_DIR}/amp-init.sh" --name "-badname" --tenant "myorg"
    assert_failure
    assert_output --partial "Invalid agent name"
}

@test "init_flow: normalizes name to lowercase" {
    run bash "${SCRIPTS_DIR}/amp-init.sh" --name "MyBot" --tenant "myorg"
    assert_success

    local config_file
    config_file=$(find "${HOME}/.agent-messaging/agents" -name "config.json" | head -1)
    local name
    name=$(jq -r '.agent.name' "$config_file")
    assert_equal "$name" "mybot"
}

@test "init_flow: --force regenerates keys" {
    # First init
    bash "${SCRIPTS_DIR}/amp-init.sh" --name "forcetest" --tenant "myorg" >/dev/null 2>&1

    # Get first fingerprint
    local config_file
    config_file=$(find "${HOME}/.agent-messaging/agents" -name "config.json" | head -1)
    local fp1
    fp1=$(jq -r '.agent.fingerprint' "$config_file")

    # Set AMP_DIR to the existing agent dir for --force
    local agent_dir
    agent_dir=$(dirname "$config_file")
    export AMP_DIR="$agent_dir"

    # Re-init with --force
    run bash "${SCRIPTS_DIR}/amp-init.sh" --name "forcetest" --tenant "myorg" --force
    assert_success

    # Get second fingerprint — should be different
    config_file=$(find "${HOME}/.agent-messaging/agents" -name "config.json" | head -1)
    local fp2
    fp2=$(jq -r '.agent.fingerprint' "$config_file")
    [ "$fp1" != "$fp2" ]
}

@test "init_flow: refuses reinit without --force" {
    # First init
    bash "${SCRIPTS_DIR}/amp-init.sh" --name "noforce" --tenant "myorg" >/dev/null 2>&1

    local config_file
    config_file=$(find "${HOME}/.agent-messaging/agents" -name "config.json" | head -1)
    local agent_dir
    agent_dir=$(dirname "$config_file")
    export AMP_DIR="$agent_dir"

    # Try again without --force
    run bash "${SCRIPTS_DIR}/amp-init.sh" --name "noforce" --tenant "myorg"
    assert_success
    assert_output --partial "already initialized"
}
