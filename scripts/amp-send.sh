#!/bin/bash
# =============================================================================
# AMP Send - Send a Message
# =============================================================================
#
# Send a message to another agent.
#
# Usage:
#   amp-send <recipient> <subject> <message> [options]
#
# Examples:
#   amp-send alice "Hello" "How are you?"
#   amp-send backend-api@23blocks.crabmail.ai "Deploy" "Ready for deploy" --priority high
#   amp-send bob --type task "Review PR" "Please review PR #42"
#
# =============================================================================

set -e

# Source helper functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/amp-helper.sh"

# Parse arguments
RECIPIENT=""
SUBJECT=""
MESSAGE=""
PRIORITY="normal"
TYPE="notification"
REPLY_TO=""
CONTEXT="null"

show_help() {
    echo "Usage: amp-send <recipient> <subject> <message> [options]"
    echo ""
    echo "Send a message to another agent."
    echo ""
    echo "Arguments:"
    echo "  recipient   Agent address (e.g., alice, bob@tenant.provider)"
    echo "  subject     Message subject"
    echo "  message     Message body"
    echo ""
    echo "Options:"
    echo "  --priority, -p PRIORITY   low|normal|high|urgent (default: normal)"
    echo "  --type, -t TYPE           request|response|notification|task|status (default: notification)"
    echo "  --reply-to, -r ID         Message ID this is replying to"
    echo "  --context, -c JSON        Additional context as JSON"
    echo "  --help, -h                Show this help"
    echo ""
    echo "Address formats:"
    echo "  alice                     → alice@default.local (local)"
    echo "  alice@myteam.local        → alice@myteam.local (local)"
    echo "  alice@acme.crabmail.ai    → alice@acme.crabmail.ai (external)"
    echo ""
    echo "Examples:"
    echo "  amp-send alice \"Hello\" \"How are you?\""
    echo "  amp-send backend-api \"Deploy\" \"Ready\" --priority high"
    echo "  amp-send bob@acme.crabmail.ai \"Help\" \"Need assistance\" --type request"
}

# Parse positional and optional arguments
POSITIONAL=()
while [[ $# -gt 0 ]]; do
    case $1 in
        --priority|-p)
            PRIORITY="$2"
            shift 2
            ;;
        --type|-t)
            TYPE="$2"
            shift 2
            ;;
        --reply-to|-r)
            REPLY_TO="$2"
            shift 2
            ;;
        --context|-c)
            CONTEXT="$2"
            shift 2
            ;;
        --help|-h)
            show_help
            exit 0
            ;;
        -*)
            echo "Unknown option: $1"
            echo "Run 'amp-send --help' for usage."
            exit 1
            ;;
        *)
            POSITIONAL+=("$1")
            shift
            ;;
    esac
done

