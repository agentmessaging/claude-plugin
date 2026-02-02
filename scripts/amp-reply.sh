#!/bin/bash
# =============================================================================
# AMP Reply - Reply to a Message
# =============================================================================
#
# Reply to a message in your inbox.
#
# Usage:
#   amp-reply <message-id> <reply-message>
#   amp-reply <message-id> <reply-message> --priority high
#
# =============================================================================

set -e

# Source helper functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/amp-helper.sh"

# Parse arguments
MESSAGE_ID=""
REPLY_MESSAGE=""
PRIORITY=""
TYPE="response"

show_help() {
    echo "Usage: amp-reply <message-id> <reply-message> [options]"
    echo ""
    echo "Reply to a message."
    echo ""
    echo "Arguments:"
    echo "  message-id      The message ID to reply to"
    echo "  reply-message   Your reply message"
    echo ""
    echo "Options:"
    echo "  --priority, -p PRIORITY   Override priority (default: same as original)"
    echo "  --type, -t TYPE           Message type (default: response)"
    echo "  --help, -h                Show this help"
    echo ""
    echo "Examples:"
    echo "  amp-reply msg_1234567890_abc \"Got it, working on it\""
    echo "  amp-reply msg_1234567890_abc \"Urgent update\" --priority urgent"
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
        --help|-h)
            show_help
            exit 0
            ;;
        -*)
            echo "Unknown option: $1"
            echo "Run 'amp-reply --help' for usage."
            exit 1
            ;;
        *)
            POSITIONAL+=("$1")
            shift
            ;;
    esac
done

# Check positional arguments
if [ ${#POSITIONAL[@]} -lt 2 ]; then
    echo "Error: Missing required arguments."
    echo ""
    show_help
    exit 1
fi

MESSAGE_ID="${POSITIONAL[0]}"
REPLY_MESSAGE="${POSITIONAL[1]}"

# Require initialization
require_init

# Read the original message
ORIGINAL=$(read_message "$MESSAGE_ID" "inbox" 2>/dev/null)

if [ $? -ne 0 ] || [ -z "$ORIGINAL" ]; then
    echo "Error: Message not found: ${MESSAGE_ID}"
    echo ""
    echo "Make sure the message ID is correct. Use 'amp-inbox' to list messages."
    exit 1
fi

# Extract original message details
ORIGINAL_FROM=$(echo "$ORIGINAL" | jq -r '.envelope.from')
ORIGINAL_SUBJECT=$(echo "$ORIGINAL" | jq -r '.envelope.subject')
ORIGINAL_PRIORITY=$(echo "$ORIGINAL" | jq -r '.envelope.priority')
ORIGINAL_THREAD=$(echo "$ORIGINAL" | jq -r '.envelope.thread_id')

# Use original priority if not overridden
if [ -z "$PRIORITY" ]; then
    PRIORITY="$ORIGINAL_PRIORITY"
fi

# Build reply subject
if [[ "$ORIGINAL_SUBJECT" != Re:* ]]; then
    REPLY_SUBJECT="Re: ${ORIGINAL_SUBJECT}"
else
    REPLY_SUBJECT="$ORIGINAL_SUBJECT"
fi

# Create the reply using amp-send
echo "Sending reply to ${ORIGINAL_FROM}..."
echo ""

# Use the send script with reply-to
"${SCRIPT_DIR}/amp-send.sh" \
    "$ORIGINAL_FROM" \
    "$REPLY_SUBJECT" \
    "$REPLY_MESSAGE" \
    --priority "$PRIORITY" \
    --type "$TYPE" \
    --reply-to "$MESSAGE_ID"
