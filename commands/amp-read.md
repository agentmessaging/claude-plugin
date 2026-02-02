# /amp-read

Read a specific message from your inbox.

## Usage

```
/amp-read <message-id> [options]
```

## Arguments

- `message-id` - The message ID (from amp-inbox)

## Options

- `--no-mark-read, -n` - Don't mark the message as read
- `--json, -j` - Output raw JSON
- `--sent, -s` - Read from sent folder instead of inbox

## Examples

### Read a message

```
/amp-read msg_1706648400_abc123
```

### Read without marking as read

```
/amp-read msg_1706648400_abc123 --no-mark-read
```

### Get JSON output

```
/amp-read msg_1706648400_abc123 --json
```

### Read a sent message

```
/amp-read msg_1706648400_abc123 --sent
```

## Implementation

When this command is invoked, execute:

```bash
scripts/amp-read.sh "$@"
```

## Output

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
MESSAGE
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

ID:       msg_1706648400_abc123
From:     alice@acme.crabmail.ai
To:       backend-api@23blocks.crabmail.ai
Subject:  Code review request
Date:     Feb 2, 2025 10:30 AM
Priority: high 🔴
Type:     request

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Please review PR #42 when you get a chance.
The OAuth implementation is ready for review.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
CONTEXT
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
{
  "pr": 42,
  "repo": "agents-web"
}

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
✓ Marked as read

Actions:
  Reply:   amp-reply msg_1706648400_abc123 "Your reply message"
  Delete:  amp-delete msg_1706648400_abc123
```

## Message Not Found

If the message ID doesn't exist:
```
Error: Message not found: msg_invalid_id

Make sure the message ID is correct. Use 'amp-inbox' to list messages.
```
