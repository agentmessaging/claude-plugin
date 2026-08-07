#!/bin/bash
# =============================================================================
# AMP Test Helper - Shared test fixtures and utilities
# =============================================================================

# Load bats libraries
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "${TESTS_DIR}/.." && pwd)"
SCRIPTS_DIR="${PLUGIN_DIR}/scripts"

load "${PLUGIN_DIR}/node_modules/bats-support/load"
load "${PLUGIN_DIR}/node_modules/bats-assert/load"

# =============================================================================
# Environment Isolation
# =============================================================================

# Set up isolated AMP environment for each test
setup_amp_env() {
    # Each test gets its own AMP_DIR inside BATS_TEST_TMPDIR
    # Use a UUID-style dirname so load_config() skips name-mismatch auto-fix
    export AMP_DIR="${BATS_TEST_TMPDIR}/00000000-0000-0000-0000-000000000000"
    export AMP_MAESTRO_URL="http://localhost:99999"  # intentionally unreachable
    export AMP_PROVIDER_DOMAIN="aimaestro.local"
    export HOME="${BATS_TEST_TMPDIR}/home"

    # Unset agent identity vars to prevent leaking from host
    unset CLAUDE_AGENT_NAME
    unset CLAUDE_AGENT_ID
    unset TMUX

    # Create directory structure
    mkdir -p "${AMP_DIR}/keys"
    mkdir -p "${AMP_DIR}/messages/inbox"
    mkdir -p "${AMP_DIR}/messages/sent"
    mkdir -p "${AMP_DIR}/registrations"
    mkdir -p "${AMP_DIR}/attachments"
    mkdir -p "${HOME}/.agent-messaging/agents"
    chmod 700 "${AMP_DIR}/keys"
}

# =============================================================================
# Fixture Creators
# =============================================================================

# Create a minimal config.json for tests that need an initialized agent
# Args: name [tenant]
create_test_config() {
    local name="${1:-testagent}"
    local tenant="${2:-testorg}"
    local address="${name}@${tenant}.aimaestro.local"

    cat > "${AMP_DIR}/config.json" << EOF
{
  "version": "1.1",
  "agent": {
    "name": "${name}",
    "tenant": "${tenant}",
    "address": "${address}",
    "fingerprint": "SHA256:testfingerprint123",
    "createdAt": "2025-01-01T00:00:00Z"
  },
  "provider": {
    "domain": "aimaestro.local",
    "maestro_url": "${AMP_MAESTRO_URL}"
  }
}
EOF
}

# Generate real Ed25519 keypair for signing tests
create_test_keys() {
    local openssl_bin
    openssl_bin=$(_find_openssl)
    if [ -z "$openssl_bin" ]; then
        skip "No Ed25519-capable OpenSSL available"
    fi

    $openssl_bin genpkey -algorithm Ed25519 -out "${AMP_DIR}/keys/private.pem" 2>/dev/null
    chmod 600 "${AMP_DIR}/keys/private.pem"
    $openssl_bin pkey -in "${AMP_DIR}/keys/private.pem" -pubout -out "${AMP_DIR}/keys/public.pem" 2>/dev/null
    chmod 644 "${AMP_DIR}/keys/public.pem"
}

# Find a working openssl binary (same logic as amp-helper.sh)
_find_openssl() {
    local candidates=(
        "openssl"
        "/usr/local/opt/openssl@3/bin/openssl"
        "/opt/homebrew/opt/openssl@3/bin/openssl"
        "/home/linuxbrew/.linuxbrew/opt/openssl@3/bin/openssl"
    )
    for candidate in "${candidates[@]}"; do
        if command -v "$candidate" &>/dev/null || [ -x "$candidate" ]; then
            local ver
            ver=$($candidate version 2>/dev/null || true)
            if [[ "$ver" == OpenSSL\ 3.* ]] || [[ "$ver" == OpenSSL\ 1.1.1* ]]; then
                echo "$candidate"
                return 0
            fi
        fi
    done
    return 1
}

# Create a registration file for a provider
# Args: provider api_url api_key [agent_name] [tenant]
create_test_registration() {
    local provider="$1"
    local api_url="$2"
    local api_key="$3"
    local agent_name="${4:-testagent}"
    local tenant="${5:-testorg}"
    local address="${agent_name}@${tenant}.${provider}"

    cat > "${AMP_DIR}/registrations/${provider}.json" << EOF
{
  "provider": "${provider}",
  "apiUrl": "${api_url}",
  "agentName": "${agent_name}",
  "tenant": "${tenant}",
  "address": "${address}",
  "apiKey": "${api_key}",
  "registeredAt": "2025-01-01T00:00:00Z"
}
EOF
    chmod 600 "${AMP_DIR}/registrations/${provider}.json"
}

