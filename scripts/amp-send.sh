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

if [ "$ROUTE" = "local" ]; then
    # ==========================================================================
    # Local Delivery
    # ==========================================================================

    parse_address "$RECIPIENT"
    FULL_RECIPIENT=$(build_address "$ADDR_NAME" "$ADDR_TENANT" "$ADDR_PROVIDER")

    # For local delivery, we store in both sent (our copy) and
    # simulate delivery by storing in recipient's inbox
    # In a real multi-machine setup, this would be different

    # Save to our sent folder
    save_to_sent "$MESSAGE_JSON" >/dev/null

    # For true local delivery, we'd need to know where the recipient's
    # inbox is. In single-machine scenarios, it's the same ~/.agent-messaging
    # For now, we save to inbox (simulating local delivery on same machine)
    INBOX_FILE=$(save_to_inbox "$MESSAGE_JSON")

    MSG_ID=$(echo "$MESSAGE_JSON" | jq -r '.envelope.id')

    echo "✅ Message sent (local delivery)"
    echo ""
    echo "  To:       ${FULL_RECIPIENT}"
    echo "  Subject:  ${SUBJECT}"
    echo "  Priority: ${PRIORITY}"
    echo "  Type:     ${TYPE}"
    echo "  ID:       ${MSG_ID}"

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
    EXTERNAL_ADDRESS=$(echo "$REGISTRATION" | jq -r '.address')

    # Update the 'from' address to use external address
    MESSAGE_JSON=$(echo "$MESSAGE_JSON" | jq --arg from "$EXTERNAL_ADDRESS" '.envelope.from = $from')

    # Sign the message
    # Create canonical string for signing (envelope without signature)
    SIGN_DATA=$(echo "$MESSAGE_JSON" | jq -r '[.envelope.id, .envelope.from, .envelope.to, .envelope.subject, .envelope.timestamp] | join("|")')
    SIGNATURE=$(sign_message "$SIGN_DATA")

    # Add signature to message
    MESSAGE_JSON=$(echo "$MESSAGE_JSON" | jq --arg sig "$SIGNATURE" '.envelope.signature = $sig')

    # Send via provider API
    RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "${API_URL}/v1/route" \
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
