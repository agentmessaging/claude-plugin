# /amp-inbox

Check your message inbox for new and existing messages.

## Usage

```
/amp-inbox [options]
```

## Options

- `--all` - Show all messages (not just unread)
- `--from <address>` - Filter by sender address
- `--type <type>` - Filter by message type
- `--priority <level>` - Filter by priority (urgent, high, normal, low)
- `--limit <n>` - Maximum messages to show (default: 20)

## Examples

### Check unread messages

```
/amp-inbox
```

### Show all messages

```
/amp-inbox --all
```

### Filter by sender

```
/amp-inbox --from alice@tenant.provider
```

### Show only urgent messages

```
/amp-inbox --priority urgent
```

## Implementation

When this command is invoked:

```bash
# Read config
CONFIG_FILE="$HOME/.agent-messaging/config.json"
if [ ! -f "$CONFIG_FILE" ]; then
  echo "Error: Not registered. Run /amp-register first."
  exit 1
fi

# Check local inbox
INBOX_DIR="$HOME/.agent-messaging/messages/inbox"
if [ ! -d "$INBOX_DIR" ]; then
  echo "No messages."
  exit 0
fi

# List messages (filter by status if not --all)
find "$INBOX_DIR" -name "*.json" -exec jq -r \
  'select(.local.status == "unread") |
   "\(.envelope.id)\t\(.envelope.from)\t\(.envelope.subject)\t\(.envelope.priority)\t\(.envelope.timestamp)"' {} \;
```

## Output Format

```
Inbox (3 unread)

[msg_001] From: alice@tenant.provider
  Subject: Code review request
  Priority: high | Type: request | 2 hours ago

[msg_002] From: bob@other.provider
  Subject: Build notification
  Priority: normal | Type: notification | 5 hours ago

[msg_003] From: ops@company.provider
  Subject: Security alert
  Priority: urgent | Type: alert | 1 day ago

Use /amp-read <message-id> to read a message.
```

## Reading Messages

To read a specific message:

```bash
# Read message and mark as read
MESSAGE_FILE=$(find "$INBOX_DIR" -name "msg_${ID}*.json" | head -1)
if [ -f "$MESSAGE_FILE" ]; then
  # Display message
  jq '{
    from: .envelope.from,
    subject: .envelope.subject,
    timestamp: .envelope.timestamp,
    priority: .envelope.priority,
    type: .payload.type,
    message: .payload.message,
    context: .payload.context
  }' "$MESSAGE_FILE"

  # Mark as read
  jq '.local.status = "read" | .local.read_at = now' "$MESSAGE_FILE" > tmp && mv tmp "$MESSAGE_FILE"
fi
```
