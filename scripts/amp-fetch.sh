#!/bin/bash
# =============================================================================
# AMP Fetch - Fetch Messages from External Providers
# =============================================================================
#
# Pull new messages from registered external providers.
#
# Usage:
#   amp-fetch                    # Fetch from all providers
#   amp-fetch --provider crabmail.ai   # Fetch from specific provider
#
# =============================================================================

set -e

# Source helper functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/amp-helper.sh"

# Parse arguments
PROVIDER=""
VERBOSE=false
MARK_AS_FETCHED=true

show_help() {
    echo "Usage: amp-fetch [options]"
    echo ""
    echo "Fetch new messages from external providers."
    echo ""
    echo "Options:"
    echo "  --provider, -p PROVIDER   Fetch from specific provider only"
    echo "  --verbose, -v             Show detailed output"
    echo "  --no-mark                 Don't mark messages as fetched on provider"
    echo "  --help, -h                Show this help"
    echo ""
    echo "Examples:"
    echo "  amp-fetch                     # Fetch from all registered providers"
    echo "  amp-fetch -p crabmail.ai      # Fetch from Crabmail only"
    echo "  amp-fetch --verbose           # Show details"
}

while [[ $# -gt 0 ]]; do
    case $1 in
        --provider|-p)
            PROVIDER="$2"
            shift 2
            ;;
        --verbose|-v)
            VERBOSE=true
            shift
            ;;
        --no-mark)
            MARK_AS_FETCHED=false
            shift
            ;;
        --help|-h)
            show_help
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Run 'amp-fetch --help' for usage."
            exit 1
            ;;
    esac
done

# Require initialization
require_init

# Get list of providers to fetch from
if [ -n "$PROVIDER" ]; then
    PROVIDER_LOWER=$(echo "$PROVIDER" | tr '[:upper:]' '[:lower:]')
    REG_FILE="${AMP_REGISTRATIONS_DIR}/${PROVIDER_LOWER}.json"
    if [ ! -f "$REG_FILE" ]; then
        echo "Error: Not registered with ${PROVIDER}"
        echo ""
        echo "Register first: amp-register --provider ${PROVIDER}"
        exit 1
    fi
    PROVIDERS=("$PROVIDER_LOWER")
else
    # Find all registered providers
    PROVIDERS=()
    if [ -d "$AMP_REGISTRATIONS_DIR" ]; then
        for reg_file in "${AMP_REGISTRATIONS_DIR}"/*.json; do
            if [ -f "$reg_file" ]; then
                provider_name=$(basename "$reg_file" .json)
                PROVIDERS+=("$provider_name")
            fi
        done
    fi
fi

if [ ${#PROVIDERS[@]} -eq 0 ]; then
    echo "No external providers registered."
    echo ""
    echo "Register with a provider first:"
    echo "  amp-register --provider crabmail.ai --tenant <your-tenant>"
    exit 0
fi

# Fetch from each provider
TOTAL_NEW=0

for provider in "${PROVIDERS[@]}"; do
    REG_FILE="${AMP_REGISTRATIONS_DIR}/${provider}.json"
    REGISTRATION=$(cat "$REG_FILE")

    API_URL=$(echo "$REGISTRATION" | jq -r '.apiUrl')
    API_KEY=$(echo "$REGISTRATION" | jq -r '.apiKey')
    EXTERNAL_ADDRESS=$(echo "$REGISTRATION" | jq -r '.address')

    if [ "$VERBOSE" = true ]; then
        echo "Fetching from ${provider}..."
        echo "  API: ${API_URL}"
        echo "  Address: ${EXTERNAL_ADDRESS}"
    fi

    # Fetch messages from provider
    RESPONSE=$(curl -s -w "\n%{http_code}" -X GET "${API_URL}/v1/inbox" \
        -H "Authorization: Bearer ${API_KEY}" \
        -H "Accept: application/json" 2>&1)

    HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
    BODY=$(echo "$RESPONSE" | sed '$d')

    if [ "$HTTP_CODE" = "200" ]; then
        # Parse messages
        MESSAGE_COUNT=$(echo "$BODY" | jq '.messages | length' 2>/dev/null || echo "0")

        if [ "$MESSAGE_COUNT" = "0" ] || [ "$MESSAGE_COUNT" = "null" ]; then
            if [ "$VERBOSE" = true ]; then
                echo "  No new messages"
            fi
            continue
        fi

        if [ "$VERBOSE" = true ]; then
            echo "  Found ${MESSAGE_COUNT} new message(s)"
        fi

        # Process each message
        echo "$BODY" | jq -c '.messages[]' 2>/dev/null | while read -r msg; do
            # Get message ID
            msg_id=$(echo "$msg" | jq -r '.envelope.id // .id')

            # Check if already exists locally
            if [ -f "${AMP_INBOX_DIR}/${msg_id}.json" ]; then
                if [ "$VERBOSE" = true ]; then
                    echo "    Skipping ${msg_id} (already exists)"
                fi
                continue
            fi

            # Add metadata
            msg=$(echo "$msg" | jq \
                --arg receivedAt "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
                --arg provider "$provider" \
                '. + {
                    metadata: (.metadata // {}) + {
                        status: "unread",
                        receivedAt: $receivedAt,
                        fetchedFrom: $provider
                    }
                }')

            # Save to inbox
            echo "$msg" > "${AMP_INBOX_DIR}/${msg_id}.json"

            if [ "$VERBOSE" = true ]; then
                subject=$(echo "$msg" | jq -r '.envelope.subject')
                from=$(echo "$msg" | jq -r '.envelope.from')
                echo "    Saved: ${msg_id}"
                echo "      From: ${from}"
                echo "      Subject: ${subject}"
            fi

            TOTAL_NEW=$((TOTAL_NEW + 1))

            # Mark as fetched on provider (if enabled)
            if [ "$MARK_AS_FETCHED" = true ]; then
                curl -s -X POST "${API_URL}/v1/inbox/${msg_id}/ack" \
                    -H "Authorization: Bearer ${API_KEY}" \
                    >/dev/null 2>&1 || true
            fi
        done

    elif [ "$HTTP_CODE" = "401" ]; then
        echo "Error: Authentication failed for ${provider}"
        echo "  Your API key may have expired. Re-register with:"
        echo "  amp-register --provider ${provider} --force"

    elif [ "$HTTP_CODE" = "000" ]; then
        echo "Error: Could not connect to ${provider}"
        echo "  Check your internet connection."

    else
        echo "Error: Failed to fetch from ${provider} (HTTP ${HTTP_CODE})"
        ERROR_MSG=$(echo "$BODY" | jq -r '.error // .message // empty' 2>/dev/null)
        if [ -n "$ERROR_MSG" ]; then
            echo "  ${ERROR_MSG}"
        fi
    fi
done

# Summary
if [ "$TOTAL_NEW" -gt 0 ]; then
    echo ""
    echo "✅ Fetched ${TOTAL_NEW} new message(s)"
    echo ""
    echo "View messages: amp-inbox"
else
    echo "No new messages from external providers."
fi
