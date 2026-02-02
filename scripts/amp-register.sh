#!/bin/bash
# =============================================================================
# AMP Register - Register with External Provider
# =============================================================================
#
# Register your agent with an external AMP provider (like Crabmail).
# This enables sending/receiving messages with agents on other providers.
#
# Usage:
#   amp-register --provider crabmail.ai --tenant mycompany
#   amp-register --provider crabmail.ai --tenant mycompany --name myagent
#
# =============================================================================

set -e

# Source helper functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/amp-helper.sh"

# Known providers
declare -A PROVIDER_APIS
PROVIDER_APIS["crabmail.ai"]="https://api.crabmail.ai"
PROVIDER_APIS["crabmail"]="https://api.crabmail.ai"

# Parse arguments
PROVIDER=""
TENANT=""
NAME=""
API_URL=""
FORCE=false

show_help() {
    echo "Usage: amp-register --provider <provider> --tenant <tenant> [options]"
    echo ""
    echo "Register your agent with an external AMP provider."
    echo ""
    echo "Required:"
    echo "  --provider, -p PROVIDER   Provider domain (e.g., crabmail.ai)"
    echo "  --tenant, -t TENANT       Your organization/tenant name"
    echo ""
    echo "Options:"
    echo "  --name, -n NAME           Agent name (default: from local config)"
    echo "  --api-url, -a URL         Custom API URL (for self-hosted providers)"
    echo "  --force, -f               Re-register even if already registered"
    echo "  --help, -h                Show this help"
    echo ""
    echo "Supported providers:"
    echo "  - crabmail.ai            Crabmail (default AMP provider)"
    echo ""
    echo "Examples:"
    echo "  amp-register --provider crabmail.ai --tenant 23blocks"
    echo "  amp-register -p crabmail.ai -t mycompany -n backend-api"
}

while [[ $# -gt 0 ]]; do
    case $1 in
        --provider|-p)
            PROVIDER="$2"
            shift 2
            ;;
        --tenant|-t)
            TENANT="$2"
            shift 2
            ;;
        --name|-n)
            NAME="$2"
            shift 2
            ;;
        --api-url|-a)
            API_URL="$2"
            shift 2
            ;;
        --force|-f)
            FORCE=true
            shift
            ;;
        --help|-h)
            show_help
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Run 'amp-register --help' for usage."
            exit 1
            ;;
    esac
done

# Validate required arguments
if [ -z "$PROVIDER" ]; then
    echo "Error: Provider required (--provider)"
    echo ""
    show_help
    exit 1
fi

if [ -z "$TENANT" ]; then
    echo "Error: Tenant required (--tenant)"
    echo ""
    show_help
    exit 1
fi

# Require local initialization first
require_init

# Use local agent name if not specified
if [ -z "$NAME" ]; then
    NAME="$AMP_AGENT_NAME"
fi

# Normalize provider name
PROVIDER_LOWER=$(echo "$PROVIDER" | tr '[:upper:]' '[:lower:]')

# Get API URL
if [ -z "$API_URL" ]; then
    API_URL="${PROVIDER_APIS[$PROVIDER_LOWER]}"
    if [ -z "$API_URL" ]; then
        # Assume standard API URL format
        API_URL="https://api.${PROVIDER_LOWER}"
    fi
fi

# Check if already registered
REG_FILE="${AMP_REGISTRATIONS_DIR}/${PROVIDER_LOWER}.json"
if [ -f "$REG_FILE" ] && [ "$FORCE" != true ]; then
    echo "Already registered with ${PROVIDER}"
    echo ""
    EXISTING=$(cat "$REG_FILE")
    echo "  Address: $(echo "$EXISTING" | jq -r '.address')"
    echo "  Registered: $(echo "$EXISTING" | jq -r '.registeredAt')"
    echo ""
    echo "Use --force to re-register."
    exit 0
fi

echo "Registering with ${PROVIDER}..."
echo ""
echo "  Provider: ${PROVIDER}"
echo "  API:      ${API_URL}"
echo "  Tenant:   ${TENANT}"
echo "  Name:     ${NAME}"
echo ""

