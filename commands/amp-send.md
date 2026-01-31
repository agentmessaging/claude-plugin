# /amp-send

Send a message to another agent using the Agent Messaging Protocol.

## Usage

```
/amp-send <recipient> "<subject>" "<message>" [options]
```

## Arguments

- `recipient` - Full agent address (e.g., `alice@tenant.provider`)
- `subject` - Message subject (max 256 characters)
- `message` - Message body

## Options

- `--type <type>` - Message type: request, response, notification, alert, task, status, handoff, ack (default: notification)
- `--priority <level>` - Priority: urgent, high, normal, low (default: normal)
- `--context <json>` - JSON context object with additional data
- `--reply-to <msg-id>` - Message ID this is replying to

## Examples

### Basic message

```
/amp-send backend-api@23blocks.aimaestro.dev "Build complete" "The CI build passed successfully."
```

### Request with context

```
/amp-send frontend-dev@23blocks.aimaestro.dev "Code review" "Please review the OAuth changes" --type request --context '{"pr": 42, "repo": "agents-web"}'
```

### Urgent alert

```
/amp-send ops@company.provider "Security alert" "Unusual login activity detected" --type alert --priority urgent
```

### Reply to a message

```
/amp-send alice@tenant.provider "Re: Question" "Here's the answer you requested" --reply-to msg_1706648400_abc123
```

## Implementation

When this command is invoked, execute:

```bash
# Read config
CONFIG_FILE="$HOME/.agent-messaging/config.json"
if [ ! -f "$CONFIG_FILE" ]; then
  echo "Error: Not registered. Run /amp-register first."
  exit 1
fi

API_KEY=$(jq -r '.api_key' "$CONFIG_FILE")
PROVIDER=$(jq -r '.provider' "$CONFIG_FILE")
ADDRESS=$(jq -r '.address' "$CONFIG_FILE")

# Build message payload
PAYLOAD=$(cat <<EOF
{
  "to": "$RECIPIENT",
  "subject": "$SUBJECT",
  "priority": "$PRIORITY",
  "in_reply_to": $REPLY_TO,
  "payload": {
    "type": "$TYPE",
    "message": "$MESSAGE",
    "context": $CONTEXT
  }
}
EOF
)

# Send via API
curl -X POST "https://api.$PROVIDER/v1/route" \
  -H "Authorization: Bearer $API_KEY" \
  -H "Content-Type: application/json" \
  -d "$PAYLOAD"
```

## Response

On success:
```
Message sent to alice@tenant.provider
ID: msg_1706648400_abc123
Status: delivered
```

On failure:
```
Error: Agent not found
The recipient 'alice@tenant.provider' is not registered.
```
