#!/usr/bin/env bats
# =============================================================================
# Integration Tests: amp-send.sh routing decisions
# Catches PR #15 bug: filesystem delivery only when config.json exists
# =============================================================================

setup() {
    load '../test_helper'
    setup_amp_env
    create_test_config "sender" "testorg"
    create_test_keys

    # Create agents index for address lookup
    mkdir -p "${HOME}/.agent-messaging/agents"
}

# --- PR #15 regression: filesystem check requires config.json ---

@test "send_routing: local delivery requires recipient config.json" {
    # Set up a recipient directory WITHOUT config.json (simulates remote agent)
    local recipient_dir="${HOME}/.agent-messaging/agents/alice"
    mkdir -p "${recipient_dir}/messages/inbox"
    # No config.json — agent exists on another host

    # Create local registration so the script can try API
    create_local_registration "http://localhost:99999/api/v1" "test-api-key"

    # Mock curl to simulate API response
    mock_curl "200" '{"id":"msg_123_abc","status":"sent","method":"api"}'

    # Send to alice — should NOT attempt filesystem delivery
    # because alice's dir has no config.json
    run bash "${SCRIPTS_DIR}/amp-send.sh" "alice" "Test" "Hello alice"
    assert_success
    # Should route via API, not filesystem
    assert_output --partial "AMP routing"
}

@test "send_routing: filesystem delivery when recipient has config.json" {
    # Set up a recipient WITH config.json (local agent)
    local recipient_uuid="test-uuid-alice"
    local recipient_dir="${HOME}/.agent-messaging/agents/${recipient_uuid}"
    mkdir -p "${recipient_dir}/messages/inbox"
    mkdir -p "${recipient_dir}/keys"
    cat > "${recipient_dir}/config.json" << 'EOF'
{
  "version": "1.1",
  "agent": {
    "name": "alice",
    "tenant": "testorg",
    "address": "alice@testorg.aimaestro.local"
  }
}
EOF

    # Create index mapping alice -> UUID
    echo '{"alice":"test-uuid-alice"}' > "${HOME}/.agent-messaging/agents/.index.json"

    # Create local registration
    create_local_registration "http://localhost:99999/api/v1" "test-api-key"

    run bash "${SCRIPTS_DIR}/amp-send.sh" "alice" "Test" "Hello alice"
    assert_success
    # Should deliver via filesystem
    assert_output --partial "local filesystem delivery"
}

@test "send_routing: filesystem delivery creates message in recipient inbox" {
    # Set up local recipient
    local recipient_uuid="test-uuid-bob"
    local recipient_dir="${HOME}/.agent-messaging/agents/${recipient_uuid}"
    mkdir -p "${recipient_dir}/messages/inbox"
    mkdir -p "${recipient_dir}/keys"
    cat > "${recipient_dir}/config.json" << 'EOF'
{
  "version": "1.1",
  "agent": {
    "name": "bob",
    "tenant": "testorg",
    "address": "bob@testorg.aimaestro.local"
  }
}
EOF

    echo '{"bob":"test-uuid-bob"}' > "${HOME}/.agent-messaging/agents/.index.json"
    create_local_registration "http://localhost:99999/api/v1" "test-api-key"

    run bash "${SCRIPTS_DIR}/amp-send.sh" "bob" "Hello" "Hi Bob"
    assert_success

    # Verify message file exists in recipient's inbox
    local inbox_files
    inbox_files=$(find "${recipient_dir}/messages/inbox" -name "msg_*.json" | head -1)
    [ -n "$inbox_files" ]
}

@test "send_routing: no registration and no local recipient fails gracefully" {
    # No registrations, no recipient on filesystem → should fail
    run bash "${SCRIPTS_DIR}/amp-send.sh" "alice" "Test" "Hello"

    # Should report auto-registration failure and no local recipient
    # With no AI Maestro running, auto-reg curl will fail
    assert_output --partial "Cannot deliver"
}

@test "send_routing: external address requires provider registration" {
    run bash "${SCRIPTS_DIR}/amp-send.sh" "bob@acme.crabmail.ai" "Test" "Hello"
    assert_failure
    assert_output --partial "Not registered with provider"
}

@test "send_routing: external delivery uses registered provider API" {
    create_test_registration "crabmail.ai" "https://api.crabmail.ai" "ext-key-123" "sender" "testorg"

    mock_curl "200" '{"id":"msg_ext_abc","status":"sent"}'

    run bash "${SCRIPTS_DIR}/amp-send.sh" "bob@acme.crabmail.ai" "Test" "Hello" 2>&1
    assert_success

    # Verify curl was called with the crabmail API URL
    local calls
    calls=$(get_curl_calls)
    echo "$calls" | grep -q "crabmail.ai"
}