# Get public key
PUBLIC_KEY_HEX=$(get_public_key_hex)
if [ -z "$PUBLIC_KEY_HEX" ]; then
    echo "Error: Could not read public key"
    exit 1
fi

# Build registration request
REG_REQUEST=$(jq -n \
    --arg name "$NAME" \
    --arg tenant "$TENANT" \
    --arg fingerprint "$AMP_FINGERPRINT" \
    --arg publicKey "$PUBLIC_KEY_HEX" \
    '{
        agent_name: $name,
        tenant: $tenant,
        fingerprint: $fingerprint,
        public_key_hex: $publicKey,
        key_algorithm: "Ed25519"
    }')

# Send registration request
echo "Sending registration request..."
RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "${API_URL}/v1/register" \
    -H "Content-Type: application/json" \
    -d "$REG_REQUEST" 2>&1)

HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
BODY=$(echo "$RESPONSE" | sed '$d')

# Check response
if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "201" ]; then
    # Parse response
    AGENT_ID=$(echo "$BODY" | jq -r '.agent_id // .agentId // empty')
    API_KEY=$(echo "$BODY" | jq -r '.api_key // .apiKey // empty')
    ADDRESS=$(echo "$BODY" | jq -r '.address // empty')

    if [ -z "$API_KEY" ]; then
        echo "Error: Provider did not return API key"
        echo "Response: $BODY"
        exit 1
    fi

    # Build external address if not returned
    if [ -z "$ADDRESS" ]; then
        ADDRESS="${NAME}@${TENANT}.${PROVIDER_LOWER}"
    fi

    # Save registration
    ensure_amp_dirs

    jq -n \
        --arg provider "$PROVIDER_LOWER" \
        --arg apiUrl "$API_URL" \
        --arg agentName "$NAME" \
        --arg tenant "$TENANT" \
        --arg address "$ADDRESS" \
        --arg apiKey "$API_KEY" \
        --arg providerAgentId "$AGENT_ID" \
        --arg fingerprint "$AMP_FINGERPRINT" \
        --arg registeredAt "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        '{
            provider: $provider,
            apiUrl: $apiUrl,
            agentName: $agentName,
            tenant: $tenant,
            address: $address,
            apiKey: $apiKey,
            providerAgentId: $providerAgentId,
            fingerprint: $fingerprint,
            registeredAt: $registeredAt
        }' > "$REG_FILE"

    # Secure the registration file (contains API key)
    chmod 600 "$REG_FILE"

    echo ""
    echo "✅ Registration successful!"
    echo ""
    echo "  External Address: ${ADDRESS}"
    echo "  Provider Agent ID: ${AGENT_ID:-N/A}"
    echo ""
    echo "You can now send and receive messages via ${PROVIDER}:"
    echo "  amp-send alice@acme.${PROVIDER_LOWER} \"Hello\" \"Message\""

elif [ "$HTTP_CODE" = "409" ]; then
    echo "Error: Agent already registered with this provider"
    echo ""
    echo "If you want to re-register, contact the provider to reset your registration,"
    echo "or use a different agent name."
    exit 1

elif [ "$HTTP_CODE" = "400" ]; then
    ERROR_MSG=$(echo "$BODY" | jq -r '.error // .message // "Bad request"' 2>/dev/null)
    echo "Error: Registration failed - ${ERROR_MSG}"
    exit 1

else
    echo "Error: Registration failed (HTTP ${HTTP_CODE})"
    ERROR_MSG=$(echo "$BODY" | jq -r '.error // .message // empty' 2>/dev/null)
    if [ -n "$ERROR_MSG" ]; then
        echo "  ${ERROR_MSG}"
    fi

    # Check if provider is reachable
    if [ "$HTTP_CODE" = "000" ]; then
        echo ""
        echo "Could not connect to ${API_URL}"
        echo "Check your internet connection and try again."
    fi

    exit 1
fi