# Check positional arguments
if [ ${#POSITIONAL[@]} -lt 3 ]; then
    echo "Error: Missing required arguments."
    echo ""
    show_help
    exit 1
fi

RECIPIENT="${POSITIONAL[0]}"
SUBJECT="${POSITIONAL[1]}"
MESSAGE="${POSITIONAL[2]}"

# Validate priority
if [[ ! "$PRIORITY" =~ ^(low|normal|high|urgent)$ ]]; then
    echo "Error: Invalid priority '${PRIORITY}'"
    echo "Valid values: low, normal, high, urgent"
    exit 1
fi

# Validate type
if [[ ! "$TYPE" =~ ^(request|response|notification|task|status|alert|update|handoff|ack)$ ]]; then
    echo "Error: Invalid type '${TYPE}'"
    echo "Valid values: request, response, notification, task, status, alert, update, handoff, ack"
    exit 1
fi

# Validate context is valid JSON (if provided)
if [ "$CONTEXT" != "null" ]; then
    if ! echo "$CONTEXT" | jq . >/dev/null 2>&1; then
        echo "Error: Invalid JSON context"
        exit 1
    fi
fi

# Require initialization
require_init

# Determine routing
ROUTE=$(get_message_route "$RECIPIENT")

# Create the message
MESSAGE_JSON=$(create_message "$RECIPIENT" "$SUBJECT" "$MESSAGE" "$TYPE" "$PRIORITY" "$REPLY_TO" "$CONTEXT")

# =============================================================================
# Sign the message (required for all delivery methods)
# =============================================================================
# Create canonical string for signing
# Format: from|to|subject|priority|in_reply_to|payload_hash
#
# This format follows AMP Protocol v1.1 specification:
# - Signs only fields the CLIENT controls (not server-generated id/timestamp)
# - Includes priority to prevent escalation attacks
# - Includes in_reply_to to prevent thread hijacking
# - payload_hash covers entire payload content
#
# Use jq -c for compact JSON (same as JSON.stringify in Node.js)
# Note: jq adds a trailing newline, so we remove it with tr before hashing
PAYLOAD_HASH=$(echo "$MESSAGE_JSON" | jq -c '.payload' | tr -d '\n' | $OPENSSL_BIN dgst -sha256 -binary | base64 | tr -d '\n')
FROM_ADDR=$(echo "$MESSAGE_JSON" | jq -r '.envelope.from')
TO_ADDR=$(echo "$MESSAGE_JSON" | jq -r '.envelope.to')
SUBJ=$(echo "$MESSAGE_JSON" | jq -r '.envelope.subject')
# PRIORITY and REPLY_TO are already set from arguments (empty string if not provided)
SIGN_DATA="${FROM_ADDR}|${TO_ADDR}|${SUBJ}|${PRIORITY}|${REPLY_TO}|${PAYLOAD_HASH}"
SIGNATURE=$(sign_message "$SIGN_DATA")

# Add signature to message
MESSAGE_JSON=$(echo "$MESSAGE_JSON" | jq --arg sig "$SIGNATURE" '.envelope.signature = $sig')

# =============================================================================
# Routing Decision
# =============================================================================
# For "local" routes, check if we're registered with AI Maestro provider
# If so, use the API for proper mesh routing; otherwise, fall back to filesystem

if [ "$ROUTE" = "local" ]; then
    # Check if registered with local AI Maestro provider
    # This enables proper mesh routing across hosts
    LOCAL_PROVIDER="${AMP_PROVIDER_DOMAIN}"

    # Try to find AI Maestro registration
    AI_MAESTRO_REG=""
    for provider_file in "${AMP_REGISTRATIONS_DIR}"/*.json; do
        [ -f "$provider_file" ] || continue
        provider=$(jq -r '.provider // empty' "$provider_file" 2>/dev/null)
        if [[ "$provider" == *"aimaestro"* ]] || [[ "$provider" == *".local"* ]]; then
            AI_MAESTRO_REG="$provider_file"
            break
        fi
    done

    if [ -n "$AI_MAESTRO_REG" ] && [ -f "$AI_MAESTRO_REG" ]; then
        # ==========================================================================
        # AI Maestro Provider Delivery (mesh routing)
        # ==========================================================================
        REGISTRATION=$(cat "$AI_MAESTRO_REG")
        API_URL=$(echo "$REGISTRATION" | jq -r '.apiUrl')
        API_KEY=$(echo "$REGISTRATION" | jq -r '.apiKey')
        ROUTE_URL=$(echo "$REGISTRATION" | jq -r '.routeUrl // empty')

        # Prepare API request body
        parse_address "$RECIPIENT"
        FULL_RECIPIENT=$(build_address "$ADDR_NAME" "$ADDR_TENANT" "$ADDR_PROVIDER")

        API_BODY=$(jq -n \
            --arg to "$FULL_RECIPIENT" \
            --arg subject "$SUBJECT" \
            --arg priority "$PRIORITY" \
            --arg type "$TYPE" \
            --arg message "$MESSAGE" \
            --arg in_reply_to "$REPLY_TO" \
            --argjson context "$CONTEXT" \
            --arg signature "$SIGNATURE" \
            '{
                to: $to,
                subject: $subject,
                priority: $priority,
                payload: {
                    type: $type,
                    message: $message,
                    context: $context
                },
                in_reply_to: (if $in_reply_to == "" then null else $in_reply_to end),
                signature: $signature
            }')

        # Send via AI Maestro API (use route_url if available, fallback to apiUrl/route)
        SEND_URL="${ROUTE_URL:-${API_URL}/route}"
        RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "${SEND_URL}" \
            -H "Content-Type: application/json" \
            -H "Authorization: Bearer ${API_KEY}" \
            -d "$API_BODY" 2>&1)

        HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
        BODY=$(echo "$RESPONSE" | sed '$d')

        if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "201" ] || [ "$HTTP_CODE" = "202" ]; then
            # Save to sent folder
            save_to_sent "$MESSAGE_JSON" >/dev/null

            MSG_ID=$(echo "$BODY" | jq -r '.id // empty')
            [ -z "$MSG_ID" ] && MSG_ID=$(echo "$MESSAGE_JSON" | jq -r '.envelope.id')

            DELIVERY_STATUS=$(echo "$BODY" | jq -r '.status // "sent"')
            DELIVERY_METHOD=$(echo "$BODY" | jq -r '.method // "api"')

            echo "✅ Message sent via AMP routing"
            echo ""
            echo "  To:       ${FULL_RECIPIENT}"
            echo "  Subject:  ${SUBJECT}"
            echo "  Priority: ${PRIORITY}"
            echo "  Type:     ${TYPE}"
            echo "  ID:       ${MSG_ID}"
            echo "  Status:   ${DELIVERY_STATUS}"
            echo "  Method:   ${DELIVERY_METHOD}"
        else
            echo "❌ Failed to send via AMP routing (HTTP ${HTTP_CODE})"
            ERROR_MSG=$(echo "$BODY" | jq -r '.error // .message // "Unknown error"' 2>/dev/null)
            if [ -n "$ERROR_MSG" ] && [ "$ERROR_MSG" != "null" ]; then
                echo "   Error: ${ERROR_MSG}"
            fi
            exit 1
        fi

    else
        # ==========================================================================
        # No AI Maestro registration found — attempt auto-registration
        # ==========================================================================
        # Instead of silently falling back to filesystem (which only works on the
        # same machine), try to register with AI Maestro first so cross-host
        # delivery works automatically.

        echo "  No AMP registration found. Auto-registering..."

        # Read agent's public key
        AUTO_REG_PUBLIC_KEY=""
        if [ -f "${AMP_KEYS_DIR}/public.pem" ]; then
            AUTO_REG_PUBLIC_KEY=$(cat "${AMP_KEYS_DIR}/public.pem")
        fi

        # Read agent name and tenant from config
        AUTO_REG_NAME=$(jq -r '.name // empty' "$AMP_CONFIG" 2>/dev/null)
        AUTO_REG_TENANT=$(jq -r '.tenant // "default"' "$AMP_CONFIG" 2>/dev/null)

        AUTO_REG_SUCCESS=false

        if [ -n "$AUTO_REG_PUBLIC_KEY" ] && [ -n "$AUTO_REG_NAME" ]; then
            AUTO_REG_REQUEST=$(jq -n \
                --arg name "$AUTO_REG_NAME" \
                --arg tenant "$AUTO_REG_TENANT" \
                --arg publicKey "$AUTO_REG_PUBLIC_KEY" \
                '{
                    name: $name,
                    tenant: $tenant,
                    public_key: $publicKey,
                    key_algorithm: "Ed25519"
                }')

            AUTO_REG_RESPONSE=$(curl -s -w "\n%{http_code}" --connect-timeout 3 -X POST \
                "${AMP_MAESTRO_URL}/api/v1/register" \
                -H "Content-Type: application/json" \
                -d "$AUTO_REG_REQUEST" 2>&1) || true

            AUTO_REG_HTTP=$(echo "$AUTO_REG_RESPONSE" | tail -n1)
            AUTO_REG_BODY=$(echo "$AUTO_REG_RESPONSE" | sed '$d')

            if [ "$AUTO_REG_HTTP" = "200" ] || [ "$AUTO_REG_HTTP" = "201" ]; then
                # Parse registration and save
                AUTO_API_KEY=$(echo "$AUTO_REG_BODY" | jq -r '.api_key // empty')
                AUTO_ADDRESS=$(echo "$AUTO_REG_BODY" | jq -r '.address // empty')
                AUTO_AGENT_ID=$(echo "$AUTO_REG_BODY" | jq -r '.agent_id // empty')
                AUTO_PROVIDER_NAME=$(echo "$AUTO_REG_BODY" | jq -r '.provider.name // "aimaestro.local"')
                AUTO_PROVIDER_ENDPOINT=$(echo "$AUTO_REG_BODY" | jq -r '.provider.endpoint // empty')
                AUTO_ROUTE_URL=$(echo "$AUTO_REG_BODY" | jq -r '.provider.route_url // empty')
                AUTO_FINGERPRINT=$(jq -r '.fingerprint // empty' "$AMP_CONFIG" 2>/dev/null)

                if [ -n "$AUTO_API_KEY" ]; then
                    ensure_amp_dirs
                    REG_FILE="${AMP_REGISTRATIONS_DIR}/${AUTO_PROVIDER_NAME}.json"

                    jq -n \
                        --arg provider "$AUTO_PROVIDER_NAME" \
                        --arg apiUrl "${AUTO_PROVIDER_ENDPOINT:-${AMP_MAESTRO_URL}/api/v1}" \
                        --arg routeUrl "${AUTO_ROUTE_URL:-${AUTO_PROVIDER_ENDPOINT:-${AMP_MAESTRO_URL}/api/v1}/route}" \
                        --arg agentName "$AUTO_REG_NAME" \
                        --arg tenant "$AUTO_REG_TENANT" \
                        --arg address "${AUTO_ADDRESS:-${AUTO_REG_NAME}@${AUTO_REG_TENANT}.${AMP_PROVIDER_DOMAIN}}" \
                        --arg apiKey "$AUTO_API_KEY" \
                        --arg providerAgentId "$AUTO_AGENT_ID" \
                        --arg fingerprint "$AUTO_FINGERPRINT" \
                        --arg registeredAt "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
                        '{
                            provider: $provider,
                            apiUrl: $apiUrl,
                            routeUrl: $routeUrl,
                            agentName: $agentName,
                            tenant: $tenant,
                            address: $address,
                            apiKey: $apiKey,
                            providerAgentId: $providerAgentId,
                            fingerprint: $fingerprint,
                            registeredAt: $registeredAt
                        }' > "$REG_FILE"

                    echo "  ✅ AMP identity registered"
                    AUTO_REG_SUCCESS=true

                    # Now send via AI Maestro API (same logic as the registered path)
                    parse_address "$RECIPIENT"
                    FULL_RECIPIENT=$(build_address "$ADDR_NAME" "$ADDR_TENANT" "$ADDR_PROVIDER")

                    API_BODY=$(jq -n \
                        --arg to "$FULL_RECIPIENT" \
                        --arg subject "$SUBJECT" \
                        --arg priority "$PRIORITY" \
                        --arg type "$TYPE" \
                        --arg message "$MESSAGE" \
                        --arg in_reply_to "$REPLY_TO" \
                        --argjson context "$CONTEXT" \
                        --arg signature "$SIGNATURE" \
                        '{
                            to: $to,
                            subject: $subject,
                            priority: $priority,
                            payload: {
                                type: $type,
                                message: $message,
                                context: $context
                            },
                            in_reply_to: (if $in_reply_to == "" then null else $in_reply_to end),
                            signature: $signature
                        }')

                    AUTO_SEND_URL="${AUTO_ROUTE_URL:-${AUTO_PROVIDER_ENDPOINT:-${AMP_MAESTRO_URL}/api/v1}/route}"
                    RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "${AUTO_SEND_URL}" \
                        -H "Content-Type: application/json" \
                        -H "Authorization: Bearer ${AUTO_API_KEY}" \
                        -d "$API_BODY" 2>&1)

                    HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
                    BODY=$(echo "$RESPONSE" | sed '$d')

                    if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "201" ] || [ "$HTTP_CODE" = "202" ]; then
                        save_to_sent "$MESSAGE_JSON" >/dev/null

                        MSG_ID=$(echo "$BODY" | jq -r '.id // empty')
                        [ -z "$MSG_ID" ] && MSG_ID=$(echo "$MESSAGE_JSON" | jq -r '.envelope.id')

                        DELIVERY_STATUS=$(echo "$BODY" | jq -r '.status // "sent"')
                        DELIVERY_METHOD=$(echo "$BODY" | jq -r '.method // "api"')

                        echo "✅ Message sent via AMP routing (auto-registered)"
                        echo ""
                        echo "  To:       ${FULL_RECIPIENT}"
                        echo "  Subject:  ${SUBJECT}"
                        echo "  Priority: ${PRIORITY}"
                        echo "  Type:     ${TYPE}"
                        echo "  ID:       ${MSG_ID}"
                        echo "  Status:   ${DELIVERY_STATUS}"
                        echo "  Method:   ${DELIVERY_METHOD}"
                    else
                        echo "❌ Failed to send via AMP after auto-registration (HTTP ${HTTP_CODE})"
                        ERROR_MSG=$(echo "$BODY" | jq -r '.error // .message // "Unknown error"' 2>/dev/null)
                        if [ -n "$ERROR_MSG" ] && [ "$ERROR_MSG" != "null" ]; then
                            echo "   Error: ${ERROR_MSG}"
                        fi
                        exit 1
                    fi
                fi
            elif [ "$AUTO_REG_HTTP" = "409" ]; then
                echo "  ⚠️  AMP identity already registered but local config is missing."
                echo "     Re-run: amp-init.sh --force --auto"
            fi
        fi

        # If auto-registration failed, check if recipient is truly local
        if [ "$AUTO_REG_SUCCESS" = false ]; then
            parse_address "$RECIPIENT"
            FULL_RECIPIENT=$(build_address "$ADDR_NAME" "$ADDR_TENANT" "$ADDR_PROVIDER")

            AGENTS_BASE_DIR="${HOME}/.agent-messaging/agents"
            RECIPIENT_AMP_DIR="${AGENTS_BASE_DIR}/${ADDR_NAME}"

            if [ -d "${RECIPIENT_AMP_DIR}" ]; then
                # Recipient IS on this machine - filesystem delivery is valid
                save_to_sent "$MESSAGE_JSON" >/dev/null
                MSG_ID=$(echo "$MESSAGE_JSON" | jq -r '.envelope.id')

                RECIPIENT_INBOX="${RECIPIENT_AMP_DIR}/messages/inbox"
                FROM_ADDR=$(echo "$MESSAGE_JSON" | jq -r '.envelope.from')
                SENDER_DIR=$(sanitize_address_for_path "$FROM_ADDR")
                mkdir -p "${RECIPIENT_INBOX}/${SENDER_DIR}"

                DELIVERY_MSG=$(echo "$MESSAGE_JSON" | jq \
                    --arg received "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
                    '.local = (.local // {}) + {received_at: $received, status: "unread"}')

                echo "$DELIVERY_MSG" > "${RECIPIENT_INBOX}/${SENDER_DIR}/${MSG_ID}.json"

                echo "✅ Message sent (local filesystem delivery)"
                echo ""
                echo "  To:       ${FULL_RECIPIENT}"
                echo "  Subject:  ${SUBJECT}"
                echo "  Priority: ${PRIORITY}"
                echo "  Type:     ${TYPE}"
                echo "  ID:       ${MSG_ID}"
            else
                # Recipient NOT on this machine AND no AMP registration
                # FAIL instead of silently losing the message
                echo "❌ Cannot deliver message to '${FULL_RECIPIENT}'"
                echo ""
                echo "  The recipient '${ADDR_NAME}' was not found on this machine,"
                echo "  and this agent has no AMP identity for cross-host routing."
                echo ""
                echo "  To fix this, run:"
                echo "    amp-init.sh --force --auto"
                echo ""
                echo "  This will create an AMP identity and enable cross-host messaging."
                exit 1
            fi
        fi
    fi

else
    # ==========================================================================
    # External Delivery (via provider)
    # ==========================================================================

    # Check if registered with this provider
    if ! is_registered "$ROUTE"; then
        echo "Error: Not registered with provider '${ROUTE}'"
        echo ""
        echo "To send messages to ${ROUTE}, you need to register first:"
        echo "  amp-register --provider ${ROUTE}"
        exit 1
    fi

    # Load registration
    REGISTRATION=$(get_registration "$ROUTE")
    API_URL=$(echo "$REGISTRATION" | jq -r '.apiUrl')
    API_KEY=$(echo "$REGISTRATION" | jq -r '.apiKey')
    ROUTE_URL=$(echo "$REGISTRATION" | jq -r '.routeUrl // empty')
    EXTERNAL_ADDRESS=$(echo "$REGISTRATION" | jq -r '.address')

    # Update the 'from' address to use external address
    MESSAGE_JSON=$(echo "$MESSAGE_JSON" | jq --arg from "$EXTERNAL_ADDRESS" '.envelope.from = $from')

    # Re-sign the message with the external address
    # Format: from|to|subject|priority|in_reply_to|payload_hash (AMP Protocol v1.1)
    EXT_FROM_ADDR=$(echo "$MESSAGE_JSON" | jq -r '.envelope.from')
    EXT_TO_ADDR=$(echo "$MESSAGE_JSON" | jq -r '.envelope.to')
    EXT_SUBJ=$(echo "$MESSAGE_JSON" | jq -r '.envelope.subject')
    EXT_PRIORITY=$(echo "$MESSAGE_JSON" | jq -r '.envelope.priority // "normal"')
    EXT_REPLY_TO=$(echo "$MESSAGE_JSON" | jq -r '.payload.in_reply_to // ""')
    EXT_PAYLOAD_HASH=$(echo "$MESSAGE_JSON" | jq -c '.payload' | tr -d '\n' | $OPENSSL_BIN dgst -sha256 -binary | base64 | tr -d '\n')
    SIGN_DATA="${EXT_FROM_ADDR}|${EXT_TO_ADDR}|${EXT_SUBJ}|${EXT_PRIORITY}|${EXT_REPLY_TO}|${EXT_PAYLOAD_HASH}"
    SIGNATURE=$(sign_message "$SIGN_DATA")

    # Add signature to message
    MESSAGE_JSON=$(echo "$MESSAGE_JSON" | jq --arg sig "$SIGNATURE" '.envelope.signature = $sig')

    # Send via provider API (use route_url if available, fallback to apiUrl/v1/route)
    EXT_SEND_URL="${ROUTE_URL:-${API_URL}/v1/route}"
    RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "${EXT_SEND_URL}" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer ${API_KEY}" \
        -d "$MESSAGE_JSON")

    HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
    BODY=$(echo "$RESPONSE" | sed '$d')

    if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "201" ] || [ "$HTTP_CODE" = "202" ]; then
        # Save to sent folder
        save_to_sent "$MESSAGE_JSON" >/dev/null

        MSG_ID=$(echo "$MESSAGE_JSON" | jq -r '.envelope.id')
        parse_address "$RECIPIENT"
        FULL_RECIPIENT=$(build_address "$ADDR_NAME" "$ADDR_TENANT" "$ADDR_PROVIDER")

        DELIVERY_STATUS=$(echo "$BODY" | jq -r '.status // "queued"' 2>/dev/null)

        echo "✅ Message sent via ${ROUTE}"
        echo ""
        echo "  To:       ${FULL_RECIPIENT}"
        echo "  Subject:  ${SUBJECT}"
        echo "  Priority: ${PRIORITY}"
        echo "  Type:     ${TYPE}"
        echo "  ID:       ${MSG_ID}"
        echo "  Status:   ${DELIVERY_STATUS}"
    else
        echo "❌ Failed to send message (HTTP ${HTTP_CODE})"
        ERROR_MSG=$(echo "$BODY" | jq -r '.error // .message // "Unknown error"' 2>/dev/null)
        if [ -n "$ERROR_MSG" ] && [ "$ERROR_MSG" != "null" ]; then
            echo "   Error: ${ERROR_MSG}"
        fi
        exit 1
    fi
fi
