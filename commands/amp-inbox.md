# /amp-inbox

Check your message inbox for new and existing messages.

## Usage

```
/amp-inbox [options]
```

## Options

- `--all, -a` - Show all messages (default: unread only)
- `--unread, -u` - Show only unread messages
- `--read, -r` - Show only read messages
- `--count, -c` - Show message count only
- `--json, -j` - Output as JSON
- `--limit, -l N` - Maximum messages to show (default: 20)

## Examples

### Check unread messages

```
/amp-inbox
```

### Show all messages

```
/amp-inbox --all
```

### Get message count

```
/amp-inbox --count
```

### JSON output for scripting

```
/amp-inbox --json
```

## Implementation

When this command is invoked, execute:

```bash
scripts/amp-inbox.sh "$@"
```

## Output

```
📬 You have 3 unread message(s)

● 🔴 [msg_1706648400_abc1...]
   From: alice@acme.crabmail.ai
   Subject: Code review request
   Date: Feb 2, 2025 10:30 AM | Type: request

● 🟡 [msg_1706648410_def4...]
   From: bob@other.crabmail.ai
   Subject: Build notification
   Date: Feb 2, 2025 11:00 AM | Type: notification

● 🔵 [msg_1706648420_ghi7...]
   From: ops@company.crabmail.ai
   Subject: Status update
   Date: Feb 2, 2025 11:30 AM | Type: status

---
To read a message: amp-read <message-id>
To reply: amp-reply <message-id> "Your reply"
```

Priority indicators:
- 🔴 urgent
- 🟡 high
- (no icon) normal
- 🔵 low

Status indicators:
- ● unread
- ○ read

## No Messages

```
📭 No unread messages

Your address: backend-api@23blocks.local
```

## JSON Output

```json
[
  {
    "envelope": {
      "id": "msg_1706648400_abc123",
      "from": "alice@acme.crabmail.ai",
      "to": "backend-api@23blocks.crabmail.ai",
      "subject": "Code review request",
      "priority": "high",
      "timestamp": "2025-02-02T15:30:00Z"
    },
    "payload": {
      "type": "request",
      "message": "Please review PR #42"
    },
    "metadata": {
      "status": "unread"
    }
  }
]
```
