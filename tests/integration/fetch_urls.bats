#!/usr/bin/env bats
# =============================================================================
# Integration Tests: amp-fetch.sh URL construction
# Catches PR #14 bug: /v1/ prefix in fetch and acknowledge URLs
# =============================================================================

setup() {
    load '../test_helper'
    setup_amp_env
    create_test_config "testagent" "testorg"
    create_test_keys
}

# --- PR #14 regression: /v1/ prefix in URLs ---

@test "fetch_urls: default fetch URL includes /v1/ prefix" {
    # Create registration WITHOUT explicit fetchUrl
    create_test_registration "crabmail.ai" "https://api.crabmail.ai" "test-key"

    # Mock curl: first call returns empty messages, so we can inspect the URL
    mock_curl "200" '{"messages":[]}'

    run bash "${SCRIPTS_DIR}/amp-fetch.sh" --provider crabmail.ai --verbose
    assert_success

    # Verify the fetch URL includes /v1/messages/pending
    local calls
    calls=$(get_curl_calls)
    echo "$calls" | grep -q "/v1/messages/pending"
}

@test "fetch_urls: fetch URL is apiUrl + /v1/messages/pending" {
    create_test_registration "crabmail.ai" "https://api.crabmail.ai" "test-key"

    mock_curl "200" '{"messages":[]}'

    run bash "${SCRIPTS_DIR}/amp-fetch.sh" --provider crabmail.ai --verbose
    assert_success

    # Check verbose output shows correct fetch endpoint
    assert_output --partial "Fetch: https://api.crabmail.ai/v1/messages/pending"
}

@test "fetch_urls: acknowledge URL includes /v1/ prefix" {
    create_test_registration "crabmail.ai" "https://api.crabmail.ai" "test-key"

    # Mock curl: return a message so we exercise the acknowledge path
    local msg_body='{"messages":[{"envelope":{"version":"amp/0.1","id":"msg_1706000000_aabb","from":"alice@acme.crabmail.ai","to":"testagent@testorg.crabmail.ai","subject":"Test","priority":"normal","timestamp":"2025-01-01T12:00:00Z","thread_id":"msg_1706000000_aabb","in_reply_to":null,"signature":null},"payload":{"type":"notification","message":"Hello","context":null}}]}'

    mock_curl "200" "$msg_body"

    run bash "${SCRIPTS_DIR}/amp-fetch.sh" --provider crabmail.ai --verbose
    assert_success

    # Verify acknowledge URL includes /v1/messages/pending/
    local calls
    calls=$(get_curl_calls)
    echo "$calls" | grep -q "/v1/messages/pending/msg_1706000000_aabb"
}

@test "fetch_urls: custom fetchUrl overrides default" {
    # Create registration WITH explicit fetchUrl
    cat > "${AMP_DIR}/registrations/crabmail.ai.json" << 'EOF'
{
  "provider": "crabmail.ai",
  "apiUrl": "https://api.crabmail.ai",
  "fetchUrl": "https://api.crabmail.ai/custom/fetch",
  "agentName": "testagent",
  "tenant": "testorg",
  "address": "testagent@testorg.crabmail.ai",
  "apiKey": "test-key",
  "registeredAt": "2025-01-01T00:00:00Z"
}
EOF
    chmod 600 "${AMP_DIR}/registrations/crabmail.ai.json"

    mock_curl "200" '{"messages":[]}'

    run bash "${SCRIPTS_DIR}/amp-fetch.sh" --provider crabmail.ai --verbose
    assert_success

    # Should use custom fetchUrl
    assert_output --partial "Fetch: https://api.crabmail.ai/custom/fetch"
}

@test "fetch_urls: regression - /messages/pending without /v1/ would fail" {
    # This test verifies that the code constructs the URL with /v1/
    # The old buggy code used ${API_URL}/messages/pending (missing /v1/)
    create_test_registration "crabmail.ai" "https://api.crabmail.ai" "test-key"

    mock_curl "200" '{"messages":[]}'

    run bash "${SCRIPTS_DIR}/amp-fetch.sh" --provider crabmail.ai --verbose
    assert_success

    # The fetch endpoint MUST contain /v1/
    local calls
    calls=$(get_curl_calls)
    # Ensure /v1/ is present (the bug was missing this)
    echo "$calls" | grep -qE "crabmail\.ai/v1/messages/pending"
}

@test "fetch_urls: saves fetched message to inbox" {
    create_test_registration "crabmail.ai" "https://api.crabmail.ai" "test-key"

    local msg_body='{"messages":[{"envelope":{"version":"amp/0.1","id":"msg_1706000000_ccdd","from":"alice@acme.crabmail.ai","to":"testagent@testorg.crabmail.ai","subject":"Fetched Message","priority":"normal","timestamp":"2025-01-01T12:00:00Z","thread_id":"msg_1706000000_ccdd","in_reply_to":null,"signature":null},"payload":{"type":"notification","message":"Hello from fetch","context":null}}]}'

    mock_curl "200" "$msg_body"

    run bash "${SCRIPTS_DIR}/amp-fetch.sh" --provider crabmail.ai
    assert_success
    assert_output --partial "Fetched 1 new message"

    # Verify message was saved in inbox
    local saved
    saved=$(find "${AMP_DIR}/messages/inbox" -name "msg_1706000000_ccdd.json" | head -1)
    [ -n "$saved" ]
}

@test "fetch_urls: auth failure returns helpful error" {
    create_test_registration "crabmail.ai" "https://api.crabmail.ai" "bad-key"

    mock_curl "401" '{"error":"Unauthorized"}'

    run bash "${SCRIPTS_DIR}/amp-fetch.sh" --provider crabmail.ai
    assert_output --partial "Authentication failed"
}