# Create a local provider registration (aimaestro.local)
create_local_registration() {
    local api_url="${1:-http://localhost:23000/api/v1}"
    local api_key="${2:-test-api-key-123}"

    cat > "${AMP_DIR}/registrations/aimaestro.local.json" << EOF
{
  "provider": "aimaestro.local",
  "apiUrl": "${api_url}",
  "routeUrl": "${api_url}/route",
  "agentName": "testagent",
  "tenant": "testorg",
  "address": "testagent@testorg.aimaestro.local",
  "apiKey": "${api_key}",
  "registeredAt": "2025-01-01T00:00:00Z"
}
EOF
    chmod 600 "${AMP_DIR}/registrations/aimaestro.local.json"
}

# Create an inbox message
# Args: msg_id from subject body [trust_level]
create_inbox_message() {
    local msg_id="$1"
    local from="$2"
    local subject="$3"
    local body="$4"
    local trust="${5:-verified}"

    local sender_dir
    sender_dir=$(echo "$from" | sed 's/[@.]/_/g' | sed 's/[^a-zA-Z0-9_-]//g')
    mkdir -p "${AMP_DIR}/messages/inbox/${sender_dir}"

    cat > "${AMP_DIR}/messages/inbox/${sender_dir}/${msg_id}.json" << EOF
{
  "envelope": {
    "version": "amp/0.1",
    "id": "${msg_id}",
    "from": "${from}",
    "to": "testagent@testorg.aimaestro.local",
    "subject": "${subject}",
    "priority": "normal",
    "timestamp": "2025-01-01T12:00:00Z",
    "thread_id": "${msg_id}",
    "in_reply_to": null,
    "signature": null
  },
  "payload": {
    "type": "notification",
    "message": "${body}",
    "context": null
  },
  "local": {
    "received_at": "2025-01-01T12:00:01Z",
    "status": "unread",
    "security": {
      "trust": "${trust}",
      "injection_flags": [],
      "wrapped": false,
      "verified_at": null
    }
  }
}
EOF
}

# =============================================================================
# Curl Mocking
# =============================================================================

# Mock curl using a PATH-based script that works across subprocesses.
# Creates a mock "curl" script in $BATS_TEST_TMPDIR/bin and prepends to PATH.
# Args: http_code [response_body]
# The mock logs all curl invocations to $BATS_TEST_TMPDIR/curl_calls.log
mock_curl() {
    local http_code="$1"
    local response_body="${2:-\{\}}"
    local mock_dir="${BATS_TEST_TMPDIR}/bin"
    local log_file="${BATS_TEST_TMPDIR}/curl_calls.log"
    local body_file="${BATS_TEST_TMPDIR}/curl_response_body.txt"
    local code_file="${BATS_TEST_TMPDIR}/curl_response_code.txt"

    mkdir -p "$mock_dir"

    # Write response body and code to separate files to avoid heredoc issues
    printf '%s' "$response_body" > "$body_file"
    printf '%s' "$http_code" > "$code_file"

    # Write mock curl script that reads from the files
    cat > "${mock_dir}/curl" << 'MOCK_EOF'
#!/bin/bash
_mock_dir="$(cd "$(dirname "$0")/.." && pwd)"
echo "$@" >> "${_mock_dir}/curl_calls.log"
if echo "$@" | grep -q -- '-w'; then
    cat "${_mock_dir}/curl_response_body.txt"
    echo ""
    cat "${_mock_dir}/curl_response_code.txt"
else
    cat "${_mock_dir}/curl_response_body.txt"
fi
exit 0
MOCK_EOF
    chmod +x "${mock_dir}/curl"
    export PATH="${mock_dir}:${PATH}"
}

# Get logged curl calls
get_curl_calls() {
    cat "${BATS_TEST_TMPDIR}/curl_calls.log" 2>/dev/null || true
}

# =============================================================================
# Source Helper (loads amp-helper.sh with isolation)
# =============================================================================

# Source amp-helper.sh in isolated mode
# Must be called AFTER setup_amp_env and create_test_config
source_amp_helper() {
    # Prevent amp-helper.sh from exiting on missing config
    # by ensuring AMP_DIR is set and config exists
    source "${SCRIPTS_DIR}/amp-helper.sh"
}
